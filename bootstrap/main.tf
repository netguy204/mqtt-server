variable "aws_region" {
  description = "AWS region for the state bucket. Should match the region of the resources whose state it holds."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name to hold Terraform state. S3 bucket names share a global namespace, so this must be unique across all AWS accounts."
  type        = string
}

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "state_bucket_name" {
  description = "S3 bucket holding Terraform state."
  value       = aws_s3_bucket.tfstate.id
}

output "backend_config" {
  description = "Drop this into ../backend.hcl, then run `terraform init -backend-config=backend.hcl` in the parent directory."
  value       = <<EOT
bucket = "${aws_s3_bucket.tfstate.id}"
region = "${var.aws_region}"
EOT
}
