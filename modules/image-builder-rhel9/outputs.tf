output "image_recipe_arn" {
  description = "ARN of the RHEL 9 image recipe"
  value       = aws_imagebuilder_image_recipe.rhel9.arn
}

output "docker_component_arn" {
  description = "ARN of the Docker installation component"
  value       = aws_imagebuilder_component.docker_install.arn
}

output "java_component_arn" {
  description = "ARN of the Java installation component"
  value       = aws_imagebuilder_component.java_install.arn
}

output "scap_compliance_test_component_arn" {
  description = "ARN of the SCAP compliance test component"
  value       = aws_imagebuilder_component.scap_compliance_test.arn
}

output "rhel9_infrastructure_configuration_arn" {
  description = "ARN of the RHEL 9 infrastructure configuration"
  value       = aws_imagebuilder_infrastructure_configuration.rhel9.arn
}

output "rhel9_distribution_configuration_arn" {
  description = "ARN of the RHEL 9 distribution configuration"
  value       = aws_imagebuilder_distribution_configuration.rhel9.arn
}

output "logs_bucket_name" {
  description = "Name of the S3 bucket for RHEL 9 Image Builder logs"
  value       = aws_s3_bucket.image_builder_logs.bucket
}

output "security_group_id" {
  description = "ID of the RHEL 9 Image Builder security group"
  value       = aws_security_group.image_builder.id
}

