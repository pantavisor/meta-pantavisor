SUMMARY = "SmolLM2-135M-Instruct GGUF packaged as a pv-llama model squashfs"

require pv-llama-model.inc

LLAMA_MODEL_NAME = "smollm2-135m"
LLAMA_MODEL_FAMILY = "smollm2"
LLAMA_MODEL_PARAMS = "135M"
LLAMA_MODEL_VERSION = "smollm2-135m-instruct-q4_k_m"
LLAMA_MODEL_DESC = "SmolLM2-135M-Instruct, Q4_K_M (~100 MB) — low-spec workhorse"

# bartowski's GGUF of HuggingFaceTB/SmolLM2-135M-Instruct. The official
# HF repo only ships fp16 / q8_0 today; bartowski publishes the full
# quantisation matrix.
LLAMA_MODEL_URL = "https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q4_K_M.gguf"
LLAMA_MODEL_SHA256 = "2e8040ceae7815abe0dcb3540b9995eaa1fa0d2ca9e797d0a635ae4433c68c2d"
