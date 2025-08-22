

module "image_builder_base_rhel9" {
  source = "./modules/image-builder-rhel9"

  name         = "base_rhel9"
  vpc_id       = module.vpc.vpc_id
  subnet_id    = module.vpc.private_subnets[0]
  rhel9_ami_id = local.selected_rhel9_ami
  s3_bucket_name = var.s3_bucket_name

  additional_components = compact([
    try(aws_imagebuilder_component.my_custom_app.arn, null)
  ])

  tags = {}
}




