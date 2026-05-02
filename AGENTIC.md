# Agentic on Pantavisor

A high-level vision for what *agentic* means on Pantavisor — and a guide to
the building blocks this layer ships today so developers can compose it
into real products. Companion document to [EXAMPLES.md](EXAMPLES.md);
implementation pointers live in
[recipes-containers/agentic/](recipes-containers/agentic/).

## The pitch in one sentence

> A Pantavisor device should be able to run useful AI **on its own
> hardware, offline, behind a signed atomic update, with no SaaS in the
> loop** — and stay that way for years in the field.

## Why this matters

The interesting move in embedded AI right now is not "can we run a 70B
model on a phone." It is the opposite: tiny language models (135M–1.5B
params) and tiny vision-language models have crossed the threshold where
they are **genuinely useful as the language layer of a sensor pipeline**.
Pair classical or TFLite perception with a tiny LLM and you get devices
that *talk*, *decide*, *summarize*, and *act* — entirely on a $50 board,
with no cloud, no per-device subscription, and no privacy story to
explain to a customer.

Pantavisor is uniquely well-suited to ship this:

- **Atomic, signed OTA** of both the runtime *and* the model weights.
- **Container isolation** between perception, reasoning, and action —
  upgradeable independently.
- **Multi-arch, multi-board** from the same image lineage (Pi 5, sunxi,
  i.MX, x86 appengine).
- **xconnect service mesh** so containers compose without each one
  reinventing IPC.
- **Bandwidth-aware OTA**: model weights ship as their own pvr objects;
  bumping the runtime does not re-upload 1 GB of weights, and bumping
  one model does not touch the others.

## Four roles, one orchestrator

The architecture has four roles, but only one of them is the actor: the
**agent app**. Everything else is something the agent calls.

```
                   ┌─────────────────────────────────────┐
                   │            AGENT APP                │
                   │  (the agentic device app container) │
   PERCEPTION ────▶│                                     │◀──── ACTION
   (events in)     │  • owns the business prompt         │      (tool
                   │  • owns the tool catalog            │       calls
                   │  • owns conversation / scratchpad   │       out)
                   │  • runs the reasoning loop          │
                   │  • parses tool calls and executes   │
                   │    them against other services      │
                   │  • decides when to escalate to      │
                   │    cloud reasoning                  │
                   └────────┬───────────────────────▲────┘
                            │ prompt                │ tool results,
                            │ (system + context     │ next-step decision
                            │  + recent events +    │ (text or JSON
                            │  tool catalog)        │  tool call)
                            ▼                       │
                   ┌─────────────────────────────────────┐
                   │             REASONING               │
                   │  pv-llama (local, multi-model)      │
                   │  pv-llama-router (cloud offload)    │
                   └─────────────────────────────────────┘
```

The four roles:

1. **PERCEPTION** — *dumb-and-fast.* Classical CV, TFLite on Linux,
   thresholds, FFTs, Whisper.cpp, a VLM. Turns raw signal into a tight
   structured event (`{kind, source, timestamp, …details}`) and emits it
   over xconnect. Knows nothing about products, prompts, or LLMs.

2. **AGENT APP** — *the actor.* This is the **agentic device app**: a
   container whose job is to *be the product*. It subscribes to one or
   more perception feeds, owns the system prompt and the tool catalog,
   composes prompts, calls the reasoner, parses tool-call responses,
   executes the tools by talking to other xconnect services, and loops
   until the task completes. Per-product business logic lives here, and
   *only* here.

3. **REASONING** — *a function, not an actor.* `pv-llama` (and optional
   `pv-llama-router` for cloud offload) is a stateless OpenAI-compatible
   service. It is **never** wired to actuators directly. It returns text
   or JSON; the agent app decides what to do with it.

4. **ACTION** — *the world.* MQTT, Matter, Home Assistant, webhooks,
   TTS, GPIO, e-mail, MIDI, the screen. Each is a tool the agent app
   can call (typically itself another xconnect service).

Why the agent app is a separate role and not "just call the model from
the analyzer or directly from the action sink":

- **Prompts and policy live with the product, not with the model.** The
  same `pv-llama` serves a wildlife trail-cam, a 3D-printer monitor,
  and a doorbell — each has its own agent app with its own prompt,
  tools, and personality. Swap the agent app, get a different product
  on the same model.
- **Tool calls are executed by the device, not by the model.** Models
  can hallucinate. Letting an LLM directly poke MQTT or a webhook is
  how you get cursed bug reports. The agent app validates the tool
  call against its catalog (schema, allow-list, rate limits) before
  acting. The model proposes; the device disposes.
- **Conversation / scratchpad / memory belong to the agent.** The
  reasoner is stateless on purpose. The agent app keeps the loop
  state, retries failed tools, tracks budgets, and decides when the
  task is done.
- **Cloud-vs-local is an agent-app policy decision.** Easy queries go
  to local. Hard queries get escalated through `pv-llama-router`. The
  app, not the model, makes the call — based on cost, latency,
  privacy, or capability requirements.

Tiny LLMs are not sensor processors and not actuators. They are the
universal adapter between machine signals and humans (or other
machines), wrapped by an agent that turns adapter output into action.
Treat them that way and they punch far above their weight at 135M–500M
params.

## Many apps, one model

The most important structural property of this design — and the one that
makes it a *platform* rather than a per-product code dump — is that
**`pv-llama` is shared infrastructure**. One model container per device,
many agent-app containers consuming it concurrently. Every product that
ships on the box pays the model cost once, and adds only its own
container.

```
            ┌──────────────────────────────────────────┐
            │           one  pv-llama  container       │
            │   (multi-model serving, stateless)       │
            │                                          │
            │   /v1/models  →  local-qwen,             │
            │                  local-deepseek-r1, …    │
            │   /v1/chat/completions  →  swap-on-demand│
            └─────────▲──────────▲─────────▲───────────┘
                      │          │         │
        xconnect REST │          │         │  xconnect REST
        (per-app UDS) │          │         │
                      │          │         │
        ┌─────────────┴──┐  ┌────┴─────┐ ┌─┴──────────────┐
        │ agentic-app:   │  │agentic-  │ │ agentic-app:   │
        │ trail-cam      │  │log-      │ │ doorbell       │
        │  • prompt: "be │  │anomaly   │ │  • prompt:     │
        │    a wildlife  │  │ • prompt:│ │    "describe   │
        │    journalist" │  │   triage │ │    visitors,   │
        │  • tools:      │  │   sev    │ │    classify    │
        │    journal-    │  │ • tools: │ │    intent"     │
        │    write       │  │   ticket,│ │  • tools:      │
        │  • RAG: prior  │  │   alert  │ │    notify,     │
        │    journal     │  │ • policy:│ │    capture-    │
        │    entries     │  │   local- │ │    save        │
        │  • policy:     │  │   only   │ │  • policy:     │
        │    local-only  │  │          │ │    cloud for   │
        │                │  │          │ │    rare faces  │
        └────────────────┘  └──────────┘ └────────────────┘
```

What each agent-app brings of its own:

- **System prompt / persona / instructions.** The trail-cam agent is a
  wildlife journalist; the log-anomaly agent is a senior SRE; the
  doorbell agent is a security-aware household assistant. Same model,
  three completely different products.
- **Tool catalog.** A JSON schema list of tools the agent can call,
  with allow-lists and rate limits enforced inside the agent-app.
  Trail-cam has `journal-write` and `notify`; log-anomaly has
  `open-ticket` and `escalate`; doorbell has `notify`, `capture-save`,
  `unlock` (gated). Tools are *declared per app*, not globally.
- **Context.** Recent events, conversation history, scratchpad, RAG
  corpus. The trail-cam agent ships its prior journal entries as a
  squashfs object and retrieves the last week as context. The doorbell
  agent ships face embeddings. The log-anomaly agent ships nothing —
  each event is independent.
- **Routing policy.** Local-only, local-with-cloud-escalation, or
  cloud-only — per app, per event type, per cost budget. The agent-app
  decides; the model container has no opinion.
- **Persistence layout.** Where the agent's state lives, how often it
  is checkpointed, what survives a reboot. Pantavisor's pvr makes this
  a per-container concern.
- **Update cadence.** Tweaking a system prompt is an agent-app revision
  bump (a tiny pvr delta). Bumping the model is a separate, less
  frequent event. Bumping a tool implementation is yet another
  independent change.

What `pv-llama` provides to *all* of them:

- An OpenAI-compatible REST endpoint over xconnect, mediated as a
  shared service consumed by many.
- Multi-model serving (`local-qwen`, `local-deepseek-r1`, …) so each
  agent can pick the model that fits its task without negotiating
  with anyone.
- Lazy load + RAM-bounded swap, so two agents using two different
  models on the same device get reasonable behaviour automatically.
- Statelessness: no per-app session state inside the model container,
  which is what *lets* it be shared without coordination.

Why this matters for the platform pitch:

1. **Amortise the model cost.** A 1 GB model on disk and 1 GB resident
   in RAM serves N products on one device. The marginal cost of
   adding the (N+1)th product is its agent-app, typically a few MB
   of code plus its prompt and tools.
2. **One device, many personalities.** A single appliance can run a
   wildlife journal, a security narrator, and a maintenance assistant
   simultaneously, each as its own container with its own update
   cadence and its own update audit trail.
3. **Ecosystem ergonomics.** A third party can ship an `agentic-app-*`
   container against the existing `pv-llama` contract and have it
   work on every Pantavisor device that already has the model. No
   model retraining, no SDK lock-in, no cloud account required.
4. **Per-app safety boundary.** Tool catalogs are a per-app
   capability list. The wildlife agent can never call `unlock` because
   it isn't in its catalog — nothing about the model knows or cares,
   and the model can't escape the catalog because it never directly
   touches actuators in the first place.
5. **Independent evolution.** A prompt regression in one agent doesn't
   touch the others. A model upgrade is an opt-in choice each agent
   makes via its routing policy. A new tool ships only to the agents
   that need it.

The single-container, single-app deployments are the simple case;
multi-app sharing is what the architecture is *designed for*. Every
piece — xconnect's many-to-one service mediation, pvr's per-container
update granularity, llama-swap's transparent multi-model serving,
grammar-constrained per-app tool catalogs — points at this shape.

## The container pipeline pattern

The four-role architecture above is an abstraction; the concrete shape
on Pantavisor is a **pub/sub pipeline of containers**, each a
specialist that subscribes to events from upstream peers, does its one
job, and emits its own events or actions. This is how the existing
agentic suite is already wired:

```
┌─────────┐   ┌──────────┐   ┌────────────────┐   ┌──────────┐   ┌────────┐
│  feed:  │──▶│ analyzer:│──▶│  agent-app:    │──▶│ reasoner:│   │tools:  │
│  raw    │   │perception│   │  the agent     │◀──│ pv-llama │   │MQTT,   │
│  signal │   │ (TFLite, │   │  • prompt      │   └──────────┘   │matter, │
│ capture │   │  OpenCV, │   │  • tool catalog│         ▲         │webhook,│
│         │   │  VLM …)  │   │  • loop driver │         │         │TTS, …  │
└─────────┘   └──────────┘   │  • tool exec   │─────────┼────────▶└────────┘
                             └────────────────┘   tool calls
   feed       analyzed       composes prompts,    out (xconnect
   events     events         dispatches tools     to other
                                                  services)
```

The agent-app is the centre of the loop: it pulls events in from the
analyzer, composes a prompt, asks the reasoner, parses the response,
calls tools, feeds tool results back into the next prompt, and decides
when the loop is done. Reasoning is a stateless function it calls.
Tools are other xconnect services. The agent-app is the only container
that holds product-specific business logic; everything else is generic.

Two existing agentic suites already follow the perception side of this
shape (their agent-app stage is collapsed for now, will be split out
as the demo apps land):

- **Camera pipeline:** `agentic-camera-feed` (capture) → `agentic-camera-analyzer`
  (object detection + OCR) → `agentic-camera-stream` (browser-viewable
  client). Each step is a separate container. The feed has no idea what
  the analyzer does; the analyzer has no idea who is downstream; the
  client only knows the analyzed-events schema. Replace any one and the
  others keep working.

- **Log pipeline:** `agentic-log-feed` (fan-out errors with surrounding
  context) → `agentic-log-anomaly` (LLM-backed triage that decides
  whether to escalate). Same shape, different signal — and
  `agentic-log-anomaly` is the simplest existing example of an
  agent-app role: it owns the prompt, calls the model, and decides
  whether to act.

Properties that fall out of this design:

1. **Compositional.** Add a new sensor by adding a feed container; add
   a new way of analyzing it by adding an analyzer; ship a new product
   by adding an agent-app with its own prompt and tool catalog. None
   of the existing containers change.
2. **Replaceable.** Swap the analyzer (classical CV → tiny VLM)
   without touching the agent-app. Swap the reasoner (local LLM →
   cloud router) without touching anything. Swap the agent-app to
   ship a different product on the same hardware.
3. **Independently updatable.** Each container is its own pvr object;
   bumping one is a small OTA delta. Updating a system prompt is an
   agent-app revision, not a model re-roll.
4. **Independently restartable.** A crashy analyzer doesn't take down
   the feed; auto-recovery handles it container-locally.
5. **Discoverable.** Every link in the pipeline is an xconnect service
   with a declared schema in `services.json` — `pvcontrol graph ls`
   shows the wiring at runtime.
6. **Auditable.** Because the agent-app is the only container that
   talks to both the model and the tools, every tool call is logged
   in one place. The audit trail is the agent-app's log.

The feed/analyzer/agent-app/reasoner/tool roles are conventional, not
enforced: many real pipelines collapse roles (a feed that already
produces analyzed JSON, or an agent-app that talks straight to a
webhook with no separate tool container). The point is the **boundary
contracts**, not the box count.

### Agent-app skeleton

Every agent-app container does roughly the same dance, so the recipe
ships a skeleton (`agentic-app-skeleton`, planned) that handles the
plumbing and lets a product container override only what's specific.
Sketch:

```python
# agentic-app-skeleton: pseudocode for the loop every product subclasses
on_event(event):
    history.append(event_to_user_msg(event))
    while True:
        resp = call_reasoner(
            system_prompt + history,
            tools=tool_catalog,            # JSON schema per tool
            grammar=tool_call_grammar,     # llama.cpp GBNF
            model=routing_policy(event),   # local / cloud decision
        )
        if resp.is_tool_call:
            result = dispatch_tool(resp.tool, resp.args)   # ← validated against catalog
            history.append(tool_result(result))
            continue
        emit_action(resp.text)             # final answer / narrative
        break
```

A product container provides:

- a `system_prompt.md` (its persona, task, constraints, examples);
- a `tools.json` (catalog of tool schemas it understands);
- a Python module with the tool implementations (each calls another
  xconnect service or local syscall);
- subscriptions: which feeds/analyzers it listens to;
- an action sink: where the final result goes (UI, MQTT, …);
- optional `routing_policy.py` that decides local-vs-cloud reasoning
  per event.

Everything else (model HTTP client, retry, logging, schema validation,
xconnect wiring, auto-recovery) comes from the skeleton.

## Design principles

1. **Models are easy to add.** A new LLM is one ~10-line recipe
   (URL + SHA + family). A new VLM is the same pattern. Models live as
   their own pvr objects so OTA deltas stay small.
2. **Context comes from containers.** Each container is a domain expert
   that knows how to translate its sensor / log / state into text or
   JSON the language layer can consume. The language layer never reads
   raw frames or raw bytes; it reads *captions* and *records*.
3. **Sensor translators are pluggable.** A "perception" container is
   defined by a single contract: *somehow produce structured events,
   expose them as an xconnect REST or message service*. What is inside
   (TFLite, OpenCV, Whisper.cpp, a VLM, a hand-tuned threshold) is the
   container's business.
4. **Business logic lives in the agent-app, not in the model.** The
   model is a stateless reasoner that takes a prompt and returns
   text or a tool call. The agent-app owns the system prompt, the
   tool catalog, the loop, the validation, the memory, and the
   local-vs-cloud routing decision. Replacing the agent-app changes
   the product without touching anything else.
5. **Tools are services, not model capabilities.** When the model
   "calls a tool", what really happens is the agent-app parses a
   JSON object, validates it against a schema, and dispatches it to
   another xconnect service the device controls. The model never
   reaches the world directly.
6. **Structure beats prose.** Grammar-constrained generation (llama.cpp
   `--grammar` / GBNF) eliminates the "tiny model rambles" failure mode.
   The default contract between agent-app and reasoner is JSON, not free
   text.
7. **Cloud is opt-in and out-of-band.** The default mode is fully
   offline. Cloud offload is a separate router container the agent-app
   chooses to call, configured per-device via signed pv-config — not a
   library dep baked into every product.
8. **The model is part of the product, not a runtime download.** No
   "first-boot pulls 1 GB from HuggingFace" patterns. Models are baked
   in, signed, and delta-updated.

## Building blocks shipped today

| Component                          | Role                                          | Status |
|------------------------------------|-----------------------------------------------|--------|
| `pv-llama`                         | Multi-model LLM serving (OpenAI-compatible)   | ✅      |
| `pv-llama-model-deepseek-r1`       | DeepSeek-R1-Distill-Qwen-1.5B (~1.1 GB Q4)    | ✅      |
| `pv-llama-model-qwen`              | Qwen2.5-0.5B-Instruct (~470 MB Q4)            | ✅      |
| `llama-swap`                       | Lazy-spawn / swap llama-server backends       | ✅      |
| `agentic-camera-feed`              | Camera capture as an xconnect service         | ✅      |
| `agentic-camera-mock`              | Synthetic frame source for development        | ✅      |
| `agentic-camera-stream`            | Browser-viewable MJPEG stream                 | ✅      |
| `agentic-camera-analyzer`          | Frame analyzer skeleton                       | ✅      |
| `agentic-log-feed`                 | Local-log fan-out as an xconnect service      | ✅      |
| `agentic-log-anomaly`              | Single-product agent-app: log triage          | ✅      |
| `pv-llama-model-smollm2-135m`      | SmolLM2-135M-Instruct (~100 MB Q4)            | ✅      |
| `pv-llama-model-smollm2-360m`      | SmolLM2-360M-Instruct (~260 MB Q4)            | ✅      |
| `agentic-app-skeleton`             | Generic agent-app harness (loop, tool exec)   | ✅      |
| `agentic-example-log-triage`       | Reference product: log triage on top of the skeleton | ✅      |
| `pv-llama-router` (litellm)        | Cloud offload (Anthropic / Bedrock / OpenAI)  | 🚧 next |
| `pv-llama-model-smolvlm-256m`      | SmolVLM-256M vision-language (~250 MB)        | 🚧 next |
| `pv-llama-model-moondream2`        | Moondream2 (~900 MB) richer VLM for Pi 5 size | 🚧 next |

### `pv-llama` shape

Single OpenAI-compatible REST endpoint exposed via xconnect. Every
local model registered in `LLAMA_MODELS` shows up under `/v1/models`
as `local-<name>`. `llama-swap` cold-loads a model on first request,
keeps it hot under a configurable TTL, evicts under a RAM budget.

Adding a model is one recipe of three lines that matter:

```bitbake
LLAMA_MODEL_NAME = "qwen"
LLAMA_MODEL_URL = "https://…/qwen2.5-0.5b-instruct-q4_k_m.gguf"
LLAMA_MODEL_SHA256 = "74a4da8c…"
```

…then append `qwen` to `LLAMA_MODELS` in the container recipe.

### Sensor translator contract

A perception container should:

- expose an xconnect service (REST, unix socket, or message stream);
- emit structured events: a JSON record with at minimum `{timestamp,
  source, kind, …details}`, or a one-line caption suitable to drop
  into an LLM prompt;
- own its own model lifecycle (TFLite interpreter, OpenCV pipeline,
  whatever) — the language layer never touches raw frames or bytes;
- be replaceable: swapping the perception container must not require
  changes to the reasoning container.

This is just good service design, but stating it explicitly keeps the
ecosystem composable.

## Killer demos to lead with

These are the inspiration set. Each is feasible on a Pi 5 (8 GB), most
fit on a Pi Zero 2 W or i.MX-class with the right model choice. Every
one of them *only works* because of what Pantavisor already does:
offline, atomic update, container-isolated, signed, no SaaS dependency.

1. **Trail-cam that writes its own journal**
   Wildlife camera with no signal. Motion → frame → SmolVLM describes
   the scene → SmolLM2 appends to a daily journal with a literary
   summary. Pull the SD card a month later and read the diary of your
   land. *Containers: agentic-camera-feed + pv-llama (vlm + text).*

2. **3D printer that explains its own failures**
   Webcam on the print bed; VLM watching every Nth layer. Detects
   spaghetti / layer shift / detachment and writes a real diagnosis
   ("first-layer adhesion lost on left, likely bed leveling") rather
   than "anomaly." Auto-pause via Octoprint webhook. Maker-community
   gold.

3. **Voice-controlled home appliance that genuinely never phones home**
   Whisper.cpp on-device for STT, pv-llama with grammar-constrained
   JSON output for intent, local Matter / Home Assistant integration
   for actions. *"Alexa with no Amazon, Google, or Apple — one image
   deploy."*

4. **Bandwidth-poor remote-site reporter**
   Solar farm, weather buoy, livestock pasture, shipping container.
   Local sensors plus camera. Once a day the tiny LLM writes a
   200-byte human-readable digest that goes out over Iridium / LoRa /
   2G — instead of streaming raw telemetry at $5/MB.

5. **Field-service handheld that diagnoses kit on site**
   Technician points a tablet at a faulty unit and presses talk.
   STT → tiny LLM with the local service manual and the device's last
   24h of logs in context → spoken diagnosis and a parts list.
   Factory floor / mine / refinery / aircraft hangar — places with no
   WiFi by design.

Honourable mentions, each a weekend demo:

- Doorbell that says *"dog walker with three dogs"* instead of "motion".
- Aquarium / pet-cam watcher: *"Mochi has been at the food bowl 3 times
  in 20 minutes."*
- Garden / greenhouse caretaker: *"tomatoes look thirsty, basil shows a
  fungal pattern."*
- Air-gapped enterprise log scanner for regulated shops.
- Personal RAG box: a small LLM with retrieval over your local notes /
  manuals — your second brain that doesn't phone home.

## Picking a model size

| Model                           | Q4_K_M size | Min RAM    | Recipe in this layer            | Good for                                       |
|---------------------------------|-------------|------------|---------------------------------|------------------------------------------------|
| SmolLM2-135M-Instruct           | ~100 MB     | 256 MB     | `pv-llama-model-smollm2-135m`   | Pi Zero 2 W, i.MX6 — captions, intent → JSON   |
| SmolLM2-360M-Instruct           | ~260 MB     | 512 MB     | `pv-llama-model-smollm2-360m`   | mid-spec — light reasoning, structured output  |
| Qwen2.5-0.5B-Instruct           | ~470 MB     | 1 GB       | `pv-llama-model-qwen`           | the workhorse for low-end Linux                |
| Qwen2.5-1.5B-Instruct           | ~1.0 GB     | 2 GB       | (not bundled — easy to add)     | reasoning-tier on a Pi 5 / 8 GB box            |
| DeepSeek-R1-Distill-Qwen-1.5B   | ~1.1 GB     | 2 GB       | `pv-llama-model-deepseek-r1`    | chain-of-thought reasoning at the small end    |
| SmolVLM-256M                    | ~250 MB     | 1 GB       | (planned)                       | tiny vision-language: scene captioning         |
| Moondream2 (~1.8B)              | ~900 MB     | 2 GB       | (planned)                       | richer VLM at Pi 5 size                        |

Pi 5 8 GB happily runs the 1.5B models. A 256 MB i.MX6 with SmolLM2-135M
plus a sensible classical perception step is a complete agentic device.

## Tactical patterns

**Grammar-constrained JSON.** The single most impactful trick for tiny
models. Make the language layer's contract a strict JSON schema; pass it
to llama.cpp as a GBNF grammar. The model physically *cannot* emit
malformed output. Removes the entire class of "the LLM hallucinated a
field name" bugs.

**Tight system prompts + 1–2 few-shot examples.** Tiny models reward
discipline. A 200-token system prompt plus two worked examples turns a
135M model into a competent task-specific component.

**RAG over a small local corpus.** For field-service / docs / knowledge
demos: ship the manual or recent logs as a separate pvr object, embed
once at boot, retrieve by sentence-transformer (also tiny — `all-MiniLM-L6`
is ~90 MB). The LLM reasons over retrieved snippets, not its training
data.

**Composition, not capability stretch.** Never ask the tiny LLM to do
detection. Always pair it with the right classical detector and let the
LLM do language. This is the rule that makes the rest work.

**Cloud offload as a separate concern.** When you genuinely need
frontier-model capability for the hard 5% of queries, run
`pv-llama-router` (litellm) in front. The local container does not
change. Cloud creds live in signed pv-config. The decision of "local vs
cloud" is a router policy, not a container coupling.

## Roadmap

Near-term (already in the recipes tree or being added):

- [x] `pv-llama` multi-model serving with `llama-swap`
- [x] DeepSeek-R1 1.5B and Qwen2.5 0.5B model recipes
- [x] SmolLM2-135M and SmolLM2-360M model recipes
- [x] `agentic-app-skeleton` — generic agent-app harness with the
      reasoner-loop / tool-dispatch / schema-validation plumbing so
      product apps only have to ship a system prompt, a tools.json,
      and a Python module of tool implementations
      (see `recipes-containers/agentic/agentic-app-skeleton.inc` for the
      product contract; reference product in `agentic-example-log-triage`)
- [ ] SmolVLM-256M / Moondream2 vision-language model recipes
      (multimodal needs `llama.cpp`'s `llama-mtmd-cli` path —
      separate binary, separate `.mmproj-*` projector file alongside
      the GGUF; the model squashfs format will need a slot for the
      projector and the recipe a way to bundle two files)
- [ ] `pv-llama-router` (litellm) container for cloud offload, called
      *by the agent-app* via a routing-policy hook
- [ ] End-to-end "trail-cam journal" demo: feed → analyzer → agent-app
      (with prompt + tools) → action sink, in EXAMPLES.md
- [ ] Whisper.cpp container as the canonical STT building block
      (perception role for voice)
- [ ] Piper TTS container as the canonical TTS building block
      (action role for voice)

Longer-term:

- Standardised perception-event JSON schema across `agentic-*`
  containers, with a registry doc.
- Standardised tool-catalog format (`tools.json`) and a registry of
  reusable tools (MQTT publisher, Matter actuator, webhook, GPIO,
  e-mail, etc.) any agent-app can compose.
- Local sentence-transformer container for RAG, callable as a tool
  from any agent-app.
- Multi-agent / multi-app patterns: one device hosting several
  cooperating agent-apps (e.g. a doorbell agent that calls a
  face-recognition agent as a tool).
- Power-budget profiling per model size for battery-powered demos.
- A "starter image" with one camera container + agent-app skeleton +
  pv-llama + sensible defaults so a developer can flash a Pi 5 and
  have something working in 10 minutes.

## Where to read next

- [README.md](README.md) — the layer at a glance.
- [DEVELOPMENT.md](DEVELOPMENT.md) — building, iterating, deploying.
- [EXAMPLES.md](EXAMPLES.md) — xconnect example containers
  (unix / rest / dbus / drm / wayland).
- [recipes-containers/agentic/](recipes-containers/agentic/) — the
  agentic recipe tree this document describes.
- [recipes-ai/](recipes-ai/) — `llama-cpp`, `llama-swap`, model
  packaging.
