variable "vpc_id" {}
variable "environment" {}
variable "region" {}
variable "subnet_ids" {type = "list"}
variable "redis_port" {default = 6400}
variable "api_hostname" {}
