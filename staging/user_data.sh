#!/bin/bash
set -e

# 로그 파일 설정
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting user data script..."

# 시스템 업데이트
apt update -y
apt upgrade -y

# Java 21 설치
apt install -y openjdk-21-jdk

# MySQL 설치
apt install -y mysql-server
systemctl start mysql
systemctl enable mysql

# Redis 설치
apt install -y redis-server
systemctl start redis-server
systemctl enable redis-server

# Nginx 설치
apt install -y nginx

# 프론트엔드 디렉토리 생성
mkdir -p /var/www/frontend
chown -R ubuntu:ubuntu /var/www/frontend

# 애플리케이션 디렉토리 생성
mkdir -p /app
chown -R ubuntu:ubuntu /app

# 환경 변수 파일 생성
cat > /app/.env << 'ENVEOF'
S3_BUCKET=${s3_bucket}
DB_HOST=localhost
DB_PORT=3306
DB_NAME=klosetlab
DB_USER=root
DB_PASSWORD=your-secure-password
REDIS_HOST=localhost
REDIS_PORT=6379
ENVEOF

chown ubuntu:ubuntu /app/.env

# Nginx 설정 파일 생성 (HTTP만, certbot이 HTTPS 자동 추가)
cat > /etc/nginx/sites-available/staging.conf << 'EOF'
server {
    listen 80 default_server;
    server_name _;

    root /var/www/frontend;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://localhost:8080/;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto http;
    }
}
EOF

# Nginx 설정 활성화
ln -s /etc/nginx/sites-available/staging.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Nginx 설정 테스트 및 리로드
nginx -t && systemctl reload nginx

echo "User data script completed!"
echo ""
echo "=========================================="
echo "다음 단계를 수동으로 진행하세요:"
echo "=========================================="
echo "1. SSH 접속:"
echo "   ssh -i your-key.pem ubuntu@$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo ""
echo "MySQL root password: your-secure-password"
echo "Database: klosetlab"
echo "=========================================="