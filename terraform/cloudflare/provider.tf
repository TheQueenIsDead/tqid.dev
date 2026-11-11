terraform {
  cloud {
    organization = "TheQueenIsDead"
    hostname     = "app.terraform.io"

    workspaces {
      project = "cloudflare"
      name    = "cloudflare"
    }
  }
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      # v5 rewrote the Zero Trust resources used here; upgrade deliberately, not via init -upgrade
      version = "~> 5.0"
    }
  }
}

provider "cloudflare" {
  # Configuration options
  api_token = var.cloudflare_token
}