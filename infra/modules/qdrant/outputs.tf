output "instance_id" {
  description = "ID of the Qdrant EC2 instance"
  value       = aws_instance.qdrant.id
}

output "private_ip" {
  description = "Private IP address of Qdrant"
  value       = aws_instance.qdrant.private_ip
}

output "http_endpoint" {
  description = "Qdrant HTTP endpoint"
  value       = "http://${aws_instance.qdrant.private_ip}:6333"
}

output "grpc_endpoint" {
  description = "Qdrant gRPC endpoint"
  value       = "${aws_instance.qdrant.private_ip}:6334"
}
