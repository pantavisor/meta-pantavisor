#!/bin/bash

AWS_KEY_ID=$1
AWS_SECRET_KEY=$2
AWS_S3_BUCKET=$3
TAG=$4
MACHINE_NAME=$5
OUTPUT_FILES=$6

AWS_S3_URL="https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor"

RELEASE_FILE="releases.json"

TARNAME="$MACHINE_NAME-$TAG.tar.gz" 

aws configure set aws_access_key_id $AWS_KEY_ID
aws configure set aws_secret_access_key $AWS_SECRET_KEY

tar -czf "$TARNAME" $OUTPUT_FILES
CHECKSUM=$(sha256sum "$TARNAME" | cut -d' ' -f1)

# Upload to S3
aws s3 cp "$TARNAME" "s3://$AWS_S3_BUCKET/$MACHINE_NAME/$TARNAME"

RELEASE_TYPE=""
if [[ "$TAG" == 0* ]]; then
    RELEASE_TYPE="stable"

elif [[ "$TAG" == *-rc* ]]; then
    RELEASE_TYPE="release-candidate" # Note que o nome no JSON é 'release-candidate'

else
    echo "WARN: the type '$INPUT_TYPE' is not a valid value." >&2
    RELEASE_TYPE="unknown" 
fi

aws s3 cp s3://$AWS_S3_BUCKET/$RELEASE_FILE $RELEASE_FILE

NEW_DEVICE=$(jq -n \
  --arg name "$MACHINE_NAME" \
  --arg url "$AWS_S3_URL/$MACHINE_NAME/$TARNAME" \
  --arg checksum "$CHECKSUM" \
  '{name: $name, url: $url, checksum: $checksum}')

jq --arg type "$RELEASE_TYPE" \
   --arg rname "$TAG" \
   --argjson new_device "$NEW_DEVICE" \
   '
    (.[$type] //= []) |

    (.[$type] | map(.name) | index($rname)) as $release_idx |

    if $release_idx == null then
        .[$type] += [{
            "name": $rname,
            "devices": [$new_device]
        }]
    else
        (.[$type][$release_idx].devices | map(.name) | index($new_device.name)) as $device_idx |

        if $device_idx == null then
            .[$type][$release_idx].devices += [$new_device]
        else
            .[$type][$release_idx].devices[$device_idx] = $new_device
        end
    end
   ' $RELEASE_FILE > temp.json && mv temp.json $RELEASE_FILE

aws s3 cp $RELEASE_FILE s3://$AWS_S3_BUCKET/$RELEASE_FILE