locals {
  # Public sites probed from outside the network. Keys become the check's job name.
  # Health endpoints where the app has one, so the check tests the app rather than a login redirect.
  synthetic_checks = {
    "Immich"     = "https://photos.tqid.dev/api/server/ping"
    "Jellyfin"   = "https://jellyfin.tqid.dev/health"
    "Jellyseerr" = "https://jellyseer.tqid.dev/api/v1/status"
    "Chat"       = "https://chat.tqid.dev"
    "Speedtest"  = "https://speed.tqid.dev"
  }

  synthetic_probes = [15] # Sydney

  # Spread the free tier's executions evenly across every check and probe, assuming a 31 day month,
  # rounded up to whole minutes so the total always stays under the budget.
  synthetic_frequency_minutes = ceil(
    31 * 24 * 60 * length(local.synthetic_checks) * length(local.synthetic_probes) / var.sm_monthly_executions
  )
}

resource "grafana_synthetic_monitoring_check" "http" {
  for_each = local.synthetic_checks

  job                = each.key
  target             = each.value
  enabled            = true
  probes             = local.synthetic_probes
  frequency          = local.synthetic_frequency_minutes * 60 * 1000
  timeout            = 10000
  basic_metrics_only = true

  settings {
    http {
      ip_version = "V4"
      method     = "GET"
    }
  }
}
