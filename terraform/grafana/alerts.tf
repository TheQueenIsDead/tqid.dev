locals {
  datasources = {
    prometheus = { type = "prometheus", uid = "grafanacloud-prom" }
    loki       = { type = "loki", uid = "grafanacloud-logs" }
    # Grafana Cloud's own billing/usage metrics for this stack.
    usage = { type = "prometheus", uid = "grafanacloud-usage" }
  }

  # Golden-signal error alerts for applications, built from the telemetry shipped by etc/alloy.
  # `expr` must return the value compared against `threshold`; `no_data` applies when it returns nothing.
  application_alerts = {
    "HTTP 5xx error rate" = {
      datasource = "prometheus"
      # Ratio of 5xx responses per Traefik service, ignoring services with negligible traffic.
      expr        = <<-EOT
        (
          sum by (service) (rate(traefik_service_requests_total{code=~"5.."}[5m]))
          /
          sum by (service) (rate(traefik_service_requests_total[5m]))
        )
        and
        sum by (service) (rate(traefik_service_requests_total[5m])) > 0.01
      EOT
      threshold   = 0.05
      comparison  = "gt"
      for         = "5m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ $labels.service }} is returning 5xx errors"
      description = "{{ humanizePercentage $values.A.Value }} of requests to {{ $labels.service }} returned 5xx over the last 5m."
    }

    "Container restarting" = {
      datasource  = "prometheus"
      expr        = "changes(container_start_time_seconds[15m])"
      threshold   = 2
      comparison  = "gt"
      for         = "0s"
      no_data     = "OK"
      severity    = "critical"
      summary     = "{{ $labels.container }} is restarting"
      description = "{{ $labels.container }} restarted {{ $values.A.Value }} times in the last 15m; it may be crash looping."
    }

    "Error log spike" = {
      datasource  = "loki"
      expr        = "sum by (container) (count_over_time({job=\"integrations/docker\"} | detected_level=~\"error|fatal|critical\" [5m]))"
      threshold   = 10
      comparison  = "gt"
      for         = "5m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ $labels.container }} is logging errors"
      description = "{{ $labels.container }} logged {{ $values.A.Value }} error lines in the last 5m."
    }

    "Metrics target down" = {
      datasource  = "prometheus"
      expr        = "up == 0"
      threshold   = -1
      comparison  = "gt"
      for         = "5m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ $labels.job }} metrics are unreachable on {{ $labels.instance }}"
      description = "Alloy has failed to scrape {{ $labels.job }} ({{ $labels.instance }}) for 5m; the service may be down."
    }

    # From the Synthetic Monitoring checks in synthetics.tf, so this sees what visitors see.
    "Site down" = {
      datasource  = "prometheus"
      expr        = "avg by (job, instance) (avg_over_time(probe_success[15m]))"
      threshold   = 0.5
      comparison  = "lt"
      for         = "10m"
      no_data     = "OK"
      severity    = "critical"
      summary     = "{{ $labels.job }} is down"
      description = "Only {{ humanizePercentage $values.A.Value }} of external checks against {{ $labels.instance }} succeeded over the last 15m."
    }

    "Cloudflare tunnel down" = {
      datasource  = "prometheus"
      expr        = "sum(cloudflared_tunnel_ha_connections)"
      threshold   = 1
      comparison  = "lt"
      for         = "5m"
      no_data     = "Alerting"
      severity    = "critical"
      summary     = "Cloudflare tunnel has no connections"
      description = "cloudflared has {{ $values.A.Value }} connections to Cloudflare; public apps routed through the tunnel are unreachable."
    }
  }

  # Alerts that telemetry is being lost, or is about to be, on the Grafana Cloud free tier.
  observability_alerts = {
    "Logs being discarded" = {
      datasource  = "usage"
      expr        = "sum by (reason) (grafanacloud_logs_instance_discarded_bytes_per_second)"
      threshold   = 0
      comparison  = "gt"
      for         = "15m"
      no_data     = "OK"
      severity    = "critical"
      summary     = "Grafana Cloud is discarding logs ({{ $labels.reason }})"
      description = "Loki is rejecting {{ humanize1024 $values.A.Value }}B/s of logs with reason {{ $labels.reason }}. rate_limited usually means the free tier's monthly logs quota is exhausted."
    }

    "Metrics being discarded" = {
      datasource  = "usage"
      expr        = "sum by (reason) (grafanacloud_instance_samples_discarded_per_second)"
      threshold   = 0
      comparison  = "gt"
      for         = "15m"
      no_data     = "OK"
      severity    = "critical"
      summary     = "Grafana Cloud is discarding metrics ({{ $labels.reason }})"
      description = "Prometheus is rejecting {{ $values.A.Value }} samples/s with reason {{ $labels.reason }}."
    }

    "Logs quota forecast" = {
      datasource = "usage"
      # Monthly volume projected from the last 24h, against the free tier's 50GB.
      expr        = "sum(avg_over_time(grafanacloud_logs_instance_billable_bytes_received_per_second[24h])) * 86400 * 30 / 1e9"
      threshold   = 40
      comparison  = "gt"
      for         = "1h"
      no_data     = "OK"
      severity    = "warning"
      summary     = "Logs on track to exceed the free tier"
      description = "The last 24h of ingestion projects to {{ humanize $values.A.Value }}GB/month; the free tier allows 50GB before logs are dropped."
    }

    "Active series near limit" = {
      datasource  = "usage"
      expr        = "sum(grafanacloud_instance_active_series)"
      threshold   = 8000
      comparison  = "gt"
      for         = "1h"
      no_data     = "OK"
      severity    = "warning"
      summary     = "Active metric series near the free tier limit"
      description = "{{ $values.A.Value }} active series; the free tier allows 10k. Check the allowlists in etc/alloy."
    }

    # The free tier covers 10k series at 1 data point per minute; faster scrapes use it up just like more series.
    "Metrics ingestion rate near limit" = {
      datasource  = "usage"
      expr        = "sum(grafanacloud_instance_samples_per_second) * 60"
      threshold   = 8000
      comparison  = "gt"
      for         = "1h"
      no_data     = "OK"
      severity    = "warning"
      summary     = "Metrics ingestion near the free tier limit"
      description = "Ingesting {{ humanize $values.A.Value }} data points per minute; the free tier allows about 10k. Check scrape intervals and allowlists in etc/alloy."
    }
  }

  alert_groups = {
    Applications  = local.application_alerts
    Host          = local.host_alerts
    Observability = local.observability_alerts
  }

  host_alerts = {
    # Dead man's switch: no data means the host or Alloy is down, so treat it as alerting.
    "Host down" = {
      datasource  = "prometheus"
      expr        = "sum(up{job=\"integrations/node_exporter\"})"
      threshold   = 1
      comparison  = "lt"
      for         = "5m"
      no_data     = "Alerting"
      severity    = "critical"
      summary     = "nuc is not reporting metrics"
      description = "No node metrics have been received for 5m; the host, Alloy, or its connection to Grafana Cloud is down."
    }

    "Disk filling up" = {
      datasource = "prometheus"
      # Free space in 24h, extrapolated from the last 6h.
      expr        = "predict_linear(node_filesystem_avail_bytes[6h], 24 * 3600)"
      threshold   = 0
      comparison  = "lt"
      for         = "30m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ $labels.mountpoint }} will be full within 24h"
      description = "At the current rate {{ $labels.mountpoint }} ({{ $labels.device }}) runs out of space within a day."
    }

    "Disk almost full" = {
      datasource  = "prometheus"
      expr        = "node_filesystem_avail_bytes / node_filesystem_size_bytes"
      threshold   = 0.1
      comparison  = "lt"
      for         = "15m"
      no_data     = "OK"
      severity    = "critical"
      summary     = "{{ $labels.mountpoint }} is almost full"
      description = "Only {{ humanizePercentage $values.A.Value }} free on {{ $labels.mountpoint }} ({{ $labels.device }})."
    }

    # The kernel remounts a filesystem read-only when the disk under it fails.
    "Filesystem read-only" = {
      datasource  = "prometheus"
      expr        = "node_filesystem_readonly{fstype=~\"ext4|xfs|btrfs\"}"
      threshold   = 0
      comparison  = "gt"
      for         = "1m"
      no_data     = "OK"
      severity    = "critical"
      summary     = "{{ $labels.mountpoint }} has gone read-only"
      description = "{{ $labels.mountpoint }} ({{ $labels.device }}) was remounted read-only, usually because the disk is failing. Check `dmesg` and the disk's SMART data."
    }

    # Early warning of a failing disk or flaky USB-SATA link, before it goes read-only.
    "Kernel disk errors" = {
      datasource  = "loki"
      expr        = "sum by (instance) (count_over_time({job=\"integrations/node_exporter\", syslog_identifier=\"kernel\"} |~ \"(?i)(I/O error, dev|Buffer I/O error|EXT4-fs error|blk_update_request|uas_eh_abort_handler|reset (high|super)speed.* USB device|ata[0-9.]+: .*exception Emask)\" [5m]))"
      threshold   = 0
      comparison  = "gt"
      for         = "0s"
      no_data     = "OK"
      severity    = "warning"
      summary     = "Kernel is reporting disk errors on {{ $labels.instance }}"
      description = "{{ $values.A.Value }} kernel disk/I/O error lines in the last 5m. Check `journalctl -k` for the affected device."
    }

    "Memory pressure" = {
      datasource  = "prometheus"
      expr        = "node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes"
      threshold   = 0.1
      comparison  = "lt"
      for         = "15m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "Low available memory on {{ $labels.instance }}"
      description = "Only {{ humanizePercentage $values.A.Value }} of memory is available; containers may be OOM killed."
    }

    "Disk I/O saturated" = {
      datasource  = "prometheus"
      expr        = "rate(node_disk_io_time_seconds_total[5m])"
      threshold   = 0.9
      comparison  = "gt"
      for         = "30m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ $labels.device }} is saturated"
      description = "{{ $labels.device }} has been busy {{ humanizePercentage $values.A.Value }} of the time for 30m; it may be overloaded or failing."
    }
  }
}

resource "grafana_rule_group" "tqid" {
  for_each = local.alert_groups

  name             = each.key
  folder_uid       = grafana_folder.tqid.uid
  interval_seconds = 60

  dynamic "rule" {
    for_each = each.value

    content {
      name           = rule.key
      condition      = "C"
      for            = rule.value.for
      no_data_state  = rule.value.no_data
      exec_err_state = "Error"

      labels = {
        severity = rule.value.severity
      }

      annotations = {
        summary     = rule.value.summary
        description = rule.value.description
      }

      data {
        ref_id         = "A"
        query_type     = rule.value.datasource == "loki" ? "instant" : ""
        datasource_uid = local.datasources[rule.value.datasource].uid

        relative_time_range {
          from = 900
          to   = 0
        }

        model = jsonencode(merge(
          {
            datasource = local.datasources[rule.value.datasource]
            expr       = trimspace(rule.value.expr)
            instant    = true
            refId      = "A"
          },
          rule.value.datasource == "loki" ? { queryType = "instant" } : {},
        ))
      }

      data {
        ref_id         = "C"
        datasource_uid = "__expr__"

        relative_time_range {
          from = 0
          to   = 0
        }

        model = jsonencode({
          type       = "threshold"
          expression = "A"
          refId      = "C"
          datasource = { type = "__expr__", uid = "__expr__" }
          conditions = [{
            evaluator = {
              type   = rule.value.comparison
              params = [rule.value.threshold]
            }
          }]
        })
      }

      notification_settings {
        # Contact point is managed manually in the Grafana UI.
        contact_point = "Discord"
        # One notification per alert, so the Discord template's CommonAnnotations are populated.
        group_by = ["..."]
      }
    }
  }
}
