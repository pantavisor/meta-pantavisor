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

ORIG_PWD=$PWD
# Use path from environment or fallback to a temp location
COMMIT_MSG_FILE="${COMMIT_MSG_FILE:-/tmp/updates-commit-msg}"
echo "recipes-pv: automated srcrev update" > "$COMMIT_MSG_FILE"
echo "" >> "$COMMIT_MSG_FILE"

UPDATES_FOUND=0

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
    CURRENT_SRCREV=""
    if grep -q "SRCREV =" "$RECIPE"; then
        CURRENT_SRCREV=$(grep -oP 'SRCREV = "\K[^"]+' "$RECIPE")
    # Update rev=... format (like in lxc-pv)
    elif grep -q "rev=" "$RECIPE"; then
        CURRENT_SRCREV=$(grep -oP 'rev=\K[^; "]+' "$RECIPE" | head -n 1)
    fi

    if [ -n "$CURRENT_SRCREV" ]; then
        echo "  Current SRCREV: $CURRENT_SRCREV"
        if [ "$CURRENT_SRCREV" != "$REMOTE_SHA" ]; then
            echo "  UPDATE FOUND: $REMOTE_SHA"
            if grep -q "SRCREV =" "$RECIPE"; then
                sed -i "s/SRCREV = \"$CURRENT_SRCREV\"/SRCREV = \"$REMOTE_SHA\"/" "$RECIPE"
            else
                sed -i "s/rev=$CURRENT_SRCREV/rev=$REMOTE_SHA/" "$RECIPE"
            fi
            
            # Generate log for commit message
            echo "Updating $COMPONENT in $RECIPE:" >> "$COMMIT_MSG_FILE"
            echo "  $CURRENT_SRCREV -> $REMOTE_SHA" >> "$COMMIT_MSG_FILE"
            
            TEMP_DIR=$(mktemp -d)
            (
                cd "$TEMP_DIR"
                git init -q
                git remote add origin "$FULL_URL"
                # Fetch only the necessary commits to save time/bandwidth
                # Use --no-tags and -n to speed up
                git fetch -q --depth=50 origin "$REMOTE_SHA" 2>/dev/null
                # Try to fetch the old commit as well
                git fetch -q --depth=50 origin "$CURRENT_SRCREV" 2>/dev/null || true
                
                # Check if we can actually see both commits to generate a log
                if git rev-parse "$CURRENT_SRCREV" >/dev/null 2>&1 && git rev-parse "$REMOTE_SHA" >/dev/null 2>&1; then
                    git log --oneline "$CURRENT_SRCREV..$REMOTE_SHA" | sed 's/^/    * /' >> "$COMMIT_MSG_FILE"
                else
                    echo "    * (could not fetch detailed logs)" >> "$COMMIT_MSG_FILE"
                fi
            )
            rm -rf "$TEMP_DIR"
            echo "" >> "$COMMIT_MSG_FILE"
            UPDATES_FOUND=1
        else
            echo "  Up to date."
        fi
    else
        echo "  Error: Could not find SRCREV or rev= in $RECIPE"
    fi
    echo ""
done

if [ "$UPDATES_FOUND" -eq 0 ]; then
    rm -f "$COMMIT_MSG_FILE"
fi
