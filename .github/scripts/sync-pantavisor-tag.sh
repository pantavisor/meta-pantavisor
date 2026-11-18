#!/bin/bash
#
# Push the meta-pantavisor tag to the upstream pantavisor repo at the SRCREV
# pinned in recipes-pv/pantavisor/pantavisor.inc (PANTAVISOR_SRCREV).
#
# Inputs (env):
#   TAG_NAME  meta-pantavisor tag name (e.g. 030-rc1)
#   GH_TOKEN  PAT with `repo` scope on github.com/pantavisor/pantavisor
#
# RC tags (0NN-rcN) point straight at SRCREV.
#
# Stable tags (0NN) point at a finalize commit instead: pantavisor's
# changelog-gate requires the tagged commit to carry CHANGELOG/CHANGELOG-0NN.md,
# so the script clones upstream at SRCREV, runs
# `.github/scripts/make-changelog.sh --finalize 0NN` (which commits only that
# file), and pushes the resulting commit as the tag. The commit is a direct
# child of SRCREV that adds one file, so the built source is unchanged. Nothing
# is pushed to a branch, so branch protection on master is not involved. Run it
# after every RC's tag-changelogs workflow has finished, so the S3 accumulator
# holds all RC sections.
#
# Idempotent: re-running on a tag that already points at the matching SHA (for a
# stable tag: SRCREV or its finalize child) is a no-op. Aborts (non-zero) if the
# upstream tag exists at a different SHA.

set -euo pipefail

RECIPE="recipes-pv/pantavisor/pantavisor.inc"
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

STABLE=0
if [[ "$TAG_NAME" =~ ^0[0-9]+$ ]]; then
    STABLE=1
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
# Use the singular git/ref endpoint: it matches the tag exactly (or 404s).
# The plural git/refs endpoint does prefix matching and would return a JSON
# array for "028" once 028-rc* tags exist, breaking the .object.sha lookup.
if EXISTING_REF=$(gh api "repos/$UPSTREAM/git/ref/tags/$TAG_NAME" 2>/dev/null); then
    EXISTING_SHA=$(echo "$EXISTING_REF" | jq -r '.object.sha // empty')
fi

UPSTREAM_TAG_URL="https://github.com/$UPSTREAM/releases/tag/$TAG_NAME"

# A stable tag is in sync when it is SRCREV itself or the finalize commit
# directly on top of it.
IN_SYNC=0
if [ -n "$EXISTING_SHA" ]; then
    if [ "$EXISTING_SHA" = "$SRCREV" ]; then
        IN_SYNC=1
    elif [ "$STABLE" -eq 1 ]; then
        PARENT_SHA=$(gh api "repos/$UPSTREAM/commits/$EXISTING_SHA" --jq '.parents[0].sha // empty' 2>/dev/null || true)
        [ "$PARENT_SHA" = "$SRCREV" ] && IN_SYNC=1
    fi
fi

if [ -n "$EXISTING_SHA" ]; then
    if [ "$IN_SYNC" -eq 1 ]; then
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
    if [ "$STABLE" -eq 1 ]; then
        WORKDIR=$(mktemp -d)
        trap 'rm -rf "$WORKDIR"' EXIT
        git -c credential.helper='!gh auth git-credential' \
            clone --quiet "https://github.com/$UPSTREAM.git" "$WORKDIR/pantavisor"
        cd "$WORKDIR/pantavisor"
        git checkout --quiet --detach "$SRCREV"
        export GIT_AUTHOR_NAME="github-actions[bot]" GIT_COMMITTER_NAME="github-actions[bot]"
        export GIT_AUTHOR_EMAIL="github-actions[bot]@users.noreply.github.com"
        export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
        ./.github/scripts/make-changelog.sh --finalize "$TAG_NAME"
        TAG_SHA=$(git rev-parse HEAD)
        echo "  Finalize commit: $TAG_SHA (on top of $SRCREV)"
        git -c credential.helper='!gh auth git-credential' \
            push --quiet origin "$TAG_SHA:refs/tags/$TAG_NAME"
        cd - >/dev/null
    else
        gh api -X POST "repos/$UPSTREAM/git/refs" \
            -f "ref=refs/tags/$TAG_NAME" \
            -f "sha=$SRCREV" \
            --silent
    fi
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
