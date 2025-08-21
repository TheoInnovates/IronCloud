data "aws_region" "current" {}
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

# Random string for unique bucket naming
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 bucket for Image Builder logs
resource "aws_s3_bucket" "image_builder_logs" {
  bucket = "${var.name}-rhel9-image-builder-logs-${random_string.bucket_suffix.result}"
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

# IAM role for Image Builder instances
resource "aws_iam_role" "image_builder_instance_role" {
  name = "${var.name}-rhel9-image-builder-instance-role"

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
}

# Attach AWS managed policy for Image Builder
resource "aws_iam_role_policy_attachment" "image_builder_instance_role_policy" {
  role       = aws_iam_role.image_builder_instance_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/EC2InstanceProfileForImageBuilder"
}

# Attach AWS managed policy for SSM
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.image_builder_instance_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Custom policy for S3 bucket access
resource "aws_iam_role_policy" "s3_bucket_policy" {
  name = "${var.name}-rhel9-s3-bucket-policy"
  role = aws_iam_role.image_builder_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.image_builder_logs.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.image_builder_logs.arn
      }
    ]
  })
}

# IAM instance profile
resource "aws_iam_instance_profile" "image_builder_instance_profile" {
  name = "${var.name}-rhel9-image-builder-instance-profile"
  role = aws_iam_role.image_builder_instance_role.name
}

# Security group for Image Builder instances
resource "aws_security_group" "image_builder" {
  name_prefix = "${var.name}-rhel9-image-builder-sg"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-rhel9-image-builder-sg"
  })
}

# Docker installation component
resource "aws_imagebuilder_component" "docker_install" {
  name        = "${var.name}-docker-install"
  description = "Install Docker on RHEL 9"
  platform    = "Linux"
  version     = "1.0.0"

  data = yamlencode({
    name          = "${var.name}-docker-install"
    description   = "Install Docker on RHEL 9"
    schemaVersion = "1.0"
    phases = [
      {
        name = "build"
        steps = [
          {
            name   = "InstallDocker"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "dnf update -y",
                "dnf install -y yum-utils",
                "dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo",
                "dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",
                "systemctl enable docker",
                "usermod -aG docker ec2-user"
              ]
            }
          }
        ]
      }
    ]
  })

  tags = var.tags
}


# SCAP Compliance Test component
resource "aws_imagebuilder_component" "scap_compliance_test" {
  name        = "${var.name}-scap-compliance-test"
  description = "SCAP compliance testing for RHEL 9"
  platform    = "Linux"
  version     = "1.0.0"

  data = yamlencode({
    name          = "${var.name}-scap-compliance-test"
    description   = "SCAP compliance testing for RHEL 9"
    schemaVersion = "1.0"
    phases = [
      {
        name = "test"
        steps = [
          {
            name   = "SCAPComplianceCheck"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "# Install SCAP tools if not present",
                "dnf install -y openscap-scanner scap-security-guide",
                "# Create timestamp for unique file naming",
                "TIMESTAMP=$(date +%Y%m%d-%H%M%S)",
                "AMI_ID=$(curl -s http://169.254.169.254/latest/meta-data/ami-id)",
                "INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)",
                "# Run SCAP compliance scan",
                "oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_stig --results /tmp/scap-results-$TIMESTAMP.xml --report /tmp/scap-report-$TIMESTAMP.html /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml",
                "SCAP_EXIT_CODE=$?",
                "# Upload results to S3 bucket",
                "echo 'Uploading SCAP results to S3...'",
                "aws s3 cp /tmp/scap-results-$TIMESTAMP.xml s3://${aws_s3_bucket.image_builder_logs.bucket}/scap-compliance/ami-$AMI_ID/instance-$INSTANCE_ID/scap-results-$TIMESTAMP.xml",
                "aws s3 cp /tmp/scap-report-$TIMESTAMP.html s3://${aws_s3_bucket.image_builder_logs.bucket}/scap-compliance/ami-$AMI_ID/instance-$INSTANCE_ID/scap-report-$TIMESTAMP.html",
                "# Create summary file",
                "echo '{' > /tmp/scap-summary-$TIMESTAMP.json",
                "echo '  \"timestamp\": \"'$TIMESTAMP'\",' >> /tmp/scap-summary-$TIMESTAMP.json",
                "echo '  \"ami_id\": \"'$AMI_ID'\",' >> /tmp/scap-summary-$TIMESTAMP.json",
                "echo '  \"instance_id\": \"'$INSTANCE_ID'\",' >> /tmp/scap-summary-$TIMESTAMP.json",
                "echo '  \"scap_exit_code\": '$SCAP_EXIT_CODE',' >> /tmp/scap-summary-$TIMESTAMP.json",
                "if [ $SCAP_EXIT_CODE -eq 0 ]; then",
                "  echo '  \"status\": \"PASSED\",' >> /tmp/scap-summary-$TIMESTAMP.json",
                "  echo '  \"message\": \"SCAP compliance scan passed successfully\"' >> /tmp/scap-summary-$TIMESTAMP.json",
                "else",
                "  echo '  \"status\": \"FAILED\",' >> /tmp/scap-summary-$TIMESTAMP.json",
                "  echo '  \"message\": \"SCAP compliance scan completed with findings\"' >> /tmp/scap-summary-$TIMESTAMP.json",
                "fi",
                "echo '}' >> /tmp/scap-summary-$TIMESTAMP.json",
                "# Upload summary to S3",
                "aws s3 cp /tmp/scap-summary-$TIMESTAMP.json s3://${aws_s3_bucket.image_builder_logs.bucket}/scap-compliance/ami-$AMI_ID/instance-$INSTANCE_ID/scap-summary-$TIMESTAMP.json",
                "# Display results",
                "echo 'SCAP compliance test completed'",
                "echo 'Results uploaded to: s3://${aws_s3_bucket.image_builder_logs.bucket}/scap-compliance/ami-'$AMI_ID'/instance-'$INSTANCE_ID'/'",
                "if [ $SCAP_EXIT_CODE -ne 0 ]; then",
                "  echo 'SCAP compliance scan completed with findings'",
                "  echo 'Review report at: s3://${aws_s3_bucket.image_builder_logs.bucket}/scap-compliance/ami-'$AMI_ID'/instance-'$INSTANCE_ID'/scap-report-'$TIMESTAMP'.html'",
                "else",
                "  echo 'SCAP compliance scan passed successfully'",
                "fi"
              ]
            }
          }
        ]
      }
    ]
  })

  tags = var.tags
}

# Java installation component
resource "aws_imagebuilder_component" "java_install" {
  name        = "${var.name}-java-install"
  description = "Install Java on RHEL 9"
  platform    = "Linux"
  version     = "1.0.0"

  data = yamlencode({
    name          = "${var.name}-java-install"
    description   = "Install Java on RHEL 9"
    schemaVersion = "1.0"
    phases = [
      {
        name = "build"
        steps = [
          {
            name   = "InstallJava"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "dnf install -y java-17-openjdk java-17-openjdk-devel",
                "echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk' >> /etc/profile",
                "echo 'export PATH=$JAVA_HOME/bin:$PATH' >> /etc/profile"
              ]
            }
          }
        ]
      }
    ]
  })

  tags = var.tags
}

# RHEL 9 Infrastructure Configuration
resource "aws_imagebuilder_infrastructure_configuration" "rhel9" {
  name                          = "${var.name}-rhel9-infrastructure-config"
  description                   = "Infrastructure configuration for RHEL 9 image builds"
  instance_profile_name         = aws_iam_instance_profile.image_builder_instance_profile.name
  instance_types                = ["t3.medium"]
  security_group_ids            = [aws_security_group.image_builder.id]
  subnet_id                     = var.subnet_id
  terminate_instance_on_failure = false

  logging {
    s3_logs {
      s3_bucket_name = aws_s3_bucket.image_builder_logs.bucket
      s3_key_prefix  = "rhel9-logs"
    }
  }

  tags = merge(var.tags, {
    OS = "rhel9"
  })
}

# RHEL 9 Distribution Configuration
resource "aws_imagebuilder_distribution_configuration" "rhel9" {
  name = "${var.name}-rhel9-distribution-config"

  distribution {
    ami_distribution_configuration {
      name               = "${var.image_name != "" ? var.image_name : "${var.name}-rhel9"}-{{ imagebuilder:buildDate }}"
      description        = "RHEL 9 AMI with Docker and Java"
      ami_tags = merge(var.tags, {
        OS          = "rhel9"
        Name        = var.image_name != "" ? var.image_name : "${var.name}-rhel9"
        BuildDate   = "{{ imagebuilder.dateCreated }}"
        SourceAMI   = "{{ imagebuilder.sourceImageId }}"
      })
    }

    region = data.aws_region.current.name
  }

  tags = merge(var.tags, {
    OS = "rhel9"
  })
}

# RHEL 9 Image Recipe
resource "aws_imagebuilder_image_recipe" "rhel9" {
  name         = "${var.name}-rhel9-recipe"
  description  = "RHEL 9 image recipe with Docker and Java"
  parent_image = var.rhel9_ami_id
  version      = "1.0.0"

  # AWS managed components
  component {
    component_arn = "arn:${data.aws_partition.current.partition}:imagebuilder:${data.aws_region.current.name}:aws:component/update-linux/x.x.x"
  }

  component {
    component_arn = "arn:${data.aws_partition.current.partition}:imagebuilder:${data.aws_region.current.name}:aws:component/aws-cli-version-2-linux/x.x.x"
  }

  component {
    component_arn = "arn:${data.aws_partition.current.partition}:imagebuilder:${data.aws_region.current.name}:aws:component/stig-build-linux-high/x.x.x"
  }


  # Custom components
  component {
    component_arn = aws_imagebuilder_component.docker_install.arn
  }

  component {
    component_arn = aws_imagebuilder_component.java_install.arn
  }

  component {
    component_arn = aws_imagebuilder_component.scap_compliance_test.arn
  }

  # Additional custom components
  dynamic "component" {
    for_each = var.additional_components
    content {
      component_arn = component.value
    }
  }

  block_device_mapping {
    device_name = "/dev/sda1"
    ebs {
      delete_on_termination = true
      encrypted             = true
      volume_size           = 30
      volume_type           = "gp3"
    }
  }

  tags = merge(var.tags, {
    OS = "rhel9"
  })
}

