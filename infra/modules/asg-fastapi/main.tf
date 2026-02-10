#######################################
# Data Source - Ubuntu 22.04 LTS AMI
#######################################
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

#######################################
# Launch Template
#######################################
resource "aws_launch_template" "fastapi" {
  name_prefix   = "${var.project_name}-fastapi-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [var.security_group_id]

  iam_instance_profile {
    name = var.instance_profile_name
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    aws_region     = var.aws_region
    ecr_registry   = var.ecr_registry
    ecr_repo_name  = var.ecr_repo_name
    image_tag      = var.image_tag
    fastapi_port   = var.fastapi_port
    config_bucket  = var.config_bucket
    env_file_key   = var.env_file_key
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-fastapi"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

#######################################
# Auto Scaling Group
#######################################
resource "aws_autoscaling_group" "fastapi" {
  name                = "${var.project_name}-fastapi-asg"
  desired_capacity    = var.desired_capacity
  min_size            = var.min_size
  max_size            = var.max_size
  vpc_zone_identifier = var.subnet_ids
  target_group_arns   = [var.target_group_arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.fastapi.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-fastapi"
    propagate_at_launch = true
  }
}

#######################################
# Auto Scaling Policies
#######################################
resource "aws_autoscaling_policy" "fastapi_scale_up" {
  name                   = "${var.project_name}-fastapi-scale-up"
  autoscaling_group_name = aws_autoscaling_group.fastapi.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_autoscaling_policy" "fastapi_scale_down" {
  name                   = "${var.project_name}-fastapi-scale-down"
  autoscaling_group_name = aws_autoscaling_group.fastapi.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

#######################################
# CloudWatch Alarms for Scaling
#######################################
resource "aws_cloudwatch_metric_alarm" "fastapi_cpu_high" {
  alarm_name          = "${var.project_name}-fastapi-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = var.cpu_scale_up_threshold
  alarm_description   = "Scale up if CPU > ${var.cpu_scale_up_threshold}%"
  alarm_actions       = [aws_autoscaling_policy.fastapi_scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.fastapi.name
  }
}

resource "aws_cloudwatch_metric_alarm" "fastapi_cpu_low" {
  alarm_name          = "${var.project_name}-fastapi-cpu-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = var.cpu_scale_down_threshold
  alarm_description   = "Scale down if CPU < ${var.cpu_scale_down_threshold}%"
  alarm_actions       = [aws_autoscaling_policy.fastapi_scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.fastapi.name
  }
}
