# Dashboards are plain JSON in dashboards/, so they can be edited in the Grafana UI and exported back.
# They link to each other through the "tqid" tag.
resource "grafana_dashboard" "tqid" {
  for_each = fileset("${path.module}/dashboards", "*.json")

  folder      = grafana_folder.tqid.uid
  config_json = file("${path.module}/dashboards/${each.value}")
}
