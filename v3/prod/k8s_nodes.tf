# ========== Master Node ==========
# import: terraform import aws_instance.master_1 i-0c4db7b27b235a4d0

resource "aws_instance" "master_1" {
  ami                    = var.ubuntu_ami
  instance_type          = var.master_instance_type
  subnet_id              = aws_subnet.private_a.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.master.id]

  root_block_device {
    volume_type = "gp3"
    volume_size = var.master_volume_size
  }

  tags = {
    Name = "${var.project_name}-master-1"
    Role = "master"
  }
}

# ========== Worker Node 1 ==========
# import: terraform import aws_instance.worker_1 i-0c1660d0ba9e182ab

resource "aws_instance" "worker_1" {
  ami                    = var.ubuntu_ami
  instance_type          = var.worker_instance_type
  subnet_id              = aws_subnet.private_c.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.worker.id]

  root_block_device {
    volume_type = "gp3"
    volume_size = var.worker_volume_size
  }

  tags = {
    Name = "${var.project_name}-worker-1"
    Role = "worker"
  }
}

# ========== Worker Node 2 ==========
# 기존 worker-2는 default VPC에 있어 새로 생성
# 콘솔에서 기존 worker-2 (i-0ad6cfdf7c6e3b0a1) 먼저 종료 후 apply

resource "aws_instance" "worker_2" {
  ami                    = var.ubuntu_ami
  instance_type          = var.worker_instance_type
  subnet_id              = aws_subnet.private_a.id # AZ 분산: worker-1(c) / worker-2(a)
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.worker.id]

  root_block_device {
    volume_type = "gp3"
    volume_size = var.worker_volume_size
  }

  tags = {
    Name = "${var.project_name}-worker-2"
    Role = "worker"
  }
}
