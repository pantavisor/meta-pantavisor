#!/bin/bash
#
# Generate a Kubernetes-style changelog section for a meta-pantavisor release
# tag. Output is one Markdown section ("## v<TAG>") containing:
#   - Downloads table sourced from the public releases.json (when available)
#   - Component-version diff (SRCREV) vs the previous tag in the stream
#   - Categorized changes (Conventional Commits, no hashes)
#
# Modes (auto-detected by whether the tag already exists):
#
#   pre-tag (tag does NOT yet exist)
#     The script treats HEAD as the commit that will be tagged with <TAG>.
#     SRCREVs are read from HEAD; git log range is <PREV>..HEAD; release
#     date is today. After writing the file, the script commits it with
#     "changelogs(<TAG>): autoadd changelog" — ready to be tagged.
#     The downloads section is empty in this mode (releases.json hasn't
#     been published yet).
#
#   historical (tag already exists)
#     SRCREVs are read from <TAG>; git log range is <PREV>..<TAG>; release
#     date is the tag's commit date; downloads come from releases.json.
#     No commit is made — useful for backfill, regeneration, or preview.
#
# Usage:
#   make-changelog.sh <TAG>              # pre-tag: write file + commit; or historical: write file
#   make-changelog.sh --no-commit <TAG>  # write file but never commit
#   make-changelog.sh --stdout <TAG>     # print section to stdout, no file write, no commit
#
# Requires: git, curl, jq, awk.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
COMPONENTS_JSON="$SCRIPT_DIR/components.json"
mapfile -t COMPONENTS < <(jq -r '.[] | "\(.name)|\(.recipe_glob)|\(.branch)|\(.repo_org)"' "$COMPONENTS_JSON")

RELEASES_JSON_URL="${RELEASES_JSON_URL:-https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/releases.json}"
GH_REPO="${GH_REPO:-pantavisor/meta-pantavisor}"

STDOUT_ONLY=0
NO_COMMIT=0
TAG=""
for arg in "$@"; do
    case "$arg" in
        --stdout)    STDOUT_ONLY=1 ;;
        --no-commit) NO_COMMIT=1 ;;
        -h|--help)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "ERROR: unknown flag $arg" >&2
            exit 1
            ;;
        *)
            if [ -z "$TAG" ]; then
                TAG="$arg"
            else
                echo "ERROR: unexpected positional argument $arg" >&2
                exit 1
            fi
            ;;
    esac
done

if [ -z "$TAG" ]; then
    echo "ERROR: TAG is required" >&2
    exit 1
fi

if [[ ! "$TAG" =~ ^0[0-9]+(-rc[0-9]+)?$ ]]; then
    echo "ERROR: '$TAG' is not a release tag (expected 0NN or 0NN-rcN)" >&2
    exit 1
fi

cd "$REPO_ROOT"

# --- Mode detection --------------------------------------------------------
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    MODE="historical"
    SOURCE_REV="$TAG"
    RELEASE_DATE="$(git log -1 --format=%cs "$TAG")"
else
    MODE="pre-tag"
    SOURCE_REV="HEAD"
    RELEASE_DATE="$(date -u +%Y-%m-%d)"
fi

MAJOR="${TAG%%-*}"
if [[ "$TAG" == *-rc* ]]; then
    RELEASE_TYPE="release-candidate"
else
    RELEASE_TYPE="stable"
fi

prev_release_type_for() {
    local t="$1"
    [ -z "$t" ] && return 0
    if [[ "$t" == *-rc* ]]; then echo "release-candidate"; else echo "stable"; fi
}

echo "Mode:    $MODE" >&2
echo "Tag:     $TAG" >&2
echo "Source:  $SOURCE_REV" >&2

determine_previous_tag() {
    local tag="$1"
    local major="${tag%%-*}"
    local candidates=()
    local t

    while IFS= read -r t; do
        [ -z "$t" ] && continue
        [ "$t" = "$tag" ] && continue
        [ "$(printf '%s\n%s\n' "$t" "$tag" | sort -V | head -n 1)" = "$t" ] && candidates+=("$t")
    done < <(git tag -l "${major}-rc*")

    while IFS= read -r t; do
        [ -z "$t" ] && continue
        [[ "$t" =~ ^[0-9]+$ ]] || continue
        [ "$(printf '%s\n%s\n' "$t" "$tag" | sort -V | head -n 1)" = "$t" ] && candidates+=("$t")
    done < <(git tag -l "0*")

    if [ ${#candidates[@]} -eq 0 ]; then
        return
    fi
    printf '%s\n' "${candidates[@]}" | sort -V | tail -n 1
}

PREV_TAG="$(determine_previous_tag "$TAG")"
PREV_RELEASE_TYPE="$(prev_release_type_for "$PREV_TAG")"
echo "Prev:    ${PREV_TAG:-(none)}" >&2

# --- helpers ---------------------------------------------------------------

# Resolve a recipe glob to a single path that exists at the given rev.
recipe_path_at() {
    local rev="$1" glob="$2"
    local pattern="^${glob//\*/[^/]*}$"
    git ls-tree -r --name-only "$rev" 2>/dev/null | grep -E "$pattern" | head -n 1
}

parse_srcrev_at() {
    local rev="$1" glob="$2"
    local recipe
    recipe="$(recipe_path_at "$rev" "$glob")"
    [ -z "$recipe" ] && return 0
    git show "$rev:$recipe" 2>/dev/null | grep -oP 'SRCREV = "\K[^"]+' | head -n 1
}

parse_repo_at() {
    local rev="$1" glob="$2" org="$3"
    local recipe
    recipe="$(recipe_path_at "$rev" "$glob")"
    [ -z "$recipe" ] && return 0
    git show "$rev:$recipe" 2>/dev/null \
        | grep -oP "github\.com/$org/\K[^; \"']+" \
        | sed 's/\.git$//' | head -n 1
}

# --- 1. Downloads table ----------------------------------------------------
RELEASES_JSON="$(mktemp)"
trap 'rm -f "$RELEASES_JSON"' EXIT

if ! curl -sf -o "$RELEASES_JSON" "$RELEASES_JSON_URL"; then
    echo "WARN: could not fetch $RELEASES_JSON_URL — downloads section will be empty" >&2
    echo "{}" > "$RELEASES_JSON"
fi

DOWNLOADS_SECTION="$(
    jq -r \
        --arg type "$RELEASE_TYPE" --arg tag "$TAG" \
        --arg prev_type "$PREV_RELEASE_TYPE" --arg prev_tag "$PREV_TAG" '
        def render_row(predicted):
            "\n| " + .name +
            " | " + (
                if (.full_image.url // "") != "" then
                    "[" + (if predicted then "Pending" else "Download" end) + "](" + .full_image.url + ")" +
                    (if (.full_image.sha256 // "") != "" then "<br>`" + (.full_image.sha256[0:12]) + "…`" else "" end)
                else "—" end) +
            " | " + (
                if (.pvrexports.url // "") != "" and (predicted or ((.pvrexports.sha256 // "") != "")) then
                    "[" + (if predicted then "Pending" else "Download" end) + "](" + .pvrexports.url + ")" +
                    (if (.pvrexports.sha256 // "") != "" then "<br>`" + (.pvrexports.sha256[0:12]) + "…`" else "" end)
                else "—" end) +
            " | " + (
                if (.bsp.url // "") != "" and (predicted or ((.bsp.sha256 // "") != "")) then
                    "[" + (if predicted then "Pending" else "Download" end) + "](" + .bsp.url + ")" +
                    (if (.bsp.sha256 // "") != "" then "<br>`" + (.bsp.sha256[0:12]) + "…`" else "" end)
                else "—" end) +
            " | " + (
                if (.sdk.url // "") != "" then
                    "[" + (if predicted then "Pending" else "Download" end) + "](" + .sdk.url + ")" +
                    (if (.sdk.sha256 // "") != "" then "<br>`" + (.sdk.sha256[0:12]) + "…`" else "" end)
                else "—" end) +
            " |";

        def render_table(entries; predicted):
            "| Machine | Image | PV Exports | BSP | SDK |\n" +
            "|---|---|---|---|---|" +
            (entries | map(render_row(predicted)) | add // "");

        def predicted_from(prev_entries):
            prev_entries | map(
                select(.name) | {
                    name,
                    full_image: {
                        url: (if (.full_image.url // "") != "" then (.full_image.url | gsub($prev_tag; $tag)) else "" end),
                        sha256: ""
                    },
                    pvrexports: {
                        url: (if (.pvrexports.url // "") != "" and ((.pvrexports.sha256 // "") != "") then (.pvrexports.url | gsub($prev_tag; $tag)) else "" end),
                        sha256: ""
                    },
                    bsp: {
                        url: (if (.bsp.url // "") != "" and ((.bsp.sha256 // "") != "") then (.bsp.url | gsub($prev_tag; $tag)) else "" end),
                        sha256: ""
                    },
                    sdk: {
                        url: (if (.sdk.url // "") != "" then (.sdk.url | gsub($prev_tag; $tag)) else "" end),
                        sha256: ""
                    }
                }
            );

        (.[$type][$tag] // [] | map(select(.name))) as $current |
        ((if $prev_tag == "" then [] else (.[$prev_type][$prev_tag] // []) end) | map(select(.name))) as $prev |
        if ($current | length) > 0 then
            render_table($current; false)
        elif ($prev | length) > 0 then
            "_Predicted artifact URLs based on the previous release `" + $prev_tag + "`. The links will activate once the build pipeline uploads the artifacts to S3 — until then they will 404._\n\n" +
            render_table(predicted_from($prev); true)
        else
            "_(no artifacts recorded in releases.json yet, and no previous release to predict from)_"
        end
    ' "$RELEASES_JSON"
)"

# --- 2. Component versions diff -------------------------------------------
build_components_section() {
    local entry name glob org repo cur_sha prev_sha repo_url compare_cell prev_display

    if [ -n "$PREV_TAG" ]; then
        echo "| Component | Previous (${PREV_TAG}) | Current (${TAG}) | Compare |"
        echo "|---|---|---|---|"
    else
        echo "| Component | Current (${TAG}) | Repo |"
        echo "|---|---|---|"
    fi

    for entry in "${COMPONENTS[@]}"; do
        IFS="|" read -r name glob _branch org <<< "$entry"
        cur_sha="$(parse_srcrev_at "$SOURCE_REV" "$glob")"
        [ -z "$cur_sha" ] && continue

        repo="$(parse_repo_at "$SOURCE_REV" "$glob" "$org")"
        repo_url="https://github.com/${org}/${repo}"

        if [ -z "$PREV_TAG" ]; then
            echo "| ${name} | \`${cur_sha:0:7}\` | [${org}/${repo}](${repo_url}) |"
            continue
        fi

        prev_sha="$(parse_srcrev_at "$PREV_TAG" "$glob")"
        if [ -z "$prev_sha" ]; then
            compare_cell="_new_"
            prev_display="—"
        elif [ "$prev_sha" = "$cur_sha" ]; then
            compare_cell="_unchanged_"
            prev_display="\`${prev_sha:0:7}\`"
        else
            compare_cell="[\`${prev_sha:0:7}…${cur_sha:0:7}\`](${repo_url}/compare/${prev_sha}...${cur_sha})"
            prev_display="\`${prev_sha:0:7}\`"
        fi

        echo "| ${name} | ${prev_display} | \`${cur_sha:0:7}\` | ${compare_cell} |"
    done
}

COMPONENTS_SECTION="$(build_components_section)"

# --- 3. Categorized changes ------------------------------------------------
emit_changes() {
    if [ -z "$PREV_TAG" ]; then
        echo "_(no previous tag — initial release)_"
        return
    fi

    local raw
    raw=$(git log --no-merges --format='%s' "${PREV_TAG}..${SOURCE_REV}" 2>/dev/null || true)
    if [ -z "$raw" ]; then
        echo "_(no commits between ${PREV_TAG} and ${SOURCE_REV})_"
        return
    fi

    awk -v raw="$raw" '
        BEGIN {
            n_feat=0; n_fix=0; n_ci=0; n_docs=0; n_other=0
            split(raw, lines, "\n")
            for (i=1; i in lines; i++) {
                line = lines[i]
                if (line == "") continue

                if (match(line, /^([a-z]+)(\(([^)]+)\))?(!)?:[ \t]+(.+)$/, m) == 0) {
                    other[++n_other] = "- **(uncategorized)**: " line
                    continue
                }
                type = m[1]
                scope = m[3]
                subject = m[5]
                prefix = (scope != "") ? ("**" scope "**: ") : ""
                bullet = "- " prefix subject

                # Drop housekeeping types entirely; "changelogs"/"changelog" is the
                # autoadd commit, dropping it prevents the changelog from absorbing
                # itself on re-runs.
                if (type == "chore" || type == "style" ||
                    type == "changelog" || type == "changelogs") continue

                if (type == "feat" || type == "feature")  feat[++n_feat] = bullet
                else if (type == "fix")                   fix[++n_fix]   = bullet
                else if (type == "ci" || type == "build") ci[++n_ci]     = bullet
                else if (type == "docs" || type == "doc") docs[++n_docs] = bullet
                else                                      other[++n_other] = "- (" type ") " prefix subject
            }

            emit("Features", feat, n_feat)
            emit("Fixes", fix, n_fix)
            emit("CI", ci, n_ci)
            emit("Docs", docs, n_docs)
            emit("Other", other, n_other)
        }
        function emit(title, arr, n,    i) {
            if (n == 0) return
            print "#### " title
            for (i = 1; i <= n; i++) print arr[i]
            print ""
        }
    '
}

CHANGES_SECTION="$(emit_changes)"

# --- 4. Render section -----------------------------------------------------
if [ -n "$PREV_TAG" ]; then
    CHANGES_PREAMBLE="Changes since [\`${PREV_TAG}\`](https://github.com/${GH_REPO}/releases/tag/${PREV_TAG}):"$'\n'
else
    CHANGES_PREAMBLE=""
fi

SECTION="$(cat <<EOF
## v${TAG}

Released: ${RELEASE_DATE}

### Downloads

${DOWNLOADS_SECTION}

Source: [\`releases.json\`](${RELEASES_JSON_URL}) (\`${RELEASE_TYPE}\` → \`${TAG}\`).

### Component versions

${COMPONENTS_SECTION}

### Changes

${CHANGES_PREAMBLE}
${CHANGES_SECTION}
EOF
)"

if [ "$STDOUT_ONLY" -eq 1 ]; then
    printf '%s\n' "$SECTION"
    exit 0
fi

# --- 5. Prepend (or replace existing section for this TAG) -----------------
CHANGELOG_DIR="${REPO_ROOT}/CHANGELOG"
CHANGELOG_FILE="${CHANGELOG_DIR}/CHANGELOG-${MAJOR}.md"
mkdir -p "$CHANGELOG_DIR"

FILE_HEADER="# CHANGELOG-${MAJOR}

This file tracks every release in the \`${MAJOR}\` stream. Each section
covers one tag — release candidates and the final stable — newest first.

Generated by [\`make-changelog.sh\`](../.github/scripts/make-changelog.sh),
which runs both automatically in CI (via
[\`changelog-on-tag.yaml\`](../.github/workflows/changelog-on-tag.yaml)
after the tag build completes) and on demand locally; see
[\`docs/ci/changelog.md\`](../docs/ci/changelog.md).
"

NEW_FILE="$(mktemp)"
if [ -f "$CHANGELOG_FILE" ]; then
    awk -v top="${NEW_FILE}.top" -v body="${NEW_FILE}.body" '
        BEGIN { mode="top" }
        /^## v/ { mode="body" }
        {
            if (mode == "top") print > top
            else                print > body
        }
    ' "$CHANGELOG_FILE"

    if [ -f "${NEW_FILE}.body" ]; then
        awk -v tag="$TAG" '
            /^## v/ { skip = ($0 == "## v" tag) ? 1 : 0 }
            !skip
        ' "${NEW_FILE}.body" > "${NEW_FILE}.body.clean"
        mv "${NEW_FILE}.body.clean" "${NEW_FILE}.body"
    fi

    {
        if [ -s "${NEW_FILE}.top" ]; then
            cat "${NEW_FILE}.top"
        else
            printf '%s\n' "$FILE_HEADER"
        fi
        printf '%s\n\n' "$SECTION"
        [ -f "${NEW_FILE}.body" ] && cat "${NEW_FILE}.body"
    } > "$NEW_FILE"

    rm -f "${NEW_FILE}.top" "${NEW_FILE}.body"
else
    {
        printf '%s\n' "$FILE_HEADER"
        printf '%s\n\n' "$SECTION"
    } > "$NEW_FILE"
fi

chmod 644 "$NEW_FILE"
mv "$NEW_FILE" "$CHANGELOG_FILE"
echo "Updated $CHANGELOG_FILE" >&2

# --- 6. Auto-commit (pre-tag mode only, unless --no-commit) ----------------
if [ "$NO_COMMIT" -eq 1 ]; then
    exit 0
fi
if [ "$MODE" != "pre-tag" ]; then
    # Historical regeneration: don't auto-commit. User can stage/commit manually.
    exit 0
fi

# Only commit if the changelog actually changed; uses --only so any other
# staged changes the user has remain untouched.
if git -C "$REPO_ROOT" diff --quiet -- "$CHANGELOG_FILE" \
   && git -C "$REPO_ROOT" diff --cached --quiet -- "$CHANGELOG_FILE"; then
    echo "No changes to ${CHANGELOG_FILE} — skipping commit." >&2
    exit 0
fi

COMMIT_MSG="changelogs(${TAG}): autoadd changelog"
git -C "$REPO_ROOT" commit --only -m "$COMMIT_MSG" -- "$CHANGELOG_FILE"
echo "Committed: $COMMIT_MSG" >&2
echo "Next: review the commit, then 'git tag $TAG && git push origin $TAG'" >&2
