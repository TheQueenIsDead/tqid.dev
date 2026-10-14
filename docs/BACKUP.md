# Backups

Offsite backups run with [restic](https://restic.net/), scheduled by
[resticprofile](https://creativeprojects.github.io/resticprofile/), stored in Backblaze B2.

The config lives in [`etc/resticprofile.yaml`](../etc/resticprofile.yaml). The
[Restic workflow](../.github/workflows/restic.yml) deploys it to the NUC and installs the
systemd timers — it does **not** run the backups. The host does that on its own timers, so
backups keep happening when GitHub or the self-hosted runner is down.

## What gets backed up

Only data and config that would be slow or impossible to rebuild by hand.

| Profile | Sources | Schedule |
| --- | --- | --- |
| `apps` | Memos and Mealie volumes; radarr, sonarr, prowlarr, sportarr, qbittorrent, jellyfin, jellyseer and tdarr config under `/mnt/unitek/config` | Daily, 02:00 |
| `immich` | `library/`, `upload/`, `profile/` and `backups/` under `/mnt/unitek/immich/library` | Daily, 03:00 |
| `maintenance` | — (`restic check` with `--read-data-subset 5%`) | Sundays, 05:00 |

Retention is 7 daily, 4 weekly, 12 monthly, 3 yearly, pruned after each backup.

Docker is snap-installed on the NUC, so named volumes live under
`/var/snap/docker/common/var-lib-docker/volumes`, not `/var/lib/docker/volumes`. Volumes from
compose files without a `name:` carry the `docker_` project prefix (`docker_memos`,
`docker_mealie-data`). Renaming a compose project renames its volumes, so update the paths in
`etc/resticprofile.yaml` alongside it.

Deliberately **not** backed up:

- **Media** — `/mnt/unitek/{movies,tv,sport,downloads,media}`. Large, and re-acquirable.
- **The file store** — `/mnt/unitek/files`, mostly raw photography. To be culled before it is
  worth keeping offsite.
- **Finance apps** — Actual and budge re-sync from Akahu.
- **Caches, artwork and transcodes** — jellyfin cache, metadata and transcodes, *arr
  `MediaCover`, tdarr cache, immich `thumbs/` and `encoded-video/`, logs. All regenerated.
- **Everything else on the host** — Pi-hole, Portainer, Librespeed, Homarr, Filebrowser config,
  `/etc`. Cheap to recreate, or recreated from this repo.
- **The live Immich postgres directory** (`/home/tqid/immich/postgres`). Copying a running
  postgres data directory does not reliably restore. Immich's own nightly dump in `backups/`
  is stored instead.

## Immich's database

Immich dumps its database every night at 02:00 into `backups/` in the upload folder, and the
`immich` profile picks that dump up at 03:00. Check it is switched on under **Administration >
Settings > Backup Settings** — without it the photos are backed up but the albums, people,
faces and metadata are not.

## A caveat on consistency

The `apps` profile copies Memos and Mealie volumes and the *arr config while the containers
are running. restic is consistent per file, but not across a SQLite database that is
mid-write, so a snapshot can in principle catch a torn write. In practice SQLite's WAL recovers
from this, and 02:00 is a quiet hour. The *arr apps also keep their own zipped backups in their
config folders, which are included.

If that stops being an acceptable trade, the options are a `run-before` that pauses the
affected containers for the duration, or per-app dumps.

## Backblaze setup

1. Create a **private** bucket in the [B2 console](https://secure.backblaze.com/b2_buckets.htm).
   The bucket name is global, so it may need a suffix. Enable object lock if you want
   ransomware protection — restic works with it, but `forget --prune` will fail on locked
   objects until they expire.
2. Note the bucket's **Endpoint** (e.g. `s3.us-west-004.backblazeb2.com`). It has to match
   the `repository` in `etc/resticprofile.yaml`, along with the bucket name.
3. Create an **Application Key** scoped to that bucket, with read and write access. Copy the
   `keyID` and `applicationKey` — the secret is shown once.

restic talks to B2 over its S3-compatible API rather than the native `b2:` backend, which is
[what restic recommends](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html#backblaze-b2).

## Repository secrets

Set these in the repository's Actions secrets:

| Secret | Value |
| --- | --- |
| `RESTIC_PASSWORD` | Encryption passphrase for the repo. Generate with `openssl rand -base64 32`. |
| `B2_APPLICATION_KEY_ID` | The `keyID` from the application key. |
| `B2_APPLICATION_KEY` | The `applicationKey` from the application key. |

> **Keep `RESTIC_PASSWORD` somewhere outside this setup**, along with the other secrets that only
> live in GitHub and HCP Terraform (`CLOUDFLARE_TOKEN`, `NEWT_ID`/`NEWT_SECRET`, `DB_PASSWORD`,
> the Grafana tokens). It is not recoverable, and without
> it the backups are so much noise. A GitHub secret is write-only — it cannot be read back.

The workflow writes all three to `/etc/resticprofile/env` (`0600`, root) and the profiles
reference it via `env-file`. They are kept out of the systemd units on purpose: anything in a
unit's `Environment=` is readable by every user on the box
([resticprofile#367](https://github.com/creativeprojects/resticprofile/issues/367)).

## Host requirements

The self-hosted runner needs passwordless `sudo` for the two commands the workflow uses — it
installs binaries to `/usr/local/bin`, writes to `/etc/resticprofile`, and registers systemd
units. The backups themselves run as root (`schedule-permission: system`) because they read
Docker volumes and other users' files.

```shell
# Use the user the runner runs as: ps -o user= -C Runner.Listener
echo 'tqid ALL=(root) NOPASSWD: /usr/bin/install, /usr/local/bin/resticprofile' \
  | sudo tee /etc/sudoers.d/github-runner
sudo chmod 0440 /etc/sudoers.d/github-runner
sudo visudo -c
```

Scoping it to two commands keeps it auditable, but `sudo install` can write any file as root,
so the runner is effectively root on the NUC — as it already is through Docker. Keep
`runs-on: self-hosted` to workflows triggered from `main` or by hand, never `pull_request`.

## Operating it

Everything below is on the NUC. `resticprofile` picks up `/etc/resticprofile/profiles.yaml`
by default once deployed.

```shell
# What is scheduled, and when it next runs
sudo resticprofile status --all
systemctl list-timers 'resticprofile-*'

# Snapshots, and repo size
sudo resticprofile --name apps snapshots
sudo resticprofile --name apps stats

# Run one now, out of band
sudo resticprofile --name apps backup

# Logs
tail -f /var/log/resticprofile/apps.log
journalctl -u resticprofile-backup@profile-apps.service
```

The same runs are available from the Actions tab via the **Restic** workflow's
`workflow_dispatch`, which takes a command and a profile.

## Restoring

Any command resticprofile doesn't recognise is handed to `restic` with the profile's
repository and credentials already applied, so drive restores through it rather than calling
`restic` directly — bare `restic` has no idea where the repo is or how to unlock it.

```shell
# Find the snapshot
sudo resticprofile --name apps snapshots

# Everything, somewhere safe to inspect first
sudo resticprofile --name apps restore <snapshot-id> --target /mnt/unitek/restore

# Or one path, back where it came from
sudo resticprofile --name apps restore <snapshot-id> --target / --include /mnt/unitek/config/jellyfin

# Browse before committing to it
sudo resticprofile --name apps ls <snapshot-id>
```

Tdarr is backed up from its own nightly export (`server/Tdarr/Backups`), not its live
database. To restore, put back `tdarr/configs` and the `Backups` folder, stop Tdarr, empty
`server/Tdarr` of everything except `Backups`, and unzip the newest zip into `server/Tdarr`.

```shell
sudo resticprofile --name apps restore latest --target / \
  --include /mnt/unitek/config/tdarr/configs --include /mnt/unitek/config/tdarr/server/Tdarr/Backups
docker compose -f docker/arr.yml stop tdarr
cd /mnt/unitek/config/tdarr/server/Tdarr
sudo find . -mindepth 1 -maxdepth 1 ! -name Backups -exec rm -rf {} +
sudo unzip "$(ls -t Backups/*.zip | head -1)" -d .
docker compose -f docker/arr.yml start tdarr
```

Restoring Immich is two steps: restore the four folders under `/mnt/unitek/immich/library`,
then load the newest dump from `backups/` into a fresh database.

```shell
docker compose -f docker/immich.yml up -d database
gunzip --stdout /mnt/unitek/immich/library/backups/<newest>.sql.gz \
  | docker exec -i immich_postgres psql --username=postgres --dbname=postgres
docker compose -f docker/immich.yml up --wait
```

## First run

The first `apps` backup uploads everything and will take a while. `immich` will take longer.
Both are `priority: low` and `ionice` class 2/7, so they should stay out of the way, but it's
worth kicking the first one off manually rather than finding out at 02:00.

A restore is the only real test of a backup. Worth doing once, now, before it matters.

## Monitoring

Each backup writes its result to `/var/lib/resticprofile/metrics/<profile>.prom`. Alloy reads
that directory with node exporter's textfile collector (`etc/alloy/node.alloy`), and the `Host`
alert group in `terraform/grafana/alerts.tf` raises:

- **Backup failed** — `resticprofile_backup_status` is 0 (1 is a warning, 2 a success).
- **Backup stale** — a profile's metrics file has not been written in over 26 hours, i.e. the
  timer has stopped.

Removing a profile leaves its `.prom` file behind, which will then alert as stale; delete the
file on the NUC when you retire a profile.
