output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the ALB"
  value       = aws_lb.main.zone_id
}

output "app_target_group_arn" {
  description = "ARN of the App target group"
  value       = aws_lb_target_group.app.arn
}

output "chat_target_group_arn" {
  description = "ARN of the Chat target group"
  value       = aws_lb_target_group.chat.arn
}

output "fastapi_target_group_arn" {
  description = "ARN of the FastAPI target group"
  value       = aws_lb_target_group.fastapi.arn
}
