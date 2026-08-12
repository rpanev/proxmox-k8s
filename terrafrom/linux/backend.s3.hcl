# Optional remote state backend for AWS S3.
# Usage:
#   1. Comment out or remove the backend "local" block in versions.tf
#   2. Add: backend "s3" {}
#   3. terraform init -migrate-state -backend-config=backend.s3.hcl

bucket         = "panev-homelab-terraform-state"
key            = "proxmox/homelab/terraform.tfstate"
region         = "eu-central-1"
encrypt        = true
# profile        = "default"
# dynamodb_table = "terraform-state-lock"
