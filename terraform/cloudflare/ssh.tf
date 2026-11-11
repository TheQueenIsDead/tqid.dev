# A shell on the NUC in the browser, at ssh.tqid.dev, through the tunnel and behind Access.
# Cloudflare renders the terminal (application type "ssh"); sshd then asks for tqid's password, so
# a login needs both the GitHub account and the password.
#
# No short-lived certificates: the browser terminal only presents one for the user named by the
# email prefix ("me"), never tqid, and a passwordless account behind GitHub alone would be weaker.
#   https://developers.cloudflare.com/cloudflare-one/applications/non-http/browser-rendering/

resource "cloudflare_zero_trust_access_application" "ssh" {
  zone_id = data.cloudflare_zone.this.id
  name    = "ssh"
  domain  = "ssh.${data.cloudflare_zone.this.name}"
  type    = "ssh"
  # A root shell, so log in again more often than the 24h the web apps get
  session_duration          = "4h"
  auto_redirect_to_identity = true
  app_launcher_visible      = true
  allowed_idps              = [local.github_idp_id]
  policies = [{
    id         = cloudflare_zero_trust_access_policy.github.id
    precedence = 1
  }]
}

resource "cloudflare_dns_record" "ssh" {
  zone_id = data.cloudflare_zone.this.id
  name    = "ssh.${var.cloudflare_zone_name}"
  content = "${data.cloudflare_zero_trust_tunnel_cloudflared.nuc.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}
