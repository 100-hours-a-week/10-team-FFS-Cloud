# Bastion + NAT 인스턴스
# - public subnet에 위치
# - source_dest_check = false (NAT 동작에 필수)
# - user_data로 IP forwarding + iptables MASQUERADE 설정
# - EIP로 고정 공인 IP 부여

resource "aws_eip" "bastion_nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-bastion-nat-eip"
  }
}

resource "aws_instance" "bastion_nat" {
  ami                    = var.ubuntu_ami
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.public_a.id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.bastion_nat.id]
  source_dest_check      = false # NAT 동작 필수

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # IP 포워딩 활성화
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p

    # 실제 인터페이스명 동적 감지 (Ubuntu 24.04는 ens5 사용)
    IFACE=$(ip route | grep default | awk '{print $5}' | head -1)

    # iptables MASQUERADE (NAT)
    iptables -t nat -A POSTROUTING -s 10.0.0.0/16 -o $IFACE -j MASQUERADE
    iptables -A FORWARD -i $IFACE -o $IFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -s 10.0.0.0/16 -o $IFACE -j ACCEPT

    # iptables 규칙 영구 저장
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
    netfilter-persistent save
  EOF

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  tags = {
    Name = "${var.project_name}-bastion-nat"
    Role = "bastion-nat"
  }
}

resource "aws_eip_association" "bastion_nat" {
  instance_id   = aws_instance.bastion_nat.id
  allocation_id = aws_eip.bastion_nat.id
}
