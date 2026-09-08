"""Run the Lambda handler using a local PDF instead of S3."""

import argparse
import getpass
import os
from pathlib import Path
import shutil
import tempfile
from unittest.mock import patch
from urllib.parse import quote_plus


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Encrypted PDF")
    parser.add_argument("output", type=Path, help="New output PDF (must not exist)")
    args = parser.parse_args()
    source = args.input.resolve()
    destination = args.output.resolve()
    if not source.is_file() or source.suffix.lower() != ".pdf":
        parser.error("Input must be an existing PDF file")
    if destination.exists():
        parser.error("Output already exists; choose a new output path")
    if "PDF_PASSWORD" not in os.environ:
        os.environ["PDF_PASSWORD"] = getpass.getpass("PDF password: ")

    class LocalS3:
        def download_file(self, bucket, key, filename):
            shutil.copyfile(source, filename)

        def upload_file(self, filename, bucket, key, ExtraArgs=None):
            destination.parent.mkdir(parents=True, exist_ok=True)
            with open(filename, "rb") as decrypted, destination.open("xb") as output:
                shutil.copyfileobj(decrypted, output)

    # Patch before importing: the handler creates its S3 client at import time.
    # The handler runs normally, so breakpoints work in the Lambda code.
    with tempfile.TemporaryDirectory(prefix="pdf-unlock-") as workdir:
        with patch("boto3.client", return_value=LocalS3()), patch(
            "tempfile.gettempdir", return_value=workdir
        ):
            from lambdas.pdf_unlock import lambda_function

            event = {"Records": [{"s3": {
                "bucket": {"name": "local-only"},
                "object": {"key": quote_plus(f"incoming/{source.name}")},
            }}]}
            lambda_function.lambda_handler(event, None)
    print(f"Saved: {destination}")


if __name__ == "__main__":
    main()
