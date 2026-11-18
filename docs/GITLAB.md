# GitLab Runner

`docker/gitlab-runner.yml` runs a GitLab Runner for the `lotly` GitLab group, so lotly's
pipelines don't depend on GitLab.com's shared-runner compute minutes. It's deployed by
`.github/workflows/gitlab-runner.yml` like every other stack.

## Setup

1. In GitLab: group **lotly** → **Build → Runners → New group runner**. Tick **Run untagged
   jobs** (lotly's jobs have no tags), give it the description `nuc`, and create it. Copy the
   `glrt-...` token it shows.
2. In this repo on GitHub: **Settings → Secrets and variables → Actions**, add
   `GITLAB_RUNNER_TOKEN` with that token.
3. Run the **GitLab Runner** workflow (or push a change to `docker/gitlab-runner.yml`).
4. Optionally, turn off shared runners for the lotly group (**Settings → CI/CD → Runners**), so
   jobs never wait on the exhausted quota.

The settings are in `etc/gitlab-runner/config.toml`, mounted into the container. The runner can't
read its token from the environment, so that file has a placeholder and the container fills in
`GITLAB_RUNNER_TOKEN` on start. The token lives only in the GitHub secret, there's no
`gitlab-runner register` step, and nothing to back up.

## Limits

The NUC has 8 GB, so CI is kept from crowding out everything else:

- one job at a time (`concurrent = 1`)
- each job capped at 3 GB of memory (swap included) and 2 CPUs
- jobs get a low CPU share (256 vs Docker's default 1024)
- earlyoom (`ansible/nuc.yml`) avoids killing the runner process itself; job containers are fair
  game

Pipelines are slower than on GitLab.com: jobs queue behind each other, and the first Flutter job
pulls the 2.3 GB image (kept afterwards).

## Security

Unlike GitHub Actions here, where only pushes to `main` reach the self-hosted runner, this runs
every lotly pipeline, merge requests included. That's acceptable because lotly is a private group
with no outside contributors, and each job runs in its own unprivileged container without the
Docker socket. Only the runner container has the socket. Don't add the runner to projects that
take merge requests from people you don't trust.

## Disk

Job images and per-project cache volumes accumulate. If disk gets tight:
`docker image prune -a --filter "until=168h"` and `docker volume prune` (cache volumes are named
`runner-*`).
