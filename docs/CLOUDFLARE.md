# Cloudflare

[//]: # (TODO: Write more informative documentation)

## Cloudflared (Tunnels)

Runs a daemon that reaches out to cloudflare, config is done via the UI and exposes a few subdomains (public addresses)

## Access

Cloudflare zero trust is used to authenticate with apps on the tqid.dev subdomain.
## Browser SSH

`ssh.tqid.dev` opens a shell on the NUC in the browser, behind the same GitHub login as the other
apps, with a 4h session. The tunnel sends it to the host's sshd (`terraform/cloudflare/ssh.tf`).
Log in as `tqid` with its password, so getting in takes both the GitHub account and the password.

Cloudflare's short-lived SSH certificates aren't used: the browser terminal only presents one for
the user named by the email prefix (`me`), never `tqid`.

It does not work through Zscaler (the terminal's WebSocket is cut, leaving a blinking cursor), and
it does not help if the NUC hangs: the tunnel goes down with it.

cloudflared reaches sshd over its own Docker network, `ssh` (10.222.22.0/29). The `ssh-guard`
unit on the host drops port 22 from every other container, so a compromised app can't try sshd.
Only `tqid` may log in over SSH, and never root. Password logins are still on for the LAN: once
you log in with a key at home, set `PasswordAuthentication no` in
`/etc/ssh/sshd_config.d/10-logins.conf` (via `ansible/nuc.yml`).
