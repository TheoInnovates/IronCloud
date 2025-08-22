module "vpc" {
  source = "./modules/vpc"

  vpc_cidr = var.vpc_cidr
  name     = var.environment_name
}

