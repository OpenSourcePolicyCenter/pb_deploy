# pb_deploy
`pb_deploy` is a [Terraform](https://www.terraform.io) configuration for a
production deployment of [PolicyBrain], as run by the
[Open Source Policy Center], on Amazon Web Services infrastructure.

## Why Terraform?
Terraform is a declarative "infrastructure as code" open-source application,
meaning that it can deploy a new set of infrastructure components with ease
given account information, and it can keep it up-to-date with a programmatically
specified configuration, performing changes only as needed.

This is possible because Terraform keeps track of the [state][Terraform state].
In the case of OSPC, we use [AWS S3 and DynamoDB][Terraform S3 backend] to share
and lock state information among different OSPC collaborators.

## Infrastructure description
The main component of this infrastructure is [Amazon ECS Fargate], which is a
technology for deploying Docker containers without having to manage the
underlying servers. ECS is used to run relatively few Internet-facing Flask
servers, as well as relatively many Celery workers. Rather than being run on
ECS, Redis is managed through [Amazon ElastiCache], and stores the task queue.
[Amazon Route 53] and [Amazon ELB] are used to provide a permanent hostname,
such as `staging.ospcapi.org`, that will always point to the correct ECS task
IP(s). (Currently, the alternative, Route53 Service Discovery for ECS, only
  supports private IPs.)

The networking is handled using a [Virtual Public Cloud][Amazon VPC] and a
single public subnet, and all instances are given public IPs. This is to avoid
the expense of a NAT gateway required with private subnets, but AWS security
groups are used to define permissible Internet access as restrictively as
possible.

## Usage
Because of Terraform's declarative nature, the steps for initial setup and for
modification of the infrastructure should be the same. You should specify
[AWS authentication credentials][Terraform AWS authentication] either through
environment variables or through the `~/.aws/credentials` file. The
configuration also assumes that the following resources have already been
created in the region given in the `terraform.tfvars` file:

 - An [Amazon ECS task execution role]
 - An Amazon Route 53 zone with the name given in `terraform.tfvars`; this can
   be any domain or subdomain for which you need to configure the nameservers
 - An S3 bucket and a DynamoDB table with the names given in `main.tf` in order
   to store Terraform state

This configuration makes extensive use of [Terraform workspaces] in order to
separate state and resources for different deployment environments. The
`default` workspace can be used if this distinction is not needed, but should
**not** be used for OSPC deployments, which will make use of the `production`
and `staging` environments.

An example deployment workflow would be:

```shell
cd ~/pb_deploy
terraform init
terraform workspace select production
terraform plan -out=production.tfplan
terraform apply production.tfplan
```

A deployment environment could be torn down as follows:

```shell
cd ~/pb_deploy
terraform init
terraform workspace select staging
terraform destroy
```

[PolicyBrain]: https://github.com/OpenSourcePolicyCenter/PolicyBrain
[Open Source Policy Center]: https://github.com/OpenSourcePolicyCenter/PolicyBrain
[Terraform state]: https://www.terraform.io/docs/state/index.html
[Terraform S3 backend]: https://www.terraform.io/docs/backends/types/s3.html
[Amazon ECS Fargate]: https://aws.amazon.com/fargate/
[Amazon ElastiCache]: https://aws.amazon.com/elasticache/
[Amazon Route 53]: https://aws.amazon.com/route53/
[Amazon ELB]: https://aws.amazon.com/elasticloadbalancing/
[Amazon VPC]: https://aws.amazon.com/vpc/
[Terraform AWS authentication]: https://www.terraform.io/docs/providers/aws/index.html#authentication
[Amazon ECS task execution role]: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html
[Terraform workspaces]: https://www.terraform.io/docs/state/workspaces.html
