variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "klosetlab"
}

variable "key_name" {
  description = "EC2 key pair name"
  type        = string
  default     = "klosetlab-key"
}

variable "ubuntu_ami" {
  description = "Ubuntu 24.04 AMI ID (ap-northeast-2)"
  type        = string
  default     = "ami-04f851a80be515079"
}

# VPC
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_a_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "public_subnet_c_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "private_subnet_a_cidr" {
  type    = string
  default = "10.0.11.0/24"
}

variable "private_subnet_c_cidr" {
  type    = string
  default = "10.0.12.0/24"
}

# Kubernetes Nodes
variable "master_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "worker_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "bastion_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "master_volume_size" {
  type    = number
  default = 20
}

variable "worker_volume_size" {
  type    = number
  default = 30
}
