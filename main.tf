provider "aws" {
  region = "${var.region}"
}

terraform {
  backend "s3" {
    bucket         = "ospc-terraform-state-storage-s3"
    key            = "terraform.tfstate"
    dynamodb_table = "ospc-terraform-state-lock-table"
    region         = "us-east-2"
    encrypt        = true
  }
}

module "networking" {
  source       = "./modules/networking"
  environment  = "${terraform.workspace}"
  region       = "${var.region}"
}

module "worker" {
  source      = "./modules/worker"
  environment = "${terraform.workspace}"
  region      = "${var.region}"
  vpc_id      = "${module.networking.vpc_id}"
  subnet_ids  = ["${module.networking.public_subnet_ids}"]
  api_hostname = "${var.api_hostname}"
}
