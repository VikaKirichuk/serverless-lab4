# Terraform HCL
# envs/dev/main.tf

provider "aws" {
  region = "eu-central-1"
}

locals {
  prefix      = "kyrychuk-vikoriia-07" 
  db_password = "1122334455667788"     
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_s3_bucket" "logs" {
  bucket        = "${local.prefix}-logs"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

module "database" {
  source      = "../../modules/rds"
  prefix      = local.prefix
  db_name     = "studentsdb"
  db_user     = "dbadmin"
  db_password = local.db_password
  vpc_id      = data.aws_vpc.default.id
  subnet_ids  = data.aws_subnets.default.ids
}

module "backend" {
  source          = "../../modules/lambda"
  function_name   = "${local.prefix}-students-handler"
  source_dir      = "${path.root}/../../src"
  log_bucket_name = aws_s3_bucket.logs.bucket
  log_bucket_arn  = aws_s3_bucket.logs.arn
  db_host         = module.database.db_host
  db_port         = module.database.db_port
  db_name         = module.database.db_name
  db_user         = module.database.db_user
  db_password     = module.database.db_password
}

module "api" {
  source               = "../../modules/api_gateway"
  api_name             = "${local.prefix}-students-api"
  lambda_invoke_arn    = module.backend.invoke_arn
  lambda_function_name = module.backend.function_name
}

output "api_url" { value = module.api.api_endpoint }
output "log_bucket" { value = aws_s3_bucket.logs.bucket }
output "rds_host" { value = module.database.db_host }