# Cleanuparr

Fake releases are a torrent named like an episode that contains a `.exe`, `.iso` or archive
instead. qBittorrent's **Excluded file names** stops the file downloading, but the torrent then
completes empty and Sonarr stops at *"no files found to import"*, waiting for someone to remove
it. [Cleanuparr](https://github.com/Cleanuparr/Cleanuparr) closes that loop: its Malware Blocker
skips the blocked files in qBittorrent and, when nothing wanted is left, removes the download
through Sonarr or Radarr, which blocklists the release and searches again.

It runs in [`docker/arr.yml`](../docker/arr.yml) at `https://cleanuparr.tqid.dev`, behind
Cloudflare Access like the other *arr apps. Its settings live in its own database under
`${CONFIG_FOLDER}/cleanuparr` (backed up with the `apps` restic profile), not in this repo.

## Settings

Services are reached by container name on the `backend` network. API keys are under each
app's **Settings > General**.

| Section | Setting | Value |
| --- | --- | --- |
| Download Clients | qBittorrent | `http://qbittorrent:8080`, the web UI username and password |
| Arrs | Sonarr | `http://sonarr:8989` and its API key |
| Arrs | Radarr | `http://radarr:7878` and its API key |
| Arrs | Sportarr | `http://sportarr:1867` and its API key, API version v4 |
| Malware Blocker | Enabled | On, every 5 minutes |
| Malware Blocker | Delete if any file is blocked | Off: the blocklist covers `.jpg` and `.txt` too, so this removed real releases with a poster or a tracker's ad file. Off, those files are just skipped, and a download is only removed when nothing in it is wanted |
| Malware Blocker | Sonarr and Radarr blocklist | `https://cleanuparr.pages.dev/static/blacklist`, type Blacklist |
| Malware Blocker | Process downloads with no content ID | Off |
| Queue Cleaner | Failed imports | Remove after 3 strikes, so downloads Sonarr can't import don't sit in the queue |

The official blocklist covers executables, disc images, archives and sample files, and is
reloaded every 5 minutes. If a legitimate release ever arrives as a `.rar`, switch to
`https://cleanuparr.pages.dev/static/blacklist_permissive`.

**Seeker** runs the replacement search for anything Cleanuparr removes, so turn its **Search**
toggle on or a removed fake just leaves a gap. Leave **Proactive search** (missing items and
upgrades) off: the indexers already rate-limit Sonarr and Radarr, and the *arrs search for
missing items themselves.

## Checking it

Blocked and removed downloads show in Cleanuparr's **Events** page, and as
`Blocklisted`/`Grabbed` pairs in Sonarr's **History**. Its logs are in Loki:
`{container="cleanuparr"}`.
