variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "Public subnets configuration (Tier 1)"
  type = map(object({
    cidr = string
    az   = string
  }))
  default = {
    a = {
      cidr = "10.0.1.0/24"
      az   = "ap-northeast-2a"
    }
    c = {
      cidr = "10.0.2.0/24"
      az   = "ap-northeast-2c"
    }
  }
}

variable "private_app_subnets" {
  description = "Private App subnets configuration (Tier 2)"
  type = map(object({
    cidr = string
    az   = string
  }))
  default = {
    a = {
      cidr = "10.0.11.0/24"
      az   = "ap-northeast-2a"
    }
    c = {
      cidr = "10.0.12.0/24"
      az   = "ap-northeast-2c"
    }
  }
}

variable "private_data_subnets" {
  description = "Private Data subnets configuration (Tier 3)"
  type = map(object({
    cidr = string
    az   = string
  }))
  default = {
    a = {
      cidr = "10.0.21.0/24"
      az   = "ap-northeast-2a"
    }
    c = {
      cidr = "10.0.22.0/24"
      az   = "ap-northeast-2c"
    }
  }
}
