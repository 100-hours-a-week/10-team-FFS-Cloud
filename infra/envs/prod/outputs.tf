#######################################
# VPC
#######################################
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

#######################################
# Bastion
#######################################
output "bastion_public_ip" {
  description = "Bastion Host public IP"
  value       = module.bastion.public_ip
}

#######################################
# ALB
#######################################
output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns_name
}

#######################################
# CloudFront
#######################################
output "cloudfront_domain_name" {
  description = "CloudFront domain name"
  value       = module.s3_cloudfront.cloudfront_domain_name
}

#######################################
# Route53
#######################################
output "website_url" {
  description = "Website URL"
  value       = "https://${var.domain_name}"
}

output "api_url" {
  description = "API URL"
  value       = "https://api.${var.domain_name}"
}

#######################################
# RDS
#######################################
output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.endpoint
}

#######################################
# Data Layer
#######################################
output "mongodb_private_ip" {
  description = "MongoDB private IP"
  value       = module.mongodb.private_ip
}

output "redis_private_ip" {
  description = "Redis private IP"
  value       = module.redis.private_ip
}

output "qdrant_private_ip" {
  description = "Qdrant private IP"
  value       = module.qdrant.private_ip
}

#######################################
# ECR
#######################################
output "ecr_repository_urls" {
  description = "ECR repository URLs"
  value       = module.ecr.repository_urls
}

#######################################
# S3
#######################################
output "frontend_bucket_name" {
  description = "Frontend S3 bucket name"
  value       = module.s3_cloudfront.frontend_bucket_name
}

output "config_bucket_name" {
  description = "Config S3 bucket name"
  value       = module.s3_cloudfront.config_bucket_name
}
