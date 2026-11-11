data "cloudflare_zone" "this" {
  filter = {
    name = var.cloudflare_zone_name
  }
}

# v5's single identity provider lookup only takes an ID, so find GitHub by name in the list.
data "cloudflare_zero_trust_access_identity_providers" "this" {
  account_id = var.cloudflare_account_id
}

data "cloudflare_zero_trust_tunnel_cloudflared" "nuc" {
  account_id = var.cloudflare_account_id
  filter = {
    name = "nuc"
    # Unset, the lookup also matches deleted tunnels, and once returned a deleted "nuc"
    # (e8ac3e02-...) instead of the live one, which is why the IDs below were pinned for a while.
    is_deleted = false
  }
}

locals {
  github_idp_id = one([
    for idp in data.cloudflare_zero_trust_access_identity_providers.this.result : idp.id if idp.name == "GitHub"
  ])
}

resource "cloudflare_zero_trust_access_policy" "github" {
  account_id = var.cloudflare_account_id
  name       = "Allow TheQueenIsDead"
  decision   = "allow"

  include = [for email in var.cloudflare_access_allowed_emails : { email = { email = email } }]
}

resource "cloudflare_zero_trust_access_policy" "public" {
  account_id = var.cloudflare_account_id
  name       = "Bypass Public"
  decision   = "bypass"

  include = [{ everyone = {} }]
}

resource "cloudflare_zero_trust_access_application" "this" {

  for_each = { for k, v in var.subdomains : v.name => v }

  zone_id                   = data.cloudflare_zone.this.id
  name                      = each.key
  domain                    = "${each.value.name}.${data.cloudflare_zone.this.name}"
  type                      = "self_hosted"
  session_duration          = "24h"
  auto_redirect_to_identity = false
  app_launcher_visible      = true
  allowed_idps              = [local.github_idp_id]
  policies = [{
    id         = each.value.public ? cloudflare_zero_trust_access_policy.public.id : cloudflare_zero_trust_access_policy.github.id
    precedence = 1
  }]
}

resource "cloudflare_dns_record" "http_app" {
  for_each = { for k, v in var.subdomains : v.name => v }
  zone_id  = data.cloudflare_zone.this.id
  # v5 wants the full hostname, as the API returns it
  name    = "${each.value.name}.${var.cloudflare_zone_name}"
  content = "${data.cloudflare_zero_trust_tunnel_cloudflared.nuc.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = data.cloudflare_zero_trust_tunnel_cloudflared.nuc.id
  config = {
    ingress = concat(
      [
        for s in var.subdomains : {
          hostname = "${s.name}.${var.cloudflare_zone_name}"
          service  = s.name == "traefik" ? "http://traefik:8080" : "http://traefik:80"
        }
      ],
      [{
        hostname = "ssh.${var.cloudflare_zone_name}"
        service  = "ssh://host.docker.internal:22"
      }],
      [{ service = "http_status:404" }],
    )
  }
}
