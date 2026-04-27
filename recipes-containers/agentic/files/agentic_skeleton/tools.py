"""
Tool catalog + dispatcher.

The catalog is OpenAI tools format (a list of objects with type=function and
a JSON-schema parameters block). Products ship it as tools.json. The harness
loads it once, derives a GBNF grammar from it (so the model can be forced to
emit a valid call even when it has no native tool-use training), and wires
each entry to a Python callable in the product's tools.py module.

Tool implementations are *just functions*. By convention the harness expects:

    def tool_<name>(args: dict) -> dict | str

so a `notify` tool in tools.json becomes `tool_notify` in tools.py. We map
underscores↔hyphens transparently because tool names are often hyphenated in
catalogs but Python identifiers can't be.
"""

import importlib.util
import json
import re
from pathlib import Path


class ToolCatalog:
    """OpenAI tools catalog loader + minimal validator.

    We don't pull in jsonschema (extra dep, ~200 KB on a tiny image). We
    enforce only the constraints the model can actually be coerced into via
    grammar: required keys present, no unexpected keys, types are
    string/number/boolean/object/array. That's enough for the
    agent-app-skeleton contract; products that need tighter validation can
    do their own check inside the tool implementation.
    """

    def __init__(self, path):
        with open(path) as f:
            data = json.load(f)
        if not isinstance(data, list):
            raise ValueError(f"{path}: expected top-level JSON array of tools")
        self._tools = data
        self._by_name = {}
        for t in data:
            if t.get("type") != "function":
                raise ValueError(f"only type=function tools supported: {t!r}")
            fn = t.get("function") or {}
            name = fn.get("name")
            if not name:
                raise ValueError(f"tool missing function.name: {t!r}")
            if name in self._by_name:
                raise ValueError(f"duplicate tool name: {name}")
            self._by_name[name] = fn

    def names(self):
        return list(self._by_name.keys())

    def schemas(self):
        """Return the catalog in the OpenAI tools wire format (for the
        `tools` parameter of chat completions)."""
        return self._tools

    def validate(self, name, args):
        """Validate a tool call's args against the catalog schema. Returns
        the args dict on success, raises ValueError otherwise."""
        if name not in self._by_name:
            raise ValueError(f"unknown tool: {name}")
        params = self._by_name[name].get("parameters") or {}
        if not isinstance(args, dict):
            raise ValueError(f"tool {name}: args must be an object")
        required = params.get("required") or []
        for r in required:
            if r not in args:
                raise ValueError(f"tool {name}: missing required arg {r!r}")
        props = params.get("properties") or {}
        # Reject unexpected keys — tiny models love to invent fields.
        for k in args:
            if k not in props:
                raise ValueError(f"tool {name}: unexpected arg {k!r}")
            self._check_type(name, k, args[k], props[k].get("type"))
        return args

    @staticmethod
    def _check_type(tool, key, value, expected):
        if expected is None:
            return
        ok = {
            "string": isinstance(value, str),
            "number": isinstance(value, (int, float)) and not isinstance(value, bool),
            "integer": isinstance(value, int) and not isinstance(value, bool),
            "boolean": isinstance(value, bool),
            "object": isinstance(value, dict),
            "array": isinstance(value, list),
        }.get(expected, True)
        if not ok:
            raise ValueError(
                f"tool {tool}: arg {key!r} expected {expected}, got {type(value).__name__}"
            )


class ToolDispatcher:
    """Bind catalog entries to Python implementations and run them.

    The product ships /usr/lib/agentic-app/tools.py with `tool_<name>(args)`
    callables. We import that module once, look up each tool, and remember
    the callable. A missing implementation is a hard error at construction —
    we'd rather fail fast than ship a product whose model can call a tool
    nobody implemented.
    """

    _ID_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

    def __init__(self, catalog: ToolCatalog, tools_py_path):
        self._catalog = catalog
        self._impls = {}

        spec = importlib.util.spec_from_file_location(
            "agentic_app_tools", tools_py_path
        )
        if not spec or not spec.loader:
            raise RuntimeError(f"cannot load tools module from {tools_py_path}")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)

        for name in catalog.names():
            ident = name.replace("-", "_")
            if not self._ID_RE.match(ident):
                raise ValueError(f"tool name not a valid Python ident: {name}")
            fn = getattr(mod, f"tool_{ident}", None)
            if fn is None or not callable(fn):
                raise RuntimeError(
                    f"tools.py is missing tool_{ident}() for catalog entry {name!r}"
                )
            self._impls[name] = fn

    def call(self, name, args):
        """Validate and dispatch. Returns whatever the tool returns; errors
        are converted to a {"error": str} dict so the agent loop can feed
        them back to the model as a tool result rather than crashing."""
        try:
            args = self._catalog.validate(name, args or {})
            result = self._impls[name](args)
            # Normalize to something JSON-serialisable for the loop.
            if result is None:
                return {"ok": True}
            if isinstance(result, str):
                return {"ok": True, "text": result}
            return result
        except Exception as e:  # noqa: BLE001 — caught for the model's benefit
            return {"error": f"{type(e).__name__}: {e}"}
