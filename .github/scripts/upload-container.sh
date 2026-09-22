#!/bin/bash

AWS_KEY_ID=$1
AWS_SECRET_KEY=$2
AWS_S3_BUCKET=$3
TAG=$4
MACHINE_NAME=$5
CONTAINER_NAME=$6
MACHINE=$7

AWS_S3_URL="https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/containers"

RELEASE_FILE="containers-releases.json"

CONTAINERS_JSON=".github/containers.json"
DISPLAY_NAME=$(jq -r --arg n "$CONTAINER_NAME" \
  '.containers[] | select(.name == $n) | .display_name // empty' "$CONTAINERS_JSON")
DESCRIPTION=$(jq -r --arg n "$CONTAINER_NAME" \
  '.containers[] | select(.name == $n) | .description // empty' "$CONTAINERS_JSON")
[ -n "$DISPLAY_NAME" ] || DISPLAY_NAME="$CONTAINER_NAME"

aws configure set aws_access_key_id $AWS_KEY_ID
aws configure set aws_secret_access_key $AWS_SECRET_KEY

PVREXPORT_FILE=$(find pvexports -maxdepth 1 -name "*pvrexport.tgz" | head -1)

if [ -z "$PVREXPORT_FILE" ]; then
    echo "warning: no pvrexport.tgz found in pvexports/ — nothing to upload" >&2
    exit 0
fi

# MACHINE is "docker-x86_64"/"docker-armv6"/"docker-armv8"; strip the
# "docker-" prefix so the uploaded name reads e.g. pv-avahi-x86_64.pvrexport.tgz.
ARCH="${MACHINE#docker-}"
PVREXPORT_NAME="${CONTAINER_NAME}-${ARCH}.pvrexport.tgz"
PVREXPORT_CSUM=$(sha256sum "$PVREXPORT_FILE" | cut -d' ' -f1)

aws s3 cp "$PVREXPORT_FILE" "s3://$AWS_S3_BUCKET/containers/$TAG/$MACHINE_NAME/$PVREXPORT_NAME"

RELEASE_TYPE=""
if [[ "$TAG" == *"-rc"* ]]; then
    RELEASE_TYPE="release-candidate"
elif [[ "$TAG" =~ ^[0-9] ]]; then
    RELEASE_TYPE="stable"
else
    echo "WARN: the type for tag '$TAG' could not be determined." >&2
    RELEASE_TYPE="unknown"
fi

aws s3 cp s3://$AWS_S3_BUCKET/$RELEASE_FILE $RELEASE_FILE || echo "{}" > $RELEASE_FILE

TIMESTAMP=$(date -u --iso-8601=minutes)

jq --arg type "$RELEASE_TYPE" \
   --arg rname "$TAG" \
   --arg time "$TIMESTAMP" \
   --arg cname "$CONTAINER_NAME" \
   --arg display "$DISPLAY_NAME" \
   --arg desc "$DESCRIPTION" \
   --arg machine "$MACHINE" \
   --arg url "$AWS_S3_URL/$TAG/$MACHINE_NAME/$PVREXPORT_NAME" \
   --arg sha "$PVREXPORT_CSUM" \
'
    .[$type] //= {} |
    .[$type][$rname] //= {} |
    .[$type][$rname].containers //= [] |
    .[$type][$rname]["release-date"] //= $time |

    (.[$type][$rname].containers | map(.name) | index($cname)) as $idx |

    ($idx // (.[$type][$rname].containers | length)) as $i |

    .[$type][$rname].containers[$i].name = $cname |
    .[$type][$rname].containers[$i].display_name = $display |
    (if $desc != "" then .[$type][$rname].containers[$i].description = $desc else . end) |
    .[$type][$rname].containers[$i].machines[$machine] = { pvrexport: { url: $url, sha256: $sha } }

' "$RELEASE_FILE" > temp.json && mv temp.json "$RELEASE_FILE"

aws s3 cp $RELEASE_FILE s3://$AWS_S3_BUCKET/$RELEASE_FILE
