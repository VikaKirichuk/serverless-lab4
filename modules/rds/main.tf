variable "prefix"      { type = string }
variable "db_name"     { type = string }
variable "db_user"     { type = string }
variable "db_password" { type = string }
variable "vpc_id"      { type = string }
variable "subnet_ids"  { type = list(string) }

resource "aws_security_group" "rds_sg" {
  name   = "${var.prefix}-rds-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
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

resource "aws_db_subnet_group" "main" {
  name       = "${var.prefix}-subnet-group"
  subnet_ids = var.subnet_ids
}

resource "aws_db_instance" "main" {
  identifier        = "${var.prefix}-db"
  engine            = "postgres"
  engine_version    = "16.6"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = var.db_name
  username = var.db_user
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  skip_final_snapshot = true
  publicly_accessible = true
}

output "db_host"     { value = aws_db_instance.main.address }
output "db_name"     { value = var.db_name }
output "db_user"     { value = var.db_user }
output "db_password" { value = var.db_password }
output "db_port"     { value = "5432" }