locals {
  notification_timing = {
    # Wait before the first notification, so related alerts arrive together.
    group_wait = "30s"
    # Wait before notifying about changes to an already-notified group.
    group_interval = "5m"
    # How often a still-firing alert is re-sent.
    repeat_interval = {
      critical = "4h"
      warning  = "24h"
    }
  }
}

# Notification layout for the Discord contact point. The contact point itself is managed manually in the
# Grafana UI (to keep its webhook out of Terraform) and uses these templates via its settings:
#   Title:   {{ template "discord.title" . }}
#   Message: {{ template "discord.message" . }}
resource "grafana_message_template" "discord" {
  name     = "discord"
  template = <<-EOT
    {{ define "discord.title" -}}
    {{ if eq .Status "firing" }}🔥{{ else }}✅{{ end }} {{ .CommonLabels.alertname }}{{ with .CommonAnnotations.summary }}: {{ . }}{{ end }}
    {{- end }}

    {{ define "discord.message" -}}
    {{ range .Alerts -}}
    **{{ if eq .Status "firing" }}Firing{{ else }}Resolved{{ end }}**{{ with .Labels.severity }} · {{ . }}{{ end }}
    {{ with .Annotations.description }}{{ . }}
    {{ end -}}
    Started <t:{{ .StartsAt.Unix }}:R>{{ if eq .Status "resolved" }}, resolved <t:{{ .EndsAt.Unix }}:R>{{ end }}
    [View rule]({{ .GeneratorURL }}){{ if eq .Status "firing" }}{{ with .SilenceURL }} · [Silence]({{ . }}){{ end }}{{ end }}

    {{ end -}}
    {{- end }}
  EOT
}
