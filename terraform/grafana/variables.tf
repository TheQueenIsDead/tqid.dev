variable "grafana_url" {
  type    = string
  default = "https://tqid.grafana.net"
}

variable "grafana_token" {
  type      = string
  sensitive = true
}
