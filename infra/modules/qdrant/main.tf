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
# EBS Volume for Qdrant Data
#######################################
resource "aws_ebs_volume" "qdrant_data" {
  availability_zone = var.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "${var.project_name}-qdrant-data"
  }
}

#######################################
# Qdrant EC2 Instance
#######################################
resource "aws_instance" "qdrant" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    qdrant_version  = var.qdrant_version
    data_device     = "/dev/xvdf"
    data_mount_path = "/data/qdrant"
  }))

  tags = {
    Name = "${var.project_name}-qdrant"
  }
}

#######################################
# Attach EBS Volume
#######################################
resource "aws_volume_attachment" "qdrant_data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.qdrant_data.id
  instance_id = aws_instance.qdrant.id
}
