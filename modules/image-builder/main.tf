data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# IAM role for Image Builder instances
resource "aws_iam_role" "image_builder_instance_role" {
  name = "${var.name}-image-builder-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "image_builder_instance_role_policy" {
  role       = aws_iam_role.image_builder_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder"
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.image_builder_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "image_builder_instance_profile" {
  name = "${var.name}-image-builder-instance-profile"
  role = aws_iam_role.image_builder_instance_role.name

  tags = var.tags
}

# Security group for Image Builder instances
resource "aws_security_group" "image_builder" {
  name        = "${var.name}-image-builder-sg"
  description = "Security group for Image Builder instances"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-image-builder-sg"
  })
}

# Image Builder Infrastructure Configuration
resource "aws_imagebuilder_infrastructure_configuration" "this" {
  name                          = "${var.name}-infrastructure-config"
  description                   = "Infrastructure configuration for ${var.name}"
  instance_profile_name         = aws_iam_instance_profile.image_builder_instance_profile.name
  instance_types                = var.instance_types
  security_group_ids            = [aws_security_group.image_builder.id]
  subnet_id                     = var.subnet_id
  terminate_instance_on_failure = true

  logging {
    s3_logs {
      s3_bucket_name = aws_s3_bucket.image_builder_logs.bucket
      s3_key_prefix  = "logs"
    }
  }

  tags = var.tags
}

# S3 bucket for Image Builder logs
resource "aws_s3_bucket" "image_builder_logs" {
  bucket = "${var.name}-image-builder-logs-${random_string.bucket_suffix.result}"

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "image_builder_logs" {
  bucket = aws_s3_bucket.image_builder_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "image_builder_logs" {
  bucket = aws_s3_bucket.image_builder_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "image_builder_logs" {
  bucket = aws_s3_bucket.image_builder_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Custom components for Image Builder
resource "aws_imagebuilder_component" "custom_components" {
  for_each = var.custom_components

  name        = each.key
  description = each.value.description
  platform    = each.value.platform
  version     = each.value.version
  data        = each.value.data

  tags = var.tags
}

# Distribution Configuration
resource "aws_imagebuilder_distribution_configuration" "this" {
  name = "${var.name}-distribution-config"

  distribution {
    ami_distribution_configuration {
      name               = "${var.name}-ami-{{ imagebuilder:buildDate }}"
      description        = "AMI created by Image Builder for ${var.name}"
      ami_tags           = var.tags
      target_account_ids = [data.aws_caller_identity.current.account_id]
    }
    region = data.aws_region.current.name
  }

  tags = var.tags
}