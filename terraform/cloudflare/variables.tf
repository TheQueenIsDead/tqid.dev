variable "cloudflare_account_id" {
  type = string
}

variable "cloudflare_token" {
  type = string
  sensitive = true
}

variable "cloudflare_zone_name" {
  type = string
  default = "tqid.dev"
}

variable "cloudflare_access_allowed_emails" {
  type = set(string)
}

variable "subdomains" {
  type = set(object({
    name   = string
    public = optional(bool, false)
  }))
  default = [
    { name = "apps" },
    { name = "actual" },
    { name = "budge" },
    { name = "chat", public = true },
    { name = "filebrowser" },
    { name = "files" },
    { name = "home", public = false },
    { name = "jellyfin", public = true },
    { name = "jellyseer", public = true },
    { name = "memos" },
    { name = "portainer" },
    { name = "photos", public = true },
    { name = "prism" },
    { name = "prowlarr" },
    { name = "qbittorrent" },
    { name = "radarr" },
    { name = "recipes"},
    { name = "sonarr" },
    { name = "speed", public = true },
    { name = "sportarr" },
    { name = "tdarr" },
    { name = "traefik" },
  ]
}
