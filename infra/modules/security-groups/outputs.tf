#######################################
# ALB
#######################################
output "alb_sg_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

#######################################
# Bastion
#######################################
output "bastion_sg_id" {
  description = "ID of the Bastion security group"
  value       = aws_security_group.bastion.id
}

#######################################
# Application Servers
#######################################
output "app_sg_id" {
  description = "ID of the App security group"
  value       = aws_security_group.app.id
}

output "chat_sg_id" {
  description = "ID of the Chat security group"
  value       = aws_security_group.chat.id
}

output "fastapi_sg_id" {
  description = "ID of the FastAPI security group"
  value       = aws_security_group.fastapi.id
}

#######################################
# Data Layer
#######################################
output "rds_sg_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

output "mongodb_sg_id" {
  description = "ID of the MongoDB security group"
  value       = aws_security_group.mongodb.id
}

output "redis_sg_id" {
  description = "ID of the Redis security group"
  value       = aws_security_group.redis.id
}

output "qdrant_sg_id" {
  description = "ID of the Qdrant security group"
  value       = aws_security_group.qdrant.id
}
