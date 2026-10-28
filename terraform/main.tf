
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# Latest Amazon Linux 2023 image
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# Public key of the key pair created on the control machine
resource "aws_key_pair" "k3s" {
  key_name   = "devops-k3s"
  public_key = file(pathexpand("~/.ssh/devops-k3s.pub"))
}

# Firewall: SSH allowed only from inside the VPC
resource "aws_security_group" "k3s" {
  name        = "devops-k3s-sg"
  description = "SSH from inside the VPC only"

  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "devops-k3s-sg"
  }
}

# The server where k3s (Kubernetes) will run
resource "aws_instance" "k3s" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "c7i-flex.large"
  availability_zone      = "ap-south-1b"
  key_name               = aws_key_pair.k3s.key_name
  vpc_security_group_ids = [aws_security_group.k3s.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "devops-k3s"
  }
}

output "k3s_private_ip" {
  value = aws_instance.k3s.private_ip
}

