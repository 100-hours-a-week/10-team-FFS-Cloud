variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "klosetlab"
}

variable "domain_name" {
  description = "Domain name"
  type        = string
  default     = "klosetlab.site"
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "db_password" {
  description = "RDS database password"
  type        = string
  sensitive   = true
}

variable "bastion_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH into Bastion"
  type        = list(string)
}

variable "alb_certificate_arn" {
  description = "ARN of the ACM certificate for ALB"
  type        = string
}

variable "cloudfront_certificate_arn" {
  description = "ARN of the ACM certificate for CloudFront (must be in us-east-1)"
  type        = string
}
