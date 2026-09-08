import io
import os
import unittest
from email.message import EmailMessage
from unittest.mock import Mock, patch

import email_extractor


class ExtractPdfAttachmentsTests(unittest.TestCase):
    def test_extracts_pdf_and_ignores_other_attachments(self):
        message = EmailMessage()
        message["From"] = "sender@example.com"
        message["To"] = "receiver@example.com"
        message["Subject"] = "Payslip"
        message.set_content("Attached.")
        message.add_attachment(
            b"%PDF-1.7 encrypted",
            maintype="application",
            subtype="pdf",
            filename="給与明細.pdf",
        )
        message.add_attachment(
            b"not a PDF",
            maintype="text",
            subtype="plain",
            filename="notes.txt",
        )

        fake_s3 = Mock()
        fake_s3.get_object.return_value = {"Body": io.BytesIO(message.as_bytes())}

        with patch.object(email_extractor, "s3", fake_s3):
            result = email_extractor.extract_pdf_attachments(
                "example-pdf-unlock-bucket",
                "kyuyo-mail-original/vmomqkf6eesoj2fqn513u9rb5v7559hf534lgpg1",
            )

        self.assertEqual(
            result,
            ["incoming/vmomqkf6eesoj2fqn513u9rb5v7559hf534lgpg1/給与明細.pdf"],
        )
        fake_s3.put_object.assert_called_once_with(
            Bucket="example-pdf-unlock-bucket",
            Key=result[0],
            Body=b"%PDF-1.7 encrypted",
            ContentType="application/pdf",
        )

    def test_sanitizes_and_disambiguates_attachment_names(self):
        message = EmailMessage()
        message.set_content("Attached.")
        for filename in ("../payslip.pdf", "..\\payslip.pdf"):
            message.add_attachment(
                b"%PDF",
                maintype="application",
                subtype="pdf",
                filename=filename,
            )

        fake_s3 = Mock()
        fake_s3.get_object.return_value = {"Body": io.BytesIO(message.as_bytes())}

        with patch.object(email_extractor, "s3", fake_s3):
            result = email_extractor.extract_pdf_attachments("bucket", "kyuyo-mail-original/id")

        self.assertEqual(
            result,
            ["incoming/id/_payslip.pdf", "incoming/id/_payslip-2.pdf"],
        )


if __name__ == "__main__":
    unittest.main()
