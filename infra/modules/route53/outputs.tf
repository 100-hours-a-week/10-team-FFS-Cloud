output "zone_id" {
  description = "Route53 hosted zone ID"
  value       = var.create_records ? data.aws_route53_zone.main[0].zone_id : null
}

output "cloudfront_fqdn" {
  description = "FQDN for CloudFront record"
  value       = var.create_records && var.cloudfront_domain_name != "" ? aws_route53_record.cloudfront[0].fqdn : null
}

output "alb_fqdn" {
  description = "FQDN for ALB record"
  value       = var.create_records && var.alb_dns_name != "" ? aws_route53_record.alb[0].fqdn : null
}
