terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Partial backend config. Initialize with:
  #   terraform init -backend-config=backend.hcl
  # The S3 bucket is created by the `bootstrap/` config; see bootstrap/README
  # for the one-time setup. State locking uses S3's native conditional writes
  # (Terraform >= 1.11), so no DynamoDB table is required.
  backend "s3" {
    key          = "mqtt-server/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "mqtt-server"
      ManagedBy = "terraform"
    }
  }
}
