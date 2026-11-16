variable "cloudflare_account_id" {
  type = string
}

variable "cloudflare_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_zone_name" {
  type    = string
  default = "tqid.dev"
}

variable "cloudflare_access_allowed_emails" {
  type = set(string)
}

variable "subdomains" {
  type = set(object({
    name   = string
    public = optional(bool, false)
    # App Launcher logo: a dashboard-icons name (defaults to `name`) or a full image URL
    logo = optional(string)
  }))
  default = [
    { name = "budge", logo = "https://cdn.jsdelivr.net/gh/TheQueenIsDead/budge@main/web/public/favicon.ico" },
    { name = "chat", public = true, logo = "https://cdn.jsdelivr.net/gh/jdecked/twemoji@v17.0.3/assets/72x72/1f4ac.png" },
    { name = "cleanuparr" },
    { name = "files", logo = "filebrowser-quantum" },
    { name = "jellyfin", public = true },
    { name = "jellyseer", public = true, logo = "seerr" },
    { name = "memos" },
    { name = "portainer" },
    { name = "photos", public = true, logo = "immich" },
    { name = "prowlarr" },
    { name = "qbittorrent" },
    { name = "radarr" },
    { name = "recipes", logo = "mealie" },
    { name = "sonarr" },
    { name = "speed", public = true, logo = "librespeed" },
    { name = "sportarr" },
    { name = "tdarr" },
    { name = "traefik" },
  ]
}
