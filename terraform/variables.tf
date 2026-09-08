variable "aws_region" {
  description = "AWS リソースを作成するリージョン。SES、S3 通知、Lambda は同一リージョンで使用します。"
  type        = string
  default     = "ap-northeast-1"
}

variable "bucket_name" {
  description = "SES のメール保存と Lambda の入出力に使用する、グローバルに一意な S3 バケット名。"
  type        = string
}

variable "lambda_role_name" {
  description = "Lambda 2関数で共有する IAM ロール名。"
  type        = string
  default     = "pdf-unlock-lambda-role"
}

variable "unlock_function_name" {
  description = "PDF 復号 Lambda の関数名。"
  type        = string
  default     = "pdf-unlock-lambda-zip"
}

variable "extractor_function_name" {
  description = "メール添付抽出 Lambda の関数名。"
  type        = string
  default     = "pdf-attachment-extractor"
}

variable "mail_prefix" {
  description = "SES が生メールを保存する S3 プレフィックス。"
  type        = string
  default     = "kyuyo-mail-original/"
}

variable "incoming_prefix" {
  description = "抽出した PDF を保存する S3 プレフィックス。"
  type        = string
  default     = "incoming/"
}

variable "decrypted_prefix" {
  description = "復号済み PDF を保存する S3 プレフィックス。"
  type        = string
  default     = "decrypted/"
}

variable "extractor_zip_path" {
  description = "メール添付抽出 Lambda のデプロイ用 ZIP ファイル。terraform ディレクトリからの相対パス。"
  type        = string
  default     = "../deploy/email-extractor.zip"
}

variable "unlock_zip_path" {
  description = "PDF 復号 Lambda のデプロイ用 ZIP ファイル。terraform ディレクトリからの相対パス。"
  type        = string
  default     = "../deploy/pdf-unlock-function.zip"
}

variable "pdf_password" {
  description = "PDF の復号パスワード。Git には保存しないでください。この値は Terraform state に保存されます。"
  type        = string
  sensitive   = true
}

variable "extractor_memory_size" {
  description = "メール添付抽出 Lambda のメモリサイズ（MB）。"
  type        = number
  default     = 256
}

variable "unlock_memory_size" {
  description = "PDF 復号 Lambda のメモリサイズ（MB）。"
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Lambda のタイムアウト（秒）。"
  type        = number
  default     = 30
}

variable "extractor_log_retention_days" {
  description = "メール添付抽出 Lambda のログ保持日数。0 は無期限です。"
  type        = number
  default     = 0
}

variable "unlock_log_retention_days" {
  description = "PDF 復号 Lambda のログ保持日数。"
  type        = number
  default     = 30
}

variable "route53_zone_id" {
  description = "SES 用 DNS レコードを作成する Route53 Hosted Zone ID。"
  type        = string
}

variable "ses_domain" {
  description = "メール受信と送信 identity に使用する SES ドメイン。"
  type        = string
}

variable "ses_mail_from_domain" {
  description = "SES domain identity のカスタム MAIL FROM ドメイン。"
  type        = string
}

variable "ses_configuration_set_name" {
  description = "SES domain identity が使用する設定セット名。"
  type        = string
}

variable "ses_receipt_rule_set_name" {
  description = "受信ルールを格納し、active にする SES Receipt Rule Set 名。"
  type        = string
}

variable "ses_receipt_rule_name" {
  description = "給与明細メールを S3 に保存する SES Receipt Rule 名。"
  type        = string
}

variable "ses_receipt_recipient" {
  description = "給与明細メールを受信する SES Receipt Rule の宛先。"
  type        = string
}
