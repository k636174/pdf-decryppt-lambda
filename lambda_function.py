import boto3
import os
import tempfile
import urllib.parse
from pathlib import Path

from pypdf import PdfReader, PdfWriter

s3 = boto3.client("s3")

PDF_PASSWORD = os.environ["PDF_PASSWORD"]


def decrypt_pdf(input_path, output_path):
    reader = PdfReader(input_path)
    if reader.is_encrypted and reader.decrypt(PDF_PASSWORD) == 0:
        raise RuntimeError("PDF password is incorrect")

    writer = PdfWriter()
    writer.clone_document_from_reader(reader)
    with open(output_path, "wb") as output_file:
        writer.write(output_file)


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

        input_path = str(Path(tempfile.gettempdir()) / filename)
        output_path = str(Path(tempfile.gettempdir()) / f"decrypted-{filename}")

        print(f"Downloading s3://{bucket}/{key}")

        s3.download_file(
            bucket,
            key,
            input_path
        )

        print("Decrypting PDF with pypdf")
        decrypt_pdf(input_path, output_path)

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
