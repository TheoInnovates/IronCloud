terraform {
  backend "s3" {
    bucket = "theo-projects"
    key    = "ironcloud/terraform.tfstate"
    region = "us-east-1"
  }
}