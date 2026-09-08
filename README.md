# pdf-unlock-lambda

SES が S3 の `kyuyo-mail-original/` に保存した生メールから PDF 添付を抽出し、復号Lambdaへ連携する2つのZIP形式 AWS Lambda関数です。PDFの復号には `pypdf[crypto]` を使用します。

## 処理の流れ

1. ZIP形式の `pdf-attachment-extractor` が `kyuyo-mail-original/` のS3イベントを受け、生メール（RFC 5322/MIME）から PDF 添付を抽出します。
2. 添付を `incoming/<SESのメールオブジェクト名>/<添付ファイル名>` に保存します。
3. 既存の `pdf-unlock-lambda` が、その保存で発生するS3イベントを受け、PDF を `/tmp` にダウンロードします。
4. pypdf で復号し、`decrypted/<添付ファイル名>` にアップロードします。

元の S3 オブジェクトは残ります。PDF の復号に失敗すると、関数はエラーになります。

## ファイル構成

| ファイル                   | 用途                                                |
|----------------------------|-----------------------------------------------------|
| `lambdas/pdf_unlock/lambda_function.py` | PDFを復号するLambdaハンドラー             |
| `lambdas/email_extractor/email_extractor.py` | SES保存メールからPDF添付を抽出するLambdaハンドラー |
| `terraform/`               | AWS リソースとLambdaデプロイのTerraform定義         |
| `scripts/build_lambda_zips.ps1` | Lambda用ZIPを生成するPowerShellスクリプト       |

## 設定

- Lambda の環境変数 `PDF_PASSWORD` に PDF のパスワードを設定します。コードや Git 管理ファイルには記載しません。
- 添付抽出LambdaでSESの保存先プレフィックスを変える場合だけ、環境変数 `MAIL_PREFIX` を設定します。既定値は `kyuyo-mail-original/` です。
- AWS リソース、IAMポリシー、S3通知は `terraform/` で管理します。設定方法は `terraform/README.md` を参照してください。

## PyCharm でローカル開発（Windows）

1. Python 3.13 をインストールします（Lambda と同じバージョン）。
2. PyCharm の **Open** でこのプロジェクトのフォルダーを開きます。
3. **Settings → Python → Interpreter**（バージョンによっては **Project → Python Interpreter**）からローカルの Virtualenv を追加します。ベースに Python 3.13、保存先にプロジェクト内の `.venv` を指定します。
4. PyCharm の Terminal で依存パッケージをインストールします。

   ```powershell
   .\.venv\Scripts\python.exe -m pip install -r requirements.txt
   ```

5. 手元の暗号化 PDF を、例えば `samples/input.pdf` として置きます。
6. **Run → Edit Configurations → + → Python** で次を設定します。

   | 項目                  | 値                                     |
   |-----------------------|----------------------------------------|
   | Script path           | プロジェクト内の `local_run.py`        |
   | Parameters            | `samples/input.pdf samples/output.pdf` |
   | Working directory     | プロジェクトのルートフォルダー         |
   | Python interpreter    | `.venv` の Python                      |
   | Environment variables | `PDF_PASSWORD=対象PDFのパスワード`     |

7. `lambdas/pdf_unlock/lambda_function.py` にブレークポイントを置き、**Debug** で実行します。

実行構成は個人用にし、パスワードを含む設定を共有ファイルに保存しないでください。`.idea/` は Git 管理から除外しています。`.env` ファイルは自動読み込みしません。環境変数を省略した場合はパスワードを対話入力します（Terminal からの実行を推奨）。

```powershell
.\.venv\Scripts\python.exe local_run.py samples/input.pdf samples/output.pdf
```

`local_run.py` は S3 のダウンロード・アップロードだけをローカルファイル操作に置き換え、実際の Lambda ハンドラーと pypdf を実行します。AWS 認証情報やバケットは不要です。既存の出力ファイルへの上書きは拒否します。ローカル実行用の一時フォルダーは実行終了時に削除します。S3 権限・通知・Lambda上の動作確認は AWS 環境で別途必要です。

PyCharm の設定詳細は [インタープリターの設定](https://www.jetbrains.com/help/pycharm/configuring-python-interpreter.html)と [Python 実行構成](https://www.jetbrains.com/help/pycharm/run-debug-configuration-python.html)を参照してください。

## ZIP Lambdaのデプロイ

復号Lambdaは `pypdf[crypto]` を使用します。リポジトリのルートで次のスクリプトを実行すると、`deploy/` と `deploy/package/` が自動作成され、Lambda互換のZIPが生成されます。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_lambda_zips.ps1
```

ZIPの作成後、`terraform/` からデプロイします。詳しい手順は `terraform/README.md` を参照してください。

- `pdf-unlock-lambda-zip`：Python 3.13 ZIP形式の復号Lambda
- `pdf-attachment-extractor`：メール添付抽出Lambda

## S3イベント設定

Terraformで次の2種類の `s3:ObjectCreated:*` 通知を設定します。

- `kyuyo-mail-original/` → `pdf-attachment-extractor`：生メールからPDF添付を抽出
- `incoming/` かつ `.pdf` → `pdf-unlock-lambda`：抽出済みPDFを復号

既にバケットに保存されているメールオブジェクトは、通知設定を追加しただけでは処理されません。対象オブジェクトをコピーし直してイベントを発生させるか、同じ形式のS3イベントでLambdaを一度手動実行してください。

## 現在の動作上の注意

- パスワードは環境変数で設定した1種類を全 PDF に使用します。
- `decrypted/` はフラットに配置します。別メールに同名の添付がある場合、後から処理したファイルで上書きされます。同じメール内の同名添付には、`incoming/` 保存時に `-2` 以降を付けます。
- ハンドラーは拡張子の大文字・小文字を区別しませんが、Terraformで設定する通知のサフィックスは `.pdf` です。
- 一時ファイルの明示的な削除は実装していません。対象 PDF のサイズや件数に応じて、Lambda の一時ストレージとタイムアウトを設定してください。

## Git 管理対象外

`memo.txt` と `memo2.txt` はローカルの作業メモ・ブログ下書き、`response.json` は実行結果のため、コミット対象から除外しています。ローカルの PDF、環境変数ファイル、Python のキャッシュも除外します。
