#!/bin/bash
set -e

# Wait for EBS volume to be attached
while [ ! -e ${data_device} ]; do
  sleep 1
done

# Format and mount EBS volume (only if not already formatted)
if ! blkid ${data_device}; then
  mkfs -t ext4 ${data_device}
fi

mkdir -p ${data_mount_path}
mount ${data_device} ${data_mount_path}

# Add to fstab for persistence
echo "${data_device} ${data_mount_path} ext4 defaults,nofail 0 2" >> /etc/fstab

# Install Docker
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start Docker
systemctl enable docker
systemctl start docker

# Create docker-compose file
mkdir -p /opt/mongodb
cat > /opt/mongodb/docker-compose.yml <<EOF
version: '3.8'
services:
  mongodb:
    image: mongo:${mongodb_version}
    container_name: mongodb
    restart: unless-stopped
    ports:
      - "27017:27017"
    volumes:
      - ${data_mount_path}:/data/db
    environment:
      - MONGO_INITDB_ROOT_USERNAME=admin
      - MONGO_INITDB_ROOT_PASSWORD=changeme
EOF

# Start MongoDB
cd /opt/mongodb
docker compose up -d
