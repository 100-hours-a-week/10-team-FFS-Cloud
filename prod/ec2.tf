resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = var.key_name
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  user_data = templatefile("${path.module}/user_data.sh", {
    s3_bucket   = aws_s3_bucket.app_storage.id
    domain_name = var.domain_name
  })

  tags = {
    Name = "klosetlab-ec2"
  }
}