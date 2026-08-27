FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# 0003-i2c-imx-prevent-rescheduling-in-non-dma-mode.patch (pinned meta-toradex-bsp-common
# commit 2ed6281) no longer applies to the pinned linux-6.6.y SRCREV_machine: 5 of its 14
# hunks reject against the current drivers/i2c/busses/i2c-imx.c (upstream has drifted since
# the patch was last rebased in ca09533). It's an SMBus-timing optimization, not a
# correctness fix, so drop it here rather than hand-repair a 272-line driver rewrite blind;
# re-add once Toradex rebases it upstream. The 3 patches after it in the queue
# (fix-emulated-smbus-block-read, fix-i2c-issue-when-reading-multiple-messages,
# ensure-no-clock-is-generated-after-last-read) are written against the code structure
# this one introduces, so they fail to apply once it's dropped and have to go with it.
# 0001-i2c-imx-fix-missing-stop-condition-in-single-master-.patch sits between them in
# the queue but applies independently, so it stays.
SRC_URI:remove:colibri-imx6ull = " \
	file://0003-i2c-imx-prevent-rescheduling-in-non-dma-mode.patch \
	file://0001-i2c-imx-fix-emulated-smbus-block-read.patch \
	file://0001-i2c-imx-fix-i2c-issue-when-reading-multiple-messages.patch \
	file://0002-i2c-imx-ensure-no-clock-is-generated-after-last-read.patch \
"

SRC_URI:append:colibri-imx6ull = " \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'dcp', 'file://0001-ARM-dts-imx6ull-colibri-enable-dcp.patch file://0002-crypto-mxs-dcp-Add-support-for-hardware-bound-keys.patch file://0003-KEYS-trusted-Introduce-NXP-DCP-backed-trusted-keys.patch file://0004-crypto-mxs-dcp-Ensure-payload-is-zero-when-using-ke.patch file://0005-KEYS-trusted-fix-DCP-blob-payload-length-assignment.patch file://0006-KEYS-trusted-dcp-fix-leak-of-blob-encryption-key.patch file://0007-KEYS-trusted-dcp-fix-NULL-dereference-in-AEAD-crypt.patch file://0008-KEYS-trusted-dcp-fix-improper-sg-use-with-CONFIG_VM.patch', '', d) if bb.utils.contains('PROVIDES', 'virtual/kernel', True, False, d) else ''} \
"
