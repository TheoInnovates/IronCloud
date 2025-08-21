
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  name = var.name
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  public_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i in range(3, 6) : cidrsubnet(var.vpc_cidr, 4, i)]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
  enable_dns_hostnames   = true
  enable_dns_support     = true

}

module "endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "5.8.1"

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [aws_security_group.vpc_tls.id]

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags            = { Name = "s3-endpoint" }
    },
    ssm = {
      service             = "ssm"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      tags                = { Name = "ssm-endpoint" }
    },
    ssmmessages = {
      service             = "ssmmessages"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      tags                = { Name = "ssmmessages-endpoint" }
    },
    ec2messages = {
      service             = "ec2messages"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      tags                = { Name = "ec2messages-endpoint" }
    },
    ec2 = {
      service             = "ec2"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      tags                = { Name = "ec2-endpoint" }
    },
    imagebuilder = {
      service             = "imagebuilder"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      tags                = { Name = "imagebuilder-endpoint" }
    },
    sts = {
      service             = "sts"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      tags                = { Name = "sts-endpoint" }
    },
    logs = {
      service             = "logs"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      tags                = { Name = "logs-endpoint" }
    },
    kms = {
      service             = "kms"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      tags                = { Name = "kms-endpoint" }
    }
  }

}

resource "aws_security_group" "vpc_tls" {
  name        = "vpc-endpoint-tls"
  description = "Allow TLS traffic from within the VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow VPC ingress on port 443"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}





