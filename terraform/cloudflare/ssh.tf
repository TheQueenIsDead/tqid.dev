# A shell on the NUC in the browser, at ssh.tqid.dev, through the tunnel and behind Access.
# Cloudflare renders the terminal (application type "ssh"), and signs a short-lived SSH certificate
# for whoever passes the policy, which sshd trusts (ansible/nuc.yml). So there are no keys or
# passwords to hold, and no way to log in that skips Access.
#   https://developers.cloudflare.com/cloudflare-one/applications/non-http/browser-rendering/
#   https://developers.cloudflare.com/cloudflare-one/identity/users/short-lived-certificates/

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

resource "cloudflare_zero_trust_access_short_lived_certificate" "ssh" {
  zone_id = data.cloudflare_zone.this.id
  app_id  = cloudflare_zero_trust_access_application.ssh.id
}

resource "cloudflare_dns_record" "ssh" {
  zone_id = data.cloudflare_zone.this.id
  name    = "ssh.${var.cloudflare_zone_name}"
  content = "${data.cloudflare_zero_trust_tunnel_cloudflared.nuc.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

# Goes in ansible/files/cloudflare-ssh-ca.pub, for sshd to trust. A public key, so safe to commit.
output "ssh_ca_public_key" {
  value = cloudflare_zero_trust_access_short_lived_certificate.ssh.public_key
}
