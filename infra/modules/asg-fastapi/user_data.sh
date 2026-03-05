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

# Install node_exporter
NODE_EXPORTER_VERSION="1.7.0"
curl -fsSL "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" -o /tmp/node_exporter.tar.gz
tar xzf /tmp/node_exporter.tar.gz -C /tmp/
mv /tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
rm -rf /tmp/node_exporter*
useradd -rs /bin/false node_exporter || true

cat > /etc/systemd/system/node_exporter.service <<'SYSTEMD_EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# Run cAdvisor
docker run -d \
  --name cadvisor \
  --restart unless-stopped \
  --volume /:/rootfs:ro \
  --volume /var/run:/var/run:ro \
  --volume /sys:/sys:ro \
  --volume /var/lib/docker/:/var/lib/docker:ro \
  --publish 8888:8080 \
  gcr.io/cadvisor/cadvisor:v0.47.2

# Login to ECR
aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${ecr_registry}

# Create fastapi directory
mkdir -p /opt/fastapi

# Download env file from S3 (if exists)
aws s3 cp s3://${config_bucket}/${env_file_key} /opt/fastapi/.env || echo "No env file found, using defaults"

# Create docker-compose file
cat > /opt/fastapi/docker-compose.yml <<EOF
version: '3.8'
services:
  fastapi:
    image: ${ecr_registry}/${ecr_repo_name}:${image_tag}
    container_name: fastapi
    restart: unless-stopped
    ports:
      - "${fastapi_port}:${fastapi_port}"
    env_file:
      - .env
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
EOF

# Start FastAPI application
cd /opt/fastapi
docker compose up -d
