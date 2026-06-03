# This file is intentionally left empty.
# All resources are organized into dedicated files:
#
#   versions.tf              — Terraform version and provider requirements
#   variables.tf             — All input variables (region, instance type, schedules, etc.)
#   data.tf                  — Data sources: latest AL2023 AMI, default VPC and subnets
#   ec2.tf                   — Key pair, security group, EC2 instance, Elastic IP
#   iam.tf                   — IAM roles and policies for Lambda and EventBridge
#   scheduler.tf             — Lambda function, schedule group, start/stop rules
#   outputs.tf               — All output values (IP, SSH command, schedule names, etc.)
#   terraform.tfvars.example — Copy to terraform.tfvars and fill in your values
