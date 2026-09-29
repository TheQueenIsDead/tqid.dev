# Backups

Offsite backups run with [restic](https://restic.net/), scheduled by
[resticprofile](https://creativeprojects.github.io/resticprofile/), stored in Backblaze B2.

The config lives in [`etc/resticprofile.yaml`](../etc/resticprofile.yaml). The
[Restic workflow](../.github/workflows/restic.yml) deploys it to the NUC and installs the
systemd timers — it does **not** run the backups. The host does that on its own timers, so
backups keep happening when GitHub or the self-hosted runner is down.

## What gets backed up

| Profile | Sources | Schedule |
| --- | --- | --- |
| `nuc` | `/var/lib/docker/volumes`, `/mnt/unitek/config`, `/mnt/unitek/files` | Daily, 02:00 |
| `immich` | `/mnt/unitek/immich/dump` (pg_dumpall), `/mnt/unitek/immich/library` | Daily, 03:00 |
| `maintenance` | — (`restic check` with `--read-data-subset 5%`) | Sundays, 05:00 |

Retention is 7 daily, 4 weekly, 12 monthly, 3 yearly, pruned after each backup.

Deliberately **not** backed up:

- **Media** — `/mnt/unitek/{movies,tv,sport,downloads}`. Large, and re-acquirable.
- **Caches and transcodes** — jellyfin cache, tdarr cache, immich `thumbs/` and
  `encoded-video/`. All regenerated from the originals.
- **The live Immich postgres directory** (`/home/tqid/immich/postgres`). Copying a running
  postgres data directory does not reliably restore. The `immich` profile instead runs
  `pg_dumpall` into `/mnt/unitek/immich/dump/immich.sql` before each backup and stores that.

## A caveat on consistency

The `nuc` profile copies Docker volumes while the containers are running. restic is
consistent per file, but not across a database that is mid-write, so a snapshot of a busy
SQLite app (memos, actual, budge, mealie, the *arr stack) can in principle catch a torn
write. In practice SQLite's WAL recovers from this, and 02:00 is a quiet hour. Immich is the
one that genuinely would not survive it, which is why its database is dumped rather than
copied.

If that stops being an acceptable trade, the options are a `run-before` that pauses the
affected containers for the duration, or per-app dumps in the shape of the Immich one.

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

> **Keep `RESTIC_PASSWORD` somewhere outside this setup.** It is not recoverable, and without
> it the backups are so much noise. A GitHub secret is write-only — it cannot be read back.

The workflow writes all three to `/etc/resticprofile/env` (`0600`, root) and the profiles
reference it via `env-file`. They are kept out of the systemd units on purpose: anything in a
unit's `Environment=` is readable by every user on the box
([resticprofile#367](https://github.com/creativeprojects/resticprofile/issues/367)).

## Host requirements

The self-hosted runner needs passwordless `sudo` — it installs binaries to `/usr/local/bin`,
writes to `/etc/resticprofile`, and registers systemd units. The backups themselves run as
root (`schedule-permission: system`) because they read Docker volumes and other users' files.

## Operating it

Everything below is on the NUC. `resticprofile` picks up `/etc/resticprofile/profiles.yaml`
by default once deployed.

```shell
# What is scheduled, and when it next runs
sudo resticprofile status --all
systemctl list-timers 'resticprofile-*'

# Snapshots, and repo size
sudo resticprofile --name nuc snapshots
sudo resticprofile --name nuc stats

# Run one now, out of band
sudo resticprofile --name nuc backup

# Logs
tail -f /var/log/resticprofile/nuc.log
journalctl -u resticprofile-backup@profile-nuc.service
```

The same runs are available from the Actions tab via the **Restic** workflow's
`workflow_dispatch`, which takes a command and a profile.

## Restoring

Any command resticprofile doesn't recognise is handed to `restic` with the profile's
repository and credentials already applied, so drive restores through it rather than calling
`restic` directly — bare `restic` has no idea where the repo is or how to unlock it.

```shell
# Find the snapshot
sudo resticprofile --name nuc snapshots

# Everything, somewhere safe to inspect first
sudo resticprofile --name nuc restore <snapshot-id> --target /mnt/unitek/restore

# Or one path, back where it came from
sudo resticprofile --name nuc restore <snapshot-id> --target / --include /mnt/unitek/config/homarr

# Browse before committing to it
sudo resticprofile --name nuc ls <snapshot-id>
```

Restoring Immich is two steps: restore `/mnt/unitek/immich/library`, then load the dump into
a fresh database.

```shell
docker compose -f docker/immich.yml up -d database
cat /mnt/unitek/immich/dump/immich.sql | docker exec -i immich_postgres psql --username=postgres
docker compose -f docker/immich.yml up --wait
```

## First run

The first `nuc` backup uploads everything and will take a while. `immich` will take longer.
Both are `priority: low` and `ionice` class 2/7, so they should stay out of the way, but it's
worth kicking the first one off manually rather than finding out at 02:00.

A restore is the only real test of a backup. Worth doing once, now, before it matters.

## Possible follow-ups

- The profiles write a status file to `/var/lib/resticprofile/status.json`. resticprofile can
  also emit Prometheus metrics (`prometheus-save-to-file`), which
  [Alloy](../etc/config.alloy) could scrape to alert on a backup that stopped running.
- A `send-after-fail` hook could push a failure to a webhook rather than relying on someone
  noticing the timer went quiet.
