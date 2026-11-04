#!/bin/bash
#
# Publish SDK installers to S3 and list them in releases.json.
#
#   upload-sdk.sh upload <bucket> <tag> <arch> <installer>
#   upload-sdk.sh index  <bucket> <tag>
#
# AWS credentials come from the environment. <bucket> is AWS_S3_BUCKET, as
# upload.sh takes it, prefix included.
#
# The two steps are separate because releases.json is read, edited and written
# back with no lock: parallel SDK jobs only upload their own files, and one job
# merges them once the machine jobs, which also write it, have finished.

set -euo pipefail

AWS_S3_URL="https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor"
RELEASE_FILE="releases.json"

die() {
	echo "upload-sdk: $*" >&2
	exit 1
}

upload() {
	[ $# -eq 4 ] || die "usage: upload <bucket> <tag> <arch> <installer>"
	local bucket=$1 tag=$2 arch=$3 installer=$4 platform name entry

	[ -f "$installer" ] || die "no installer at $installer"
	case "$arch" in
	x86_64) platform=linux/amd64 ;;
	armv8) platform=linux/arm64 ;;
	armv6) platform=linux/arm/v6 ;;
	# Not built any more, but 031-rc3 and 031-rc4 released one.
	armv7) platform=linux/arm/v7 ;;
	*) die "no platform for arch $arch" ;;
	esac

	name="pv-sdk-$tag-$arch"
	entry=$(mktemp)
	trap 'rm -f "$entry"' RETURN
	jq -n \
		--arg release "$tag" --arg platform "$platform" --arg arch "$arch" \
		--arg url "$AWS_S3_URL/$tag/sdk/$name.sh" \
		--arg sha256 "$(sha256sum "$installer" | cut -d' ' -f1)" \
		'{release: $release, platform: $platform, arch: $arch, url: $url, sha256: $sha256}' \
		>"$entry"

	# The entry goes last: index treats it as the mark of a complete upload.
	aws s3 cp --no-progress "$installer" "s3://$bucket/$tag/sdk/$name.sh"
	aws s3 cp --no-progress "$entry" "s3://$bucket/$tag/sdk/$name.json"
	cat "$entry"
}

index() {
	[ $# -eq 2 ] || die "usage: index <bucket> <tag>"
	local bucket=$1 tag=$2 type work

	case "$tag" in
	*-rc*) type=release-candidate ;;
	[0-9]*) type=stable ;;
	*) die "the type of tag $tag could not be determined" ;;
	esac

	work=$(mktemp -d)
	trap 'rm -rf "$work"' RETURN
	aws s3 cp --no-progress --recursive "s3://$bucket/$tag/sdk/" "$work/entries/" \
		--exclude '*' --include '*.json'
	compgen -G "$work/entries/*.json" >/dev/null || die "no SDK entries under $tag/sdk/"

	# No fallback to an empty file as upload.sh has: a failed read here must
	# not replace the whole index.
	aws s3 cp --no-progress "s3://$bucket/$RELEASE_FILE" "$work/$RELEASE_FILE"
	jq -s 'sort_by(.arch)' "$work"/entries/*.json >"$work/sdks.json"
	jq --arg type "$type" --arg tag "$tag" --arg time "$(date -u --iso-8601=minutes)" \
		--slurpfile sdks "$work/sdks.json" '
		.[$type][$tag].devices //= [] |
		.[$type][$tag]["release-date"] //= $time |
		.[$type][$tag].sdks = $sdks[0]
		' "$work/$RELEASE_FILE" >"$work/new.json"
	aws s3 cp --no-progress --content-type application/json \
		"$work/new.json" "s3://$bucket/$RELEASE_FILE"
	jq -r '.[] | "\(.arch)\t\(.url)"' "$work/sdks.json"
}

command=${1:-}
[ $# -gt 0 ] && shift
case "$command" in
upload) upload "$@" ;;
index) index "$@" ;;
*) die "usage: upload-sdk.sh upload|index ..." ;;
esac
