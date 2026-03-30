
variable "function_name"    { type = string }
variable "source_dir"       { type = string }
variable "log_bucket_name"  { type = string }
variable "log_bucket_arn"   { type = string }
variable "db_host"          { type = string }
variable "db_port"          { type = string }
variable "db_name"          { type = string }
variable "db_user"          { type = string }
variable "db_password"      { type = string }

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/app.zip"
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.function_name}_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "s3_logs_access" {
  name = "s3_logs_access_policy"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${var.log_bucket_arn}/logs/*"
    }]
  })
}

resource "aws_lambda_function" "api_handler" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.function_name
  role             = aws_iam_role.lambda_exec.arn
  handler          = "app.handler"
  runtime          = "python3.12"
  timeout          = 15
  memory_size      = 256
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DB_HOST     = var.db_host
      DB_PORT     = var.db_port
      DB_NAME     = var.db_name
      DB_USER     = var.db_user
      DB_PASSWORD = var.db_password
      LOG_BUCKET  = var.log_bucket_name
    }
  }
}

output "invoke_arn"    { value = aws_lambda_function.api_handler.invoke_arn }
output "function_name" { value = aws_lambda_function.api_handler.function_name }