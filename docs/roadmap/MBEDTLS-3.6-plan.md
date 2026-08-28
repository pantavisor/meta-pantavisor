# mbedtls 2.28 → 3.6 LTS Migration Plan

## Goal

Move pantavisor off mbedtls 2.28 (about to leave LTS) onto **mbedtls 3.6 LTS**
(supported through ~2027). 3.6 ships in meta-openembedded *scarthgap* as
`mbedtls_3.6.5.bb`; for *kirkstone* we'll vendor the same recipe inside
meta-pantavisor.

mbedtls 4.x is explicitly **out of scope**: PSA-only redesign, libevent's
`bufferevent_mbedtls` not yet validated against it, and our crypto code would
have to be rewritten against PSA. Revisit only after 3.6 ships and stabilises.

## Current state (baseline)

### Where mbedtls is consumed in the source

| File | Surface used |
|------|--------------|
| `signature.c` | `mbedtls_x509_crt`, `mbedtls_pk_*`, `mbedtls_x509_crt_verify`, `mbedtls_md`, direct struct member access (`name->oid`, `crt->subject`, `crt->serial`) |
| `event/event_rest.c` | `mbedtls_ssl_*`, `mbedtls_x509_crt_*`, `mbedtls_ctr_drbg_*`, `mbedtls_entropy_*` (TLS client to Hub) |
| `updater.c`, `storage.c` | `mbedtls_sha256_*` (object hashing) |
| `utils/base64.c` | `mbedtls_base64_encode/decode` |

### Recipe / build glue

- `meta-pantavisor/recipes-pv/mbedtls/mbedtls_2.28%.bbappend` — bbappend on top
  of meta-oe `mbedtls_2.28.10.bb`. Two purposes:
  1. Add `TARGET_CFLAGS` block forcing `MBEDTLS_CONFIG_FILE=<config-mini-tls1_1.h>`
     plus a list of `-DMBEDTLS_*` feature defines (ECP curves, ECDSA, SHA512,
     SNI, debug, error strings, …).
  2. Apply per-PV patch:
     `recipes-pv/mbedtls/mbedtls/${PV}/0001-make-pk_wrap.c-support-validating-ANSI-X9.62-FIPS-18.patch`
- `PREFERRED_VERSION_mbedtls = "2.28.%"` pinned in 4 places:
  - `conf/distro/panta-distro.conf`
  - `conf/distro/panta-distro-bsp.conf`
  - `conf/distro/panta-appengine.inc`
  - `conf/multiconfig/pv-initramfs-panta.conf`

### Pantacor mbedtls fork

`https://gitlab.com/pantacor/mbedtls`

- `pv_external-mbedtls-2.28.8` — substantive commits:
  - `b7acb068` / `0cd14242` — `config-mini-tls1_1.h` mods (TLS 1.2 + EC + SNI)
  - `18c8a07f` + `12d3b1f1` — pk_wrap.c: accept raw `(r,s)` ECDSA signatures
- `pv_external-mbedtls-3.2.1` — has only an unrelated config commit, **does
  not** carry the pk_wrap.c patch. Treat as abandoned.

The Yocto recipe today does **not** consume the fork; the bbappend reproduces
the substantive changes (config via `-D` flags, pk_wrap.c via the .patch).
**The fork can be retired** once 3.6 ships — meta-pantavisor's
`recipes-pv/mbedtls/` remains the source of truth.

## Target

- mbedtls **3.6.5** (or latest 3.6.x at port time).
- Drop the `2.28.%` `PREFERRED_VERSION` pins.
- Forward-port the pk_wrap.c patch to 3.6.
- Decide on config approach (see below).
- Vendor `mbedtls_3.6.x.bb` inside meta-pantavisor for kirkstone.

## API porting checklist

mbedtls 3.0 broke source compatibility in many places. Concrete items in our
tree:

1. **Struct field access → `MBEDTLS_PRIVATE(...)` or accessors**
   `signature.c` reads `name->oid`, `crt->subject`, `crt->serial`,
   `cert->subject` directly. In 3.x these are private; either wrap each access
   with `MBEDTLS_PRIVATE(field)` or switch to public accessors where
   available (e.g. `mbedtls_x509_crt_get_subject_alt_name`,
   `mbedtls_asn1_get_alg_null`).

2. **`mbedtls_sha256_*` return types**
   `mbedtls_sha256_starts/update/finish` return `int` in 3.x and the
   `_ret` suffixed wrappers were removed. Check return values at
   `updater.c:207-213` and `storage.c:453-458`.

3. **`mbedtls_pk_parse_public_keyfile`**
   3.x signature: `(mbedtls_pk_context *ctx, const char *path,
                     int (*f_rng)(void *, unsigned char *, size_t),
                     void *p_rng)`
   Update `signature.c:732` to pass our `mbedtls_ctr_drbg_random`/ctx (or
   `NULL, NULL` for non-PSA paths — verify which we hit).

4. **`mbedtls_pk_verify` argument order is unchanged**, but verify behaviour
   when `MBEDTLS_USE_PSA_CRYPTO` is on (raw `(r,s)` already supported via PSA;
   our patch may then be redundant — see config decision below).

5. **`mbedtls_ctr_drbg_seed` / entropy** — unchanged API, unchanged.

6. **TLS config in `event_rest.c`**
   - `MBEDTLS_SSL_VERIFY_NONE` still exists but consider switching to
     `MBEDTLS_SSL_VERIFY_REQUIRED` — our cloud comma path should already
     verify Hub certs (this is unrelated to 3.x port but worth fixing here).
   - `mbedtls_ssl_config_defaults`, `mbedtls_ssl_conf_*` API unchanged.
   - `mbedtls_ssl_conf_authmode` unchanged.

7. **`mbedtls_oid_get_attr_short_name`** at `signature.c:634` — unchanged.

8. **`mbedtls_x509_serial_gets` / `mbedtls_x509_dn_gets`** — unchanged.

9. **`MBEDTLS_PRIVATE` opt-out**: as a stop-gap we can build with
   `-DMBEDTLS_ALLOW_PRIVATE_ACCESS` (provided as a build-time escape hatch in
   3.x) to avoid touching every field reference in one go. Acceptable as a
   transition; long-term we want the accessor-based code.

## Config decision (the `config-mini-tls1_1.h` story)

The `TARGET_CFLAGS` override in our bbappend sets
`MBEDTLS_CONFIG_FILE=<config-mini-tls1_1.h>`. That header **does not exist in
3.x** — 3.x ships `mbedtls_config.h` plus a few `configs/config-*.h`
profiles (`config-suite-b.h`, `config-ccm-psk-tls1_2.h`, …) but not
`config-mini-tls1_1.h`.

Three options, ranked:

1. **Drop the override entirely (recommended).** Use the stock 3.6
   `mbedtls_config.h`. Verify the resulting binary size is acceptable for
   initramfs (the original motivation for the mini config was footprint).
   Add only the deltas we genuinely need as `-D` flags or via
   `MBEDTLS_USER_CONFIG_FILE`. This is the cleanest, lowest-maintenance path.

2. **Carry our own config header** — port the relevant 2.28 mini config
   contents into `recipes-pv/mbedtls/mbedtls/files/pv-config.h`, install it
   alongside the source, and point `MBEDTLS_CONFIG_FILE` at it. Higher
   maintenance, but gives full control over footprint.

3. **`MBEDTLS_USER_CONFIG_FILE`** to layer enables/disables on top of stock
   config. Good middle ground if (1) is too maximal.

Pick (1) by default; fall back to (3) if size budget breaks.

### Concrete enables we definitely need

(from current `TARGET_CFLAGS` and pantavisor code paths):

- `MBEDTLS_SSL_PROTO_TLS1_2`
- `MBEDTLS_SSL_SERVER_NAME_INDICATION` (Hub uses SNI)
- `MBEDTLS_SHA256_C`, `MBEDTLS_SHA512_C`
- `MBEDTLS_PK_C`, `MBEDTLS_PK_PARSE_C`, `MBEDTLS_PK_PARSE_EC_EXTENDED`
- `MBEDTLS_X509_CRT_PARSE_C`, `MBEDTLS_X509_USE_C`
- `MBEDTLS_ECP_C`, `MBEDTLS_ECDSA_C`, `MBEDTLS_ECP_NIST_OPTIM`
- ECP curves: `SECP{192,224,256,384,521}R1`, `SECP{192,224,256}K1`,
  `BP{256,384,512}R1`, `CURVE25519`, `CURVE448`
- `MBEDTLS_BASE64_C`
- `MBEDTLS_CTR_DRBG_C`, `MBEDTLS_ENTROPY_C`
- `MBEDTLS_DEBUG_C`, `MBEDTLS_ERROR_C` (debug builds; consider gating)
- *Removed in 3.x — drop:* `MBEDTLS_REMOVE_ARC4_CIPHERSUITES`,
  `MBEDTLS_REMOVE_3DES_CIPHERSUITES`. ARC4 and 3DES are gone by default in
  3.x; these defines no longer exist.

### PSA crypto — viability analysis

PSA is the elephant in this migration. Two questions, often conflated:

- **Is PSA built in?** Controlled by `MBEDTLS_PSA_CRYPTO_C`. In our 2.28.10
  build today: **yes, on by default** (verified in the stock `config.h` of
  the unpacked sysroot). PSA functions like `psa_crypto_init`,
  `psa_verify_hash`, the keystore, ITS file storage — all already linked.
- **Does the legacy API route through PSA?** Controlled by
  `MBEDTLS_USE_PSA_CRYPTO`. **Off by default in 2.28**, off by default in
  3.6 too — but in 3.6 the upstream stance changed from "experimental" to
  "production ready" (3.6 release notes explicitly call this out).

Our prior pain in 2.28 was exactly the second switch: turning on
`USE_PSA_CRYPTO` meant some TLS cipher suites bypassed PSA, the driver
model was alpha, and X.509 paths were partially wired. Those issues are
materially fixed in 3.6:

- `MBEDTLS_USE_PSA_CRYPTO` covers all standard TLS 1.2 and 1.3 paths in 3.6.
- ECDSA verify under PSA accepts raw `r||s` natively (`PSA_ALG_ECDSA`) →
  the pk_wrap.c patch becomes redundant on PSA-routed verify calls.
- Driver model is stable enough that mbedtls 3.6 ships with PSA used as the
  default backend for several primitives via `MBEDTLS_PSA_CRYPTO_CONFIG`.

#### What "PSA-only build" forces on the distro

Worth being explicit, because the user's instinct ("we limit what folks can
use") deserves a concrete answer:

- **API surface for downstream consumers** (libthttp, libevent_mbedtls,
  pantavisor itself): **no impact**. With or without `USE_PSA_CRYPTO`, the
  legacy `mbedtls_*` API stays callable. `USE_PSA_CRYPTO` is an *internal*
  routing switch — the library translates legacy calls into PSA calls
  beneath, transparently.
- **Runtime requirement**: when `USE_PSA_CRYPTO` is on, `psa_crypto_init()`
  must be called once before any PSA-routed call. mbedtls auto-inits in
  many paths in 3.x; we should still call it explicitly at pantavisor init
  for safety. One-line change in `event_rest.c` init or a new `pv_psa_init`.
- **Config knob shape**: if we *also* turn on `MBEDTLS_PSA_CRYPTO_CONFIG`,
  primitive enablement moves from `MBEDTLS_*_C` defines to `PSA_WANT_*`
  defines. This is a config-author change only; it doesn't leak into the
  API consumed by libthttp/libevent. Recommendation: **leave
  `MBEDTLS_PSA_CRYPTO_CONFIG` off** for the first cut. Stick with the
  classic `MBEDTLS_*_C` enables and only flip on `USE_PSA_CRYPTO` for
  routing. Smaller blast radius, easier rollback.
- **Storage**: `MBEDTLS_PSA_CRYPTO_STORAGE_C` + `MBEDTLS_PSA_ITS_FILE_C`
  are on by default. They only matter if we ever call `psa_import_key` /
  `psa_generate_key` with `PSA_KEY_LIFETIME_PERSISTENT` — we don't, and
  won't even when TLS client auth (mTLS) is added later (see below).
  **Recommendation: disable both.** This avoids creating yet another
  mutable directory under `/var/pantavisor/` and the
  `MBEDTLS_PSA_ITS_FILEIO_LOCATION` decision entirely.

  **TLS client auth doesn't need PSA persistence either.** mTLS loads the
  device private key the same way we load the trust store today:
  `mbedtls_pk_parse_keyfile` + `mbedtls_ssl_conf_own_cert`. Under
  `USE_PSA_CRYPTO`, mbedtls imports it as a *volatile* PSA key for the
  handshake and destroys it on teardown. The on-disk key file is the
  persistence layer — same model as the trust store, no ITS involved.

  PSA persistence (or an opaque driver) only matters when the device
  private key must **never** sit as a file on disk — i.e. when it lives
  in a TPM, secure element, or PKCS#11 token. That's an independent
  hardware-key architecture choice; flipping storage flags doesn't get us
  there. Defer to a future "device identity key" project (see below).

#### Future direction: PSA opaque driver over Linux keyctl

When/if pantavisor grows a hardware-backed device identity key, the
architecturally cleanest path on Linux is a **PSA opaque driver targeting
`keyctl_pkey_sign` / `keyctl_pkey_verify`** (plus `KEYCTL_PKEY_QUERY` for
capability discovery). The kernel keyring already abstracts the underlying
backends:

- `trusted` key type → TPM2-sealed blobs (kernel does seal/unseal),
- NXP **CAAM** → secure-key blobs as a native keyring type,
- OP-TEE → `tee` keyring shim,
- ATECC608 / SE050 / STSAFE → reachable via the `asymmetric` key type once
  a kernel-side bridge exists.

One driver, every SoC's secure key store works through it — no per-vendor
mbedtls code. Such a driver does **not** exist upstream today (mbedtls's
PSA driver API stabilised slowly; the `keyctl` audience mostly uses
OpenSSL). Estimated ~500–1000 LoC plus the JSON driver-description
plumbing.

This is **out of scope for the 2.28→3.6 migration** but worth flagging:
the choice to disable `*_STORAGE_C`/`*_ITS_FILE_C` is consistent with
this future direction (we'd never use the file-based ITS anyway —
opaque-driver keys live kernel-side).
- **Footprint**: turning on `USE_PSA_CRYPTO` and keeping the classic
  enables grows the binary (both code paths exist). Turning on
  `PSA_CRYPTO_CONFIG` and dropping classic enables shrinks it again. So
  the ordering matters: phase 1 is bigger, phase 2 (if we adopt PSA-only
  config) trims back.

#### Recommended PSA stance for this migration

**Phase 1 (this PR): pure 2.28→3.6 port, no PSA routing change.** Build
with `MBEDTLS_PSA_CRYPTO_C` on (default) and `MBEDTLS_USE_PSA_CRYPTO`
**off** — same posture as 2.28 today. Forward-port the pk_wrap.c patch so
the legacy ECDSA path keeps accepting raw `(r,s)` signatures. Pantavisor
source changes are limited to the unavoidable 3.0 API breaks
(`MBEDTLS_PRIVATE`, sha256 return values, `mbedtls_pk_parse_public_keyfile`
RNG arg) — no behavioural rework. Disable
`MBEDTLS_PSA_CRYPTO_STORAGE_C`/`MBEDTLS_PSA_ITS_FILE_C` (we don't use
persistent PSA keys).

**Phase 2 (follow-up): switch pantavisor to PSA-native crypto for paths
that benefit.** Concretely: rewrite `signature.c` to use `psa_import_key`
+ `psa_verify_hash` directly instead of `mbedtls_pk_parse_public_keyfile`
+ `mbedtls_pk_verify`. Wire `psa_crypto_init()` at pantavisor startup.
Other call sites stay legacy:
- `event_rest.c` keeps `mbedtls_ssl_*` (TLS isn't a PSA win for us yet),
- `updater.c`/`storage.c` sha256 — optional cosmetic switch to
  `psa_hash_compute`, low value,
- `base64` — legacy, no PSA equivalent.

This is an **explicit opt-in to PSA in pantavisor source**, not a global
routing flip — `USE_PSA_CRYPTO` stays off, so libthttp/libevent and the
TLS stack are unaffected. PSA's `psa_verify_hash` accepts raw `(r,s)`
natively, so this also obsoletes the pk_wrap.c patch's reason for
existing in our deployment (see Phase 3).

**Phase 3: drop the pk_wrap.c patch.** Once pantavisor's signature
verification has fully moved to PSA in Phase 2, our build no longer hits
the legacy `ecdsa_verify_wrap` path the patch hooks. The patch becomes
dead code from our perspective and the bbappend can drop it. Validate by
running the local-signature test suite (raw `(r,s)` ECDSA on
SECP256R1/384R1/CURVE25519 must still verify).

**Phase 4 (future, optional, tied to hardware-key work):** adopt
`MBEDTLS_PSA_CRYPTO_CONFIG`, move config to `PSA_WANT_*` defines, drop
redundant `MBEDTLS_*_C` enables. Pairs naturally with adding a PSA
opaque driver (e.g. the keyctl/CAAM driver discussed above) for a
hardware-backed device identity key — that's the concrete trigger.

| Phase | Pantavisor source                   | mbedtls bbappend                    | pk_wrap.c patch  |
|-------|-------------------------------------|-------------------------------------|------------------|
| 1     | 3.0 API-break fixes only            | new 3.6 patch, adjusted CFLAGS      | **kept** (forward-ported) |
| 2     | rewrite `signature.c` to PSA-native | (no recipe change)                  | still kept (harmless dead code) |
| 3     | (validation only)                   | drop the patch from bbappend        | **dropped**      |
| 4     | (none beyond Phase 2)               | `PSA_CRYPTO_CONFIG` on, classic enables → `PSA_WANT_*` | n/a |

Why this ordering is better than flipping `USE_PSA_CRYPTO` globally:
- No implicit re-routing of the TLS stack, libthttp, libevent — they
  keep the well-trodden legacy crypto path.
- Pantavisor explicitly chooses PSA where useful; explicit beats implicit.
- Each phase is independently revertable: Phase 2 is a pantavisor-source
  change with no recipe coupling; Phase 3 is a recipe change with no
  source coupling.

The move to 3.6 (Phase 1) doesn't depend on any of Phases 2–4 — that's
the cheapest path back to a supported lane.

## Patches to forward-port

| Patch | From | To 3.6.5 status |
|-------|------|-----------------|
| `0001-make-pk_wrap.c-support-validating-ANSI-X9.62-FIPS-18.patch` | `recipes-pv/mbedtls/mbedtls/2.28.10/` | Forward-port if PSA path doesn't cover raw `(r,s)`. File `library/pk_wrap.c` exists but is heavily restructured (more `#if defined(MBEDTLS_USE_PSA_CRYPTO)` branches around `ecdsa_verify_wrap`). The helper functions `asn1_write_mpibuf` and `pk_ecdsa_sig_asn1_from_psa` already live in `library/pk_wrap.c` upstream in 3.6 — likely just need the fallback hook in `ecdsa_verify_wrap`/`ecdsa_verify_rs_wrap`. |

## Recipe changes

### scarthgap

1. Remove `PREFERRED_VERSION_mbedtls = "2.28.%"` from:
   - `conf/distro/panta-distro.conf`
   - `conf/distro/panta-distro-bsp.conf`
   - `conf/distro/panta-appengine.inc`
   - `conf/multiconfig/pv-initramfs-panta.conf`
2. Rename bbappend `recipes-pv/mbedtls/mbedtls_2.28%.bbappend` →
   `mbedtls_3.6%.bbappend`. Update CFLAGS per "Concrete enables" above. Drop
   the `MBEDTLS_REMOVE_*_CIPHERSUITES` defines.
3. Update patch path: `recipes-pv/mbedtls/mbedtls/3.6.5/0001-...patch`
   (forward-ported).

### kirkstone

Kirkstone meta-oe ships only 2.28.x. Two options:

1. **Vendor the recipe** — copy `mbedtls_3.6.5.bb` (and `files/`) from
   scarthgap meta-oe into `meta-pantavisor/dynamic-layers/openembedded-layer/`
   gated by `LAYERSERIES_OVERRIDES`/`LAYERSERIES_COMPAT`. Pro: self-contained,
   doesn't require kirkstone meta-oe upgrade.
2. **Bump kirkstone meta-oe** to a fork/branch that has 3.6.5. Pro: aligned
   with upstream; con: layer surgery in user builds.

Default to (1).

## libevent compatibility

We ship a custom `libevent` recipe at `recipes-pv/libevent/libevent_2.2.1.bb`,
pinned to **2.2.1-alpha-dev** (May 2023 release tag). It DEPENDS on mbedtls,
builds with `--enable-mbedtls` and `--enable-static`, and carries one patch:

- **`files/undef_ssl_renegotiation.patch`** — adds
  `#undef MBEDTLS_SSL_RENEGOTIATION` before the `#ifdef` block in
  `mbedtls_context_renegotiate()` to force-disable the renegotiation path.

### Bump libevent SRCREV to a recent upstream master commit

**This is not a libevent major-version jump.** Upstream master *is* the
2.2.x development line — there is no `release-2.2.x-stable` yet, and
`release-2.2.1-alpha` is just a tagged snapshot of that same line.
Pantavisor and libthttp consume the standard 2.2.x public API
(`event_base_*`, `bufferevent_*`, `evhttp_*`, the `bufferevent_mbedtls`
glue) and that surface has been stable across all 2.2.x commits.

**Verified:** the public header set in `include/event2/*.h` on `master` is
**byte-for-byte identical** to `release-2.2.1-alpha` — 27 headers, no
additions or removals. The `bufferevent_mbedtls` setup-function signature
is unchanged. Our call sites need zero changes on the libevent side.

**Why no tagged stable since May 2023:** upstream issue
[#1094 "libevent 2.2 release checklist"](https://github.com/libevent/libevent/issues/1094)
shows the engineering work for 2.2-stable is complete (mbedTLS 3.0,
OpenSSL 3.0, all major compat blockers ticked). The only remaining items
are administrative: update changelog, bump version numbers, cut the tag.

The community has been **actively asking for a release for 3+ years**
(comments from Nov 2022, Jan 2023, Jan 2025 — the last by a Debian
contributor pre-Debian-13 freeze). The lead maintainer (`azat`)
acknowledged each time that the next release is API-compatible and "on
my todo list," but tagging keeps slipping. No technical blocker is cited
anywhere in the thread. Classic single-maintainer-with-day-job tag-slip.

This means the lack of a tag is a **social** artefact, not a technical
one. Pinning a master SHA is the same workaround other distros (Debian,
Alpine) are using in the meantime. Reinforces option (1) above.

**Project liveness check** (verified 2026-05): master gets pushes
~weekly; last push was 2026-04-01. Past 12 months: ~58 commits to master,
44 by lead maintainer Azat Khuzhin plus 9 other contributors. Recent
work is routine maintenance (parallel CI, MinGW build fixes, doxygen
update). 11.9 k stars, 134 open issues. **Not abandonware** — single
active maintainer, responsive to issues, just doesn't cut release tags.

**De facto vs de jure rolling.** The project has *not* formally adopted a
track-master / rolling-release model — README still documents tagged
installs, `whatsnew-2.2.txt` is already written, and azat keeps saying
he wants to tag (Jan 2025: *"I can't make any promises, but I will try
very hard"*). What's happened is that downstream consumers (Debian sid,
Alpine edge, etc., and now us) silently treat master as the source of
truth because the tag has been three years pending. Practical
implication for our recipe: **pin a specific SHA, don't use `AUTOREV`,
and bump deliberately** — same posture as any upstream lacking formal
release engineering. No LTS branches, no CVE backports, no upstream
"stability windows" to rely on; we own the bump cadence.

Relevant commits we'd inherit by bumping past 2.2.1-alpha-dev:

| Commit | Date       | Why we want it |
|--------|------------|----------------|
| `384c52e6be` | 2022-06-23 | Initial Mbed-TLS 3 support (PR #1299) |
| `285fc7cc6d` | 2022-10-08 | Heap-based contexts for MbedTLS handles — likely the fix for upstream issue #1709 (double-free in 2.2.1-alpha-dev) we'd otherwise still ship |
| `370d99244d` | 2024-10-15 | Properly disables renegotiation for mbedtls 3 (TLS 1.3 only) — **supersedes our `undef_ssl_renegotiation.patch`** |
| `7cfffeaa5c` | 2025-11-28 | mbedtls 4 compatibility (future-proofing, not needed for 3.6) |

Mechanism: a central **`mbedtls-compat.h`** shim that includes
`<mbedtls/compat-2.x.h>` (mbedtls 3.x's own deprecated-name compat header)
for 3.x and `<mbedtls/compat-3-crypto.h>` for 4.x. Most of
`bufferevent_mbedtls.c` then compiles unchanged across mbedtls 2 / 3 / 4 —
**no `MBEDTLS_PRIVATE` patch needed on our side.**

### Release-tag landscape

The only release tag is still `release-2.2.1-alpha` (May 2023). All the
mbedtls 3.x improvements live on **master only** — there is no newer
stable tag to pin to. Options:

1. **Pin a recent master SHA via `SRCREV`** *(recommended)*. Set
   `PV = "2.2.1+git${SRCPV}"`, `SRCREV = "<sha>"`, `BRANCH = "master"`.
   Deterministic build, easy to bump, picks up everything in the table
   above.
2. **`AUTOREV`** — too unstable.
3. **Stay on `release-2.2.1-alpha` + carry forward-port patches** —
   strictly worse than (1) since upstream has already done the work.

Pick (1). Choose the SHA at port time — currently the latest mbedtls-relevant
commit is `7cfffeaa5c` (2025-11-28), but use whatever HEAD looks like the
day we open the PR (run a smoke build first).

### Recipe changes

- Bump `SRCREV` to the chosen upstream master commit.
- Update `SRC_URI` from the github releases tarball to a git fetch:
  `SRC_URI = "git://github.com/libevent/libevent.git;protocol=https;branch=master"`.
- Drop `SRC_URI[sha256sum]` (no longer applicable to git fetch).
- Update `S` to point at `${WORKDIR}/git`.
- Adjust `PV` to a `${SRCPV}`-derived form.
- **Drop `files/undef_ssl_renegotiation.patch`** — superseded by upstream
  `370d99244d`.
- No new patches needed (the compat shim handles the 3.x API breaks).

### Sanity-check at port time

- [ ] Build libevent against mbedtls 3.6.5 — `bufferevent_mbedtls` must
      compile clean (no warnings about private member access; if any
      slip in, fall back to `-DMBEDTLS_ALLOW_PRIVATE_ACCESS` in CFLAGS).
- [ ] `event_rest.c` TLS handshake to Hub via libevent's bufferevent works
      (covered by Validation §4).
- [ ] No regression in long-running TLS sessions — confirm upstream
      issue #1709 (double-free) is in fact fixed at the chosen SHA.
- [ ] If we kept renegotiation on the wire anywhere (we shouldn't —
      our patch was already hard-disabling it), confirm upstream's TLS 1.3
      stance matches ours.

## libthttp compatibility

`libthttp` (`recipes-pv/libthttp/libthttp_git.bb`) also DEPENDS on mbedtls.
Audit its uses for the same 3.x API breaks: struct-field access (need
`MBEDTLS_PRIVATE` wrapping), sha256 return-value handling, and any
`mbedtls_pk_parse_*` signature changes. Most likely treatment matches
pantavisor's own surface — small mechanical patch or the
`MBEDTLS_ALLOW_PRIVATE_ACCESS` flag during the transition.

## Validation plan

The port is "done" when the following all pass on **scarthgap docker-x86_64**
(fast iteration) and **at least one BSP target** (e.g. raspberrypi-armv8 or
docker-arm64).

### 0. Build / packaging

- [ ] `kas build .github/configs/release/docker-x86_64-scarthgap.yaml` clean.
- [ ] `bitbake -e mbedtls | grep '^PV='` reports `3.6.5`.
- [ ] `bitbake pantavisor` and `bitbake libthttp` and `bitbake libevent`
      compile without warnings beyond the baseline.
- [ ] Same on a kirkstone config once recipe is vendored.
- [ ] Same on `bsp-multi.yaml` (multiconfig path) — initramfs side picks up
      3.6 too.

### 1. Local signature validation (offline)

Goal: state.json/object signatures verified by `signature.c` continue to
verify both ASN.1-wrapped and raw `(r,s)` ECDSA signatures.

Test artefacts: a known signed revision (TESTING + INSTALLED transitions),
plus a synthetic signed payload using a raw `(r,s)` signature produced by an
HSM/cloud KMS-style signer.

- [ ] **CA-signed device cert path**: with appengine started normally, a
      revision signed against the bundled trust store transitions
      `TESTING → INSTALLED`. Look for `pv_signature_verify` success in
      `pantavisor.log`.
- [ ] **Bad signature**: corrupt one byte of the signature → revision
      remains in `ERROR` (signature failure logged, not a crash).
- [ ] **Raw (r,s) ECDSA**: produce a payload with raw 64-byte ECDSA-P256
      signature (no ASN.1 wrapping). With our forward-ported pk_wrap.c
      patch (or PSA-backed path), verification succeeds. Without the
      patch + without PSA, this **must** fail — confirms patch coverage.
- [ ] **All curves we ship** (`SECP256R1`, `SECP384R1`, `CURVE25519`):
      sign+verify roundtrip via `pvr` tool.

### 2. SHA256 hashing

Sanity check `mbedtls_sha256_*` return-value handling in `updater.c` /
`storage.c`.

- [ ] Verify `pvr` object hashes for an existing revision match
      `sha256sum` of the underlying file (spot check 5 objects).
- [ ] Truncate one object on disk → `pv_storage_validate_objects` flags
      mismatch (hash mismatch logged, no crash).

### 3. base64

- [ ] Round-trip `pv-utils-base64` (or equivalent in tests) on random
      payloads ≤ 4 KiB.

### 4. Online cloud-comma (Hub TLS path)

This exercises `event_rest.c` end-to-end against Pantacor Hub or a local
mock matching its TLS profile.

- [ ] `pv-ctrl signal claim` → device claims successfully.
- [ ] Device polls `/devices/<id>/steps` and downloads a new revision over
      TLS. Confirm `mbedtls_ssl_handshake` completes (no errors logged) and
      payload integrity holds (object hashes match).
- [ ] **SNI**: connect to a host requiring SNI (Hub frontend); confirm cert
      chain validates with `MBEDTLS_SSL_VERIFY_REQUIRED` once we flip from
      `_VERIFY_NONE`.
- [ ] **Trust store**: with a CA *not* in the bundled
      `/etc/ssl/certs/ca-certificates.crt`, handshake fails closed.
- [ ] **Reconnect / long-running**: leave the device polling for 30 min;
      no leaks (RSS stable in `pantavisor` process), no deadlocks.
- [ ] **Update lifecycle**: full DOWNLOAD → TESTING → INSTALLED → next
      DOWNLOAD against Hub — exercises both online (TLS download) and
      offline (signature verify on TESTING) paths together.

### 5. xconnect / pv-ctrl regression

xconnect doesn't link mbedtls directly today, but pv-ctrl shares the
process. Run the `TESTPLAN-pvctrl.md` and `TESTPLAN-xconnect.md` smoke
suites to catch any incidental breakage from the libevent/libthttp recompile.

- [ ] Full `TESTPLAN-pvctrl.md` API surface returns expected results.
- [ ] xconnect unix + rest examples (provider/consumer) connect.

### 6. Auto-recovery / reboot loop

Sanity check the runtime under stress to surface any heap/stack regression
introduced by the larger 3.6 footprint.

- [ ] `pv-example-recovery` group: 3 crash cycles, backoff respected.
- [ ] Hard reboot; revision survives, signature re-verified on boot.

### 7. Footprint check (size budget)

- [ ] Compare initramfs size (`pantavisor-initramfs-*.cpio.gz`) before and
      after. Document the delta in the PR. Target: < +10 % vs 2.28-mini.
      If we exceed budget, fall back to `MBEDTLS_USER_CONFIG_FILE`
      pruning (option 3 above).

## Rollout

1. Branch `feature/mbedtls-3.6` in meta-pantavisor (and matching feature
   branch in pantavisor source if needed for the API port).
2. CI: run scarthgap docker-x86_64 + at least one ARM BSP via the existing
   `buildkas-target.yaml` workflow.
3. Manual validation per "Validation plan" above on docker-x86_64 against
   staging Hub.
4. Field test on at least one ARM BSP against staging Hub for 48 h before
   merging to master.
5. Retire the `pantacor/mbedtls` GitLab fork (archive the repo, link to
   meta-pantavisor `recipes-pv/mbedtls/` from its README).

## Open questions

- ~~Does `MBEDTLS_USE_PSA_CRYPTO` cover raw `(r,s)` ECDSA verification in 3.6,
  making the pk_wrap.c patch unnecessary?~~ — **Resolved as a phasing
  question above.** Phase 1 keeps the patch and matches our current 2.28
  posture; Phase 2 turns `USE_PSA_CRYPTO` on and validates the patch can
  be dropped.
- If/when we go to Phase 2 (USE_PSA_CRYPTO on): where do we put
  `MBEDTLS_PSA_ITS_FILEIO_LOCATION` for persistence? Candidates:
  `/var/pantavisor/psa-its/` (per-device, persists across updates) vs
  disabling `MBEDTLS_PSA_CRYPTO_STORAGE_C`/`MBEDTLS_PSA_ITS_FILE_C`
  outright if we have no need for persistent PSA keys.
- Do we want to flip `MBEDTLS_SSL_VERIFY_NONE` → `MBEDTLS_SSL_VERIFY_REQUIRED`
  in `event_rest.c` as part of this work, or as a follow-up? Security says
  "yes, now"; risk says "separate PR".
- kirkstone vendoring location: `dynamic-layers/openembedded-layer/` vs
  a top-level `recipes-pv/mbedtls/mbedtls_3.6.5.bb` with kirkstone-only
  override. Decide before opening the PR.
