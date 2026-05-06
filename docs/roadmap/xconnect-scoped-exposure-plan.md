# pv-xconnect: scoped service exposure + LISTEN-gated readiness

## Implementation status (2026-05-06)

The plan below was authored in one block; it is being implemented in slices.
Current state of each slice:

| Slice | Status | Notes |
|-------|--------|-------|
| OUTPUT-chain DNAT in `pvx_services` nft table | **landed** (uncommitted) | `xconnect/services_nft.c`: rule install/delete now mirrors across `prerouting` + `output` (and `PREROUTING` + `OUTPUT` for iptables fallback). Teardown flushes both. |
| Loopback backend pick for host↔host | **landed** (uncommitted) | `state.c:pvx_provider_ipv4_for` returns `127.0.0.1` when both provider and consumer are host-net. |
| Network-anchor rejection rules at parse time | **planned, not started** | See "Slice A — network-anchor rejection" below. |
| LISTEN-probe + candidate set | **planned** | The full Phase-1 design described later in this doc. |
| `expose:` field + scoped DNAT | **planned** | Phase 2. |
| `/xconnect-status` → `pv_platform_start` READY gate | **planned** | Phase 3. |

End-state goal of this whole roadmap: every legal (provider, consumer)
combination — including all four quadrants of {pool, host} × {pool, host} —
is reachable through the ClusterIP front door, link establishment is
LISTEN-gated, scope is declared via `expose:`, and link health drives the
existing status-goal / rollback machinery.

## Slice A — network-anchor rejection (next to land)

Authored after the host↔host fix landed; close it out before the LISTEN-probe
work because the parser invariants it establishes simplify everything that
follows.

### Rule

Any container that touches the service mesh (provides via `services.json`
**or** requires via `services.required`) must declare exactly one network
anchor. Pantavisor never silently rewrites a container's network config.

| Brings own `lxc.net.*` | Pool declared | Network mode | Verdict |
|------------------------|---------------|--------------|---------|
| no  | yes  | (n/a)         | OK — IPAM pool member |
| yes | yes  | (anything)    | **REJECT** — pool participation requires no hand-rolled `lxc.net.*` (already enforced in `99e2fba feat(ipam): refuse pool-using container that bakes lxc.net.* config`) |
| yes | no   | host or absent| OK — host-net, container owns its netns config |
| no  | no   | host or absent| **REJECT** (new) — service participant must declare a network anchor; no implicit defaulting |

### Code points

- `parser/parser_system1.c:1523–1605` (network section parser; finishes around
  line 1605 where `p->network` is finalised).
  - After parsing per-platform: if `p->service_exports` non-empty **or**
    `p->services_required` non-empty, run a new validator
    `pvx_validate_network_anchor(p)`.
  - For row "no `lxc.net.*` + no pool + (host|absent)": emit
    `pv_log(ERROR, "platform '%s' touches xconnect services but declares no network anchor; must specify pool or carry own lxc.net config")` and return a parse error code.
  - For row "yes `lxc.net.*` + yes pool" already handled by the existing
    pool/lxc.net check from `99e2fba`. Cross-reference there in the comment.
- `state.c` / platform startup path — the parse-time fatal already prevents
  the platform from reaching running state via the existing error propagation;
  no new code path needed.
- READY gate hookup: nothing new for this slice — an unstarted platform
  already blocks READY through the existing status-goal machinery, and a
  timeout funnels into rollback (tryboot) or degraded continue (normal boot).
  This slice piggybacks entirely on what already exists.

### Verification additions

Add to `docs/testing/testplans/testplan-xconnect-services.md`:

- **TC-09 — Reject service participant without network anchor.** Container
  with `services.json` + no `lxc.net.*` + no pool: boot must fail at parse,
  log line must mention the platform name and the rule. Exit cleanly without
  starting the platform.
- **TC-10 — Reject pool + lxc.net.\* combo for service participant.**
  Regression for the existing `99e2fba` rule, now hit through a service
  participant rather than just the IPAM path.

### Documentation

`docs/overview/xconnect-services.md` — add a "Network requirements for
service participants" section with the matrix above and the reachability
matrix (pool/host × pool/host) once the host↔host slice is in (it is).
**Done in the same change as this slice** so the user-facing doc never
describes a state the code disagrees with.

## Context

The current `pv-xconnect` service-IP layer (TCP ClusterIPs / `<name>.pv.local`) decides backend IPs in `state.c:pvx_provider_ipv4_for` from a static heuristic (IPAM lease → host-net + consumer pool gateway → 0.0.0.0 unreachable) and installs DNAT unconditionally as soon as the graph is built. Two gaps fall out of that:

1. **Liveness blindness** — DNAT exists whether or not the provider has actually `listen()`ed on the port. Consumers see "connection refused" instead of a clean "service not ready" signal, and pantavisor's READY/rollback machinery has nothing to key on.
2. **No expressible scope** — a host-net provider can only choose between "0.0.0.0 (everyone, including external NICs)" and "127.0.0.1 (host only)." There is no way to say "expose to all pool consumers but not the internet" or "expose to pool *internal* only" without leaking pool-bridge IPs into the container so it can `bind()` to them.

This plan replaces the static resolver with **observation-gated, scope-aware** link establishment:

- pv-ctrl observes whether the provider's netns has a LISTENing socket on the predicted port; only then does it hand pv-xconnect a candidate set of provider IPs.
- A new `expose:` field in `services.json` lets the manifest author declare reach (`any | host | pools | pool:<name>`); xconnect (which already has IPAM bridge state) installs scoped DNAT rules accordingly. The container itself never enumerates pool bridges.
- Link establishment plus consumer reachability gates pantavisor's READY state via `/xconnect-status`. Timeout → existing status-goal failure path (tryboot rollback / normal-boot continue).

## Design

### Cases and how each is realised

| # | Intent | Provider does | Manifest declares | Observed candidates | xconnect installs |
|---|--------|---------------|-------------------|---------------------|-------------------|
| 1 | Anyone | `bind 0.0.0.0:N` | `expose: any` (default if omitted) | full netns IPv4 set | DNAT in PREROUTING + OUTPUT, no `iif` filter |
| 2 | All pools, no host, no internet | `bind 0.0.0.0:N` (in any netns) | `expose: pools` | full netns IPv4 set | DNAT in PREROUTING with `iif` match against every pool bridge in `pv_ipam_get()` |
| 3 | Host only | `bind 127.0.0.1:N` (host-net) | `expose: host` (or inferred when only `127.0.0.1` observed) | `[127.0.0.1]` | DNAT in OUTPUT chain only |
| 4 | Specific pool(s) | `bind 0.0.0.0:N` | `expose: pool:internal` (string or array) | full netns IPv4 set | DNAT in PREROUTING with `iif` = that pool's `bridge` |

Default precedence (the "Hybrid" answer): **observed-bind narrows; `expose:` further narrows.** If `expose:` is absent and the service is observed bound only to `127.0.0.1`, we infer `host`. If observed on `0.0.0.0` we default to `any`. Authors set `expose:` only when observation can't express the intent (the dominant case 2).

### Link state machine (per link in graph)

- `pending` — declared, no LISTEN observed yet on `provider_pid`'s netns. No DNAT, no /32 on bridge. Re-probed on a reconcile tick.
- `established` — LISTEN observed; candidate set non-empty; DNAT installed.
- `lost` — was established, LISTEN absent for ≥3 consecutive reconcile ticks (~3s debounce). Tear down DNAT, return to `pending`.
- `unreachable` — LISTEN observed but candidate set ∩ consumer-reach is empty (e.g., `127.0.0.1`-only provider, IPAM-pool consumer). Surfaces in `/xconnect-status` with `last_error: "unreachable_for_consumer"`.

### Pantavisor READY gating

The existing `/xconnect-status` endpoint (POSTed by pv-xconnect every reconcile, served by `ctrl/ctrl_xconnect_status_ep.c`) becomes the input to `pv_platform_start`'s health gate:

- All links must be `established` (or explicitly accepted as unreachable, e.g. provider not in current revision) for pantavisor to declare READY.
- Failure to reach READY within the existing status-goal timeout funnels into the same path used today: tryboot rollback in tryboot, "continue as-is" in normal boot. **No new rollback machinery is added** — we simply hook xconnect's view into the existing gate.

## Files to modify

### Manifest + parsing
- **`parser/parser_system1.c:860–928`** — `parse_service_exports()`: parse new optional `expose` field. Accept string (`any`/`host`/`pools`/`pool:<name>`) or array of those. Bump accepted `#spec` to `service-manifest-xconnect@2.1` (older `@2` continues to work, treated as `expose: any`).
- **`platforms.h:90–96`** — `struct pv_platform_service_export`: add `enum pvx_expose_kind { ANY, HOST, POOLS, POOL_LIST } expose_kind;` and `char **expose_pools; size_t expose_pools_n;`.
- **`platforms.c:1658–1674`** — `pv_platform_add_service_export()`: extend signature / accept the parsed expose info.

### LISTEN probe + candidate set (pv-ctrl)
- **`state.c`** (new helpers, replacing `pvx_provider_ipv4_for`):
  - `static int pvx_proc_listen_addrs(pid_t pid, uint16_t port, uint32_t *out, size_t cap, int *count)` — read `/proc/<pid>/net/tcp` and `tcp6`, filter `st == 0A` and matching local port, return distinct local addresses. IPv4 only in v1; tcp6's `::ffff:0.0.0.0` mapped any-bind is normalised to `0.0.0.0`. Skip IPv6-only binds.
  - `static int pvx_provider_candidates(struct pv_platform *provider, struct pv_platform_service_export *exp, uint32_t **ips, size_t *n)` — call `pvx_proc_listen_addrs`. If `0.0.0.0` is in the result, expand to the full IPv4 set in the netns (`getifaddrs()` after fork+`setns(/proc/<pid>/ns/net)` in a helper subprocess). Apply `expose:` filter: drop bridge gateways not in declared pools, etc.
- **`state.c:pv_state_get_xconnect_graph_json`** (line ~2092 onwards) — emit per-link:
  - `provider_ips: ["a.b.c.d", ...]` (new — array of observed/admissible candidates)
  - `provider_ip` (kept — first element of `provider_ips` for back-compat)
  - `link_state: "pending" | "established" | "lost" | "unreachable"`
  - `last_error: "no_listener" | "unreachable_for_consumer" | null`
  - Drop the link entirely is **not** an option — pending links must be visible so callers (and READY gate) know they're blocking.

### pv-xconnect picker + DNAT scoping
- **`xconnect/main.c`** — graph parser: read `provider_ips` (array) and `link_state`. Skip `pending`/`lost` links (no DNAT, /32 OK to pre-create). For `established`, run a per-consumer picker:
  1. consumer on IPAM pool whose subnet contains a candidate → that candidate.
  2. consumer on IPAM pool, no subnet match, candidate equals consumer's pool gateway → that.
  3. consumer in host netns, candidate is `127.0.0.1` or matches a host IP → that.
  4. otherwise → mark link `unreachable_for_consumer` in next status POST; no DNAT.
- **`xconnect/services_nft.c`**:
  - `pvx_services_nft_init` — add an `output` chain alongside `prerouting`: `chain output { type nat hook output priority -100; }`.
  - `pvx_services_nft_add_dnat` — extend signature to accept a scope hint: `{ kind: ANY|POOLS|POOL_LIST|HOST, bridges: [...] }`. Emit:
    - `ANY` — same rule in both `prerouting` and `output`, no `iif`/`oif` match.
    - `POOLS` — one `prerouting` rule per bridge in `pv_ipam_get()->pools` with `iif <bridge>`. No `output` rule (host-netns consumers excluded).
    - `POOL_LIST` — same as POOLS but only the listed pools.
    - `HOST` — `output` rule only, no `iif` (locally-originated traffic).
  - `pvx_services_nft_del_dnat` — comment-based delete already finds rules across both chains (re-uses the existing `link_comment` grep loop, just iterates both chain names).

### Reconcile cadence
- **`xconnect/main.c`** — add a libevent timer (1s while any link is `pending` or `lost`-debouncing, idle otherwise). On tick, request a fresh `/xconnect-graph` from pv-ctrl. pv-ctrl re-probes LISTEN on each call, so the gate isn't event-driven; it's polling, which matches how status-goals work elsewhere.

### READY gate hookup
- **`platforms.c` (around `pv_platform_start`)** — consult latest `/xconnect-status` body. While any link is `pending`/`unreachable`/`lost` *and* its consumer or provider belongs to a platform in the current revision, the platform-readiness check returns "not ready yet." Existing status-goal timeout machinery will eventually fail the revision; no new rollback code path.

## Critical files (paths)

- `/home/panta/yocto/panta/meta/meta-pantavisor-xconnect-services/build/workspace/sources/pantavisor/parser/parser_system1.c`
- `.../platforms.h` and `.../platforms.c`
- `.../state.c`
- `.../ipam.h` (read-only — `struct pv_ip_pool { name, bridge, gateway, subnet, mask }`, iterator via `pv_ipam_get()`)
- `.../xconnect/include/xconnect.h` (extend `struct pvx_link` with `provider_ips`, `link_state`)
- `.../xconnect/main.c`
- `.../xconnect/services_nft.c`
- `.../xconnect/plugins/tcp.c` (only minor — read multi-IP candidate, otherwise unchanged)
- `.../ctrl/ctrl_xconnect_status_ep.c` (no change; consumed by READY gate via existing GET)

## Verification

1. **Unit-ish probe test** — host: spawn `nc -l 12345` in a fresh netns (`unshare -n`), call `pvx_proc_listen_addrs` against that pid. Expect `[0.0.0.0]`. Kill nc; expect empty.
2. **Case 1 (any)** — existing `pv-example-svc-tcp-{provider,consumer}` pair, manifest unchanged. Boot, verify `link_state: established`, `wget hello-tcp.pv.local` from consumer succeeds, `/xconnect-status` clean.
3. **Case 2 (pools)** — add second pool `external` to IPAM and a third container on `external`. Provider declares `expose: pools`. Verify `wget` works from both pool consumers; verify a host-netns curl to ClusterIP fails (no OUTPUT chain rule).
4. **Case 3 (host)** — provider in host-netns binds `127.0.0.1:80`, declares `expose: host`. Verify host-side `curl` to ClusterIP works (OUTPUT DNAT); pool consumer fails with `link_state: unreachable_for_consumer` in status.
5. **Case 4 (pool:internal)** — same as case 2 but `expose: pool:internal`. Consumer on `internal` works; consumer on `external` fails with the same unreachable status.
6. **READY gate** — start a revision where the provider container is missing or hangs before `listen()`. Expect pantavisor never declares READY; in tryboot it rolls back; in normal boot it keeps the container in `pv-example-svc-tcp-consumer.log` showing `FAIL ip=unresolved`.
7. **Lost debounce** — kill the provider after established. Verify `link_state` flips to `lost` only after 3 consecutive ticks; DNAT is removed; new requests get clean refused; restart provider, verify recovery to `established` without manual intervention.
8. **Build smoke** — `./kas-container build .config.yaml:kas/with-workspace.yaml -- pantavisor-bsp` clean from current state. Same path the user has used; logs into `/tmp/build-ws-<n>.log` per memory.

## Out of scope (deferred to a follow-up roadmap)

### Pool isolation enforcement

Today same-pool traffic is free, cross-pool is routed via `ip_forward=1` (set
by `xconnect/services_bridge.c`), and host↔pool is open because the host owns
each pool's gateway. The `expose:` field added in this plan is therefore
**advisory**: it scopes ClusterIP DNAT installation but does not prevent a
rogue consumer on pool `external` from connecting directly to a provider's
IPAM lease that declared `expose: pool:internal`.

A follow-up ("pool isolation policy") will add coarse-grained enforcement —
the leaning is **pools default-deny inter-pool, default-deny host↔pool, with
xconnect's DNAT rules being the only punch-through**. Deferring here because:

1. We don't need direct cross-pool traffic for any current use case — once
   xconnect works end-to-end the mesh is the path.
2. We want to validate `expose:` + LISTEN gate + READY hook end-to-end before
   adding firewall state.

**Hook point added in v1**: at the tail of `ipam.c:setup_bridge` (~line 526–629)
add a no-op call `pv_ipam_apply_pool_policy(pool)` (empty body, TODO comment)
so the future enforcement layer has a defined integration site without
committing to rule shape yet. ~5 lines, mechanical.

**Documentation note**: `docs/overview/xconnect-services.md` should explicitly
state that `expose:` is advisory in v1 and that direct IPAM-IP traffic
bypassing the mesh is not blocked. Avoids users assuming `expose: pool:foo`
gives them firewall-grade isolation.

### Other deferred items

- IPv6 ClusterIPs and IPv6 LISTEN observation (parse `tcp6` only enough to normalise mapped any-bind today).
- UDP services (the manifest `type: tcp` is the only declared transport in v1.x).
- Per-link rate limits / connection caps.
- A `services` block in `device.json` for cross-revision policy — explicitly v2 per `XCONNECT.md:290`.
