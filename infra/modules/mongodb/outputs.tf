output "instance_id" {
  description = "ID of the MongoDB EC2 instance"
  value       = aws_instance.mongodb.id
}

output "private_ip" {
  description = "Private IP address of MongoDB"
  value       = aws_instance.mongodb.private_ip
}

output "connection_string" {
  description = "MongoDB connection string (update password)"
  value       = "mongodb://admin:changeme@${aws_instance.mongodb.private_ip}:27017"
  sensitive   = true
}
