output "frontend_bucket_name" {
  description = "Name of the frontend S3 bucket"
  value       = aws_s3_bucket.frontend.id
}

output "frontend_bucket_arn" {
  description = "ARN of the frontend S3 bucket"
  value       = aws_s3_bucket.frontend.arn
}

output "frontend_bucket_domain" {
  description = "Domain name of the frontend S3 bucket"
  value       = aws_s3_bucket.frontend.bucket_regional_domain_name
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.frontend[0].id : null
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.frontend[0].domain_name : null
}

output "cloudfront_hosted_zone_id" {
  description = "Hosted zone ID of the CloudFront distribution"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.frontend[0].hosted_zone_id : null
}

output "config_bucket_name" {
  description = "Name of the config S3 bucket"
  value       = aws_s3_bucket.config.id
}

output "config_bucket_arn" {
  description = "ARN of the config S3 bucket"
  value       = aws_s3_bucket.config.arn
}
