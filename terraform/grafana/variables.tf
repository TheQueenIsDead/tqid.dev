variable "grafana_url" {
  type    = string
  default = "https://tqid.grafana.net"
}

variable "grafana_token" {
  type      = string
  sensitive = true
}

variable "sm_url" {
  type    = string
  default = "https://synthetic-monitoring-api-au-southeast-1.grafana.net"
}

variable "sm_access_token" {
  type      = string
  sensitive = true
}

variable "sm_monthly_executions" {
  description = "Synthetic Monitoring free tier check executions per month, shared across all checks."
  type        = number
  default     = 100000
}
