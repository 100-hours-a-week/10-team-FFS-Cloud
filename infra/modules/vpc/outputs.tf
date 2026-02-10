#######################################
# VPC
#######################################
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

#######################################
# Internet Gateway
#######################################
output "igw_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

#######################################
# NAT Gateway
#######################################
output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = aws_nat_gateway.main.id
}

output "nat_gateway_eip" {
  description = "Elastic IP of the NAT Gateway"
  value       = aws_eip.nat.public_ip
}

#######################################
# Public Subnets
#######################################
output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = { for k, v in aws_subnet.public : k => v.id }
}

output "public_subnet_ids_list" {
  description = "List of public subnet IDs"
  value       = [for k, v in aws_subnet.public : v.id]
}

#######################################
# Private App Subnets
#######################################
output "private_app_subnet_ids" {
  description = "IDs of the private app subnets"
  value       = { for k, v in aws_subnet.private_app : k => v.id }
}

output "private_app_subnet_ids_list" {
  description = "List of private app subnet IDs"
  value       = [for k, v in aws_subnet.private_app : v.id]
}

#######################################
# Private Data Subnets
#######################################
output "private_data_subnet_ids" {
  description = "IDs of the private data subnets"
  value       = { for k, v in aws_subnet.private_data : k => v.id }
}

output "private_data_subnet_ids_list" {
  description = "List of private data subnet IDs"
  value       = [for k, v in aws_subnet.private_data : v.id]
}

#######################################
# Route Tables
#######################################
output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_app_route_table_id" {
  description = "ID of the private app route table"
  value       = aws_route_table.private_app.id
}

output "private_data_route_table_id" {
  description = "ID of the private data route table"
  value       = aws_route_table.private_data.id
}
