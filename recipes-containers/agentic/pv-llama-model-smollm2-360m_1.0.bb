SUMMARY = "SmolLM2-360M-Instruct GGUF packaged as a pv-llama model squashfs"

require pv-llama-model.inc

LLAMA_MODEL_NAME = "smollm2-360m"
LLAMA_MODEL_FAMILY = "smollm2"
LLAMA_MODEL_PARAMS = "360M"
LLAMA_MODEL_VERSION = "smollm2-360m-instruct-q4_k_m"
LLAMA_MODEL_DESC = "SmolLM2-360M-Instruct, Q4_K_M (~260 MB) — mid-tier low-spec"

LLAMA_MODEL_URL = "https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q4_K_M.gguf"
LLAMA_MODEL_SHA256 = "2fa3f013dcdd7b99f9b237717fa0b12d75bbb89984cc1274be1471a465bac9c2"
