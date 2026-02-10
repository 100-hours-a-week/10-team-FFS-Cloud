variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "klosetlab-staging"
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
  default     = ["0.0.0.0/0"]
}
