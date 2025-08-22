locals {
  # Determine if we're in GovCloud or Commercial
  is_govcloud = length(regexall("^us-gov-", var.aws_region)) > 0

  # RHEL 9 AMI IDs by region
  rhel9_amis = {
    commercial = {
      us-east-1 = "ami-026ebd4cfe2c043b2"
      us-west-1 = "ami-0b8d0d6ac70e5750c"
    }
    govcloud = {
      us-gov-east-1 = "ami-044d9b4de1ebc4c5c"
      us-gov-west-1 = "ami-0ae6f6dc4a5de5e59"
    }
  }

  # Select the appropriate RHEL 9 AMI
  selected_rhel9_ami = local.is_govcloud ? local.rhel9_amis.govcloud[var.aws_region] : local.rhel9_amis.commercial[var.aws_region]

  rhel9_additional_components = compact([
    try(aws_imagebuilder_component.my_custom_app.arn, null)
  ])
}

