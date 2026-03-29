variable "name_prefix" { type = string }

resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.name_prefix}-artifacts"
}

output "bucket_name" {
  value = aws_s3_bucket.artifacts.bucket
}
