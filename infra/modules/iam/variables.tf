variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "config_bucket_name" {
  description = "Name of the S3 bucket for configuration files"
  type        = string
}

variable "app_storage_bucket_name" {
  description = "Name of the S3 bucket for app file storage (image uploads)"
  type        = string
}
