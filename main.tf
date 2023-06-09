provider "aws" {
  region = "ap-south-1"
}

variable "vpc-cidr-block" {}
variable "subnet-cidr-block" {}
variable "availability_zone" {}
variable "env_prefix" {}
variable "ip-address" {}
variable "instance-type" {}
variable "public-key-path" {}

resource "aws_vpc" "myapp-vpc" {
  cidr_block = var.vpc-cidr-block
  tags = {
    Name = "${var.env_prefix}-vpc"
  }
}

resource "aws_subnet" "myapp-subnet" {
  vpc_id            = aws_vpc.myapp-vpc.id
  cidr_block        = var.subnet-cidr-block
  availability_zone = var.availability_zone
  tags = {
    Name = "${var.env_prefix}-subnet"
  }
}

resource "aws_internet_gateway" "myapp-internet-gateway" {
  vpc_id = aws_vpc.myapp-vpc.id
  tags = {
    Name = "${var.env_prefix}-internet-gateway"
  }
}

resource "aws_default_route_table" "main-route-table" {
  default_route_table_id = aws_vpc.myapp-vpc.default_route_table_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.myapp-internet-gateway.id
  }
  tags = {
    Name = "${var.env_prefix}-main-route-table"
  }
}

resource "aws_security_group" "Jenkins-security-group" {
  name   = "Jenkins-security-group"
  vpc_id = aws_vpc.myapp-vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ip-address]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
    prefix_list_ids = []
  }

  tags = {
    Name = "Jenkins-${var.env_prefix}-security-group"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

output "aws-ami-id" {
  value = data.aws_ami.ubuntu.id
}

output "ec-2-public-ip" {
  value = aws_instance.myapp-server.public_ip
}

resource "aws_key_pair" "ssh-key" {
  key_name   = "server-key"
  public_key = file(var.public-key-path)
}

resource "aws_instance" "myapp-server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance-type

  subnet_id                   = aws_subnet.myapp-subnet.id
  vpc_security_group_ids      = [aws_security_group.Jenkins-security-group.id]
  availability_zone           = var.availability_zone
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ssh-key.key_name

  # user_data = file("entry-script.sh")     

  tags = {
    Name = "Jenkins-${var.env_prefix}-server"
  }
}

resource "null_resource" "update_hosts_file" {
  provisioner "local-exec" {
    command = "truncate -s 0 hosts && echo -n '${aws_instance.myapp-server.public_ip} ansible_user=ubuntu' >> hosts"
  }
}