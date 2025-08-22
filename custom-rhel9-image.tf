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

# RHEL 9 Image Pipeline with Custom Components
resource "aws_imagebuilder_image_pipeline" "rhel9_custom" {
  name                             = "custom_rhel_9"
  description                      = "RHEL 9 image pipeline with Docker, Java and custom app"
  image_recipe_arn                 = module.image_builder_rhel9.image_recipe_arn
  infrastructure_configuration_arn = module.image_builder_rhel9.rhel9_infrastructure_configuration_arn
  distribution_configuration_arn   = module.image_builder_rhel9.rhel9_distribution_configuration_arn
  status                           = "ENABLED"

  schedule {
    schedule_expression                = "cron(0 2 ? * SUN *)"
    pipeline_execution_start_condition = "EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE"
  }

  image_tests_configuration {
    image_tests_enabled = true
    timeout_minutes     = 720
  }

   image_scanning_configuration {
     image_scanning_enabled = true
   }

}


