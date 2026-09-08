---
title: "Runner Stack"
description: "Add/remove GitHub Actions self-hosted runner instances on a host to run more than one job in parallel."
sidebar_position: 8
---

# Runner Stack

GitHub runs exactly **one job per registered runner instance** — there is no
concurrency setting on a single runner. The only way to run N jobs in
parallel on one host is to register N separate runner instances, each with
its own systemd service. `.github/scripts/runner-stack.sh` manages those
extra instances on top of an existing base install (e.g. `pvtest-scw` at
`/home/ubuntu/actions-runner`, or a `bsp-builder` at `/opt/actions-runner`).

Copy the script onto the runner host and invoke it there as root; the base
install (instance 1) is never touched or removable by this script.

## Status

```console
$ ./runner-stack.sh status
Stack base: /home/ubuntu/actions-runner
INSTANCE                       NAME                      SERVICE    WORK DIR
/home/ubuntu/actions-runner    pvtest-scw                active     /home/ubuntu/actions-runner/_work
/home/ubuntu/actions-runner-2  pvtest-scw-2              active     /home/ubuntu/actions-runner-2/_work
```

The base install is auto-detected: `--base <dir>`, else the script's own
directory if it has a `config.sh`, else `/opt/actions-runner`, else
`/home/ubuntu/actions-runner`.

## Adding an instance

```console
$ sudo ./runner-stack.sh add --labels pvtest-runner
```

This copies the base install into `<base>-N` (e.g. `actions-runner-2`),
registers it as `<base-name>-N` (e.g. `pvtest-scw-2`), and installs+starts
it as a root systemd service (`actions.runner.<org>.<name>.service`). If
the base runner has self-updated, `bin`/`externals` are symlinks into the
base's own versioned directories — the copy dereferences them into real
directories so each instance updates independently.
Labels default to whatever was saved from a previous `add --labels`
(`<base>/.runner-stack-labels`) — pass `--labels` again to change them.

## Removing an instance

```console
$ sudo ./runner-stack.sh remove
```

Pops the highest-numbered instance: stops and uninstalls its service,
deregisters it from GitHub, then deletes its directory. **The base
instance can never be removed this way** — with only instance 1 left,
`remove` refuses with an explicit error, so there is no path to
deregistering the base runner through this script.

## Tokens

`add` needs a registration token, `remove` needs a removal token; both are
short-lived (one hour) and can only be minted by someone with the org
"Self-hosted runners" permission. The script never mints one itself — run
without `--token`/`$RUNNER_TOKEN` and it prints the exact command to run on
your own workstation, e.g. for `add`:

```console
$ gh api -X POST orgs/pantavisor/actions/runners/registration-token --jq .token
```

(or `repos/<owner>/<repo>/actions/runners/registration-token` if the base
runner is registered at the repo level instead of the org level), then the
re-invocation to paste the token into:

```console
$ sudo ./runner-stack.sh add --token <paste>
```

This needs the `admin:org` scope, or a fine-grained PAT with org permission
"Self-hosted runners: Read and write", passed as `GH_TOKEN=<pat> gh api ...`.

## Dry run

`--dry-run` on `add`/`remove` prints the commands it would run without
running them — useful for checking the plan before touching a live runner.
