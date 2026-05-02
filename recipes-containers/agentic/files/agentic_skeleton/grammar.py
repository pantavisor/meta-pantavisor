"""
GBNF grammar generation for tool-call constrained generation.

Tiny LLMs (135M–1.5B) don't reliably follow native OpenAI tool-call
formats — they ramble, emit pseudo-JSON, or invent fields. Grammar-
constrained generation eliminates the failure mode entirely: the model
samples only tokens that produce a syntactically valid tool call (or
plain final-answer text).

Output shape we constrain to is a single JSON object on one line:

    {"tool":"<one-of-names>","args":{<schema>}}
or
    {"final":"<free text>"}

The agent loop then dispatches on the top-level key.

We deliberately keep the grammar permissive about *string contents* — full
JSON-string escapes are expensive in GBNF — and rely on Python's json.loads
+ the catalog validator to catch malformed args. The grammar's job is to
keep the model on the rails (always a JSON object, always a known tool
name); it does not need to be a complete JSON schema.
"""


def build_grammar(catalog) -> str:
    """Return a GBNF grammar string suitable for llama.cpp's --grammar /
    `grammar` field in the chat completions request. The catalog's tool
    names are baked in as alternatives so the model literally cannot emit
    an unknown tool name."""
    names = catalog.names()
    if not names:
        raise ValueError("cannot build grammar: catalog is empty")

    # GBNF alt list: "name1" | "name2" | ...
    name_alts = " | ".join(f'"\\"{n}\\""' for n in names)

    return r"""
root        ::= tool-call | final-answer
tool-call   ::= "{" ws "\"tool\"" ws ":" ws (""" + name_alts + r""") ws "," ws "\"args\"" ws ":" ws object ws "}"
final-answer ::= "{" ws "\"final\"" ws ":" ws string ws "}"

# JSON value subset — strings, numbers, booleans, null, arrays, objects.
value   ::= string | number | "true" | "false" | "null" | array | object
object  ::= "{" ws (kv ("," ws kv)*)? ws "}"
kv      ::= string ws ":" ws value
array   ::= "[" ws (value ("," ws value)*)? ws "]"

# Permissive string: any char except unescaped quote/backslash, plus simple
# escape passthrough. Catalog validator catches semantic issues.
string  ::= "\"" ([^"\\] | "\\" ["\\/bfnrt])* "\""
number  ::= "-"? ("0" | [1-9] [0-9]*) ("." [0-9]+)? ([eE] [-+]? [0-9]+)?
ws      ::= [ \t\n]*
"""
