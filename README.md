# pdf-unlock-lambda

S3 の `incoming/` にアップロードされた PDF を、環境変数で指定したパスワードと qpdf で復号し、同じバケットの `decrypted/` に保存する AWS Lambda 関数です。

## 処理の流れ

1. S3 イベントからバケット名とオブジェクトキーを取得します。
2. `incoming/` 配下の PDF を `/tmp` にダウンロードします。
3. qpdf で復号し、`decrypted/<ファイル名>` にアップロードします。

元の S3 オブジェクトは残ります。qpdf がゼロ以外の終了コードを返すと、関数はエラーになります。

## ファイル構成

| ファイル | 用途 |
| --- | --- |
| `lambda_function.py` | S3 イベントを処理する Lambda ハンドラー |
| `Dockerfile` | Python 3.13 の Lambda ベースイメージに qpdf を追加 |
| `deploy/trust-policy.json` | Lambda 実行ロールの信頼ポリシー |
| `deploy/s3-policy.json` | 対象バケットへの読み書き権限の設定例 |
| `deploy/notification.json` | `incoming/` 配下の `.pdf` 作成を通知する S3 設定例 |

## 設定

- Lambda の環境変数 `PDF_PASSWORD` に PDF のパスワードを設定します。コードや Git 管理ファイルには記載しません。
- `deploy/s3-policy.json` の `YOUR_BUCKET_NAME` を対象バケット名に置き換えます。
- `deploy/notification.json` の `YOUR_ACCOUNT_ID`、リージョン、関数名をデプロイ先に合わせます。
- Lambda 実行ロールには S3 の読み書き権限とログ出力権限を設定します。
- S3 から Lambda を呼び出すためのリソースベースポリシーも別途設定します。通知設定だけでは呼び出し権限は付与されません。

設定 JSON はひな形です。このリポジトリには AWS リソースの作成やデプロイを自動化するスクリプトは含まれていません。

## コンテナのビルド

Docker を利用できる環境で、リポジトリのルートから実行します。

```sh
docker build -t pdf-unlock-lambda .
```

ビルドしたイメージを ECR に登録し、Lambda のコンテナイメージとして使用します。ビルドする CPU アーキテクチャと Lambda 側の設定を合わせてください。

## 現在の動作上の注意

- パスワードは環境変数で設定した1種類を全 PDF に使用します。
- 出力キーにはファイル名のみを使用します。例えば `incoming/a/report.pdf` と `incoming/b/report.pdf` は、どちらも `decrypted/report.pdf` に保存されるため上書きされます。
- ハンドラーは拡張子の大文字・小文字を区別しませんが、通知設定例のサフィックスは `.pdf` です。
- 一時ファイルの明示的な削除は実装していません。対象 PDF のサイズや件数に応じて、Lambda の一時ストレージとタイムアウトを設定してください。

## Git 管理対象外

`memo.txt` と `memo2.txt` はローカルの作業メモ・ブログ下書き、`response.json` は実行結果のため、コミット対象から除外しています。ローカルの PDF、環境変数ファイル、Python のキャッシュも除外します。

Docker のビルドコンテキストには `Dockerfile` と `lambda_function.py` のみを含めます。
