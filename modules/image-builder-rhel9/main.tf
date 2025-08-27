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

# Red Hat Official Ansible STIG component
resource "aws_imagebuilder_component" "ansible_stig" {
  name        = "${var.name}-redhat-ansible-stig"
  description = "Install Ansible and run Red Hat Official RHEL 9 STIG role"
  platform    = "Linux"
  version     = "1.0.0"

  data = yamlencode({
    name          = "${var.name}-redhat-ansible-stig"
    description   = "Install Ansible and run Red Hat Official RHEL 9 STIG role"
    schemaVersion = "1.0"
    phases = [
      {
        name = "build"
        steps = [
          {
            name   = "InstallAnsible"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "# Install EPEL repository for Ansible",
                "dnf install -y epel-release",
                "# Install Ansible and dependencies",
                "dnf install -y ansible-core python3-pip git",
                "# Install additional Ansible collections that may be needed",
                "ansible-galaxy collection install community.general",
                "ansible-galaxy collection install ansible.posix",
                "# Create ansible working directory",
                "mkdir -p /home/root/ansible-stig",
                "cd /home/root/ansible-stig"
              ]
            }
          },
          {
            name   = "InstallRedHatSTIGRole"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "cd /home/root/ansible-stig",
                "# Install the Red Hat Official RHEL 9 STIG role",
                "ansible-galaxy install RedHatOfficial.rhel9_stig",
                "# Create requirements.yml for better dependency management",
                "cat > requirements.yml << 'EOF'",
                "---",
                "roles:",
                "  - name: RedHatOfficial.rhel9_stig",
                "    version: latest",
                "EOF",
                "# Install from requirements file",
                "ansible-galaxy install -r requirements.yml",
                "echo 'Red Hat STIG role installed successfully'"
              ]
            }
          },
          {
            name   = "CreateSTIGPlaybook"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "cd /home/root/ansible-stig",
                "# Create inventory file",
                "echo 'localhost ansible_connection=local' > inventory",
                "# Create the STIG playbook using the Red Hat Official role",
                "cat > rhel9-stig-playbook.yml << 'EOF'",
                "---",
                "- name: Apply RHEL 9 STIG using Red Hat Official Role",
                "  hosts: localhost",
                "  become: true",
                "  gather_facts: true",
                "",
                "  vars:",
                "    # STIG Configuration Variables",
                "    # Set to false to skip rules that might break basic functionality",
                "    rhel9stig_disruption_high: false",
                "    rhel9stig_complexity_high: false",
                "",
                "    # Configure based on your environment",
                "    rhel9stig_gui: false",
                "    rhel9stig_system_is_router: false",
                "    rhel9stig_ipv6_required: false",
                "",
                "    # Patch level configuration",
                "    rhel9stig_cat1_patch: true   # High severity",
                "    rhel9stig_cat2_patch: true   # Medium severity", 
                "    rhel9stig_cat3_patch: false  # Low severity (can be disruptive)",
                "",
                "    # Skip rules that might interfere with cloud environments",
                "    rhel9stig_skip_for_cloud:",
                "      - rhel_09_010001  # Disable USB storage (might affect cloud)",
                "      - rhel_09_010002  # Disable FireWire (not applicable)",
                "",
                "    # Configure authentication",
                "    rhel9stig_password_complexity:",
                "      minlen: 15",
                "      dcredit: -1",
                "      ucredit: -1", 
                "      lcredit: -1",
                "      ocredit: -1",
                "",
                "    # Configure audit log settings",
                "    rhel9stig_audit_log_storage_size: 100",
                "",
                "  roles:",
                "    - RedHatOfficial.rhel9_stig",
                "",
                "  post_tasks:",
                "    - name: Create STIG application summary",
                "      copy:",
                "        content: |",
                "          RHEL 9 STIG Application Summary",
                "          ================================",
                "          Applied on: $(date -u +%Y-%m-%dT%H:%M:%SZ)",
                "          Hostname: $(hostname)",
                "          RHEL Version: $(cat /etc/redhat-release)",
                "          STIG Role: RedHatOfficial.rhel9_stig",
                "          CAT I (High): true",
                "          CAT II (Medium): true",
                "          CAT III (Low): false",
                "        dest: /home/root/stig-application-summary.txt",
                "EOF",
                "echo 'STIG playbook created successfully'"
              ]
            }
          },
          {
            name   = "RunRedHatSTIG"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "cd /home/root/ansible-stig",
                "# Set Ansible configuration for better output",
                "export ANSIBLE_STDOUT_CALLBACK=yaml",
                "export ANSIBLE_HOST_KEY_CHECKING=False",
                "",
                "# Run the Red Hat Official STIG playbook",
                "echo 'Starting Red Hat Official RHEL 9 STIG application...'",
                "ansible-playbook -i inventory rhel9-stig-playbook.yml -v > /home/root/ansible-stig-execution.log 2>&1",
                "ANSIBLE_EXIT_CODE=$?",
                "",
                "# Create detailed results",
                "TIMESTAMP=$(date +%Y%m%d-%H%M%S)",
                "# Get IMDSv2 token for metadata access",
                "TOKEN=$(curl -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600' -s http://169.254.169.254/latest/api/token)",
                "AMI_ID=$(curl -H \"X-aws-ec2-metadata-token: $TOKEN\" -s http://169.254.169.254/latest/meta-data/ami-id || echo 'unknown')",
                "INSTANCE_ID=$(curl -H \"X-aws-ec2-metadata-token: $TOKEN\" -s http://169.254.169.254/latest/meta-data/instance-id || echo 'unknown')",
                "",
                "# Create comprehensive results summary",
                "cat > /home/root/rhel9-stig-results-$TIMESTAMP.json << EOF",
                "{",
                "  \"timestamp\": \"$TIMESTAMP\",",
                "  \"ami_id\": \"$AMI_ID\",",
                "  \"instance_id\": \"$INSTANCE_ID\",",
                "  \"stig_method\": \"redhat_official_ansible\",",
                "  \"role_name\": \"RedHatOfficial.rhel9_stig\",",
                "  \"ansible_exit_code\": $ANSIBLE_EXIT_CODE,",
                "  \"playbook_status\": \"$([ $ANSIBLE_EXIT_CODE -eq 0 ] && echo 'completed_successfully' || echo 'completed_with_errors')\",",
                "  \"log_files\": [",
                "    \"/home/root/ansible-stig-execution.log\",",
                "    \"/home/root/stig-application-summary.txt\"",
                "  ],",
                "  \"message\": \"Red Hat Official RHEL 9 STIG role execution completed\"",
                "}",
                "EOF",
                "",
                "# Upload results to S3",
                "echo 'Uploading STIG results to S3...'",
                "aws s3 cp /home/root/rhel9-stig-results-$TIMESTAMP.json s3://${var.s3_bucket_name}/rhel9-stig/ami-$AMI_ID/instance-$INSTANCE_ID/rhel9-stig-results-$TIMESTAMP.json || echo 'Failed to upload results'",
                "aws s3 cp /home/root/ansible-stig-execution.log s3://${var.s3_bucket_name}/rhel9-stig/ami-$AMI_ID/instance-$INSTANCE_ID/ansible-execution-$TIMESTAMP.log || echo 'Failed to upload execution log'",
                "aws s3 cp /home/root/ansible-stig/rhel9-stig-playbook.yml s3://${var.s3_bucket_name}/rhel9-stig/ami-$AMI_ID/instance-$INSTANCE_ID/playbook-$TIMESTAMP.yml || echo 'Failed to upload playbook'",
                "aws s3 cp /home/root/stig-application-summary.txt s3://${var.s3_bucket_name}/rhel9-stig/ami-$AMI_ID/instance-$INSTANCE_ID/summary-$TIMESTAMP.txt || echo 'Failed to upload summary'",
                "",
                "# Display completion status",
                "if [ $ANSIBLE_EXIT_CODE -eq 0 ]; then",
                "  echo 'Red Hat Official RHEL 9 STIG application completed successfully'",
                "  echo 'All STIG controls have been applied according to the role configuration'",
                "else",
                "  echo 'Red Hat Official RHEL 9 STIG application completed with some issues'",
                "  echo 'Check the execution log for details: /home/root/ansible-stig-execution.log'",
                "  echo 'Exit code: $ANSIBLE_EXIT_CODE'",
                "fi",
                "",
                "echo 'STIG application summary available at: /home/root/stig-application-summary.txt'"
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
