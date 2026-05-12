terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Local state on purpose. The bucket created here *holds* the main project's
  # state; this config rarely changes, and putting its state in S3 would create
  # a chicken-and-egg problem. Commit `terraform.tfstate` somewhere durable, or
  # accept that re-running `terraform apply` here is idempotent if you lose it
  # (the bucket creation will fail with AlreadyOwnedByYou, which you can import
  # if needed).
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "mqtt-server"
      ManagedBy = "terraform"
      Component = "tfstate-bootstrap"
    }
  }
}
