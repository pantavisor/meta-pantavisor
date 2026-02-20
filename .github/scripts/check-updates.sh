#!/bin/bash

# Fixed list of components and their branches as found in recipes
# Format: "component_name|recipe_glob|branch|repo_org"
COMPONENTS=(
    "busybox|recipes-pv/busybox/busybox*.bb|pv/1_35_stable|pantavisor"
    "dropbear|recipes-pv/dropbear/dropbear-pv*.bb|pv/master|pantacor"
    "libthttp|recipes-pv/libthttp/libthttp*.bb|master|pantavisor"
    "lxc-pv|recipes-pv/lxc-pv/lxc-pv*.bb|stable-3.0-BASE-2c5c780762981a5cfe699670c91397e29f6f6516|pantavisor"
    "lxc6-pv|recipes-pv/lxc6-pv/lxc6-pv*.bb|stable-6.0-BASE-f9ff9ea2a|pantavisor"
    "pantavisor|recipes-pv/pantavisor/pantavisor_git.bb|master|pantavisor"
    "picohttpparser|recipes-pv/picohttpparser/picohttpparser*.bb|pv/master|pantavisor"
)

for ENTRY in "${COMPONENTS[@]}"; do
    IFS="|" read -r COMPONENT RECIPE_GLOB BRANCH ORG <<< "$ENTRY"

    RECIPE=$(find . -path "./$RECIPE_GLOB" | head -n 1)
    if [ -z "$RECIPE" ]; then
        echo "Warning: Recipe for $COMPONENT not found ($RECIPE_GLOB)"
        continue
    fi

    echo "Checking $COMPONENT ($RECIPE)..."

    # Determine Repo URL
    # Handle both pantavisor and pantacor orgs
    REPO_NAME=$(grep -oP "github.com/$ORG/\K[^; ]+" "$RECIPE" | sed 's/\.git//' | head -n 1)
    FULL_URL="https://github.com/$ORG/$REPO_NAME"

    echo "  Repo: $FULL_URL"
    echo "  Branch: $BRANCH"

    # Get latest SHA from remote
    REMOTE_SHA=$(git ls-remote "$FULL_URL" "refs/heads/$BRANCH" | awk '{print $1}')

    if [ -z "$REMOTE_SHA" ]; then
        # Try without refs/heads/ in case it's a tag or a full ref
        REMOTE_SHA=$(git ls-remote "$FULL_URL" "$BRANCH" | awk '{print $1}')
    fi

    if [ -z "$REMOTE_SHA" ]; then
        echo "  Warning: Could not fetch remote SHA for branch '$BRANCH' at $FULL_URL"
        continue
    fi

    # Update SRCREV = "..." format
    if grep -q "SRCREV =" "$RECIPE"; then
        CURRENT_SRCREV=$(grep -oP 'SRCREV = "\K[^"]+' "$RECIPE")
        echo "  Current SRCREV: $CURRENT_SRCREV"
        if [ "$CURRENT_SRCREV" != "$REMOTE_SHA" ]; then
            echo "  UPDATE FOUND: $REMOTE_SHA"
            sed -i "s/SRCREV = \"$CURRENT_SRCREV\"/SRCREV = \"$REMOTE_SHA\"/" "$RECIPE"
        else
            echo "  Up to date."
        fi
    # Update rev=... format (like in lxc-pv)
    elif grep -q "rev=" "$RECIPE"; then
        CURRENT_REV=$(grep -oP 'rev=\K[^; "]+' "$RECIPE" | head -n 1)
        echo "  Current rev: $CURRENT_REV"
        if [ "$CURRENT_REV" != "$REMOTE_SHA" ]; then
            echo "  UPDATE FOUND: $REMOTE_SHA"
            sed -i "s/rev=$CURRENT_REV/rev=$REMOTE_SHA/" "$RECIPE"
        else
            echo "  Up to date."
        fi
    else
        echo "  Error: Could not find SRCREV or rev= in $RECIPE"
    fi
    echo ""
done
