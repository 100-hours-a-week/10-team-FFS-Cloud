#######################################
# VPC
#######################################
module "vpc" {
  source = "../../modules/vpc"

  project_name = var.project_name
}

#######################################
# Security Groups
#######################################
module "security_groups" {
  source = "../../modules/security-groups"

  project_name          = var.project_name
  vpc_id                = module.vpc.vpc_id
  bastion_allowed_cidrs = var.bastion_allowed_cidrs
}

#######################################
# Bastion Host
#######################################
module "bastion" {
  source = "../../modules/bastion"

  project_name      = var.project_name
  key_name          = var.key_name
  subnet_id         = module.vpc.public_subnet_ids["a"]
  security_group_id = module.security_groups.bastion_sg_id
  use_elastic_ip    = true
}

#######################################
# ECR
#######################################
module "ecr" {
  source = "../../modules/ecr"

  project_name = var.project_name
}

#######################################
# IAM
#######################################
module "iam" {
  source = "../../modules/iam"

  project_name       = var.project_name
  config_bucket_name = module.s3_cloudfront.config_bucket_name
}

#######################################
# RDS
#######################################
module "rds" {
  source = "../../modules/rds"

  project_name      = var.project_name
  subnet_ids        = module.vpc.private_data_subnet_ids_list
  security_group_id = module.security_groups.rds_sg_id
  db_password       = var.db_password
  instance_class    = "db.t3.micro"
  skip_final_snapshot = true
}

#######################################
# MongoDB
#######################################
module "mongodb" {
  source = "../../modules/mongodb"

  project_name      = var.project_name
  key_name          = var.key_name
  subnet_id         = module.vpc.private_data_subnet_ids["a"]
  security_group_id = module.security_groups.mongodb_sg_id
  availability_zone = "ap-northeast-2a"
  instance_type     = "t3.small"
}

#######################################
# Qdrant
#######################################
module "qdrant" {
  source = "../../modules/qdrant"

  project_name      = var.project_name
  key_name          = var.key_name
  subnet_id         = module.vpc.private_data_subnet_ids["a"]
  security_group_id = module.security_groups.qdrant_sg_id
  availability_zone = "ap-northeast-2a"
  instance_type     = "t3.small"
}

#######################################
# Redis
#######################################
module "redis" {
  source = "../../modules/redis"

  project_name      = var.project_name
  key_name          = var.key_name
  subnet_id         = module.vpc.private_data_subnet_ids["a"]
  security_group_id = module.security_groups.redis_sg_id
  availability_zone = "ap-northeast-2a"
  instance_type     = "t3.small"
}

#######################################
# S3 + CloudFront (Staging: CloudFront disabled)
#######################################
module "s3_cloudfront" {
  source = "../../modules/s3-cloudfront"

  project_name      = var.project_name
  bucket_name       = "${var.project_name}-frontend"
  enable_cloudfront = false
}

#######################################
# ALB
#######################################
module "alb" {
  source = "../../modules/alb"

  project_name      = var.project_name
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.public_subnet_ids_list
  security_group_id = module.security_groups.alb_sg_id
  certificate_arn   = ""  # No SSL for staging
}

#######################################
# ASG - App
#######################################
module "asg_app" {
  source = "../../modules/asg-app"

  project_name          = var.project_name
  key_name              = var.key_name
  security_group_id     = module.security_groups.app_sg_id
  instance_profile_name = module.iam.instance_profile_name
  subnet_ids            = module.vpc.private_app_subnet_ids_list
  target_group_arn      = module.alb.app_target_group_arn
  ecr_registry          = split("/", module.ecr.repository_urls["app"])[0]
  ecr_repo_name         = "${var.project_name}-app"
  config_bucket         = module.s3_cloudfront.config_bucket_name
  instance_type         = "t3.small"
  min_size              = 1
  max_size              = 2
}

#######################################
# ASG - Chat
#######################################
module "asg_chat" {
  source = "../../modules/asg-chat"

  project_name          = var.project_name
  key_name              = var.key_name
  security_group_id     = module.security_groups.chat_sg_id
  instance_profile_name = module.iam.instance_profile_name
  subnet_ids            = module.vpc.private_app_subnet_ids_list
  target_group_arn      = module.alb.chat_target_group_arn
  ecr_registry          = split("/", module.ecr.repository_urls["chat"])[0]
  ecr_repo_name         = "${var.project_name}-chat"
  config_bucket         = module.s3_cloudfront.config_bucket_name
  instance_type         = "t3.small"
  min_size              = 1
  max_size              = 2
}

#######################################
# ASG - FastAPI
#######################################
module "asg_fastapi" {
  source = "../../modules/asg-fastapi"

  project_name          = var.project_name
  key_name              = var.key_name
  security_group_id     = module.security_groups.fastapi_sg_id
  instance_profile_name = module.iam.instance_profile_name
  subnet_ids            = module.vpc.private_app_subnet_ids_list
  target_group_arn      = module.alb.fastapi_target_group_arn
  ecr_registry          = split("/", module.ecr.repository_urls["fastapi"])[0]
  ecr_repo_name         = "${var.project_name}-fastapi"
  config_bucket         = module.s3_cloudfront.config_bucket_name
  instance_type         = "t3.small"
  min_size              = 1
  max_size              = 2
}
