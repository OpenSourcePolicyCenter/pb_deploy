variable "vpc_id" {}
variable "environment" {}
variable "region" {}
variable "fargate_cpu" {}
variable "fargate_memory" {}
variable "subnet_ids" {type = "list"}
variable "default_security_group_id" {}
