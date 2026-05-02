"""
agentic_skeleton — generic agent-app harness for Pantavisor.

A product agent-app provides:

  /etc/agentic-app/config.json       runtime configuration (feeds, sink, llm)
  /etc/agentic-app/system_prompt.md  the persona / task / constraints
  /etc/agentic-app/tools.json        OpenAI-style tool catalog (JSON schemas)
  /usr/lib/agentic-app/tools.py      Python module with one callable per tool

The runtime loads these, subscribes to the configured xconnect feeds,
runs the reasoner loop (call llm -> validate tool call -> dispatch -> repeat
until final answer), and publishes results to the action sink.

Everything else (HTTP-over-UDS to pv-llama, JSON-schema validation,
grammar-constrained generation, retry, logging) lives in this package.
"""

__version__ = "1.0.0"
