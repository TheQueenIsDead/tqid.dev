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
      version = "4.45.2"
    }
  }
  }


provider "grafana" {
  # Configuration options
}