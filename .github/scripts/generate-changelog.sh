#!/bin/bash

# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT


# Fetch tags if not available (in CI usually needed)
git fetch --tags --force 2>/dev/null || true

CURRENT_TAG=$1

if [ -z "$CURRENT_TAG" ]; then
    CURRENT_TAG=$(git describe --tags --exact-match 2>/dev/null || echo "HEAD")
fi

# Find previous tag
# We can use git describe to find the closest tag reachable from HEAD^
# If CURRENT_TAG is a tag object, HEAD might be detached at that tag.
PREV_TAG=$(git describe --tags --abbrev=0 "$CURRENT_TAG^" 2>/dev/null)

echo "## Changelog ($CURRENT_TAG)"
echo ""

if [ -z "$PREV_TAG" ]; then
    echo "Initial release."
else
    echo "Changes since $PREV_TAG:"
    echo ""
    git log --no-merges --pretty=format:"* %h %s" "$PREV_TAG..$CURRENT_TAG"
fi
echo ""
