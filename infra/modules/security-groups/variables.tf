variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "bastion_allowed_cidrs" {
  description = "List of CIDR blocks allowed to SSH into Bastion"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "app_port" {
  description = "Port for Spring Application server"
  type        = number
  default     = 8080
}

variable "chat_port" {
  description = "Port for Spring Chat server"
  type        = number
  default     = 8081
}

variable "fastapi_port" {
  description = "Port for FastAPI server"
  type        = number
  default     = 8000
}
