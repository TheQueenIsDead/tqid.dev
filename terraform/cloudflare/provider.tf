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
      # 5.19 is the first release whose built-in state upgraders migrate v4 state on plan
      version = "~> 5.19"
    }
  }
}

provider "cloudflare" {
  # Configuration options
  api_token = var.cloudflare_token
}