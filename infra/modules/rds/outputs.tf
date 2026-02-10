output "endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
}

output "address" {
  description = "RDS instance address (hostname only)"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Name of the database"
  value       = aws_db_instance.main.db_name
}

output "identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.identifier
}

output "arn" {
  description = "ARN of the RDS instance"
  value       = aws_db_instance.main.arn
}
