#!/bin/bash

AWS_KEY_ID=$1
AWS_SECRET_KEY=$2
AWS_S3_BUCKET=$3
TAG=$4
MACHINE_NAME=$5

AWS_S3_URL="https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor"

RELEASE_FILE="releases.json"

TAR_IMAGES="$MACHINE_NAME-$TAG.tar.gz"
TAR_PVEXPORTS="pvexports-$MACHINE_NAME-$TAG.tar.gz"

aws configure set aws_access_key_id $AWS_KEY_ID
aws configure set aws_secret_access_key $AWS_SECRET_KEY

if [ -d "images" ]; then
    FILES_IMAGES=( $(ls images) )
    
    if [ ${#FILES_IMAGES[@]} -gt 0 ]; then
        echo "processing: ${FILES_IMAGES[*]}"
        tar -czf "$TAR_IMAGES" -C images "${FILES_IMAGES[@]}"
        
        IMAGES_CSUM=$(sha256sum "$TAR_IMAGES" | cut -d' ' -f1)
        aws s3 cp "$TAR_IMAGES" "s3://$AWS_S3_BUCKET/$TAG/$MACHINE_NAME/$TAR_IMAGES"
    else
        echo "warning: folder images is empty"
    fi
fi

if [ -d "pvexports" ]; then
    FILES_PVEXPORTS=( $(ls pvexports) )
    
    if [ ${#FILES_PVEXPORTS[@]} -gt 0 ]; then
        echo "processing: ${FILES_PVEXPORTS[*]}"
        tar -czf "$TAR_PVEXPORTS" -C pvexports "${FILES_PVEXPORTS[@]}"
        
        PVEXPORTS_CSUM=$(sha256sum "$TAR_PVEXPORTS" | cut -d' ' -f1)
        aws s3 cp "$TAR_PVEXPORTS" "s3://$AWS_S3_BUCKET/$TAG/$MACHINE_NAME/$TAR_PVEXPORTS"
    else
        echo "warning: folder pvrexports is empty"
    fi
fi

FILES_BSP=( pvexports/pantavisor-bsp* )
for FILE in "${FILES_BSP[@]}"; do
    if [ -f "$FILE" ]; then
        FILENAME=$(basename "$FILE")
        echo "processing: $FILENAME"
		BSP_FILE="$FILENAME"
        BSP_CSUM=$(sha256sum "$FILE" | cut -d' ' -f1)
        aws s3 cp "$FILE" "s3://$AWS_S3_BUCKET/$TAG/$MACHINE_NAME/$FILENAME"
    fi
done

FILES_SDK=( sdk/panta*.sh )
for FILE in "${FILES_SDK[@]}"; do
    if [ -f "$FILE" ]; then
        FILENAME=$(basename "$FILE")
        echo "processing: $FILENAME"
        
		SDK_FILE="$FILENAME"
        SDK_CSUM=$(sha256sum "$FILE" | cut -d' ' -f1)
        aws s3 cp "$FILE" "s3://$AWS_S3_BUCKET/$TAG/$MACHINE_NAME/$FILENAME"
    fi
done

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

NEW_DEVICE=$(jq -n \
  --arg name "$MACHINE_NAME" \
  --arg url1 "$AWS_S3_URL/$TAG/$MACHINE_NAME/$TAR_IMAGES" \
  --arg url2 "$AWS_S3_URL/$TAG/$MACHINE_NAME/$TAR_PVEXPORTS" \
  --arg url3 "$AWS_S3_URL/$TAG/$MACHINE_NAME/$BSP_FILE" \
  --arg IMAGES_CSUM "$IMAGES_CSUM" \
  --arg PVEXPORTS_CSUM "$PVEXPORTS_CSUM" \
  --arg BSP_CSUM "$BSP_CSUM" \
  '{name: $name, full_image: {url: $url1, sha256: $IMAGES_CSUM},
   pvrexports: { url: $url2, sha256: $PVEXPORTS_CSUM },
   bsp: {url: $url3, sha256: $BSP_CSUM} }')

if [ -e sdk/$DEPLOY_SDK ]; then
    NEW_DEVICE=$(echo "$NEW_DEVICE" | jq \
      --arg url "$AWS_S3_URL/$TAG/$MACHINE_NAME/$SDK_FILE" \
      --arg sha "$SDK_CSUM" \
      '. + {sdk: {url: $url, sha256: $sha}}')
fi

TIMESTAMP=$(date --iso-8601=minutes)

jq --arg type "$RELEASE_TYPE" \
   --arg rname "$TAG" \
   --arg time "$TIMESTAMP" \
   --argjson new_device "$NEW_DEVICE" \
'
    .[$type] //= {} |
    .[$type][$rname] //= [] |
    
    (.[$type][$rname].devices | map(.name) | index($new_device.name)) as $device_idx |

    if $device_idx == null then
        .[$type][$rname].devices += [$new_device]
    else
        .[$type][$rname].devices[$device_idx] = $new_device
    end

	.[$type][$rname] |= (map(select(.timestamp == null)) + [{timestamp: $time}])

' "$RELEASE_FILE" > temp.json && mv temp.json "$RELEASE_FILE"

aws s3 cp $RELEASE_FILE s3://$AWS_S3_BUCKET/$RELEASE_FILE