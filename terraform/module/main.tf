terraform {
  backend "s3" {}
}

provider "aws" {
  region  = "eu-central-1"
  version = "~> 2.68.0"
}

resource "aws_security_group" "default" {
  name = "rds_sg"

  # ingress {
  #   cidr = "10.0.0.0/24"
  # }
}

resource "aws_db_instance" "default" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.micro"
  name                 = "mydb"
  username             = "foo"
  password             = "foobarbaz"
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
  final_snapshot_identifier = "samdi"
   vpc_security_group_ids = [aws_security_group.default.id]
}