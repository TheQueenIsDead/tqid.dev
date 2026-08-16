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
      source = "grafana/grafana"
      version = "4.44.0"
    }
  }
  }


provider "grafana" {
  # Configuration options
}