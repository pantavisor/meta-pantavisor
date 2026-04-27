"""
agentic-app runtime — top-level entrypoint.

Reads /etc/agentic-app/config.json plus the product files (system_prompt.md,
tools.json, tools.py), wires up an AgentLoop, subscribes to the configured
feeds, and publishes results to the action sink. Designed to be the single
binary every product agent-app runs as its container init.

config.json shape:

    {
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
DEFAULT_PROMPT = "/etc/agentic-app/system_prompt.md"
DEFAULT_TOOLS_JSON = "/etc/agentic-app/tools.json"
DEFAULT_TOOLS_PY = "/usr/lib/agentic-app/tools.py"


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
             feed_name: str):
    """Drain one feed forever. Each feed gets its own thread so a slow
    reasoner on one channel doesn't stall another."""
    log = logging.getLogger(f"agentic.feed.{feed_name}")
    for event in sub:
        log.info("event: %s", _short(event))
        result = loop.handle(event)
        result["_feed"] = feed_name
        result["_event"] = event
        publisher.publish(result)
        if "error" in result:
            log.warning("loop error: %s (after %d iter)",
                        result["error"], result.get("iterations", 0))
        else:
            log.info("done in %d iter: %s",
                     result.get("iterations", 0), _short(result.get("final")))


def _short(x, n=120):
    s = json.dumps(x) if not isinstance(x, str) else x
    return s if len(s) <= n else s[:n] + "…"


def main(argv=None):
    _setup_logging()
    log = logging.getLogger("agentic.runtime")

    cfg_path = os.environ.get("AGENTIC_APP_CONFIG", DEFAULT_CONFIG)
    cfg = json.loads(_read(cfg_path))

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

    threads = []
    for feed in cfg.get("feeds", []):
        sub = NDJSONSubscriber(feed["socket"], path=feed.get("path", "/subscribe"))
        name = feed.get("name") or feed["socket"]
        t = threading.Thread(
            target=_consume, args=(loop, sub, publisher, name), daemon=True
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
