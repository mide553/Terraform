###############################################
# AWS Provider
###############################################
provider "aws" {
  region     = "us-east-1"
  access_key = var.aws_access_key_id
  secret_key = var.aws_secret_access_key
  token      = var.aws_session_token
}

###############################################
# Variables
###############################################
variable "aws_access_key_id" {
  type      = string
  sensitive = true
}

variable "aws_secret_access_key" {
  type      = string
  sensitive = true
}

variable "aws_session_token" {
  type      = string
  sensitive = true
  default   = ""
}

###############################################
# Network: VPC, GW, Routes
###############################################
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "workshop-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "workshop-igw" }
}

resource "aws_route_table" "main_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "workshop-rt" }
}

###############################################
# Subnets (Application Load Balancer requires at least two different Availability Zones)
###############################################
resource "aws_subnet" "subnet_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "subnet-1" }
}

resource "aws_subnet" "subnet_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true
  tags = { Name = "subnet-2" }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.main_rt.id
}
resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.main_rt.id
}

###############################################
# Security Group (Allow HTTP)
###############################################
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP to Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

###############################################
# Load Balancer Resources
###############################################
resource "aws_lb" "app_lb" {
  name               = "workshop-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
}

resource "aws_lb_target_group" "app_tg" {
  name     = "workshop-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

###############################################
# EC2 Instances (Count = 2)
###############################################
resource "aws_instance" "web_server" {
  count                  = 2
  ami                    = "ami-04b4f1a9cf54c11d0"
  instance_type          = "t2.micro"
  
  subnet_id              = count.index % 2 == 0 ? aws_subnet.subnet_1.id : aws_subnet.subnet_2.id
  vpc_security_group_ids = [aws_security_group.alb_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    sudo apt-get update
    sudo apt-get install -y apache2
    sudo systemctl start apache2
    sudo systemctl enable apache2
    echo "<h1>Hello World</h1>" | sudo tee /var/www/html/index.html
    echo "<h2>Server ${count.index}<h2>"
  EOF

  tags = { Name = "Web-Server-${count.index}" }
}

resource "aws_lb_target_group_attachment" "test" {
  count            = 2
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.web_server[count.index].id
  port             = 80
}

###############################################
# Output
###############################################
output "load_balancer_dns" {
  value = aws_lb.app_lb.dns_name
}