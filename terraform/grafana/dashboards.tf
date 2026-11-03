# Dashboards are plain JSON in dashboards/, so they can be edited in the Grafana UI and exported back.
# They link to each other through the "tqid" tag.
resource "grafana_dashboard" "tqid" {
  for_each = fileset("${path.module}/dashboards", "*.json")

  folder      = grafana_folder.tqid.uid
  config_json = file("${path.module}/dashboards/${each.value}")
}

locals {
  # Panel IDs by dashboard (file name without .json) and title, so an alert can name the panel it
  # belongs to and survive panels being renumbered. A title can repeat (e.g. a stat and a graph of the
  # same thing); the first one wins.
  dashboard_panel_ids = {
    for f in fileset("${path.module}/dashboards", "*.json") :
    trimsuffix(f, ".json") => { for p in jsondecode(file("${path.module}/dashboards/${f}")).panels : p.title => p.id... }
  }
}
