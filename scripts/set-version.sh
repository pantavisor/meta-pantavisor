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

echo "DISTRO_VERSION is dynamically fetched by bitbake."
echo "Run 'git describe' to see the dynamic version"
