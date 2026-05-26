# ---------------------------------------------
# Provider設定
# ---------------------------------------------
provider "aws" {
  region = "ap-northeast-1" # 
}

# ---------------------------------------------
# ネットワーク構築 (VPC, Subnet, IGW)
# ---------------------------------------------
# VPC (修正: /24 -> /16)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

# インターネットゲートウェイ
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# パブリックサブネット (修正: /16 -> /24)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true # EC2にパブリックIPを自動割り当て
  availability_zone       = "ap-northeast-1a"

  tags = {
    Name = "public-subnet"
  }
}

# プライベートサブネット (修正: /16 -> /24)
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-1a"

  tags = {
    Name = "private-subnet"
  }
}

# ---------------------------------------------
# ルートテーブル設定
# ---------------------------------------------
# パブリックルートテーブル
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

# パブリックサブネットとルートテーブルの紐づけ
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# プライベートルートテーブル (外部へのルートなし)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "private-rt"
  }
}

# プライベートサブネットとルートテーブルの紐づけ
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------
# セキュリティグループ
# ---------------------------------------------
resource "aws_security_group" "test_sg" {
  name        = "test-sg"
  description = "Security Group for test EC2"
  vpc_id      = aws_vpc.main.id

  # インバウンドルール: 指定IPからのSSH許可
  ingress {
    description = "Allow SSH from specific IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["202.230.171.193/32"]
  }

  # インバウンドルール: 指定IPからのMySQL許可
  ingress {
    description = "Allow MySQL from specific IP"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["202.230.171.193/32"]
  }

  # アウトバウンドルール: 全て許可
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "test-sg"
  }
}

# ---------------------------------------------
# EC2インスタンス
# ---------------------------------------------
# 最新のRHEL 10 AMIを自動検索して取得するデータソース
data "aws_ami" "rhel" {
  most_recent = true
  owners      = ["309956199498"] # Red Hatの公式AWSアカウントID

  filter {
    name   = "name"
    values = ["RHEL-10*"] # ※もしRHEL10が見つからないエラーが出たら "RHEL-9*" に変更してください
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.rhel.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.test_sg.id]
  key_name               = "test-key" # 手動作成済みのキーペア名を指定

  tags = {
    Name = "test-ec2-rhel"
  }
}

terraform {
  required_version = ">= 1.0.0"

  # AWSプロバイダーの設定
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # ─── S3リモートバックエンドの設定（DynamoDBなし） ───
  backend "s3" {
    bucket  = "leek-terraform-state"
    key     = "terraform.tfstate"
    region  = "ap-northeast-1"
    encrypt = true
  }
}