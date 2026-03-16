output "bastion_nat_public_ip" {
  description = "Bastion/NAT 인스턴스 공인 IP (SSH 접근 및 NAT 출발지)"
  value       = aws_eip.bastion_nat.public_ip
}

output "master_1_private_ip" {
  description = "Master 노드 사설 IP"
  value       = aws_instance.master_1.private_ip
}

output "worker_1_private_ip" {
  description = "Worker-1 노드 사설 IP"
  value       = aws_instance.worker_1.private_ip
}

output "worker_2_private_ip" {
  description = "Worker-2 노드 사설 IP"
  value       = aws_instance.worker_2.private_ip
}

output "k8s_api_endpoint" {
  description = "Kubernetes API Server 엔드포인트"
  value       = "https://${aws_instance.master_1.private_ip}:6443"
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private 서브넷 ID 목록"
  value       = [aws_subnet.private_a.id, aws_subnet.private_c.id]
}

output "public_subnet_ids" {
  description = "Public 서브넷 ID 목록"
  value       = [aws_subnet.public_a.id, aws_subnet.public_c.id]
}
