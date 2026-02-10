output "instance_id" {
  description = "ID of the Redis EC2 instance"
  value       = aws_instance.redis.id
}

output "private_ip" {
  description = "Private IP address of Redis"
  value       = aws_instance.redis.private_ip
}

output "endpoint" {
  description = "Redis endpoint"
  value       = "${aws_instance.redis.private_ip}:6379"
}
