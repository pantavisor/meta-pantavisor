#!/bin/bash
#
# Push the meta-pantavisor tag to the upstream pantavisor repo at the SRCREV
# pinned in recipes-pv/pantavisor/pantavisor_git.bb.
#
# Inputs (env):
#   TAG_NAME  meta-pantavisor tag name (e.g. 030-rc1)
#   GH_TOKEN  PAT with `repo` scope on github.com/pantavisor/pantavisor
#
# Idempotent: re-running on a tag that already points at the matching SHA is a
# no-op. Aborts (non-zero) if the upstream tag exists at a different SHA.

set -euo pipefail

RECIPE="recipes-pv/pantavisor/pantavisor_git.bb"
UPSTREAM="pantavisor/pantavisor"

if [ -z "${TAG_NAME:-}" ]; then
    echo "ERROR: TAG_NAME is not set" >&2
    exit 1
fi

if [ -z "${GH_TOKEN:-}" ]; then
    echo "ERROR: GH_TOKEN is not set" >&2
    exit 1
fi

if [ ! -f "$RECIPE" ]; then
    echo "ERROR: recipe not found: $RECIPE" >&2
    exit 1
fi

SRCREV=$(grep -oP 'SRCREV = "\K[^"]+' "$RECIPE" | head -n 1)
if [ -z "$SRCREV" ]; then
    echo "ERROR: could not parse SRCREV from $RECIPE" >&2
    exit 1
fi

echo "Tag:    $TAG_NAME"
echo "Recipe: $RECIPE"
echo "SRCREV: $SRCREV"
echo "Target: github.com/$UPSTREAM"
echo ""

echo "Verifying SRCREV exists upstream..."
if ! gh api "repos/$UPSTREAM/commits/$SRCREV" --silent 2>/dev/null; then
    echo "ERROR: SRCREV $SRCREV not reachable at github.com/$UPSTREAM." >&2
    echo "       The recipe is pinned to a commit that was never pushed upstream." >&2
    exit 1
fi
echo "  OK"
echo ""

echo "Checking for existing tag $TAG_NAME on $UPSTREAM..."
EXISTING_SHA=""
if EXISTING_REF=$(gh api "repos/$UPSTREAM/git/refs/tags/$TAG_NAME" 2>/dev/null); then
    EXISTING_SHA=$(echo "$EXISTING_REF" | jq -r '.object.sha')
fi

UPSTREAM_TAG_URL="https://github.com/$UPSTREAM/releases/tag/$TAG_NAME"

if [ -n "$EXISTING_SHA" ]; then
    if [ "$EXISTING_SHA" = "$SRCREV" ]; then
        echo "  Tag already in sync at $SRCREV. Nothing to do."
        RESULT="already in sync"
    else
        echo "ERROR: tag $TAG_NAME already exists on $UPSTREAM at $EXISTING_SHA" >&2
        echo "       expected SRCREV is $SRCREV (from $RECIPE)" >&2
        echo "       see $UPSTREAM_TAG_URL" >&2
        echo "       refusing to overwrite — resolve manually." >&2
        if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
            {
                echo "## Tag sync → pantavisor"
                echo ""
                echo "| Tag | SRCREV (recipe) | Existing upstream SHA | Result |"
                echo "| :-- | :-- | :-- | :-- |"
                echo "| \`$TAG_NAME\` | \`$SRCREV\` | \`$EXISTING_SHA\` | ❌ conflict |"
                echo ""
                echo "Existing upstream tag: $UPSTREAM_TAG_URL"
            } >> "$GITHUB_STEP_SUMMARY"
        fi
        exit 1
    fi
else
    echo "  Tag not present. Creating..."
    gh api -X POST "repos/$UPSTREAM/git/refs" \
        -f "ref=refs/tags/$TAG_NAME" \
        -f "sha=$SRCREV" \
        --silent
    echo "  Created."
    RESULT="created"
fi

echo ""
echo "Done. Upstream tag: $UPSTREAM_TAG_URL"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "## Tag sync → pantavisor"
        echo ""
        echo "| Tag | SRCREV | Upstream | Result |"
        echo "| :-- | :-- | :-- | :-- |"
        echo "| \`$TAG_NAME\` | \`$SRCREV\` | [$UPSTREAM]($UPSTREAM_TAG_URL) | ✅ $RESULT |"
    } >> "$GITHUB_STEP_SUMMARY"
fi
