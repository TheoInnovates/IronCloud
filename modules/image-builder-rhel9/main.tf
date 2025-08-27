data "aws_region" "current" {}
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

# Random string for unique bucket naming
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
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
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::${var.s3_bucket_name}",
          "arn:${data.aws_partition.current.partition}:s3:::${var.s3_bucket_name}/*"
        ]
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

# Simple RHEL 9 STIG Ansible component
resource "aws_imagebuilder_component" "ansible_stig" {
  name        = "${var.name}-simple-ansible-stig"
  description = "Simple RHEL 9 STIG application using DISA Ansible content from S3"
  platform    = "Linux"
  version     = "1.0.0"

  data = yamlencode({
    name          = "${var.name}-simple-ansible-stig"
    description   = "Simple RHEL 9 STIG application using DISA Ansible content from S3"
    schemaVersion = "1.0"
    phases = [
      {
        name = "build"
        steps = [
          {
            name   = "InstallAnsibleAndApplySTIG"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "# Simple RHEL 9 STIG Ansible Setup",
                "set -e",
                "",
                "# Install EPEL repository",
                "yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm",
                "",
                "# Install Ansible",
                "yum install -y ansible unzip",
                "",
                "# Work in /tmp directory",
                "cd /tmp",
                "",
                "# Download RHEL STIG Ansible content from S3",
                "aws s3 cp s3://${var.s3_bucket_name}/rhel9_imagebuilder/rhel9STIG-ansible.zip ./",
                "",
                "# Extract the content",
                "unzip rhel9STIG-ansible.zip",
                "",
                "# Create site.yml",
                "cat > site.yml << 'EOF'",
                "---",
                "- hosts: localhost",
                "  gather_facts: yes",
                "  become: yes",
                "  vars_files:",
                "    - custom_vars.yml",
                "  roles:",
                "    - rhel9STIG",
                "EOF",
                "",
                "# Create custom_vars.yml",
                "cat > custom_vars.yml << 'EOF'",
                "---",
                "# Custom RHEL 9 STIG Variables",
                "# Add your customizations here",
                "",
                "# Example: Disable specific STIG rules if needed",
                "# rhel9STIG_stigrule_258117_Manage: False",
                "",
                "# Example: Set minimum password length",
                "# rhel9STIG_stigrule_258107__etc_security_pwquality_conf_Line: 'minlen = 14'",
                "EOF",
                "",
                "# Set permissions",
                "chmod 644 site.yml custom_vars.yml",
                "chmod +x enforce.sh",
                "",
                "# Run the enforce.sh script",
                "./enforce.sh",
                "",
                "# Log completion",
                "echo 'RHEL 9 STIG enforcement completed via enforce.sh script'",
                "",
                "# Create completion summary",
                "TIMESTAMP=$(date +%Y%m%d-%H%M%S)",
                "TOKEN=$(curl -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600' -s http://169.254.169.254/latest/api/token)",
                "AMI_ID=$(curl -H \"X-aws-ec2-metadata-token: $TOKEN\" -s http://169.254.169.254/latest/meta-data/ami-id || echo 'unknown')",
                "INSTANCE_ID=$(curl -H \"X-aws-ec2-metadata-token: $TOKEN\" -s http://169.254.169.254/latest/meta-data/instance-id || echo 'unknown')",
                "",
                "# Create results summary",
                "cat > /tmp/stig-completion-summary.json << EOF",
                "{",
                "  \"timestamp\": \"$TIMESTAMP\",",
                "  \"ami_id\": \"$AMI_ID\",",
                "  \"instance_id\": \"$INSTANCE_ID\",",
                "  \"stig_method\": \"disa_ansible_enforce_script\",",
                "  \"status\": \"completed\",",
                "  \"message\": \"RHEL 9 STIG applied using DISA enforce.sh script\"",
                "}",
                "EOF",
                "",
                "# Upload summary to S3",
                "aws s3 cp /tmp/stig-completion-summary.json s3://${var.s3_bucket_name}/rhel9-stig/ami-$AMI_ID/instance-$INSTANCE_ID/stig-completion-$TIMESTAMP.json || echo 'Failed to upload summary'",
                "",
                "echo 'STIG application completed successfully'"
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
                "# Get IMDSv2 token for metadata access",
                "TOKEN=$(curl -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600' -s http://169.254.169.254/latest/api/token)",
                "AMI_ID=$(curl -H \"X-aws-ec2-metadata-token: $TOKEN\" -s http://169.254.169.254/latest/meta-data/ami-id)",
                "INSTANCE_ID=$(curl -H \"X-aws-ec2-metadata-token: $TOKEN\" -s http://169.254.169.254/latest/meta-data/instance-id)",
                "# Run SCAP compliance scan",
                "oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_stig --results /home/root/scap-results-$TIMESTAMP.xml --report /home/root/scap-report-$TIMESTAMP.html /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml",
                "SCAP_EXIT_CODE=$?",
                "# Upload results to S3 bucket",
                "echo 'Uploading SCAP results to S3...'",
                "aws s3 cp /home/root/scap-results-$TIMESTAMP.xml s3://${var.s3_bucket_name}/scap-compliance/ami-$AMI_ID/instance-$INSTANCE_ID/scap-results-$TIMESTAMP.xml",
                "aws s3 cp /home/root/scap-report-$TIMESTAMP.html s3://${var.s3_bucket_name}/scap-compliance/ami-$AMI_ID/instance-$INSTANCE_ID/scap-report-$TIMESTAMP.html",
                "# Create summary file",
                "echo '{' > /home/root/scap-summary-$TIMESTAMP.json",
                "echo '  \"timestamp\": \"'$TIMESTAMP'\",' >> /home/root/scap-summary-$TIMESTAMP.json",
                "echo '  \"ami_id\": \"'$AMI_ID'\",' >> /home/root/scap-summary-$TIMESTAMP.json",
                "echo '  \"instance_id\": \"'$INSTANCE_ID'\",' >> /home/root/scap-summary-$TIMESTAMP.json",
                "echo '  \"scap_exit_code\": '$SCAP_EXIT_CODE',' >> /home/root/scap-summary-$TIMESTAMP.json",
                "if [ $SCAP_EXIT_CODE -eq 0 ]; then",
                "  echo '  \"status\": \"PASSED\",' >> /home/root/scap-summary-$TIMESTAMP.json",
                "  echo '  \"message\": \"SCAP compliance scan passed successfully\"' >> /home/root/scap-summary-$TIMESTAMP.json",
                "else",
                "  echo '  \"status\": \"FAILED\",' >> /home/root/scap-summary-$TIMESTAMP.json",
                "  echo '  \"message\": \"SCAP compliance scan completed with findings\"' >> /home/root/scap-summary-$TIMESTAMP.json",
                "fi",
                "echo '}' >> /home/root/scap-summary-$TIMESTAMP.json",
                "# Upload summary to S3",
                "aws s3 cp /home/root/scap-summary-$TIMESTAMP.json s3://${var.s3_bucket_name}/scap-compliance/ami-$AMI_ID/instance-$INSTANCE_ID/scap-summary-$TIMESTAMP.json",
                "# Display results",
                "echo 'SCAP compliance test completed'",
                "echo 'Results uploaded to: s3://${var.s3_bucket_name}/scap-compliance/ami-'$AMI_ID'/instance-'$INSTANCE_ID'/'",
                "if [ $SCAP_EXIT_CODE -ne 0 ]; then",
                "  echo 'SCAP compliance scan completed with findings'",
                "  echo 'Review report at: s3://${var.s3_bucket_name}/scap-compliance/ami-'$AMI_ID'/instance-'$INSTANCE_ID'/scap-report-'$TIMESTAMP'.html'",
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
      s3_bucket_name = var.s3_bucket_name
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

  # Custom components
  component {
    component_arn = aws_imagebuilder_component.docker_install.arn
  }

  component {
    component_arn = aws_imagebuilder_component.java_install.arn
  }

  component {
    component_arn = aws_imagebuilder_component.ansible_stig.arn
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

resource "aws_imagebuilder_image_pipeline" "rhel9" {
  name                             = "${var.name}-rhel9-pipeline"
  description                      = "RHEL 9 image pipeline with Docker, Java and additional components"
  image_recipe_arn                 = aws_imagebuilder_image_recipe.rhel9.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.rhel9.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.rhel9.arn
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

  tags = merge(var.tags, {
    OS = "rhel9"
  })
}
