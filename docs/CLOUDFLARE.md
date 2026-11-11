# Cloudflare

[//]: # (TODO: Write more informative documentation)

## Cloudflared (Tunnels)

Runs a daemon that reaches out to cloudflare, config is done via the UI and exposes a few subdomains (public addresses)

## Access

Cloudflare zero trust is used to authenticate with apps on the tqid.dev subdomain.
## Browser SSH

`ssh.tqid.dev` opens a shell on the NUC in the browser, behind the same GitHub login as the other
apps, with a 4h session. The tunnel sends it to the host's sshd (`terraform/cloudflare/ssh.tf`),
and Cloudflare signs a short-lived SSH certificate for each login, so there is no key or password
to keep.

The host side is in `ansible/nuc.yml`, and needs two things from you once:

1. After Terraform has applied, copy the `ssh_ca_public_key` output (HCP Terraform, the
   `cloudflare` workspace's outputs) into `ansible/files/cloudflare-ssh-ca.pub`.
2. Set `ssh_principals` in `ansible/nuc.yml` to the part of your Access email before the `@`.
   Certificates carry that as their username, and this maps it to `tqid`.

Then log in at `ssh.tqid.dev` as `tqid`. It does not help if the NUC hangs: the tunnel goes down
with it.

cloudflared reaches sshd over its own Docker network, `ssh` (10.222.22.0/29). The `ssh-guard`
unit on the host drops port 22 from every other container, so a compromised app can't try sshd.
Only `tqid` may log in over SSH, and never root. Password logins are still on for the LAN: once
you log in with a key at home, set `PasswordAuthentication no` in
`/etc/ssh/sshd_config.d/10-logins.conf` (via `ansible/nuc.yml`).
