#!/bin/bash

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <tag-version>"
    echo "Example: $0 027"
    exit 1
fi

TAG="$1"

echo "Tagging current branch with: $TAG"
git tag -a "$TAG" -m "Release $TAG"

echo "Updating DISTRO_VERSION in distro conf files..."

# Update panta-distro.conf
sed -i 's/^DISTRO_VERSION = ".*"/DISTRO_VERSION = "'"$TAG"'"/' conf/distro/panta-distro.conf

# Update panta-distro-app.conf
sed -i 's/^DISTRO_VERSION = ".*"/DISTRO_VERSION = "'"$TAG"'"/' conf/distro/panta-distro-app.conf

# Update panta-distro-bsp.conf
sed -i 's/^DISTRO_VERSION = ".*"/DISTRO_VERSION = "'"$TAG"'"/' conf/distro/panta-distro-bsp.conf

# Update panta-appengine.conf
sed -i 's/^DISTRO_VERSION = ".*"/DISTRO_VERSION = "'"$TAG"'"/' conf/distro/panta-appengine.conf

echo "Updated to version: $TAG"
echo "Run 'git diff conf/distro/' to see changes"
