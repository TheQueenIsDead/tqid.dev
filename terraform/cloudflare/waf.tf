locals {
  # Hostnames that bypass Access (public = true in var.subdomains)
  public_hostnames = [
    for s in var.subdomains : "${s.name}.${data.cloudflare_zone.this.name}" if s.public
  ]
}

# The apps that bypass Access are only patching away from anyone on the internet, so cut them
# down to the countries they're used from. The Access-protected apps are unaffected, as is
# the Grafana synthetic probe (Sydney).
# A zone has one custom rules ruleset; this owns it, so custom rules belong here, not the dashboard.
#   https://developers.cloudflare.com/waf/custom-rules/
#   https://developers.cloudflare.com/ruleset-engine/rules-language/fields/reference/ip.src.country/
resource "cloudflare_ruleset" "waf_custom" {
  zone_id     = data.cloudflare_zone.this.id
  name        = "default"
  description = "Custom WAF rules"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules = [{
    description = "Public apps: NZ and AU only"
    action      = "block"
    expression  = "(http.host in {${join(" ", formatlist("\"%s\"", local.public_hostnames))}} and not ip.src.country in {\"NZ\" \"AU\"})"
    enabled     = true
  }]
}
