"""
The agent reasoner loop.

For each incoming event we:

  1. Render the event into a user-message turn (string).
  2. Call the LLM with system prompt + history + the event message,
     constrained by a GBNF grammar that forces the output to be either a
     {"tool":..., "args":...} call or a {"final":"<text>"} answer.
  3. If it's a tool call, dispatch it via the catalog, append the result
     as a tool message, loop back to step 2.
  4. If it's a final answer, emit it to the action sink and stop.

We bound the iterations per event so a confused model can't burn a model
slot indefinitely (`max_iterations`, default 6). Each iteration is one
chat call; a small model on a Pi 5 takes ~2 s per turn, so 6 iterations
caps the per-event wall time at ~12 s of reasoner work.
"""

import json
import logging

log = logging.getLogger("agentic.loop")


class AgentLoop:
    def __init__(
        self,
        *,
        llm,
        catalog,
        dispatcher,
        system_prompt: str,
        model: str,
        grammar: str,
        max_iterations: int = 6,
    ):
        self._llm = llm
        self._catalog = catalog
        self._dispatcher = dispatcher
        self._system_prompt = system_prompt
        self._model = model
        self._grammar = grammar
        self._max_iter = max_iterations

    def handle(self, event: dict) -> dict:
        """Run the loop for one event. Returns a dict with shape:

            {"final": str, "iterations": int, "tool_calls": [...]}
              on a clean finish, or
            {"error": str, "iterations": int, "tool_calls": [...]}
              if the loop hits max_iterations / a parse error / etc.
        """
        history = [
            {"role": "system", "content": self._system_prompt},
            {"role": "user", "content": _event_to_user_msg(event)},
        ]
        tool_calls = []

        for i in range(1, self._max_iter + 1):
            try:
                resp = self._llm.chat(
                    history,
                    model=self._model,
                    grammar=self._grammar,
                )
            except Exception as e:  # noqa: BLE001
                return {"error": f"llm: {e}", "iterations": i,
                        "tool_calls": tool_calls}

            content = _extract_content(resp)
            if content is None:
                return {"error": "no content in llm response",
                        "iterations": i, "tool_calls": tool_calls}

            try:
                obj = json.loads(content)
            except json.JSONDecodeError:
                # Grammar should prevent this; treat as a final-fallback so
                # the agent at least surfaces something rather than looping.
                return {"final": content, "iterations": i,
                        "tool_calls": tool_calls,
                        "warning": "model output was not valid JSON"}

            if "final" in obj:
                return {"final": obj["final"], "iterations": i,
                        "tool_calls": tool_calls}

            if "tool" in obj:
                name = obj["tool"]
                args = obj.get("args") or {}
                log.info("iter=%d tool=%s args=%s", i, name, args)
                result = self._dispatcher.call(name, args)
                tool_calls.append({"tool": name, "args": args, "result": result})
                # Append the assistant's tool call and the tool result to
                # history so the model sees its own action and the outcome
                # before deciding what to do next.
                history.append({"role": "assistant", "content": content})
                history.append(
                    {"role": "user",
                     "content": "tool_result: " + json.dumps(result)}
                )
                continue

            return {"error": "model returned neither tool nor final",
                    "raw": obj, "iterations": i, "tool_calls": tool_calls}

        return {"error": f"max_iterations ({self._max_iter}) exceeded",
                "iterations": self._max_iter, "tool_calls": tool_calls}


def _event_to_user_msg(event: dict) -> str:
    """How an incoming feed event is rendered as the user-turn message.

    We dump it as compact JSON. Agent-app system prompts are expected to
    explain what fields they expect — that's a product-side concern, not
    a skeleton concern."""
    return "event: " + json.dumps(event, separators=(",", ":"))


def _extract_content(resp: dict):
    """Pull the assistant message text out of an OpenAI-format response."""
    try:
        return resp["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        return None
