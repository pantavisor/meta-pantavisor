"""
agentic-app runtime — top-level entrypoint.

Reads the layered runtime config plus the product files (system_prompt.md,
tools.json, tools.py), wires up an AgentLoop, subscribes to the configured
feeds, and publishes results to the action sink. Designed to be the single
binary every product agent-app runs as its container init.

Layered config:

    /etc/agentic-app/defaults.json     mesh-constant defaults shipped by
                                       the agentic-app-skeleton package
    /etc/agentic-app/config.json       per-app overrides (optional)

defaults.json provides sensible values for the LLM UDS, model, timeout,
iteration cap, and sink socket. Per-app config.json only needs to declare
what differs (typically `feeds` and an app-specific `app_name`/`sink`).
The two are deep-merged dict-by-dict; lists (e.g. `feeds`) are replaced
wholesale by the overlay.

config.json shape (any subset of):

    {
      "app_name": "agentic-example-log-triage",
      "model":  "local-qwen",                   // llama-swap model id
      "llm":    {"uds":"/run/pv/services/pv-llama.sock"},
      "feeds":  [{"socket":"/run/pv/services/log-feed.sock",
                  "path":"/subscribe"}],
      "sink":   {"socket":"/run/agentic-app/out.sock"},
      "max_iterations": 6
    }
"""

import json
import logging
import os
import sys
import threading
import time

from .feed import NDJSONPublisher, NDJSONSubscriber
from .grammar import build_grammar
from .llm import LlamaClient
from .loop import AgentLoop
from .tools import ToolCatalog, ToolDispatcher

DEFAULT_CONFIG = "/etc/agentic-app/config.json"
DEFAULT_DEFAULTS = "/etc/agentic-app/defaults.json"
DEFAULT_PROMPT = "/etc/agentic-app/system_prompt.md"
DEFAULT_TOOLS_JSON = "/etc/agentic-app/tools.json"
DEFAULT_TOOLS_PY = "/usr/lib/agentic-app/tools.py"


def _deep_merge(base, overlay):
    """Recursively merge overlay into base, returning a new dict.

    Dicts are merged key by key; non-dict values (including lists) are
    replaced wholesale by the overlay. Lists are intentionally not
    concatenated — feeds/sinks are per-app declarations, not extensions
    of a shared default.
    """
    if not isinstance(base, dict) or not isinstance(overlay, dict):
        return overlay
    out = dict(base)
    for k, v in overlay.items():
        if k in out and isinstance(out[k], dict) and isinstance(v, dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = v
    return out


def _load_layered_config(defaults_path, config_path):
    """Load defaults + per-app config and deep-merge.

    Either file may be missing. The skeleton ships
    /etc/agentic-app/defaults.json with mesh-constant defaults (LLM UDS,
    timeout, max_iterations, default sink), so apps only need to declare
    feeds and any per-app overrides in their own config.json.
    """
    cfg = {}
    if defaults_path and os.path.exists(defaults_path):
        cfg = json.loads(_read(defaults_path))
    if config_path and os.path.exists(config_path):
        cfg = _deep_merge(cfg, json.loads(_read(config_path)))
    return cfg


def _setup_logging():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
        stream=sys.stderr,
    )


def _read(path):
    with open(path) as f:
        return f.read()


def _consume(loop: AgentLoop, sub: NDJSONSubscriber, publisher: NDJSONPublisher,
             feed_name: str, app_name: str):
    """Drain one feed forever. Each feed gets its own thread so a slow
    reasoner on one channel doesn't stall another.

    Two guards:
      1. Skip events whose source_file refers to this agent's own console
         log. log-feed-style providers tail every container's console; if
         they include ours, our own stderr would cause an infinite recursion
         (each log line generates a new event which triggers another log
         line). Without this filter the device sees thousands of
         events/sec within ms of startup.
      2. Backoff when the loop returns an LLM-unreachable error. Otherwise
         the agent burns CPU spinning on every event during the
         xconnect-wiring race window or whenever pv-llama is restarting.
    """
    log = logging.getLogger(f"agentic.feed.{feed_name}")
    self_marker = f"/{app_name}/lxc/console.log"
    consecutive_llm_errors = 0
    for event in sub:
        # (1) self-recursion guard
        src = ""
        if isinstance(event, dict):
            src = str(event.get("source_file") or event.get("source") or "")
        if self_marker in src:
            continue
        # Pull a short input descriptor for the log line so a human
        # operator can correlate the verdict with what triggered it.
        # Most feeds put a short string in `match`/`message`/`line`;
        # fall back to a single-line summary of the whole event.
        input_descr = _event_descr(event)
        result = loop.handle(event)
        result["_feed"] = feed_name
        result["_event"] = event
        publisher.publish(result)
        err = result.get("error", "")
        if err:
            if "unreachable" in err or "ConnectionError" in err:
                # (2) backoff on LLM unreachable. Caps at ~2 s so when
                # xconnect finishes wiring, we resume promptly without
                # having dropped much.
                consecutive_llm_errors = min(consecutive_llm_errors + 1, 8)
                if consecutive_llm_errors == 1:
                    log.warning("llm unreachable, backing off")
                time.sleep(min(0.25 * consecutive_llm_errors, 2.0))
            else:
                log.warning("loop error: %s | event=%s (after %d iter)",
                            err, _short(input_descr, 80),
                            result.get("iterations", 0))
                consecutive_llm_errors = 0
        else:
            if consecutive_llm_errors:
                log.info("llm reachable again")
            consecutive_llm_errors = 0
            verdict = _verdict_descr(result)
            # One-line "EVENT → VERDICT" so the operator can scan the
            # log and see input/output side by side without staring at
            # truncated prose.
            log.info("[i=%d] %s  →  %s",
                     result.get("iterations", 0),
                     _short(input_descr, 80),
                     _short(verdict, 200))


def _event_descr(event):
    """Pick the most useful one-line input descriptor for an event.
    Most feeds use `match` (regex match), `message` (rendered text),
    or `line` (raw log line); we prefer those over the full JSON dump.
    """
    if not isinstance(event, dict):
        return str(event)
    for key in ("match", "message", "line", "msg", "text"):
        v = event.get(key)
        if isinstance(v, str) and v:
            return v
    # Fall back to a compact JSON dump with the noisiest keys stripped.
    pruned = {
        k: v for k, v in event.items()
        if k not in ("pre_context", "post_context", "ts", "event_id",
                     "source_file", "source")
    }
    return json.dumps(pruned, separators=(",", ":"))


def _verdict_descr(result):
    """Prefer a tool-call verdict (e.g. classify(severity, notify,
    reason)) over the model's free-text final answer. Tool calls are
    structured by design; final-answer prose is whatever the model
    chose to say. If both are present, show severity[notify] reason —
    that matches the schema the agent-app is supposed to enforce.
    """
    tool_calls = result.get("tool_calls") or []
    if tool_calls:
        last = tool_calls[-1]
        args = last.get("args") or {}
        if {"severity", "notify"} <= set(args):
            sev = args.get("severity", "?")
            notif = "!" if args.get("notify") else "."
            reason = args.get("reason") or ""
            return f"{sev}{notif} {reason}"
        return f"{last.get('tool')}({json.dumps(args, separators=(',', ':'))})"
    final = result.get("final")
    if final is not None:
        return final
    return ""


def _short(x, n=120):
    s = json.dumps(x) if not isinstance(x, str) else x
    s = s.replace("\n", " ")
    return s if len(s) <= n else s[:n] + "…"


def main(argv=None):
    _setup_logging()
    log = logging.getLogger("agentic.runtime")

    defaults_path = os.environ.get("AGENTIC_APP_DEFAULTS", DEFAULT_DEFAULTS)
    cfg_path = os.environ.get("AGENTIC_APP_CONFIG", DEFAULT_CONFIG)
    cfg = _load_layered_config(defaults_path, cfg_path)

    prompt = _read(os.environ.get("AGENTIC_APP_PROMPT", DEFAULT_PROMPT))
    catalog = ToolCatalog(
        os.environ.get("AGENTIC_APP_TOOLS_JSON", DEFAULT_TOOLS_JSON)
    )
    dispatcher = ToolDispatcher(
        catalog,
        os.environ.get("AGENTIC_APP_TOOLS_PY", DEFAULT_TOOLS_PY),
    )

    llm = LlamaClient(
        uds=cfg["llm"].get("uds"),
        url=cfg["llm"].get("url"),
        timeout=cfg.get("llm_timeout", 120),
    )

    loop = AgentLoop(
        llm=llm,
        catalog=catalog,
        dispatcher=dispatcher,
        system_prompt=prompt,
        model=cfg["model"],
        grammar=build_grammar(catalog),
        max_iterations=cfg.get("max_iterations", 6),
    )

    publisher = NDJSONPublisher(cfg["sink"]["socket"])
    publisher.start()
    log.info("publishing on %s", cfg["sink"]["socket"])

    # Self-recursion guard needs the agent's own platform name so it can
    # skip events whose source_file is its own console log. Read from
    # config (preferred) or fall back to AGENTIC_APP_NAME env / hostname.
    app_name = (
        cfg.get("app_name")
        or os.environ.get("AGENTIC_APP_NAME")
        or os.uname().nodename
        or "agentic-app"
    )

    threads = []
    for feed in cfg.get("feeds", []):
        sub = NDJSONSubscriber(feed["socket"], path=feed.get("path", "/subscribe"))
        name = feed.get("name") or feed["socket"]
        t = threading.Thread(
            target=_consume, args=(loop, sub, publisher, name, app_name),
            daemon=True,
        )
        t.start()
        threads.append(t)
        log.info("subscribed to feed %s (%s)", name, feed["socket"])

    if not threads:
        log.warning("no feeds configured — agent-app will idle")

    # Block forever; the daemon threads keep working. SIGTERM from LXC will
    # tear us down cleanly because every worker thread is a daemon.
    while True:
        time.sleep(60)


if __name__ == "__main__":
    main()
