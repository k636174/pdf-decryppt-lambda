# Terraform による AWS 環境の構築

このディレクトリでは、PDF 添付の抽出・復号処理に必要な AWS リソースを管理します。既存環境への import は完了しており、同じ構成を別の AWS Organizations 配下のアカウントや別環境へ新規展開できる状態です。

## 作成・管理するリソース

- SES のメール保存と Lambda の入出力に使用する S3 バケット
- S3 Public Access Block
- SES による S3 書き込みを許可するバケットポリシー
- S3 から Lambda への通知設定
- Lambda 2関数で共有する IAM ロールとポリシー
- メール添付抽出用 ZIP Lambda（`pdf-attachment-extractor`）
- PDF 復号用 ZIP Lambda（`pdf-unlock-lambda-zip`）
- S3 から両 Lambda を呼び出すためのリソースベースポリシー
- 両 Lambda の CloudWatch Logs ロググループ
- SES domain identity、カスタム MAIL FROM、設定セット
- SES Receipt Rule Set、active 設定、給与明細メールを S3 に保存する Receipt Rule
- SES の受信、DKIM、カスタム MAIL FROM に必要な Route53 レコード

S3 内のオブジェクトは Terraform の管理対象ではありません。

タグをサポートするAWSリソースには、AWS Providerの `default_tags` により `ManagedBy = Terraform` と `Project = pdf-unlock-lambda` を付与します。環境名などを追加する場合は `common_tags` を環境ごとの `terraform.tfvars` で上書きします。Route53レコードやIAMポリシーアタッチメントなど、AWS APIまたはTerraformリソースがタグをサポートしないものには付与されません。

同じ Receipt Rule Set に存在する別用途の `receive-to-s3` ルールと、個人メールアドレスの SES identity はこのプロジェクトの管理対象外です。共有する SES 設定セット自体は管理しますが、個人メールアドレス identity との関連付けは管理しません。

## 前提条件

- Terraform 1.6 以上
- AWS CLI で対象アカウントへ認証できること
- Terraform 実行者に S3、Lambda、IAM、CloudWatch Logs、SES、Route53 の管理権限があること
- `deploy/email-extractor.zip` が作成済みであること
- `deploy/pdf-unlock-function.zip` が Lambda の実行環境と互換性のある依存パッケージを含んでいること
- SES を使用するリージョンと Lambda のリージョンが一致していること

ZIPが未作成の場合は、リポジトリのルートで次を実行します。スクリプトが `deploy/` と `deploy/package/` を自動作成します。

```powershell
.\scripts\build_lambda_zips.ps1
```

## 新しい Org・AWS アカウントへの展開

ここでいう Org は AWS Organizations 内の別アカウントを想定しています。リソースはアカウントごとに作成されます。

### 1. 対象アカウントへログイン

```powershell
aws login
aws sts get-caller-identity
```

表示された Account ID が展開先と一致することを必ず確認してください。

複数アカウントを扱う場合は AWS CLI のプロファイルを分け、実行時に明示する方法を推奨します。

```powershell
$env:AWS_PROFILE = "target-account"
aws sts get-caller-identity
```

### 2. 環境固有変数を設定

サンプルをコピーします。

```powershell
Set-Location terraform
Copy-Item terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` の `bucket_name` を変更します。S3 バケット名は全 AWS アカウントでグローバルに一意である必要があります。例えば、Org 名、環境名、AWS Account ID を含めます。

```hcl
aws_region  = "ap-northeast-1"
bucket_name = "example-prod-pdf-unlock-123456789012"
route53_zone_id = "Z0123456789EXAMPLE"
ses_domain                  = "ses.example.com"
ses_mail_from_domain        = "mail.ses.example.com"
ses_configuration_set_name = "example-configuration-set"
ses_receipt_rule_set_name   = "example-receiving"
ses_receipt_rule_name       = "save-mail-to-s3"
ses_receipt_recipient       = "recipient@ses.example.com"
```

Route53とSESの各値にはデフォルトがないため、すべて対象環境に合わせて指定します。

Lambda や IAM ロールの名前もアカウント内の命名規則に応じて変更できます。

### 3. PDF パスワードを設定

推奨する簡易設定は、現在の PowerShell セッションだけに環境変数として渡す方法です。

```powershell
$env:TF_VAR_pdf_password = Read-Host "PDF password"
```

Git 管理しない `terraform.tfvars` に書くこともできます。

```hcl
pdf_password = "実際のパスワード"
```

ただし、どちらの渡し方でもパスワードは Terraform state と保存済み plan に格納されます。`sensitive = true` は画面表示を抑制しますが、state を暗号化する機能ではありません。

次の運用を守ってください。

- 実値を `terraform.tfvars.example` や Git 管理ファイルへ書かない
- `terraform.tfvars`、state、plan を Git にコミットしない
- state を暗号化されたリモートバックエンドへ保存する
- state と plan を閲覧できる IAM 権限を最小限にする
- チャット、チケット、CI ログへパスワードを貼り付けない

本番や複数人での運用では、Secrets Manager または SSM Parameter Store の SecureString を使用し、Lambda が実行時に値を取得する構成を推奨します。Terraform で Secret の値を登録すると値が state に残るため、「秘密値は Terraform の外で登録し、Terraform は Secret の ARN だけを扱う」方式がより安全です。この方式へ移行する場合は Lambda コードの変更も必要です。

### 4. plan と apply

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan -out tfplan
terraform show tfplan
terraform apply tfplan
```

新規アカウントでは、管理対象リソースが `add` として表示されます。既存環境では、意図した変更以外が表示されないことを確認してください。

`terraform apply` により、SES Receipt Rule の S3 アクションと必要な Route53 レコードも作成されます。

## 既存環境での通常運用

既存環境はすでに Terraform state へ import 済みです。`imports.tf` は削除済みで、再 import は不要です。

変更時は必ず保存済み plan を確認してから apply します。

```powershell
Set-Location terraform
$env:TF_VAR_pdf_password = Read-Host "PDF password"
terraform plan -out tfplan
terraform show tfplan
terraform apply tfplan
```

AWS コンソールや AWS CLI で管理対象を直接変更すると、次回 plan で差分が表示されます。

## Lambda コードのデプロイ

Terraform は `deploy/` にある ZIP ファイルと、そのハッシュを Lambda のコードとして管理します。ZIP の内容が変わると、次回 apply で Lambda コードも更新されます。

`pdf-unlock-function.zip` には `pypdf[crypto]` と Lambda の Linux 実行環境に対応した依存パッケージが必要です。Windows 向けバイナリを含む ZIP はデプロイしないでください。

ZIP を更新した場合は、plan に Lambda の `source_code_hash` 更新が表示されることを確認します。

## Terraform state

現在の環境ではローカルの `terraform.tfstate` を使用しています。管理対象は次のコマンドで確認できます。

```powershell
terraform state list
```

`.terraform.lock.hcl` は Git にコミットします。state、plan、`terraform.tfvars` はコミットしません。

別アカウントへ継続的に展開する場合、同じローカル state を使い回してはいけません。アカウント・環境ごとに独立したバックエンドまたは workspace を用意してください。誤った state を使用すると、別アカウントのリソースを変更・削除する plan が生成されるおそれがあります。

## 安全対策と注意事項

- S3 バケット、Lambda、ロググループには `prevent_destroy` を設定しています。
- `aws_s3_bucket_notification` は対象バケットの通知設定全体を管理します。
- SNS、SQS、EventBridge、ほかの Lambda 通知を追加する場合は、既存通知も含めて `main.tf` に記述してください。
- `terraform destroy` は通常の運用では使用しないでください。
- `prevent_destroy` を外す場合は、対象リソースとデータ保持要件を個別に確認してください。
