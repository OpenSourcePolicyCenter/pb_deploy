resource "aws_cloudwatch_log_group" "pb_workers" {
  name = "${var.environment}-pb_workers"

  tags {
    Environment = "${var.environment}"
    Application = "PolicyBrain Workers"
  }
}

/* ECS cluster */
resource "aws_ecs_cluster" "cluster" {
  name = "${var.environment}-ecs-cluster"
}

resource "aws_ecr_repository" "celeryflask" {
  name = "${var.environment}-celeryflask"
}

data "aws_iam_role" "ecs_task" {
  name = "ecsTaskExecutionRole"
}

/* Redis instance to store job queue and results */
resource "aws_elasticache_subnet_group" "jobqr" {
  name       = "${var.environment}-jobqr"
  subnet_ids = ["${var.subnet_ids}"]
}

resource "aws_security_group" "jobqr" {
  vpc_id      = "${var.vpc_id}"
  name        = "${var.environment}-elasticache-jobqr-sg"

  ingress {
    from_port       = "${var.redis_port}"
    to_port         = "${var.redis_port}"
    protocol        = "tcp"
    security_groups = ["${aws_security_group.ecs_flask.id}",
                       "${aws_security_group.ecs_celery.id}"]
  }

  tags {
    Environment = "${var.environment}"
  }
}

/* Fetch the available AZs in the configured region */
data "aws_availability_zones" "available" {}

resource "aws_elasticache_cluster" "jobqr" {
  cluster_id           = "${var.environment}-jobqr"
  engine               = "redis"
  availability_zone    = "${data.aws_availability_zones.available.names[0]}"
  subnet_group_name    = "${aws_elasticache_subnet_group.jobqr.name}"
  security_group_ids   = ["${aws_security_group.jobqr.id}"]
  node_type            = "cache.t2.small"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis4.0"
  port                 = "${var.redis_port}"
  apply_immediately    = true
}

/* Security Group for Celery */
resource "aws_security_group" "ecs_celery" {
  vpc_id      = "${var.vpc_id}"
  name        = "${var.environment}-ecs-celery-sg"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Environment = "${var.environment}"
  }
}

/* Celery worker */
data "template_file" "celery_task" {
  template = "${file("${path.module}/tasks/celery_definition.json")}"

  vars {
    redis_hostname = "${aws_elasticache_cluster.jobqr.cache_nodes.0.address}"
    redis_port     = "${var.redis_port}"
    repository_url = "${aws_ecr_repository.celeryflask.repository_url}"
    ecr_region     = "${var.region}"
    log_group      = "${aws_cloudwatch_log_group.pb_workers.name}"
    log_region     = "${var.region}"
  }
}

resource "aws_ecs_task_definition" "celery" {
  family                   = "${var.environment}-celery"
  container_definitions    = "${data.template_file.celery_task.rendered}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 4096
  execution_role_arn       = "${data.aws_iam_role.ecs_task.arn}"
  task_role_arn            = "${data.aws_iam_role.ecs_task.arn}"
}

resource "aws_ecs_service" "celery" {
  name            = "${var.environment}-celery"
  task_definition = "${aws_ecs_task_definition.celery.arn}"
  desired_count   = 4
  launch_type     = "FARGATE"
  cluster         =  "${aws_ecs_cluster.cluster.id}"

  network_configuration {
    security_groups  = ["${aws_security_group.ecs_celery.id}"]
    subnets          = ["${var.subnet_ids}"]
    assign_public_ip = true
  }
}

/* Security Group for Flask */
resource "aws_security_group" "ecs_flask" {
  vpc_id = "${var.vpc_id}"
  name   = "${var.environment}-ecs-flask-sg"

  tags {
    Environment = "${var.environment}"
  }
}

resource "aws_security_group_rule" "allow_all_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.ecs_flask.id}"
}

/* Flask worker */
data "template_file" "flask_task" {
  template = "${file("${path.module}/tasks/flask_definition.json")}"

  vars {
    redis_hostname = "${aws_elasticache_cluster.jobqr.cache_nodes.0.address}"
    redis_port     = "${var.redis_port}"
    repository_url = "${aws_ecr_repository.celeryflask.repository_url}"
    ecr_region     = "${var.region}"
    log_group      = "${aws_cloudwatch_log_group.pb_workers.name}"
    log_region     = "${var.region}"
  }
}

resource "aws_ecs_task_definition" "flask" {
  family                   = "${var.environment}-flask"
  container_definitions    = "${data.template_file.flask_task.rendered}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 4096
  execution_role_arn       = "${data.aws_iam_role.ecs_task.arn}"
  task_role_arn            = "${data.aws_iam_role.ecs_task.arn}"
}

resource "aws_ecs_service" "flask" {
  name            = "${var.environment}-flask"
  task_definition = "${aws_ecs_task_definition.flask.arn}"
  desired_count   = 1
  launch_type     = "FARGATE"
  cluster         =  "${aws_ecs_cluster.cluster.id}"

  network_configuration {
    security_groups  = ["${aws_security_group.ecs_flask.id}"]
    /* With X subnets, ECS will create X instances even if X > desired count */
    subnets          = ["${var.subnet_ids[0]}"]
    assign_public_ip = true
  }

  /* See below for LB setup */
  load_balancer {
    target_group_arn = "${aws_lb_target_group.flask.id}"
    container_name   = "flask"
    container_port   = "5050"
  }
}

/* Application Load Balancer */
resource "aws_security_group" "lb_public" {
  name   = "${var.environment}-lb-public"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 5050
    to_port         = 5050
    protocol        = "tcp"
    security_groups = ["${aws_security_group.ecs_flask.id}"]
  }

  tags {
    Environment = "${var.environment}"
  }
}

resource "aws_security_group_rule" "allow_into_flask_from_lb" {
  type                     = "ingress"
  from_port                = 5050
  to_port                  = 5050
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.ecs_flask.id}"
  source_security_group_id = "${aws_security_group.lb_public.id}"
}

resource "aws_lb" "public" {
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.lb_public.id}"]
  subnets            = ["${var.subnet_ids}"]

  enable_deletion_protection = true
}

resource "aws_lb_target_group" "flask" {
  name        = "${var.environment}-flask"
  port        = 5050
  protocol    = "HTTP"
  vpc_id      = "${var.vpc_id}"
  target_type = "ip"

  health_check {
    path    = "/hello"
    matcher = 200
  }
}

resource "aws_lb_listener" "public_http" {
  load_balancer_arn = "${aws_lb.public.id}"
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_lb_target_group.flask.id}"
    type             = "forward"
  }
}

/* Route53 hosted zone */
resource "aws_route53_zone" "api" {
  name = "${var.environment == "production" ? "" : "${var.environment}."}${var.api_hostname}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_record" "lb" {
  zone_id = "${aws_route53_zone.api.zone_id}"
  name    = "${aws_route53_zone.api.name}"
  type    = "A"

  alias {
    name                   = "${aws_lb.public.dns_name}"
    zone_id                = "${aws_lb.public.zone_id}"
    evaluate_target_health = true
  }
}
