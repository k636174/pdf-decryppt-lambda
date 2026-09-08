output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "bucket_name" {
  value = aws_s3_bucket.target.id
}

output "active_lambda_functions" {
  value = {
    extractor = aws_lambda_function.extractor.arn
    unlock    = aws_lambda_function.unlock.arn
  }
}
