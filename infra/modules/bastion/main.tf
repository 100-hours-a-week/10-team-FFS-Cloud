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
# Bastion Host EC2 Instance
#######################################
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "${var.project_name}-bastion"
  }
}

#######################################
# Elastic IP for Bastion (Optional but recommended)
#######################################
resource "aws_eip" "bastion" {
  count  = var.use_elastic_ip ? 1 : 0
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-bastion-eip"
  }
}

resource "aws_eip_association" "bastion" {
  count         = var.use_elastic_ip ? 1 : 0
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion[0].id
}
