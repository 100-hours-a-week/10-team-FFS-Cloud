#######################################
# Application Load Balancer
#######################################
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.subnet_ids

  enable_deletion_protection = var.enable_deletion_protection
  idle_timeout               = var.idle_timeout

  tags = {
    Name = "${var.project_name}-alb"
  }
}

#######################################
# Target Groups
#######################################

# App Target Group (Spring API)
resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-app-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = var.app_health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.project_name}-app-tg"
  }
}

# Chat Target Group (Spring Chat - WebSocket)
resource "aws_lb_target_group" "chat" {
  name     = "${var.project_name}-chat-tg"
  port     = var.chat_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = var.chat_health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.project_name}-chat-tg"
  }
}

# FastAPI Target Group
resource "aws_lb_target_group" "fastapi" {
  name     = "${var.project_name}-fastapi-tg"
  port     = var.fastapi_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = var.fastapi_health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.project_name}-fastapi-tg"
  }
}

#######################################
# HTTP Listener (Redirect to HTTPS) - Only when SSL is enabled
#######################################
resource "aws_lb_listener" "http" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

#######################################
# HTTPS Listener
#######################################
resource "aws_lb_listener" "https" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

#######################################
# Listener Rules
#######################################

# Chat server rule (/ws/*)
resource "aws_lb_listener_rule" "chat" {
  count = var.certificate_arn != "" ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.chat.arn
  }

  condition {
    path_pattern {
      values = ["/ws/*"]
    }
  }
}

# FastAPI server rule (/ai/*)
resource "aws_lb_listener_rule" "fastapi" {
  count = var.certificate_arn != "" ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.fastapi.arn
  }

  condition {
    path_pattern {
      values = ["/ai/*"]
    }
  }
}

#######################################
# HTTP-only Listener (for staging without SSL)
#######################################
resource "aws_lb_listener" "http_only" {
  count = var.certificate_arn == "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_listener_rule" "chat_http" {
  count = var.certificate_arn == "" ? 1 : 0

  listener_arn = aws_lb_listener.http_only[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.chat.arn
  }

  condition {
    path_pattern {
      values = ["/ws/*"]
    }
  }
}

resource "aws_lb_listener_rule" "fastapi_http" {
  count = var.certificate_arn == "" ? 1 : 0

  listener_arn = aws_lb_listener.http_only[0].arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.fastapi.arn
  }

  condition {
    path_pattern {
      values = ["/ai/*"]
    }
  }
}
