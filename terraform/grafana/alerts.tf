locals {
  datasources = {
    prometheus = { type = "prometheus", uid = "grafanacloud-prom" }
    loki       = { type = "loki", uid = "grafanacloud-logs" }
    # Grafana Cloud's own billing/usage metrics for this stack.
    usage = { type = "prometheus", uid = "grafanacloud-usage" }
  }

  # Golden-signal error alerts for applications, built from the telemetry shipped by etc/alloy.
  # `expr` must return the value compared against `threshold`; `no_data` applies when it returns nothing.
  # `panel` (optional) is the [dashboard, panel title] in dashboards/ that the alert shows on.
  application_alerts = {
    "HTTP 5xx error rate" = {
      datasource = "prometheus"
      panel      = ["traffic", "Errors by service"]
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
      panel       = ["overview", "Container restarts"]
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
      panel       = ["overview", "Error logs"]
      expr        = "sum by (container) (count_over_time({job=\"integrations/docker\"} | detected_level=~\"error|fatal|critical\" [5m]))"
      threshold   = 10
      comparison  = "gt"
      for         = "5m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ $labels.container }} is logging errors"
      description = "{{ $labels.container }} logged {{ $values.A.Value }} error lines in the last 5m."
    }

    # A steady trickle of errors (e.g. an import retried every few minutes) never trips the spike alert above.
    # Requiring it every hour for 3h keeps one-off bursts out.
    "Persistent errors" = {
      datasource  = "loki"
      panel       = ["overview", "Error logs"]
      expr        = "sum by (container) (count_over_time({job=\"integrations/docker\"} | detected_level=~\"error|fatal|critical\" [1h]))"
      threshold   = 10
      comparison  = "gt"
      for         = "3h"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ $labels.container }} keeps logging errors"
      description = "{{ $labels.container }} has logged errors every hour for 3h ({{ $values.A.Value }} in the last hour); something is likely stuck retrying."
    }

    "Metrics target down" = {
      datasource  = "prometheus"
      panel       = ["overview", "Targets down"]
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
      panel       = ["overview", "Sites"]
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
      panel       = ["traffic", "Tunnel connections"]
      expr        = "sum(cloudflared_tunnel_ha_connections)"
      threshold   = 1
      comparison  = "lt"
      for         = "5m"
      no_data     = "Alerting"
      severity    = "critical"
      summary     = "Cloudflare tunnel has no connections"
      description = "cloudflared has {{ $values.A.Value }} connections to Cloudflare; public apps routed through the tunnel are unreachable."
    }

    # The tunnel is up but can't hand requests to Traefik. Traefik's own 5xx alert can't see this when
    # Traefik is the thing that's down. Normally well under 10% (client disconnects count as errors).
    "Tunnel can't reach origin" = {
      datasource  = "prometheus"
      panel       = ["traffic", "Tunnel requests"]
      expr        = <<-EOT
        (sum(rate(cloudflared_tunnel_request_errors[10m])) / sum(rate(cloudflared_tunnel_total_requests[10m])))
        and
        sum(rate(cloudflared_tunnel_total_requests[10m])) > 0.01
      EOT
      threshold   = 0.5
      comparison  = "gt"
      for         = "5m"
      no_data     = "OK"
      severity    = "critical"
      summary     = "Cloudflare tunnel can't reach Traefik"
      description = "{{ humanizePercentage $values.A.Value }} of requests through the tunnel failed over the last 10m. Check that Traefik is running and cloudflared can reach it on the edge network."
    }

    # From Traefik's access logs. One client being refused over and over is someone guessing passwords
    # (or an app of yours with a stale token, which is worth fixing anyway).
    "Repeated failed logins" = {
      datasource  = "loki"
      panel       = ["traffic", "Failed logins (401/403)"]
      expr        = "sum by (client, RequestHost) (count_over_time({container=\"traefik\"} | json | DownstreamStatus=~\"401|403\" | label_format client=`{{ or .request_Cf_Connecting_Ip .ClientHost }}` [10m]))"
      threshold   = 30
      comparison  = "gt"
      for         = "0s"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ $labels.client }} keeps failing to log in to {{ $labels.RequestHost }}"
      description = "{{ $labels.client }} was refused {{ $values.A.Value }} times by {{ $labels.RequestHost }} in the last 10m. If it isn't you, block it in Cloudflare (Security > WAF > Tools)."
    }

    # From tdarr-exporter: how many files' last transcode or health check failed. These are snapshot
    # counts, so a rise over the last hour means new failures (requeueing a file lowers it again).
    "Tdarr jobs failing" = {
      datasource  = "prometheus"
      panel       = ["overview", "Transcode errors"]
      expr        = <<-EOT
        sum by (kind) (
          label_replace(delta(tdarr_library_transcodes{status="error"}[1h]), "kind", "transcode", "", "")
          or
          label_replace(delta(tdarr_library_health_checks{status="error"}[1h]), "kind", "health check", "", "")
        )
      EOT
      threshold   = 0.5
      comparison  = "gt"
      for         = "0s"
      no_data     = "OK"
      severity    = "warning"
      summary     = "Tdarr {{ $labels.kind }}s are failing"
      description = "{{ humanize $values.A.Value }} more files failed their {{ $labels.kind }} in the last hour. Tdarr lists them under the library's error tab; their job reports are in Loki under {job=\"tdarr/job-reports\"}."
    }

    # From Tdarr's job reports: a transcode whose ffmpeg command uses a CPU encoder. Tdarr's encoder plugin
    # falls back to software without saying so, which pegs every core and runs the NUC at 90C+.
    "Software transcode" = {
      datasource  = "loki"
      panel       = ["transcoding", "Encoders"]
      expr        = "sum by (encoder) (count_over_time({job=\"tdarr/job-reports\", type=\"transcode\"} |= \"tdarr-ffmpeg -y\" | regexp \"-c:0 (?P<encoder>[a-z0-9_]+)\" | encoder=~\"libx265|libx264|libsvtav1|libaom-av1\" [15m]))"
      threshold   = 0
      comparison  = "gt"
      for         = "0s"
      no_data     = "OK"
      severity    = "warning"
      summary     = "Tdarr is transcoding in software ({{ $labels.encoder }})"
      description = "A Tdarr transcode started with {{ $labels.encoder }} instead of hevc_qsv, so it's running on the CPU. Check the flow's Set Video Encoder plugins (Hardware Encoding on, Hardware Type qsv) and that the job ran on a GPU worker."
    }
  }

  # Alerts that telemetry is being lost, or is about to be, on the Grafana Cloud free tier.
  observability_alerts = {
    # Dead man's switch for log collection; Host down only notices when metrics stop.
    "No container logs" = {
      datasource  = "loki"
      panel       = ["free-tier", "Log ingestion"]
      expr        = "sum(count_over_time({job=\"integrations/docker\"}[15m]))"
      threshold   = 1
      comparison  = "lt"
      for         = "5m"
      no_data     = "Alerting"
      severity    = "critical"
      summary     = "No container logs are reaching Grafana Cloud"
      description = "Loki has received no Docker logs for 15m; Alloy's log collection or delivery is broken."
    }

    "Logs being discarded" = {
      datasource  = "usage"
      panel       = ["free-tier", "Discarded"]
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
      panel       = ["free-tier", "Discarded"]
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
      panel      = ["free-tier", "Logs by month end"]
      # Fraction of the monthly quota used by month end: GB used so far, plus the last 6h's rate over the
      # seconds left in the (UTC) month.
      expr        = <<-EOT
        (
          sum(grafanacloud_org_logs_usage)
          +
          sum(avg_over_time(grafanacloud_logs_instance_billable_bytes_received_per_second[6h]))
          * ((days_in_month() - day_of_month() + 1) * 86400 - time() % 86400) / 1e9
        )
        / sum(grafanacloud_org_logs_included_usage)
      EOT
      threshold   = 1
      comparison  = "gt"
      for         = "1h"
      no_data     = "OK"
      severity    = "warning"
      summary     = "Logs on track to exceed the free tier"
      description = "At the last 6h's rate, logs will reach {{ humanizePercentage $values.A.Value }} of the monthly quota by month end; logs are dropped once it is used up."
    }

    # Backstop on what has actually been used, whatever the current rate. Normal months use well under 1%.
    "Logs quota half used" = {
      datasource  = "usage"
      panel       = ["free-tier", "Logs"]
      expr        = "sum(grafanacloud_org_logs_usage) / sum(grafanacloud_org_logs_included_usage)"
      threshold   = 0.5
      comparison  = "gt"
      for         = "0s"
      no_data     = "OK"
      severity    = "warning"
      summary     = "Over half the monthly logs quota is used"
      description = "{{ humanizePercentage $values.A.Value }} of this month's logs quota is used; logs are dropped once it is used up."
    }

    # Per source, so a single noisy container (e.g. one stuck in an error loop) is named, and caught hours
    # before the 24h forecast would. Usage metrics have no per-source labels, so this reads Loki directly.
    "Noisy log source" = {
      datasource  = "loki"
      panel       = ["free-tier", "Logs by source (per month)"]
      expr        = "sum by (job, container) (bytes_rate({job=~\".+\"}[1h])) * 86400 * 30 / 1e9"
      threshold   = 10
      comparison  = "gt"
      for         = "30m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ or $labels.container $labels.job }} is logging heavily"
      description = "The last hour of logs from {{ or $labels.container $labels.job }} projects to {{ humanize $values.A.Value }}GB/month, a fifth of the free tier's 50GB on its own."
    }

    # Billable series already account for both series count and scrape rate (the free tier covers 1 data
    # point per minute per series), so faster scrapes use it up just like more series.
    "Metrics quota near limit" = {
      datasource  = "usage"
      panel       = ["free-tier", "Metrics series"]
      expr        = "sum(grafanacloud_org_metrics_billable_series) / sum(grafanacloud_org_metrics_included_series)"
      threshold   = 0.8
      comparison  = "gt"
      for         = "1h"
      no_data     = "OK"
      severity    = "warning"
      summary     = "Metrics near the free tier limit"
      description = "This month's billable series are at {{ humanizePercentage $values.A.Value }} of the free tier. Check scrape intervals and allowlists in etc/alloy."
    }

    # Per job, so a cardinality explosion (e.g. a broken cAdvisor or Traefik allowlist) is named.
    "Noisy metrics source" = {
      datasource  = "prometheus"
      panel       = ["free-tier", "Series by job"]
      expr        = "count by (job) ({__name__=~\".+\"})"
      threshold   = 2500
      comparison  = "gt"
      for         = "30m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ $labels.job }} has too many metric series"
      description = "{{ $labels.job }} has {{ $values.A.Value }} active series, a quarter of the free tier's 10k on its own. Check its allowlist in etc/alloy."
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
      panel       = ["overview", "Uptime"]
      expr        = "sum(up{job=\"integrations/node_exporter\"})"
      threshold   = 1
      comparison  = "lt"
      for         = "5m"
      no_data     = "Alerting"
      severity    = "critical"
      summary     = "nuc is not reporting metrics"
      description = "No node metrics have been received for 5m; the host, Alloy, or its connection to Grafana Cloud is down."
    }

    # A disconnected or unmounted drive has no filesystem metrics at all, which every other disk
    # alert treats as OK. Only fires while node metrics are arriving, so it doesn't echo Host down.
    "Unitek drive missing" = {
      datasource  = "prometheus"
      panel       = ["overview", "Disk used"]
      expr        = "absent(node_filesystem_size_bytes{mountpoint=\"/mnt/unitek\"}) and on() (sum(up{job=\"integrations/node_exporter\"}) > 0)"
      threshold   = 0
      comparison  = "gt"
      for         = "5m"
      no_data     = "OK"
      severity    = "critical"
      summary     = "/mnt/unitek is not mounted"
      description = "The Unitek USB drive is not mounted on nuc. Media, Immich, app config and backup sources live on it. Check the enclosure's connection, `lsblk` and `dmesg`."
    }

    # A quick power cut or kernel panic can recover before Host down fires. Uptime rather than
    # changes() to the boot time, which can shift by a second when NTP adjusts the clock.
    "Host rebooted" = {
      datasource  = "prometheus"
      panel       = ["overview", "Uptime"]
      expr        = "(time() - node_boot_time_seconds) / 60"
      threshold   = 60
      comparison  = "lt"
      for         = "0s"
      no_data     = "OK"
      severity    = "warning"
      summary     = "nuc rebooted"
      description = "nuc has been up for {{ humanize $values.A.Value }} minutes. If the reboot wasn't planned, check `journalctl --list-boots` and `journalctl -b -1 -e` for what happened before it."
    }

    "Disk filling up" = {
      datasource = "prometheus"
      panel      = ["overview", "Disk used"]
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
      panel       = ["overview", "Disk used"]
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
      panel       = ["overview", "Disk used"]
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

    # SMART, from smartctl-exporter (docker/alloy.yml). The disk's own verdict: it trips when an
    # attribute crosses the manufacturer's failure threshold.
    "Disk failing" = {
      datasource  = "prometheus"
      panel       = ["overview", "Disk health"]
      expr        = "min by (instance, device) (smartctl_device_smart_status)"
      threshold   = 1
      comparison  = "lt"
      for         = "5m"
      no_data     = "OK"
      severity    = "critical"
      summary     = "{{ $labels.device }} reports it is failing"
      description = "{{ $labels.device }}'s SMART self-assessment has failed. Copy anything not in the B2 backup off it now, check `sudo smartctl -a /dev/{{ $labels.device }}`, and plan a replacement."
    }

    # A disk can pass its own verdict for months while sectors go bad, so watch the counts grow.
    # Reallocated (5), reported uncorrectable (187), pending (197) and offline uncorrectable (198).
    "Disk sectors going bad" = {
      datasource  = "prometheus"
      panel       = ["overview", "Bad sectors"]
      expr        = "max by (instance, device) (delta(smartctl_device_attribute{attribute_id=~\"5|187|197|198\", attribute_value_type=\"raw\"}[24h]))"
      threshold   = 0
      comparison  = "gt"
      for         = "0s"
      no_data     = "OK"
      severity    = "critical"
      summary     = "{{ $labels.device }} has new bad sectors"
      description = "{{ $labels.device }} gained {{ humanize $values.A.Value }} reallocated, pending or uncorrectable sectors in the last 24h, the usual early sign of a failing disk. Check `sudo smartctl -A /dev/{{ $labels.device }}`, and make sure the last backup succeeded."
    }

    # CRC errors (199) and command timeouts (188) are the link, not the platters: for the Unitek,
    # usually the USB cable, port or enclosure.
    "Disk link errors" = {
      datasource  = "prometheus"
      panel       = ["overview", "Disk health"]
      expr        = "max by (instance, device) (delta(smartctl_device_attribute{attribute_id=~\"188|199\", attribute_value_type=\"raw\"}[24h]))"
      threshold   = 0
      comparison  = "gt"
      for         = "0s"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ $labels.device }} is seeing connection errors"
      description = "{{ $labels.device }} logged {{ humanize $values.A.Value }} new CRC errors or command timeouts in the last 24h. These come from the connection rather than the disk: reseat or replace the cable, or try another USB port."
    }

    "Disk running hot" = {
      datasource  = "prometheus"
      panel       = ["overview", "Disk temperature"]
      expr        = "max by (instance, device) (smartctl_device_temperature{temperature_type=\"current\"})"
      threshold   = 55
      comparison  = "gt"
      for         = "30m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ $labels.device }} is running hot"
      description = "{{ $labels.device }} has been at {{ humanize $values.A.Value }}C for 30m. Hard drives wear faster above about 50C; check the enclosure's airflow."
    }

    # Every SMART alert above treats missing data as OK, so catch the exporter or a disk dropping
    # out. Only while node metrics arrive, so it doesn't echo Host down.
    "Disk health unknown" = {
      datasource  = "prometheus"
      panel       = ["overview", "Disk health"]
      expr        = "(count(smartctl_device_smart_status) or on() vector(0)) and on() (sum(up{job=\"integrations/node_exporter\"}) > 0)"
      threshold   = 2
      comparison  = "lt"
      for         = "15m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "SMART data is missing for a disk"
      description = "Only {{ $values.A.Value }} of the 2 disks are reporting SMART data, so their health isn't being watched. Check `docker logs smartctl-exporter` and that it can see /dev/sda and /dev/sdb."
    }

    # NUC CPUs throttle at about 100C; sustained heat usually means a failing fan or poor airflow.
    "Running hot" = {
      datasource  = "prometheus"
      panel       = ["overview", "Hottest sensor"]
      expr        = "max by (instance, chip, sensor) (node_hwmon_temp_celsius)"
      threshold   = 85
      comparison  = "gt"
      for         = "10m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ $labels.chip }} {{ $labels.sensor }} is running hot"
      description = "{{ $labels.chip }} {{ $labels.sensor }} on {{ $labels.instance }} has been at {{ humanize $values.A.Value }}C for 10m. Check the fan and airflow; sustained heat throttles the CPU."
    }

    # Counts every OOM kill on the host, including inside containers. A brief spike can kill a
    # process without Memory pressure (15m below 10% available) ever firing.
    "Out of memory kill" = {
      datasource  = "prometheus"
      panel       = ["overview", "Memory by container"]
      expr        = "increase(node_vmstat_oom_kill[10m])"
      threshold   = 0
      comparison  = "gt"
      for         = "0s"
      no_data     = "OK"
      severity    = "warning"
      summary     = "The kernel killed a process on {{ $labels.instance }} for running out of memory"
      description = "{{ humanize $values.A.Value }} out-of-memory kill(s) in the last 10m. Check `journalctl -k | grep -i 'killed process'` for which process, and the Docker overview dashboard for memory use."
    }

    "Memory pressure" = {
      datasource  = "prometheus"
      panel       = ["overview", "Memory"]
      expr        = "node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes"
      threshold   = 0.1
      comparison  = "lt"
      for         = "15m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "Low available memory on {{ $labels.instance }}"
      description = "Only {{ humanizePercentage $values.A.Value }} of memory is available; containers may be OOM killed."
    }

    # Available memory can look fine while swap sits full of idle pages, leaving no headroom: a
    # runaway Tdarr then had nowhere to go and thrashed the whole NUC.
    "Swap nearly full" = {
      datasource  = "prometheus"
      panel       = ["overview", "Memory"]
      expr        = "1 - node_memory_SwapFree_bytes / (node_memory_SwapTotal_bytes > 0)"
      threshold   = 0.9
      comparison  = "gt"
      for         = "30m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "Swap is nearly full on {{ $labels.instance }}"
      description = "{{ humanizePercentage $values.A.Value }} of swap is in use, so a memory spike has nowhere to go. Find the biggest users with `grep VmSwap /proc/*/status | sort -k2 -n | tail` (then `ps -p <pid>`), and restart them or add swap."
    }

    "Disk I/O saturated" = {
      datasource  = "prometheus"
      panel       = ["overview", "Pressure"]
      expr        = "rate(node_disk_io_time_seconds_total[5m])"
      threshold   = 0.9
      comparison  = "gt"
      for         = "30m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ $labels.device }} is saturated"
      description = "{{ $labels.device }} has been busy {{ humanizePercentage $values.A.Value }} of the time for 30m; it may be overloaded or failing."
    }

    # CPU. Pressure measures work actually being held up, so a transcode using every core only
    # alerts if it starves something else. The rest catch disk stalls, runaway containers and
    # plain saturation.
    "CPU pressure" = {
      datasource  = "prometheus"
      panel       = ["overview", "Pressure"]
      expr        = "rate(node_pressure_cpu_waiting_seconds_total[5m])"
      threshold   = 0.5
      comparison  = "gt"
      for         = "30m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "Processes on {{ $labels.instance }} are waiting for CPU"
      description = "Tasks have spent {{ humanizePercentage $values.A.Value }} of the last 30m waiting for a CPU. Check the Docker overview dashboard or `top` for what's using it."
    }

    "Disk wait" = {
      datasource  = "prometheus"
      panel       = ["overview", "Pressure"]
      expr        = "avg by (instance) (rate(node_cpu_seconds_total{mode=\"iowait\"}[5m]))"
      threshold   = 0.3
      comparison  = "gt"
      for         = "30m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ $labels.instance }} is stalled waiting on disk"
      description = "CPUs have spent {{ humanizePercentage $values.A.Value }} of the last 30m waiting on disk I/O. Usually a slow or failing disk (check the Unitek drive and `dmesg`), or something hammering it."
    }

    # Expected heavy users are excluded; anything else using a quarter of the machine for an hour
    # is likely stuck or not doing what it should.
    "Runaway container" = {
      datasource  = "prometheus"
      panel       = ["overview", "CPU by container"]
      expr        = "sum by (instance, container) (rate(container_cpu_usage_seconds_total{container!~\"tdarr|jellyfin|immich-machine-learning\"}[5m]))"
      threshold   = 3
      comparison  = "gt"
      for         = "1h"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ $labels.container }} is using a lot of CPU"
      description = "{{ $labels.container }} has used {{ humanize $values.A.Value }} cores for an hour. It may be stuck in a loop, or compromised."
    }

    "CPU saturated" = {
      datasource  = "prometheus"
      panel       = ["overview", "CPU"]
      expr        = "1 - avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m]))"
      threshold   = 0.9
      comparison  = "gt"
      for         = "30m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ $labels.instance }} CPU is saturated"
      description = "CPU has been {{ humanizePercentage $values.A.Value }} busy for 30m."
    }

    # From the metrics resticprofile writes after each backup (etc/resticprofile.yaml).
    "Backup failed" = {
      datasource  = "prometheus"
      panel       = ["backups", "Result"]
      expr        = "resticprofile_backup_status"
      threshold   = 1
      comparison  = "lt"
      for         = "0s"
      no_data     = "OK"
      severity    = "critical"
      summary     = "{{ $labels.profile }} backup failed"
      description = "The last {{ $labels.profile }} backup to Backblaze failed. Check /var/log/resticprofile/{{ $labels.profile }}.log on nuc."
    }

    # Backups run daily, so a metrics file older than a day and a bit means the timer stopped.
    # The weekly check has its own file and threshold below.
    "Backup stale" = {
      datasource  = "prometheus"
      panel       = ["backups", "Since last backup"]
      expr        = "(time() - node_textfile_mtime_seconds{file!~\".*maintenance.prom\"}) / 3600"
      threshold   = 26
      comparison  = "gt"
      for         = "15m"
      no_data     = "OK"
      severity    = "critical"
      summary     = "No backup from {{ $labels.file }} in over a day"
      description = "The last backup result ({{ $labels.file }}) is {{ humanize $values.A.Value }}h old. Check `systemctl list-timers 'resticprofile-*'` on nuc."
    }

    # Written by the maintenance profile's hooks after the weekly `restic check`.
    "Backup check failed" = {
      datasource  = "prometheus"
      panel       = ["backups", "Repository check"]
      expr        = "resticprofile_check_success"
      threshold   = 1
      comparison  = "lt"
      for         = "0s"
      no_data     = "OK"
      severity    = "critical"
      summary     = "Backup repository check failed"
      description = "The weekly restic check found a problem with the backups in Backblaze. Check /var/log/resticprofile/maintenance.log on nuc."
    }

    "Backup check stale" = {
      datasource  = "prometheus"
      panel       = ["backups", "Repository check"]
      expr        = "(time() - node_textfile_mtime_seconds{file=~\".*maintenance.prom\"}) / 86400"
      threshold   = 8
      comparison  = "gt"
      for         = "15m"
      no_data     = "OK"
      severity    = "warning"
      summary     = "Backup repository check hasn't run in over a week"
      description = "The last restic check result is {{ humanize $values.A.Value }} days old. Check `systemctl list-timers 'resticprofile-*'` on nuc."
    }

    # Compressed bytes the last run added to B2. Runs are normally under 1GB; ransomware encrypting files
    # changes everything at once (and doesn't compress), as does something big landing in a backed-up path.
    # Stays firing until the next normal run.
    "Backup unusually large" = {
      datasource  = "prometheus"
      panel       = ["backups", "Uploaded per run"]
      expr        = "max by (profile) (resticprofile_backup_added_bytes_packed) / 1e9"
      threshold   = 5
      comparison  = "gt"
      for         = "0s"
      no_data     = "OK"
      severity    = "warning"
      summary     = "{{ $labels.profile }} backup uploaded {{ humanize $values.A.Value }}GB"
      description = "The last {{ $labels.profile }} backup added {{ humanize $values.A.Value }}GB to B2, far more than usual. Check what changed with `restic diff` between the last two snapshots; mass changes can mean ransomware."
    }

    # Retention removes about one snapshot per profile as it adds one, and prune frees little, so a big
    # drop in either means backups were deleted. Written daily by the immich profile's run-finally hook.
    "Backups disappeared" = {
      datasource  = "prometheus"
      panel       = ["backups", "Stored in B2"]
      expr        = <<-EOT
        1 - (
          label_replace(max(resticprofile_repository_snapshots) / max(max_over_time(resticprofile_repository_snapshots[2d])), "measure", "snapshots", "", "")
          or
          label_replace(max(resticprofile_repository_size_bytes) / max(max_over_time(resticprofile_repository_size_bytes[2d])), "measure", "size", "", "")
        )
      EOT
      threshold   = 0.2
      comparison  = "gt"
      for         = "0s"
      no_data     = "OK"
      severity    = "critical"
      summary     = "The backup repository lost {{ humanizePercentage $values.A.Value }} of its {{ $labels.measure }}"
      description = "The B2 repository's {{ $labels.measure }} dropped {{ humanizePercentage $values.A.Value }} in the last 2 days, which retention doesn't do. Check `restic snapshots` and the B2 bucket for deleted files."
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

      # Alerts with a `panel` link to it, which shows their state on the panel (the heart icon).
      annotations = merge(
        {
          summary     = rule.value.summary
          description = rule.value.description
        },
        try(rule.value.panel, null) == null ? {} : {
          __dashboardUid__ = grafana_dashboard.tqid["${rule.value.panel[0]}.json"].uid
          __panelId__      = tostring(local.dashboard_panel_ids[rule.value.panel[0]][rule.value.panel[1]][0])
        },
      )

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
        # One notification per affected thing, so the Discord template's CommonAnnotations are populated.
        # Listed explicitly rather than "..." so Grafana's internal labels don't end up in the title.
        group_by = ["alertname", "service", "container", "job", "instance", "mountpoint", "device", "reason", "profile", "file", "chip", "sensor", "client", "RequestHost", "measure", "kind", "encoder"]

        group_wait      = local.notification_timing.group_wait
        group_interval  = local.notification_timing.group_interval
        repeat_interval = local.notification_timing.repeat_interval[rule.value.severity]
      }
    }
  }
}
