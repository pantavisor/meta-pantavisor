#!/bin/bash
# Remove a git worktree.
#
# Usage: ./worktree-remove.sh <path> [git worktree remove args...]
#
# Everything after <path> is forwarded to `git worktree remove`, so pass
# `--force` if needed.

set -euo pipefail

[ $# -ge 1 ] || { echo "Usage: $0 <path> [git worktree remove args...]" >&2; exit 1; }
WT_PATH="$1"; shift

git worktree remove "$WT_PATH" "$@"
