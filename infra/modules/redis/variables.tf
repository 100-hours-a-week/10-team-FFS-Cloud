variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
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

variable "subnet_id" {
  description = "ID of the subnet"
  type        = string
}

variable "security_group_id" {
  description = "ID of the security group"
  type        = string
}

variable "availability_zone" {
  description = "Availability zone for EBS volume"
  type        = string
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 8
}

variable "data_volume_size" {
  description = "Size of the data EBS volume in GB"
  type        = number
  default     = 20
}

variable "redis_version" {
  description = "Redis Docker image version"
  type        = string
  default     = "7.2"
}
