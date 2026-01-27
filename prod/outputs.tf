output "ec2_public_ip" {
  description = "EC2 Instance Public IP"
  value       = aws_instance.web.public_ip
}

output "ec2_instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.web.id
}

output "s3_bucket_name" {
  description = "S3 Bucket Name"
  value       = aws_s3_bucket.app_storage.id
}

output "security_group_id" {
  description = "Security Group ID"
  value       = aws_security_group.web.id
}

output "ssh_command" {
  description = "SSH command to connect to EC2"
  value       = "ssh -i ${var.key_name}.pem ubuntu@${aws_instance.web.public_ip}"
}

output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT
    ========================================
    배포 완료! 다음 단계를 진행하세요:
    ========================================
    
    1. DNS 설정:
       도메인: ${var.domain_name}
       A 레코드: ${aws_instance.web.public_ip}
    
    2. SSH 접속:
       ssh -i ${var.key_name}.pem ubuntu@${aws_instance.web.public_ip}
    
    3. SSL 인증서 발급 (SSH 접속 후):
       sudo certbot --nginx -d ${var.domain_name}
    
    4. 프론트엔드 배포:
       /var/www/frontend 에 빌드 파일 업로드
    
    5. Spring Boot 배포:
       /app 디렉토리에 jar 파일 배포
    
    MySQL 정보:
    - Host: localhost
    - Port: 3306
    - Database: klosetlab
    - User: root
    - Password: your-secure-password (변경 필요!)
    
    Redis:
    - Host: localhost
    - Port: 6379
    ========================================
  EOT
}

output "s3_bucket_url" {
  description = "S3 Bucket Public URL"
  value       = "https://${aws_s3_bucket.app_storage.bucket}.s3.${var.aws_region}.amazonaws.com"
}