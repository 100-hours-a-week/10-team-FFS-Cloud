variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "bucket_name" {
  description = "Name of the S3 bucket for frontend"
  type        = string
}

variable "enable_cloudfront" {
  description = "Enable CloudFront distribution"
  type        = bool
  default     = true
}

variable "domain_names" {
  description = "List of domain names for CloudFront"
  type        = list(string)
  default     = []
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate (must be in us-east-1)"
  type        = string
  default     = ""
}

variable "price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_200"
}

variable "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  type        = string
  default     = null
}
