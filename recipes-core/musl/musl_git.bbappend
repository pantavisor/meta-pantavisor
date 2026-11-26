# CVE-2026-107891: integer overflows in regcomp (musl <= 1.2.6), from
# https://www.openwall.com/lists/musl/2026/10/21/1. kirkstone (1.2.3) and
# scarthgap (1.2.4) share the same regcomp.c, so one patch covers both.
# Drop once poky's musl is at 1.2.7 or carries the fix.
FILESEXTRAPATHS:prepend := "${THISDIR}/musl:"
SRC_URI:append = " file://0001-regex-avoid-int-overflow-in-regcomp.patch"
