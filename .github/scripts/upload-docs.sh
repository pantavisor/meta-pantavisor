#!/bin/bash
set -euo pipefail

AWS_KEY_ID=$1
AWS_SECRET_KEY=$2
AWS_S3_BUCKET=$3
TAG=$4
DOCS_DIR=${5:-docs-out}

AWS_S3_URL="https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor"
RELEASE_FILE="releases.json"

aws configure set aws_access_key_id "$AWS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_KEY"

if [ ! -d "$DOCS_DIR" ]; then
    echo "error: docs directory '$DOCS_DIR' not found" >&2
    exit 1
fi

FILES_DOCS=( "$DOCS_DIR"/pantavisor-docs-*.tar.gz )
if [ ! -e "${FILES_DOCS[0]}" ]; then
    echo "error: no pantavisor-docs tarball found in '$DOCS_DIR'" >&2
    exit 1
fi

# One docs tarball per tag.
DOCS_FILE="${FILES_DOCS[0]}"
FILENAME=$(basename "$DOCS_FILE")
DOCS_CSUM=$(sha256sum "$DOCS_FILE" | cut -d' ' -f1)
echo "processing: $FILENAME ($DOCS_CSUM)"

aws s3 cp "$DOCS_FILE" "s3://$AWS_S3_BUCKET/$TAG/docs/$FILENAME"

# Classify the tag the same way upload.sh does.
if [[ "$TAG" == *"-rc"* ]]; then
    RELEASE_TYPE="release-candidate"
elif [[ "$TAG" =~ ^[0-9] ]]; then
    RELEASE_TYPE="stable"
else
    echo "WARN: the type for tag '$TAG' could not be determined." >&2
    RELEASE_TYPE="unknown"
fi

aws s3 cp "s3://$AWS_S3_BUCKET/$RELEASE_FILE" "$RELEASE_FILE" || echo "{}" > "$RELEASE_FILE"

# Upsert a {docs: {name, url, sha256}} entry into the tag's array in
# releases.json, keeping all other entries (machines, timestamp) intact.
jq --arg type "$RELEASE_TYPE" \
   --arg tag "$TAG" \
   --arg name "$FILENAME" \
   --arg url "$AWS_S3_URL/$TAG/docs/$FILENAME" \
   --arg sha "$DOCS_CSUM" \
   '
     .[$type] //= {} |
     .[$type][$tag] //= [] |
     (.[$type][$tag] | map(has("docs")) | index(true)) as $docs_idx |
     if $docs_idx == null then
       .[$type][$tag] += [{docs: {name: $name, url: $url, sha256: $sha}}]
     else
       .[$type][$tag][$docs_idx] = {docs: {name: $name, url: $url, sha256: $sha}}
     end
   ' "$RELEASE_FILE" > temp.json && mv temp.json "$RELEASE_FILE"

aws s3 cp "$RELEASE_FILE" "s3://$AWS_S3_BUCKET/$RELEASE_FILE"
