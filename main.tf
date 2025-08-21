module "vpc" {
  source = "./modules/vpc"

  vpc_cidr = var.vpc_cidr
  name     = var.environment_name
}

module "image_builder_rhel9" {
  source = "./modules/image-builder-rhel9"

  name         = var.environment_name
  vpc_id       = module.vpc.vpc_id
  subnet_id    = module.vpc.private_subnets[0]
  rhel9_ami_id = local.selected_rhel9_ami

  tags = {}
}