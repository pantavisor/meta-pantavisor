SUMMARY = "Qwen2.5-0.5B-Instruct GGUF packaged as a pv-llama model squashfs"

require pv-llama-model.inc

LLAMA_MODEL_NAME = "qwen"
LLAMA_MODEL_FAMILY = "qwen2.5"
LLAMA_MODEL_PARAMS = "0.5B"
LLAMA_MODEL_VERSION = "qwen2.5-0.5b-instruct-q4_k_m"
LLAMA_MODEL_DESC = "Qwen2.5-0.5B-Instruct, Q4_K_M (~470 MB)"

LLAMA_MODEL_URL = "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"
LLAMA_MODEL_SHA256 = "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db"
