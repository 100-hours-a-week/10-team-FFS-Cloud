#!/bin/bash
set -e

# Install Docker
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common unzip
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Start Docker
systemctl enable docker
systemctl start docker

# Login to ECR
aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${ecr_registry}

# Create chat directory
mkdir -p /opt/chat

# Download env file from S3 (if exists)
aws s3 cp s3://${config_bucket}/${env_file_key} /opt/chat/.env || echo "No env file found, using defaults"

# Create docker-compose file
cat > /opt/chat/docker-compose.yml <<EOF
version: '3.8'
services:
  chat:
    image: ${ecr_registry}/${ecr_repo_name}:${image_tag}
    container_name: chat
    restart: unless-stopped
    ports:
      - "${chat_port}:${chat_port}"
    env_file:
      - .env
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
EOF

# Start chat application
cd /opt/chat
docker compose up -d
