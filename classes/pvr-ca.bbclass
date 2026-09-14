PVS_VENDOR_NAME ??= "generic"
# Fetched through the GitLab API rather than the web UI's /-/archive/ path: the
# latter sits behind a Cloudflare JS challenge that answers a bare wget with
# 403, which no fetcher can pass. The API archive is byte-stable for a pinned
# sha (same approach as pvr_054.bb's DOCS_SRC_URI).
PVS_CA_SHA ??= "2340d747c4acd0a1a702b3d7d5acc014b51daaa7"
PVS_URI ??= "https://gitlab.com/api/v4/projects/pantacor%2Fpv-developer-ca/repository/archive.tar.gz?sha=${PVS_CA_SHA};downloadfilename=pv-developer-ca-${PVS_CA_SHA}.tar.gz;striplevel=1"
PVS_URI_SHA256 ??= "f7c8470b3ccd8be23974a5cf2469b59a2e39702d40a2fe4ae5bfa01399817816"

SRC_URI += "${PVS_URI};name=pv-developer-ca;subdir=pv-developer-ca_${PVS_VENDOR_NAME}"
SRC_URI[pv-developer-ca.sha256sum] = "${PVS_URI_SHA256}"
