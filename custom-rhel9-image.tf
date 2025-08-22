# Custom RHEL9 Component and Image Builder Pipeline
resource "aws_imagebuilder_component" "my_custom_app" {
  name        = "${var.environment_name}-my-custom-app"
  description = "Install my custom application on RHEL 9"
  platform    = "Linux"
  version     = "1.0.0"

  data = yamlencode({
    name          = "${var.environment_name}-my-custom-app"
    description   = "Install my custom application on RHEL 9"
    schemaVersion = "1.0"
    phases = [
      {
        name = "build"
        steps = [
          {
            name   = "InstallCustomApp"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "dnf update -y"
              ]
            }
          }
        ]
      }
    ]
  })

  tags = {
    Environment = var.environment_name
    Component   = "CustomApp"
  }
}

module "image_builder_rhel9" {
  source = "./modules/image-builder-rhel9"

  name         = "custom_rhel9"
  vpc_id       = module.vpc.vpc_id
  subnet_id    = module.vpc.private_subnets[0]
  rhel9_ami_id = local.selected_rhel9_ami
  s3_bucket_name = var.s3_bucket_name

  additional_components = compact([
    try(aws_imagebuilder_component.my_custom_app.arn, null)
  ])

  tags = {}
}




