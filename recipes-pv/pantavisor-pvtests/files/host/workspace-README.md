# Test Run Results

## Workspace Layout

```
<workspace>/
  run.log                           <- aggregate output (host + tester) + SUMMARY
  pass-<tag>.log                    <- per-pass tester output; tag is "main", or
                                       "volatile" with --model volatile
  <name>.log                        <- console capture for one target, keyed by name:
                                       appengine mode -> full pantavisor stdout_direct
                                       (docker logs, keyed by container name)
                                       device mode    -> raw serial console (from its tty,
                                       keyed by the --devices manifest name=)
  README.md
  pvtest-tarballs.manifest          <- present only when container tarballs were
                                       substituted via `install-tarballs`; records
                                       which ones, from where, and their checksums
  ctrl/<tag>/                       <- re-type protocol dirs (transient)
  ctrl-dev/<name>/                  <- device re-type protocol dir (transient, only
                                       when the --devices manifest sets hook=)
  pvtx-seed/<tag>/<pid>/            <- volatile model only: the test's tarballs, mounted
                                       into the container's pvtx.extra.d (transient)
  results/
    <tag>/<scope>/<category>/<name>/
      test.log     <- test script output interleaved with target console logs during exec_test
      diff         <- diff (expected vs actual), present only when test failed
  storage/          <- appengine mode only (a real device keeps its own on-device storage)
    <tag>/<key>/   <- persistent pantavisor storage lineage: one per worker in the
                      persistent model (w<N>), one per test in the volatile model
                      (fresh every time, never persistent); fresh at pass start,
                      kept across re-types where the model persists storage at all
      trails/ objects/ logs/ ...
  valgrind/         <- appengine mode only, with -V
    <container>/   <- per-appengine valgrind output
      valgrind.log.<pid>
```

One tester (`pvtest-run`) drives each pool pass; see `docs/overview/testing/automated/devices.md`
for the full model. `--model` picks the assignment model:
- **persistent** (default) — every test runs under exactly its `config.env`:
  `-p` workers each keep ONE storage for the whole pass, settling back to a
  gc'd factory state between tests and re-booting with new config only when
  the next test actually needs it (at most one power cycle between tests).
- **volatile** — master-like: one fresh appengine container per test (own
  storage, no re-typing), `-p` capping how many run concurrently. The test's
  tarballs are seeded into `pvtx.extra.d` so `pv-appengine` deploys the test's
  own `locals/<id>` revision on first boot and boots into it committed, which
  is what makes the model cheap: no install and no commit reboot, one
  pantavisor boot per test instead of three. Incompatible with `--devices`
  and `-n`.
- **device mode (`--devices`)** — persistent only: every selected test runs
  sequentially against the single real device (no pool). If the manifest entry
  sets `hook=` (a host command that sets the device's boot env and
  power-cycles it, with `config=` as that command's config file), a test whose
  `config.env` doesn't match triggers a re-type through the hook instead of
  skipping. The hook gets the entry's `env=` base tokens first and the test's
  own last, so a hook that writes the boot env as a full replacement keeps the
  board bootable. Without `hook=`, tests whose `config.env` the live device doesn't
  satisfy are SKIPPED as before, so run **without** `--fail-on-skip` until each
  test's `"devices"` array is triaged.
- Want both models? Just run `test.docker.sh` twice, once per `--model`.

The SUMMARY collects the per-test results.

## Log Format

All structured log lines follow the pantavisor log convention:

```
[pvtest] <epoch> LEVEL -- [source]: message
```

Sources: `test.docker.sh`, `pvtest-run`, `pv-appengine`.

## run.log

The single aggregate log: host orchestrator (`test.docker.sh`) and tester
(`pvtest-run`) output interleaved — distinguishable by the `[source]` tag — plus
one structured line per test result and a SUMMARY section at the end.

Log levels used in `run.log`:

| Level | When |
|-------|------|
| `DEBUG` | Test launch and workspace setup diagnostics |
| `INFO` | PASSED, ABORTED, SKIPPED, retry |
| `ERROR` | FAILED |

On failure the diff is printed inline after the `ERROR` line, and also saved to
`results/<scope>/<category>/<name>/diff`. Retry attempts get their own directory
(`<name>.1/`, `<name>.2/`).

Quick scan for failures:

    grep ERROR run.log

## test.log

`test.log` is a single interleaved stream of everything that happened during a test run.
It mixes output from four sources:

**1. `test.docker.sh`**
Host-side orchestrator. With `-v` produces `set -x` traces (`++ docker run ...`,
`++ allocate_slot`, etc.) covering container startup and network setup.
Structured messages use `[pvtest] LEVEL -- [test.docker.sh]: message`.

**2. `pvtest-run` + `resources/test`**
Inner test runner inside the tester container. Parses `test.json`, connects to the
appengine via PVTEST_EXEC (SSH), then runs the test script (with `set -x` injected).
Structured messages use `[pvtest] LEVEL -- [pvtest-run]: message`.
The test script output is captured and diffed against the stored `output` file.

**3. `pv-appengine`**
Pantavisor runtime launcher inside the appengine container. Sets up cgroups and storage
mounts, then runs the `pantavisor` binary in a restart loop (simulating device reboots).
Structured messages use `[pvtest] LEVEL -- [pv-appengine]: message`.

**4. Pantavisor (`stdout_direct`)**
Started with `PV_LOG_SERVER_OUTPUTS=filetree,stdout_direct`. Streams internal logs
directly to stdout without buffering:
`[pantavisor] TIMESTAMP LEVEL -- [module]: message`.

To filter by source:

    grep '\[pvtest-run\]'   test.log    # pvtest-run messages only
    grep '\[pv-appengine\]' test.log    # pv-appengine messages only
    grep '\[pantavisor\]'   test.log    # pantavisor messages only
    grep 'WARN\|ERROR'      test.log    # all warnings and errors

In GHA, WARN and ERROR lines from `test.log` are automatically surfaced in the
job step summary under **Test log issues**.

## Valgrind Logs (appengine mode, -V)

Valgrind output is under `valgrind/<N>/valgrind.log.<pid>`. The main worker is typically
the largest file. Check with:

    grep -E "definitely lost|possibly lost|ERROR SUMMARY" valgrind/<N>/valgrind.log.<largest-pid>

- `definitely lost` — real leaks, investigate
- `possibly lost` — typically PV buffer pools; consistent at ~3.7 MB, not a regression
- `ERROR SUMMARY` — mostly `Syscall param` warnings from liblxc, not pantavisor code
