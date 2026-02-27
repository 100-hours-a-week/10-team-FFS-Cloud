variable "domain_name" {
  description = "Domain name for Route53 hosted zone"
  type        = string
}

variable "create_records" {
  description = "Whether to create Route53 records"
  type        = bool
  default     = true
}

variable "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  type        = string
  default     = ""
}

variable "cloudfront_hosted_zone_id" {
  description = "Hosted zone ID of the CloudFront distribution"
  type        = string
  default     = ""
}

variable "alb_dns_name" {
  description = "DNS name of the ALB"
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "Zone ID of the ALB"
  type        = string
  default     = ""
}

variable "api_subdomain" {
  description = "Subdomain for API (e.g., 'api' for api.domain.com)"
  type        = string
  default     = "api"
}

variable "create_www_record" {
  description = "Whether to create www record"
  type        = bool
  default     = true
}

variable "enable_cloudfront_record" {
  description = "Whether to create CloudFront DNS record"
  type        = bool
  default     = true
}

variable "enable_alb_record" {
  description = "Whether to create ALB DNS record"
  type        = bool
  default     = true
}
