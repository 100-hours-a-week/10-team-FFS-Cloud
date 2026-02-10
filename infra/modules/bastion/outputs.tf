output "instance_id" {
  description = "ID of the Bastion EC2 instance"
  value       = aws_instance.bastion.id
}

output "private_ip" {
  description = "Private IP address of the Bastion Host"
  value       = aws_instance.bastion.private_ip
}

output "public_ip" {
  description = "Public IP address of the Bastion Host"
  value       = var.use_elastic_ip ? aws_eip.bastion[0].public_ip : aws_instance.bastion.public_ip
}
