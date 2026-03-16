# ========== Bastion / NAT Security Group ==========

resource "aws_security_group" "bastion_nat" {
  name        = "${var.project_name}-bastion-nat-sg"
  description = "Bastion and NAT instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # private subnet에서 오는 모든 트래픽 허용 (NAT 포워딩)
  ingress {
    description = "All traffic from VPC private subnets (NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-bastion-nat-sg"
  }
}

# ========== Master Node Security Group ==========
# 순환 참조 방지: master <-> worker 간 cross-reference는
# 아래 aws_security_group_rule 리소스로 별도 정의

resource "aws_security_group" "master" {
  name        = "${var.project_name}-master-sg"
  description = "Kubernetes master node"
  vpc_id      = aws_vpc.main.id

  # SSH via bastion
  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_nat.id]
  }

  # Kubernetes API Server (kubectl, worker join 등)
  ingress {
    description = "Kubernetes API Server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # etcd (master 자기 자신)
  ingress {
    description = "etcd server client API (self)"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
  }

  # kubelet API (master self)
  ingress {
    description = "kubelet API (self)"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  # Calico BGP (master self)
  ingress {
    description = "Calico BGP (self)"
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    self        = true
  }

  # Calico IPIP (master self) - protocol 4
  ingress {
    description = "Calico IPIP (self)"
    from_port   = -1
    to_port     = -1
    protocol    = "4"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    ignore_changes = [ingress]
  }

  tags = {
    Name = "${var.project_name}-master-sg"
  }
}

# ========== Worker Node Security Group ==========

resource "aws_security_group" "worker" {
  name        = "${var.project_name}-worker-sg"
  description = "Kubernetes worker node"
  vpc_id      = aws_vpc.main.id

  # SSH via bastion
  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_nat.id]
  }

  # NodePort Services
  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Calico BGP (worker self)
  ingress {
    description = "Calico BGP (self)"
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    self        = true
  }

  # Calico IPIP (worker self) - protocol 4
  ingress {
    description = "Calico IPIP (self)"
    from_port   = -1
    to_port     = -1
    protocol    = "4"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    ignore_changes = [ingress]
  }

  tags = {
    Name = "${var.project_name}-worker-sg"
  }
}

# ========== Cross-reference Rules (master <-> worker) ==========

# master가 worker로부터 kubelet API 허용
resource "aws_security_group_rule" "master_kubelet_from_worker" {
  type                     = "ingress"
  description              = "kubelet API from workers"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.worker.id
  security_group_id        = aws_security_group.master.id
}

# master가 worker로부터 Calico BGP 허용
resource "aws_security_group_rule" "master_bgp_from_worker" {
  type                     = "ingress"
  description              = "Calico BGP from workers"
  from_port                = 179
  to_port                  = 179
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.worker.id
  security_group_id        = aws_security_group.master.id
}

# master가 worker로부터 Calico IPIP 허용
resource "aws_security_group_rule" "master_ipip_from_worker" {
  type                     = "ingress"
  description              = "Calico IPIP from workers"
  from_port                = -1
  to_port                  = -1
  protocol                 = "4"
  source_security_group_id = aws_security_group.worker.id
  security_group_id        = aws_security_group.master.id
}

# worker가 master로부터 kubelet API 허용
resource "aws_security_group_rule" "worker_kubelet_from_master" {
  type                     = "ingress"
  description              = "kubelet API from master"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.master.id
  security_group_id        = aws_security_group.worker.id
}

# worker가 master로부터 Calico BGP 허용
resource "aws_security_group_rule" "worker_bgp_from_master" {
  type                     = "ingress"
  description              = "Calico BGP from master"
  from_port                = 179
  to_port                  = 179
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.master.id
  security_group_id        = aws_security_group.worker.id
}

# worker가 master로부터 Calico IPIP 허용
resource "aws_security_group_rule" "worker_ipip_from_master" {
  type                     = "ingress"
  description              = "Calico IPIP from master"
  from_port                = -1
  to_port                  = -1
  protocol                 = "4"
  source_security_group_id = aws_security_group.master.id
  security_group_id        = aws_security_group.worker.id
}

# ========== Calico Typha (port 5473) ==========
# Typha는 임의 노드에서 실행되며, 모든 calico-node가 연결

# worker가 worker로부터 Typha 허용 (worker간 Typha 접근)
resource "aws_security_group_rule" "worker_typha_from_worker" {
  type              = "ingress"
  description       = "Calico Typha from workers"
  from_port         = 5473
  to_port           = 5473
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.worker.id
}

# worker가 master로부터 Typha 허용 (master의 calico-node → worker의 Typha)
resource "aws_security_group_rule" "worker_typha_from_master" {
  type                     = "ingress"
  description              = "Calico Typha from master"
  from_port                = 5473
  to_port                  = 5473
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.master.id
  security_group_id        = aws_security_group.worker.id
}

# master가 worker로부터 Typha 허용 (worker의 calico-node → master의 Typha)
resource "aws_security_group_rule" "master_typha_from_worker" {
  type                     = "ingress"
  description              = "Calico Typha from workers"
  from_port                = 5473
  to_port                  = 5473
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.worker.id
  security_group_id        = aws_security_group.master.id
}

# master가 master로부터 Typha 허용 (master self)
resource "aws_security_group_rule" "master_typha_from_master" {
  type              = "ingress"
  description       = "Calico Typha (self)"
  from_port         = 5473
  to_port           = 5473
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.master.id
}
