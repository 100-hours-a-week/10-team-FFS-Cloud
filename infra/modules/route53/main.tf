#######################################
# Route53 Hosted Zone (Data Source)
#######################################
data "aws_route53_zone" "main" {
  count = var.create_records ? 1 : 0
  name  = var.domain_name
}

#######################################
# CloudFront Record
#######################################
resource "aws_route53_record" "cloudfront" {
  count   = var.create_records && var.enable_cloudfront_record ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cloudfront_www" {
  count   = var.create_records && var.enable_cloudfront_record && var.create_www_record ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

#######################################
# ALB Record
#######################################
resource "aws_route53_record" "alb" {
  count   = var.create_records && var.enable_alb_record ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.api_subdomain != "" ? "${var.api_subdomain}.${var.domain_name}" : var.domain_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}
