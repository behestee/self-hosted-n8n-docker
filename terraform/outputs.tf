output "elastic_ip" {
  description = "Public Elastic IP of your n8n server. Use this as the value in your DNS A record."
  value       = aws_eip.n8n.public_ip
}

output "ssh_command" {
  description = "Ready-to-run SSH command to connect to your server."
  value       = "ssh -i ${local_file.private_key.filename} ec2-user@${aws_eip.n8n.public_ip}"
}

output "instance_id" {
  description = "EC2 instance ID — useful for AWS CLI commands and the scheduler tag."
  value       = aws_instance.n8n.id
}

output "private_key_file" {
  description = "Path to the generated SSH private key. Guard this file — do not share or commit it."
  value       = local_file.private_key.filename
}

output "ami_id" {
  description = "Amazon Linux 2023 AMI ID that was selected for this deployment."
  value       = data.aws_ami.al2023.id
}

output "lambda_function_name" {
  description = "Name of the EC2 scheduler Lambda function."
  value       = aws_lambda_function.ec2_scheduler.function_name
}

output "schedule_names" {
  description = "All available schedule names. Add one of these as a Schedule tag on any EC2 instance to activate scheduling."
  value       = sort(keys(var.schedules))
}

output "tag_this_instance" {
  description = "AWS CLI command to tag THIS instance with the business-hours schedule."
  value       = "aws ec2 create-tags --region ${var.aws_region} --resources ${aws_instance.n8n.id} --tags Key=Schedule,Value=business-hours"
}
