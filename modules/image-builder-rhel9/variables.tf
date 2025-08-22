variable "name" {
  description = "Name prefix for RHEL 9 Image Builder resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where Image Builder will run"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for Image Builder instances"
  type        = string
}

variable "instance_types" {
  description = "Instance types for Image Builder"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "rhel9_ami_id" {
  description = "AMI ID for RHEL 9 base image"
  type        = string
  default     = "ami-026ebd4cfe2c043b2"  # RHEL 9 in us-east-1
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "additional_components" {
  description = "List of additional component ARNs to include in the image recipe"
  type        = list(string)
  default     = []
}

variable "image_name" {
  description = "Custom name for the AMI image. If empty, defaults to {name}-rhel9"
  type        = string
  default     = ""
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for Image Builder logs and artifacts"
  type        = string
  
}