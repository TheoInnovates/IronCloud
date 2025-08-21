output "infrastructure_configuration_arn" {
  description = "ARN of the Image Builder infrastructure configuration"
  value       = aws_imagebuilder_infrastructure_configuration.this.arn
}

output "distribution_configuration_arn" {
  description = "ARN of the Image Builder distribution configuration"
  value       = aws_imagebuilder_distribution_configuration.this.arn
}

output "custom_component_arns" {
  description = "ARNs of the custom Image Builder components"
  value       = { for k, v in aws_imagebuilder_component.custom_components : k => v.arn }
}

output "image_builder_role_arn" {
  description = "ARN of the Image Builder IAM role"
  value       = aws_iam_role.image_builder_instance_role.arn
}

output "security_group_id" {
  description = "ID of the Image Builder security group"
  value       = aws_security_group.image_builder.id
}

output "logs_bucket_name" {
  description = "Name of the S3 bucket for Image Builder logs"
  value       = aws_s3_bucket.image_builder_logs.bucket
}

output "instance_profile_name" {
  description = "Name of the Image Builder IAM instance profile"
  value       = aws_iam_instance_profile.image_builder_instance_profile.name
}