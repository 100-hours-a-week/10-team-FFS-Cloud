variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Bastion Host"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "subnet_id" {
  description = "ID of the public subnet for Bastion Host"
  type        = string
}

variable "security_group_id" {
  description = "ID of the Bastion security group"
  type        = string
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 8
}

variable "use_elastic_ip" {
  description = "Whether to assign an Elastic IP to Bastion"
  type        = bool
  default     = true
}
