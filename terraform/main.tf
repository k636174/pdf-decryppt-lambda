data "aws_caller_identity" "current" {}

locals {
  bucket_arn = aws_s3_bucket.target.arn
}

resource "aws_s3_bucket" "target" {
  bucket = var.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "target" {
  bucket = aws_s3_bucket.target.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "ses_delivery" {
  bucket = aws_s3_bucket.target.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowSESPuts"
      Effect    = "Allow"
      Principal = { Service = "ses.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "${local.bucket_arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role" "lambda" {
  name = var.lambda_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "s3_access" {
  name = "PdfUnlockS3Access"
  role = aws_iam_role.lambda.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:PutObject"]
      Resource = [
        "${local.bucket_arn}/${var.mail_prefix}*",
        "${local.bucket_arn}/${var.incoming_prefix}*",
        "${local.bucket_arn}/${var.decrypted_prefix}*",
      ]
    }]
  })
}

resource "aws_lambda_function" "extractor" {
  function_name = var.extractor_function_name
  role          = aws_iam_role.lambda.arn
  package_type  = "Zip"
  runtime       = "python3.13"
  handler       = "email_extractor.lambda_handler"
  filename      = abspath("${path.module}/${var.extractor_zip_path}")
  source_code_hash = filebase64sha256(
    abspath("${path.module}/${var.extractor_zip_path}")
  )
  architectures = ["x86_64"]
  memory_size   = var.extractor_memory_size
  timeout       = var.lambda_timeout

  environment {
    variables = {
      MAIL_PREFIX     = var.mail_prefix
      INCOMING_PREFIX = var.incoming_prefix
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.extractor,
    aws_iam_role_policy_attachment.basic_execution,
    aws_iam_role_policy.s3_access,
  ]

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_lambda_function" "unlock" {
  function_name = var.unlock_function_name
  role          = aws_iam_role.lambda.arn
  package_type  = "Zip"
  runtime       = "python3.13"
  handler       = "lambda_function.lambda_handler"
  filename      = abspath("${path.module}/${var.unlock_zip_path}")
  source_code_hash = filebase64sha256(
    abspath("${path.module}/${var.unlock_zip_path}")
  )
  architectures = ["x86_64"]
  memory_size   = var.unlock_memory_size
  timeout       = var.lambda_timeout

  ephemeral_storage {
    size = 512
  }

  environment {
    variables = {
      PDF_PASSWORD = var.pdf_password
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.unlock,
    aws_iam_role_policy_attachment.basic_execution,
    aws_iam_role_policy.s3_access,
  ]

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "extractor" {
  name              = "/aws/lambda/${var.extractor_function_name}"
  retention_in_days = var.extractor_log_retention_days

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "unlock" {
  name              = "/aws/lambda/${var.unlock_function_name}"
  retention_in_days = var.unlock_log_retention_days

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_lambda_permission" "extractor_from_s3" {
  statement_id   = "AllowExecutionFromS3"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.extractor.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = local.bucket_arn
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_lambda_permission" "unlock_from_s3" {
  statement_id   = "AllowExecutionFromS3"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.unlock.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = local.bucket_arn
  source_account = data.aws_caller_identity.current.account_id
}

# This resource owns the bucket's complete notification configuration.
resource "aws_s3_bucket_notification" "target" {
  bucket = aws_s3_bucket.target.id

  lambda_function {
    id                  = "ExtractPdfFromSesMail"
    lambda_function_arn = aws_lambda_function.extractor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.mail_prefix
  }

  lambda_function {
    id                  = "PdfUnlockIncoming"
    lambda_function_arn = aws_lambda_function.unlock.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.incoming_prefix
    filter_suffix       = ".pdf"
  }

  depends_on = [
    aws_lambda_permission.extractor_from_s3,
    aws_lambda_permission.unlock_from_s3,
  ]
}
