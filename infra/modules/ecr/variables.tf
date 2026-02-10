variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "repository_names" {
  description = "List of ECR repository names to create"
  type        = list(string)
  default     = ["app", "chat", "fastapi"]
}

variable "image_tag_mutability" {
  description = "Image tag mutability setting (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "enable_lifecycle_policy" {
  description = "Enable lifecycle policy to clean up old images"
  type        = bool
  default     = true
}

variable "max_image_count" {
  description = "Maximum number of images to keep per repository"
  type        = number
  default     = 10
}
