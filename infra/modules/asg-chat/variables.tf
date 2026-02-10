variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "security_group_id" {
  description = "ID of the security group"
  type        = string
}

variable "instance_profile_name" {
  description = "Name of the IAM instance profile"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for ASG"
  type        = list(string)
}

variable "target_group_arn" {
  description = "ARN of the target group"
  type        = string
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 20
}

variable "desired_capacity" {
  description = "Desired number of instances"
  type        = number
  default     = 1
}

variable "min_size" {
  description = "Minimum number of instances"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances"
  type        = number
  default     = 2
}

variable "ecr_registry" {
  description = "ECR registry URL"
  type        = string
}

variable "ecr_repo_name" {
  description = "ECR repository name"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag"
  type        = string
  default     = "latest"
}

variable "chat_port" {
  description = "Chat application port"
  type        = number
  default     = 8081
}

variable "config_bucket" {
  description = "S3 bucket for configuration files"
  type        = string
}

variable "env_file_key" {
  description = "S3 key for environment file"
  type        = string
  default     = "chat/.env"
}

variable "cpu_scale_up_threshold" {
  description = "CPU threshold for scaling up"
  type        = number
  default     = 70
}

variable "cpu_scale_down_threshold" {
  description = "CPU threshold for scaling down"
  type        = number
  default     = 30
}
