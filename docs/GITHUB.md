# Github Actions

The self-hosted runner has been added to the nuc repository using the following installation instructions.
https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners

It was installed manually on the machine and can be used by adding the following `runs-on` directive to a job:
```yaml
jobs:
  <job-id>:
    runs-on: self-hosted
    steps:
      - ...
```
It runs as a systemd service, which is easily achieved by using the included `svc.sh` helper script

https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/configuring-the-self-hosted-runner-application-as-a-service

There are a few resources on troubleshooting located here

https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/monitoring-and-troubleshooting-self-hosted-runners

## Host configuration

Configuration that lives on the NUC rather than in Docker is in `ansible/nuc.yml`, applied by
the NUC workflow (`.github/workflows/nuc.yml`) on every push to `main` that touches it:

- **earlyoom** kills the biggest process once memory and swap are both nearly gone. Without it, a
  runaway Tdarr node left the NUC thrashing for hours: the kernel's OOM killer never fired.
- **Hardware watchdog**: if systemd stops responding for 30s, the board resets the NUC.
- **Resource priority** for the runner and dockerd, so deploys still get through under pressure.
  This also gives `system.slice` the memory reservation that the containers' `mem_reservation`
  depends on.
- **sudoers** for the runner.

The workflow runs `sudo ansible-playbook`, so the playbook runs as root and needs no `become`.
That is effectively full root, as `sudo install` for restic already was, and as the Docker socket
already is. What keeps it safe is that self-hosted jobs only run from `main` or by hand, never on
`pull_request`. PR checks run on `ubuntu-latest`.

### Bootstrap

Once, by hand, on the NUC. After this the playbook manages its own sudoers entry.

```shell
sudo apt-get install -y ansible-core

# Use the user the runner runs as: ps -o user= -C Runner.Listener
echo 'tqid ALL=(root) NOPASSWD: /usr/bin/ansible-playbook, /usr/bin/install, /usr/local/bin/resticprofile' \
  | sudo tee /etc/sudoers.d/github-runner
sudo chmod 0440 /etc/sudoers.d/github-runner
sudo visudo -c
```

Then run the NUC workflow by hand with **check** ticked to see what it would change, and run it
again without check to apply.

Afterwards, when no job is running, restart the runner once so its `OOMScoreAdjust` applies. The
playbook can't do this itself, because restarting the runner kills the job that's running it:

```shell
sudo systemctl restart 'actions.runner.*'
```

Two things the playbook can't set:

- In the BIOS, set the power-loss setting to **Power On**, so a smart plug can power-cycle the
  NUC remotely.
- If the workflow says `/dev/watchdog0` is missing, check `lsmod | grep -i wdt`. Intel boards
  use `iTCO_wdt`.