terraform {
  required_version = ">= 1.9.0"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc04"
    }
  }
}

provider "proxmox" {
  pm_api_url      = var.pm_api_url
  pm_tls_insecure = true
  # pm_user            = var.pm_user
  # pm_password        = var.pm_password
  # Or use API token variables instead of user/pass
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
}
