# pvtest workspace

Run the pvtest suite from this directory with `./test.docker.sh`. One x86 tester
(`pvtest-run`) drives the tests against a target that is either a local **appengine
pool** (Docker, x86) or a **single real device** (`--devices`).

## One-time host setup

```
./test.docker.sh install-docker    # load the bundled docker images
# fresh host only: ./test.docker.sh install-deps   # docker + qemu binfmt
```

Hub-backed tests read credentials from the environment:

```
export PH_USER=... PH_PASS=...
```

## Appengine mode (default)

```
./test.docker.sh run                       # all tests (persistent model, the default: each test under its exact config.env)
./test.docker.sh run local                 # a scope
./test.docker.sh run local -p 4            # 4 parallel slots
./test.docker.sh run local --model volatile  # one fresh container per test, no re-typing
./test.docker.sh run local/core/foo -i     # interactive debug
```

## Device mode (`--devices`)

```
cp devices.txt my-device.txt            # fill in name/type/ip/exec/tty/baud
./test.docker.sh run local --devices my-device.txt
./test.docker.sh run local/core/foo -i --devices my-device.txt   # console on the device
```

Exactly one device. If the manifest's device sets `hook=` (a host command that
sets the device's boot env and power-cycles it), a test whose `config.env`
doesn't match the live device triggers a re-type through that hook. Without
`hook=`, such tests are SKIPPED instead, so run **without** `--fail-on-skip`.
The hook is called with the entry's `env=` base tokens first and the test's own
last, so a hook that writes the boot env as a full replacement keeps whatever
the board needs to stay usable. See `devices.txt` for the full contract.

A test may also restrict *which targets it runs on* with a `"devices"` allow-list
in its `test.json`; entries match the target's **class** — `appengine` for the
container, the manifest's `type=` for a real device. Tests that leave the list
empty run everywhere. See `docs/overview/testing/device-target.md`.

## Output

Each run creates a workspace with `run.log` (+ SUMMARY), a per-target `<name>.log`
console capture, and `results/.../test.log` + `diff`. A generated `README.md` inside
that run workspace documents the full layout.
