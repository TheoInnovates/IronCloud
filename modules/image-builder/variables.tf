variable "name" {
  description = "Name prefix for Image Builder resources"
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

variable "custom_components" {
  description = "Map of custom components to create"
  type = map(object({
    description = string
    platform    = string
    version     = string
    data        = string
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}