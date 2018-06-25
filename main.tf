provider "aws" {
  region = "${var.region}"
}

module "networking" {
  source             = "./modules/networking"
  vpc_cidr           = "${var.vpc_cidr}"
  environment        = "${var.environment}"
  region             = "${var.region}"
}

module "worker" {
  source                    = "./modules/worker"
  environment               = "${var.environment}"
  region                    = "${var.region}"
  fargate_cpu               = "${var.fargate_cpu}"
  fargate_memory            = "${var.fargate_memory}"
  vpc_id                    = "${module.networking.vpc_id}"
  subnet_ids                = ["${module.networking.public_subnet_ids}"]
  default_security_group_id = "${module.networking.default_security_group_id}"
}
