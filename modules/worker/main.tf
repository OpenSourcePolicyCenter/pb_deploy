resource "aws_cloudwatch_log_group" "pb_worker" {
  name = "pb_worker"

  tags {
    Environment = "${var.environment}"
    Application = "PolicyBrain Worker"
  }
}

/* ECS cluster */
resource "aws_ecs_cluster" "cluster" {
  name = "${var.environment}-ecs-cluster"
}

data "aws_ecr_repository" "flask" {
  name = "flask"
}

data "aws_ecr_repository" "celery" {
  name = "celery"
}

data "aws_iam_role" "ecs_task" {
  name = "ecsTaskExecutionRole"
}

/* ECS task definition for backend workers */
data "template_file" "worker_task" {
  template = "${file("${path.module}/tasks/worker_definition.json")}"

  vars {
    flask_image     = "${data.aws_ecr_repository.flask.repository_url}"
    celery_image    = "${data.aws_ecr_repository.celery.repository_url}"
    ecr_region      = "${var.region}"
    memory          = "${var.fargate_memory}"
    log_group       = "${aws_cloudwatch_log_group.pb_worker.name}"
    log_region      = "${var.region}"
  }
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.environment}_worker"
  container_definitions    = "${data.template_file.worker_task.rendered}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "${var.fargate_cpu}"
  memory                   = "${var.fargate_memory}"
  execution_role_arn       = "${data.aws_iam_role.ecs_task.arn}"
  task_role_arn            = "${data.aws_iam_role.ecs_task.arn}"
}

/* Security Group for ECS */
resource "aws_security_group" "ecs_service" {
  vpc_id      = "${var.vpc_id}"
  name        = "${var.environment}-ecs-service-sg"

  ingress {
    from_port   = 5050
    to_port     = 5050
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name        = "${var.environment}-ecs-service-sg"
    Environment = "${var.environment}"
  }
}

resource "aws_ecs_service" "worker" {
  name            = "${var.environment}-worker"
  task_definition = "${aws_ecs_task_definition.worker.arn}"
  desired_count   = 1
  launch_type     = "FARGATE"
  cluster         =  "${aws_ecs_cluster.cluster.id}"

  network_configuration {
    security_groups  = ["${aws_security_group.ecs_service.id}",
                        "${var.default_security_group_id}"]
    subnets          = ["${var.subnet_ids}"]
    assign_public_ip = true
  }
}
