#!/bin/bash
# Add a git worktree and link its build/sstate-cache + build/downloads
# back to the main repo's caches with relative symlinks.
#
# Usage: ./worktree-create.sh <path> [git worktree add args...]
#
# Everything after <path> is forwarded to `git worktree add`, so:
#     ./worktree-create.sh ../wt-foo feature/foo
#     ./worktree-create.sh ../wt-foo -b feature/foo origin/main
#     ./worktree-create.sh ../wt-foo --detach HEAD~3
#
# Re-running on an existing worktree path just refreshes the symlinks.

set -euo pipefail

[ $# -ge 1 ] || { echo "Usage: $0 <path> [git worktree add args...]" >&2; exit 1; }
WT_PATH="$1"; shift

# Find the main repo (works whether invoked from the main checkout or a worktree).
MAIN_REPO="$(cd "$(dirname "$(git rev-parse --git-common-dir)")" && pwd)"

[ -d "$WT_PATH" ] || git worktree add "$WT_PATH" "$@"

WT_PATH="$(cd "$WT_PATH" && pwd)"
mkdir -p "$WT_PATH/build" "$MAIN_REPO/build/sstate-cache" "$MAIN_REPO/build/downloads"
REL="$(realpath --relative-to="$WT_PATH/build" "$MAIN_REPO/build")"

for name in sstate-cache downloads; do
    link="$WT_PATH/build/$name"
    want="$REL/$name"
    [ -L "$link" ] && [ "$(readlink "$link")" = "$want" ] && continue
    rm -f "$link"
    ln -s "$want" "$link"
    echo "linked: build/$name -> $want"
done
