data "cloudflare_zone" "this" {
  name = var.cloudflare_zone_name
}

data "cloudflare_zero_trust_access_identity_provider" "github" {
  account_id = var.cloudflare_account_id
  name       = "GitHub"
}

data "cloudflare_zero_trust_tunnel_cloudflared" "nuc" {
  account_id = var.cloudflare_account_id
  name       = "nuc"
  # Unset, the lookup also matches deleted tunnels, and once returned a deleted "nuc"
  # (e8ac3e02-...) instead of the live one, which is why the IDs below were pinned for a while.
  is_deleted = false
}

resource "cloudflare_zero_trust_access_policy" "github" {
  account_id = var.cloudflare_account_id
  name       = "Allow TheQueenIsDead"
  decision   = "allow"

  include {
    email = var.cloudflare_access_allowed_emails
  }
}

resource "cloudflare_zero_trust_access_policy" "public" {
  account_id = var.cloudflare_account_id
  name       = "Bypass Public"
  decision   = "bypass"

  include {
    everyone = true
  }
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
  allowed_idps = [
    data.cloudflare_zero_trust_access_identity_provider.github.id
  ]
  policies = each.value.public ? [
    cloudflare_zero_trust_access_policy.public.id
    ] : [
    cloudflare_zero_trust_access_policy.github.id
  ]
}

resource "cloudflare_record" "http_app" {
  for_each = { for k, v in var.subdomains : v.name => v }
  zone_id  = data.cloudflare_zone.this.id
  name     = each.value.name
  content  = "${data.cloudflare_zero_trust_tunnel_cloudflared.nuc.id}.cfargotunnel.com"
  type     = "CNAME"
  ttl      = 1
  proxied  = true
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = data.cloudflare_zero_trust_tunnel_cloudflared.nuc.id
  config {
    origin_request {
      bastion_mode             = false
      disable_chunked_encoding = false
      http2_origin             = false
      keep_alive_connections   = 0
      no_happy_eyeballs        = false
      no_tls_verify            = false
      proxy_port               = 0
    }
    dynamic "ingress_rule" {
      for_each = { for k, v in var.subdomains : v.name => v }
      content {
        hostname = "${ingress_rule.value.name}.${var.cloudflare_zone_name}"
        service  = ingress_rule.value.name == "traefik" ? "http://traefik:8080" : "http://traefik:80"
      }
    }
    ingress_rule {
      service = "http_status:404"
    }
  }
}
