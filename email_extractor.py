import os
import re
import urllib.parse
from email import policy
from email.parser import BytesParser
from pathlib import Path

import boto3


s3 = boto3.client("s3")

MAIL_PREFIX = os.environ.get("MAIL_PREFIX", "kyuyo-mail-original/")
INCOMING_PREFIX = os.environ.get("INCOMING_PREFIX", "incoming/")


def _safe_filename(filename):
    """Return a filename that cannot escape the destination S3 prefix."""
    filename = re.sub(r"[\\/\x00-\x1f\x7f]+", "_", filename).strip(" .")
    return filename or "attachment.pdf"


def extract_pdf_attachments(bucket, key):
    """Extract PDF attachments from an RFC 5322 message stored by SES."""
    response = s3.get_object(Bucket=bucket, Key=key)
    message = BytesParser(policy=policy.default).parsebytes(response["Body"].read())
    message_key = _safe_filename(Path(key).name)
    used_names = set()
    saved_keys = []

    for part in message.walk():
        if part.is_multipart():
            continue

        original_name = part.get_filename()
        is_pdf = (
            part.get_content_type().lower() == "application/pdf"
            or bool(original_name and original_name.lower().endswith(".pdf"))
        )
        if not is_pdf:
            continue

        payload = part.get_payload(decode=True)
        if not payload:
            print("Skip: empty PDF attachment")
            continue

        filename = _safe_filename(original_name or "attachment.pdf")
        stem, suffix = Path(filename).stem, Path(filename).suffix
        candidate = filename
        sequence = 2
        while candidate.casefold() in used_names:
            candidate = f"{stem}-{sequence}{suffix}"
            sequence += 1
        used_names.add(candidate.casefold())

        output_key = f"{INCOMING_PREFIX}{message_key}/{candidate}"
        s3.put_object(
            Bucket=bucket,
            Key=output_key,
            Body=payload,
            ContentType="application/pdf",
        )
        saved_keys.append(output_key)
        print(f"Extracted attachment: s3://{bucket}/{output_key}")

    print(f"Extracted {len(saved_keys)} PDF attachment(s) from s3://{bucket}/{key}")
    return saved_keys


def lambda_handler(event, context):
    print("event:", event)
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        if not key.startswith(MAIL_PREFIX):
            print(f"Skip: outside mail prefix: s3://{bucket}/{key}")
            continue
        extract_pdf_attachments(bucket, key)

    return {"statusCode": 200}
