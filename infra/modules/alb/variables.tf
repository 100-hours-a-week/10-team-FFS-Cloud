variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
}

variable "security_group_id" {
  description = "ID of the ALB security group"
  type        = string
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate (empty for HTTP only)"
  type        = string
  default     = ""
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

variable "app_health_check_path" {
  description = "Health check path for App server"
  type        = string
  default     = "/actuator/health"
}

variable "chat_health_check_path" {
  description = "Health check path for Chat server"
  type        = string
  default     = "/actuator/health"
}

variable "fastapi_health_check_path" {
  description = "Health check path for FastAPI server"
  type        = string
  default     = "/health"
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for ALB"
  type        = bool
  default     = false
}

variable "idle_timeout" {
  description = "Idle timeout in seconds (increase for WebSocket)"
  type        = number
  default     = 60
}
