output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.web_server.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance (Elastic IP)"
  value       = aws_eip.web_server.public_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the EC2 instance"
  value       = aws_eip.web_server.public_dns
}

output "website_url" {
  description = "URL to access the website"
  value       = "http://${aws_eip.web_server.public_ip}"
}

output "ssh_connection" {
  description = "SSH connection command"
  value       = "ssh -i ../ansible/ssh-key.pem ubuntu@${aws_eip.web_server.public_ip}"
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.web_server.id
}

output "ami_id" {
  description = "AMI ID used for the instance"
  value       = data.aws_ami.ubuntu.id
}
