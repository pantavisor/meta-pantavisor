# pv-llama — the shared reasoner

`pv-llama` is the **reasoning tier** of the agentic architecture
described in [AGENTIC.md](AGENTIC.md). It is the one container per
device that holds the LLM models and exposes them as a stateless,
OpenAI-compatible REST service that every agent-app on the box can
consume concurrently. This document covers what's inside the container,
how it ships, how agent-apps consume it, and how the implementation
aligns (or doesn't) with the platform vision.

## At a glance

| Concern                       | Choice / value                                |
|-------------------------------|-----------------------------------------------|
| Inference engine              | `llama.cpp` / `llama-server` (CPU)            |
| Lifecycle / multi-model       | `llama-swap` (lazy-spawn, swap, TTL evict)    |
| Public API                    | OpenAI-compatible (`/v1/models`, `/v1/chat`)  |
| Wire transport                | TCP inside the container, UDS at the boundary |
| Service-mesh role             | `service-manifest-xconnect@1` REST provider   |
| Service name in xconnect      | `pv-llama`                                    |
| Models                        | One pvr object per GGUF (data squashfs)       |
| Default models bundled        | `deepseek-r1` (1.5B), `qwen` (0.5B)           |
| Other model recipes available | `smollm2-135m`, `smollm2-360m`                |
| Naming in `/v1/models`        | `local-<name>`                                |
| State                         | None (per-request, no session)                |

## Container shape

```
             xconnect (REST mediation, many-to-one)
                          │
                  /run/pv-llama/api.sock
                          │
                          ▼
                  ┌──────────────┐
                  │    socat     │   bridge UDS ↔ TCP
                  │ UDS-LISTEN → │
                  │  TCP:8080    │
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │  llama-swap  │   reads /etc/pv-llama/llama-swap.yaml
                  │   :8080      │   routes by request `model:` field
                  └──────┬───────┘
              ┌──────────┴────────────┐
              ▼                       ▼
       ┌──────────────┐        ┌──────────────┐
       │ llama-server │        │ llama-server │   spawned on demand,
       │  --model …/  │        │  --model …/  │   evicted on TTL,
       │  qwen/       │        │  deepseek/   │   one per loaded model
       │  model.gguf  │        │  model.gguf  │
       └──────────────┘        └──────────────┘
```

The model files live in **separate** squashfs objects mounted by
pantavisor at runtime under `/usr/share/pv-llama/models/<name>/`.
Bumping one model touches one pvr object; bumping the runtime touches
none of the model objects.

## File and recipe layout

```
recipes-ai/
├── llama-cpp/
│   └── llama-cpp_git.bb              # llama.cpp / llama-server (CPU build)
└── llama-swap/
    └── llama-swap_207.bb              # upstream static binary (arm64/amd64)

recipes-containers/agentic/
├── pv-llama_1.0.bb                    # container recipe
├── pv-llama-model.inc                 # shared bits for every model recipe
├── pv-llama-model-deepseek-r1_1.0.bb  # DeepSeek-R1-Distill-Qwen-1.5B (~1.1 GB)
├── pv-llama-model-qwen_1.0.bb         # Qwen2.5-0.5B-Instruct (~470 MB)
├── pv-llama-model-smollm2-135m_1.0.bb # SmolLM2-135M-Instruct (~100 MB)
├── pv-llama-model-smollm2-360m_1.0.bb # SmolLM2-360M-Instruct (~260 MB)
└── files/
    ├── pv-llama-run.sh                # entrypoint: socat + llama-swap
    └── pv-llama.services.json         # xconnect service manifest
```

### What the container ships

```
/usr/bin/llama-server                       (from llama-cpp)
/usr/bin/llama-swap                         (from llama-swap)
/usr/bin/socat                              (busybox / socat)
/usr/bin/pv-llama-run                       (entrypoint)
/etc/pv-llama/llama-swap.yaml               (auto-generated from LLAMA_MODELS)
/usr/share/pv-llama/models/<name>/          (mountpoint per model — empty in rootfs)
services.json                               (xconnect manifest, in pvrexport)
```

### What ships next to the rootfs as separate pvr objects

```
data: <name>.squashfs                       (one per model in LLAMA_MODELS)
       └── content of each squashfs:
           model.gguf                       (the GGUF weights)
           model.json                       (metadata: name, family, params,
                                             version, sha, file)
```

## Build-time configuration

Recipe variables on `pv-llama_1.0.bb`:

| Variable                       | Default            | Purpose                                                 |
|--------------------------------|--------------------|---------------------------------------------------------|
| `LLAMA_MODELS`                 | `deepseek-r1 qwen` | Whitespace list of model names to bundle                |
| `LLAMA_DEFAULT_CTX`            | `4096`             | `--ctx-size` for every model unless overridden          |
| `LLAMA_DEFAULT_THREADS`        | `4`                | `--threads` for every model unless overridden           |
| `LLAMA_DEFAULT_TTL_SECONDS`    | `300`              | llama-swap idle eviction TTL                            |
| `LLAMA_MODELS_DIR`             | `usr/share/pv-llama/models` | Mount root (relative, LXC-required)            |

Each name in `LLAMA_MODELS` must match a `pv-llama-model-<name>` recipe
that the container DEPENDS on automatically (resolved by an anonymous
python block in the recipe).

Recipe variables on `pv-llama-model.inc` (set by per-model `.bb`):

| Variable               | Required | Example                                          |
|------------------------|----------|--------------------------------------------------|
| `LLAMA_MODEL_NAME`     | yes      | `qwen`                                           |
| `LLAMA_MODEL_URL`      | yes      | `https://huggingface.co/…/q4_k_m.gguf`           |
| `LLAMA_MODEL_SHA256`   | yes      | `74a4da8c…`                                      |
| `LLAMA_MODEL_VERSION`  | yes      | `qwen2.5-0.5b-instruct-q4_k_m`                   |
| `LLAMA_MODEL_DESC`     | yes      | One-line human description                       |
| `LLAMA_MODEL_FAMILY`   | optional | `qwen2.5` (defaults to `LLAMA_MODEL_NAME`)       |
| `LLAMA_MODEL_PARAMS`   | optional | `0.5B`                                           |
| `LLAMA_MODEL_FILE`     | optional | `model.gguf` (default — keep this)               |

## Adding a model

```bitbake
# recipes-containers/agentic/pv-llama-model-smollm2-135m_1.0.bb
SUMMARY = "SmolLM2-135M-Instruct GGUF packaged as a pv-llama model squashfs"
require pv-llama-model.inc

LLAMA_MODEL_NAME    = "smollm2-135m"
LLAMA_MODEL_FAMILY  = "smollm2"
LLAMA_MODEL_PARAMS  = "135M"
LLAMA_MODEL_VERSION = "smollm2-135m-instruct-q4_k_m"
LLAMA_MODEL_DESC    = "SmolLM2-135M-Instruct, Q4_K_M (~85 MB) — low-spec workhorse"
LLAMA_MODEL_URL     = "https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct-GGUF/resolve/main/smollm2-135m-instruct-q4_k_m.gguf"
LLAMA_MODEL_SHA256  = "<sha256>"
```

Append the name to the container recipe:

```bitbake
LLAMA_MODELS = "deepseek-r1 qwen smollm2-135m"
```

Rebuild `pv-llama`. The new model is its own squashfs object; existing
devices only have to download the new object (~85 MB), not the entire
container. The model appears as `local-smollm2-135m` in `/v1/models` on
next start.

## Public API (consumed by agent-apps)

`pv-llama` exposes the standard llama-swap surface:

- `GET /v1/models` — list every configured model. Each entry has
  `id` (e.g. `local-qwen`), plus llama-swap's metadata.
- `POST /v1/chat/completions` — OpenAI-compatible chat. The `model`
  field selects the backend; cold-loads the matching `llama-server` if
  not running, swaps another model out under RAM pressure if needed.
- `POST /v1/completions` — legacy completion endpoint, same routing.
- `POST /v1/embeddings` — if the loaded model supports it.
- `GET /healthz` — liveness.
- `GET /upstream/{model}/<…>` — passthrough to the model's
  `llama-server` for endpoints not in the OpenAI surface (e.g.
  `/completion`, `/tokenize`).

Grammar-constrained generation (`response_format: { type: "grammar",
grammar: "..." }` or the `/completion` endpoint's `grammar` field) is
the canonical way an agent-app pins the response to a tool-call schema.

## Consuming `pv-llama` from an agent-app

An agent-app declares `pv-llama` as a required service in its
`args.json`:

```json
{
    "PV_SERVICES_REQUIRED": "pv-llama"
}
```

xconnect injects a socket at `/run/pv/services/pv-llama.sock` (or the
configured path) inside the agent-app's namespace. The agent-app makes
HTTP requests over that UDS exactly as if it were `localhost:8080`.

Multiple agent-apps consume the same `pv-llama` simultaneously —
xconnect mediates one provider to many consumers. Each gets its own
injected socket; the model container sees them as concurrent HTTP
clients with no notion of which agent is which.

The agent-app picks the model per request by setting the `model` field
in the body (`local-qwen`, `local-deepseek-r1`, …). Per-app preferences
typically live as env vars in the agent-app's `args.json`:

```json
{
    "PV_SERVICES_REQUIRED": "pv-llama",
    "AGENT_DEFAULT_MODEL": "local-qwen",
    "AGENT_FALLBACK_MODEL": "local-deepseek-r1"
}
```

## Operational behaviour

- **First request to an unloaded model**: cold-load. llama-swap forks
  `llama-server` with the model's args, waits for `/health` ready,
  then proxies. Latency = model file size / disk speed + a few
  hundred ms of model graph init. On a Pi 5 this is 2-6 s for the
  default models.
- **Subsequent requests to a loaded model**: sub-millisecond proxy
  hop, then llama-server inference latency.
- **Idle TTL**: a model not used for `LLAMA_DEFAULT_TTL_SECONDS` is
  killed and its RAM reclaimed. Next use cold-loads again.
- **RAM pressure / different model requested**: by default llama-swap
  keeps one model loaded at a time and swaps. Configure groups in
  `llama-swap.yaml` to allow multiple models loaded concurrently up
  to a RAM budget — useful on the 8 GB Pi 5 where two small models
  fit comfortably.
- **Concurrent same-model requests**: llama-server queues internally;
  llama-swap does not serialize. Throughput is bounded by inference
  speed.

## Architecture alignment audit

How well does the current implementation match the design described
in [AGENTIC.md](AGENTIC.md)?

| Principle (AGENTIC.md)                                     | Status | Notes                                                  |
|------------------------------------------------------------|--------|--------------------------------------------------------|
| Models are easy to add (one short recipe)                  | ✅     | 3-line `.bb` + `LLAMA_MODELS` append. Verified.        |
| Context comes from containers, not from the model          | ✅     | Model is stateless; no container-side history.         |
| Sensor translators are pluggable                           | n/a    | This is the perception tier's concern, not pv-llama.   |
| Business logic lives in the agent-app, not the model       | ✅     | Container has no app-specific code or prompts.         |
| Tools are services, not model capabilities                 | ✅     | Container has no tool registry; agent-app dispatches.  |
| Structure beats prose (grammar-constrained)                | ✅     | llama.cpp `--grammar` is exposed via the API.          |
| Cloud is opt-in and out-of-band                            | ✅     | No cloud code in the container; deferred to router.    |
| Model is part of the product, not a runtime download       | ✅     | GGUF baked in at build time, signed via pvrexport.     |
| Many apps, one model (shared infrastructure)               | ✅     | xconnect mediates many consumers; no per-app state.    |
| Independent model updates                                  | ✅     | Each model is its own pvr object.                      |
| Independent runtime updates                                | ✅     | Bumping `llama-cpp` or `llama-swap` doesn't re-upload models. |
| Reasoner is stateless                                      | ✅     | No session, no memory, per-request only.               |
| Multi-model selection per request                          | ✅     | `model:` field in the body, llama-swap routes.         |

### Known gaps and follow-ups

- **No per-app capability/quota enforcement.** Any consumer of
  `pv-llama` can request any model, including (when added) the
  cloud-routed ones via `pv-llama-router`. Mitigation today is by
  agent-app code; long-term it should move into the routing layer
  and/or xconnect policy. Not a blocker for the local-only deploy.
- **One model loaded at a time by default.** Workable for low-RAM
  boards but suboptimal on an 8 GB Pi 5 with two small models in
  active use. Action: ship a default `groups:` config in
  `/etc/pv-llama/llama-swap.yaml` that permits two simultaneously
  loaded models when the bundle includes more than one ≤500 MB
  model.
- **No fairness between concurrent agent-apps.** A noisy agent can
  hog inference time. Acceptable for v1; add per-consumer rate
  limits in `pv-llama-router` when that ships.
- **No auth on the xconnect REST socket.** xconnect's contract is
  presence-based: if you have the socket injected, you can talk.
  This is consistent with the rest of the platform; per-app
  capability limits belong in the routing layer, not here.
- **No embeddings model in the default bundle.** RAG demos will need
  a sentence-transformer-like embeddings model. Action: add a
  `pv-llama-model-embeddings-*` recipe and document its mode (most
  llama.cpp builds support an `embedding` flag toggled per-server;
  llama-swap handles routing).
- **pvr 050 template bug for ≥2 volumes.** `pvr 050`'s
  `templates/builtin-lxc-docker.go` joins the run.json `volumes`
  array with a literal `,\n` (Go raw-string escape), which makes the
  result invalid JSON when a container has two or more volumes. The
  per-model squashfs design hits this immediately with the default
  `LLAMA_MODELS` of two models. Worked around in
  `recipes-pv/pvr/pvr_050.bbappend` with a sed at do_compile time;
  drop the bbappend when upstream pvr releases the fix.
- **Resolved: build skips cleanly on incompatible arches.**
  `pv-llama_1.0.bb` now also sets
  `COMPATIBLE_HOST = "(aarch64|x86_64).*-linux"`, mirroring
  `llama-swap`. Multiconfig builds that include 32-bit ARM (e.g.
  rpi-scarthgap with `MACHINE=raspberrypi`) now skip the recipe
  cleanly instead of erroring out. To build pv-llama, target a
  64-bit machine config (`raspberrypi-armv8-scarthgap.yaml`,
  `docker-x86_64-scarthgap.yaml`, etc.).

## Update story

The pvrexport bundle for `pv-llama` is structured so each piece updates
independently:

```
pv-llama/
├── root.squashfs        ← runtime (llama-cpp + llama-swap + scripts).
│                          Changes when you bump either upstream tool
│                          or modify launcher / config rendering.
├── deepseek-r1.squashfs ← one model. Changes only when you bump that
│                          specific model recipe.
├── qwen.squashfs        ← one model. Independent.
├── run.json             ← LXC config + env. Cheap to change.
├── lxc.container.conf
└── services.json        ← xconnect manifest.
```

A typical update lifecycle on a fleet:

- **System prompt change** — not in this container; an agent-app
  revision. pv-llama is unchanged.
- **Tool catalog change** — same, agent-app side.
- **Bumping `llama-swap` to v208** — `root.squashfs` changes (~20 MB
  delta on devices). No model re-upload.
- **Bumping `llama-cpp`** — `root.squashfs` changes (~3-5 MB delta
  typically). No model re-upload.
- **Bumping the qwen model** — `qwen.squashfs` changes (~470 MB on
  devices that update). `deepseek-r1.squashfs` and `root.squashfs`
  are not touched, so devices not running qwen don't pay for it.
- **Adding a new model** — one new squashfs object enters the
  bundle. Devices that already have the existing models do a
  delta-style fetch of just the new one.

This is the storage / bandwidth payoff for the per-model-as-its-own-pvr-object design.

## Cloud offload (forthcoming)

`pv-llama-router` will be a separate container that runs litellm and
sits in front of `pv-llama`:

- Re-exposes `pv-llama`'s API and adds cloud models (`anthropic-…`,
  `openai-…`, `bedrock-…`).
- Local model names are pass-throughs (`local-qwen` still works).
- Cloud creds come from signed pv-config; never embedded in the image.
- Routing decision is made *by the agent-app* via its `model:` field
  choice. The router does not auto-route.

`pv-llama` itself does **not** change when the router lands; agent-apps
that want cloud capability declare both services in their
`PV_SERVICES_REQUIRED`.

## See also

- [AGENTIC.md](AGENTIC.md) — overall architecture, four-role model,
  many-apps-one-model platform pattern.
- [EXAMPLES.md](EXAMPLES.md) — xconnect service mesh examples.
- [DEVELOPMENT.md](DEVELOPMENT.md) — build / iterate / deploy.
- `recipes-containers/agentic/pv-llama_1.0.bb` — the container recipe.
- `recipes-containers/agentic/pv-llama-model.inc` — shared model recipe bits.
- `recipes-ai/llama-swap/llama-swap_207.bb` — llama-swap binary recipe.
- `recipes-ai/llama-cpp/llama-cpp_git.bb` — llama.cpp build.
