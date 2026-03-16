#!/bin/bash
# =============================================================
# Terraform Import Script
# 콘솔에서 이미 만들어진 리소스를 Terraform state로 가져오기
#
# 실행 전: terraform init 먼저 실행
# 실행법:  bash import.sh
# =============================================================

set -e

cd "$(dirname "$0")"

echo ">>> terraform init"
terraform init

echo ""
echo ">>> [1/2] 기존 리소스 import 시작"

# VPC
terraform import aws_vpc.main vpc-0f6928d4485cfc8ca

# Internet Gateway
terraform import aws_internet_gateway.main igw-00b8ed93bba5ac82c

# Subnets
terraform import aws_subnet.public_a  subnet-05e5c084cc97bd0cd
terraform import aws_subnet.public_c  subnet-0f020d97719a533e5
terraform import aws_subnet.private_a subnet-0ed37a305c0ccb91f
terraform import aws_subnet.private_c subnet-0886702af997ab8e2

# Route Tables
terraform import aws_route_table.public  rtb-0957f50e35ef1beaf
terraform import aws_route_table.private rtb-0b0d52658e33856cc

# Route (public 라우팅 테이블의 인터넷 경로)
terraform import 'aws_route.public_internet' rtb-0957f50e35ef1beaf_0.0.0.0/0

# Route Table Associations (public 서브넷 - 이미 연결된 것만)
terraform import 'aws_route_table_association.public_a' subnet-05e5c084cc97bd0cd/rtb-0957f50e35ef1beaf
terraform import 'aws_route_table_association.public_c' subnet-0f020d97719a533e5/rtb-0957f50e35ef1beaf

# K8s Nodes (master-1, worker-1)
terraform import aws_instance.master_1 i-0c4db7b27b235a4d0
terraform import aws_instance.worker_1 i-0c1660d0ba9e182ab

echo ""
echo ">>> [2/2] import 완료"
echo ""
echo "================================================================"
echo " 다음 단계:"
echo ""
echo " 1. 콘솔에서 기존 worker-2 종료 (default VPC)"
echo "    Instance ID: i-0ad6cfdf7c6e3b0a1"
echo ""
echo " 2. terraform plan  → 변경 내용 확인"
echo "    예상 변경사항:"
echo "    - bastion_nat 인스턴스 신규 생성"
echo "    - worker-2 신규 생성 (klosetlab-vpc private-a)"
echo "    - master/worker 보안그룹 교체 (새 SG로)"
echo "    - private route table에 NAT 경로 추가"
echo "    - private 서브넷 route table association 추가"
echo ""
echo " 3. terraform apply"
echo "================================================================"
