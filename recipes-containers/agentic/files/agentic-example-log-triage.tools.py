"""
Tool implementations for agentic-example-log-triage.

Just one tool: `classify`. It records the verdict and returns it back to the
loop unchanged so the model sees its own decision in the next turn before
emitting `{"final": ...}`. The recorded verdict is also what the action
sink publishes (the loop captures every tool call in its result dict, so
downstream consumers don't have to parse the final-answer text — they
read the structured `tool_calls[-1].args`).
"""

from typing import Any


def tool_classify(args: dict) -> dict[str, Any]:
    severity = (args.get("severity") or "ignore").lower()
    if severity not in ("critical", "warn", "info", "ignore"):
        return {"error": f"unknown severity {severity!r}"}
    return {
        "severity": severity,
        "notify": bool(args.get("notify")),
        "reason": (args.get("reason") or "")[:120],
    }
