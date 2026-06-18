FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:colibri-imx6ull = " \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'dcp', 'file://0001-ARM-dts-imx6ull-colibri-enable-dcp.patch file://0002-crypto-mxs-dcp-Add-support-for-hardware-bound-keys.patch file://0003-KEYS-trusted-Introduce-NXP-DCP-backed-trusted-keys.patch file://0004-crypto-mxs-dcp-Ensure-payload-is-zero-when-using-ke.patch file://0005-KEYS-trusted-fix-DCP-blob-payload-length-assignment.patch file://0006-KEYS-trusted-dcp-fix-leak-of-blob-encryption-key.patch file://0007-KEYS-trusted-dcp-fix-NULL-dereference-in-AEAD-crypt.patch file://0008-KEYS-trusted-dcp-fix-improper-sg-use-with-CONFIG_VM.patch', '', d) if bb.utils.contains('PROVIDES', 'virtual/kernel', True, False, d) else ''} \
"
