terraform {
  cloud {
    organization = "TheQueenIsDead"
    hostname     = "app.terraform.io"

    workspaces {
      project = "grafana"
      name    = "grafana"
    }
  }
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "4.49.0"
    }
  }
}

provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_token

  sm_url          = var.sm_url
  sm_access_token = var.sm_access_token
}
