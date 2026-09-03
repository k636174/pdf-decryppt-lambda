import boto3
import os
import subprocess
import urllib.parse
from pathlib import Path

s3 = boto3.client("s3")

PDF_PASSWORD = os.environ["PDF_PASSWORD"]


def lambda_handler(event, context):
    print("event:", event)

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(
            record["s3"]["object"]["key"]
        )

        print(f"bucket={bucket}")
        print(f"key={key}")

        # incoming/ 配下のPDFだけ処理
        if not key.startswith("incoming/"):
            print("Skip: not incoming/")
            continue

        if not key.lower().endswith(".pdf"):
            print("Skip: not PDF")
            continue

        filename = Path(key).name

        input_path = f"/tmp/{filename}"
        output_path = f"/tmp/decrypted-{filename}"

        print(f"Downloading s3://{bucket}/{key}")

        s3.download_file(
            bucket,
            key,
            input_path
        )

        print("Running qpdf")

        result = subprocess.run(
            [
                "qpdf",
                f"--password={PDF_PASSWORD}",
                "--decrypt",
                input_path,
                output_path,
            ],
            capture_output=True,
            text=True
        )

        print("qpdf returncode:", result.returncode)
        print("qpdf stdout:", result.stdout)
        print("qpdf stderr:", result.stderr)

        if result.returncode != 0:
            raise RuntimeError(
                f"qpdf failed: {result.stderr}"
            )

        output_key = f"decrypted/{filename}"

        print(
            f"Uploading to s3://{bucket}/{output_key}"
        )

        s3.upload_file(
            output_path,
            bucket,
            output_key,
            ExtraArgs={
                "ContentType": "application/pdf"
            }
        )

        print(
            f"Completed: s3://{bucket}/{key}"
            f" -> s3://{bucket}/{output_key}"
        )

    return {
        "statusCode": 200
    }
