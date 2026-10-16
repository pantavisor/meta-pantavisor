# pv-trust: who a Pantavisor image trusts, and which keys sign it.
#
# Pantavisor checks every signature of a revision against one of two bundles
# of root certificates in /etc/pantavisor/pvs/trust/ (pantavisor signature.c):
#
#   ca-oem-certificates.crt  signatures whose certificate CN is PV_OEM_NAME and
#                            that cover nothing under bsp/** or <PV_OEM_NAME>/**
#   ca-certificates.crt      everything else: the BSP, the OEM configuration,
#                            the _pvskel signature and any other CN
#
# Without the variables below an image keeps pantavisor's developer bundles
# and pvr's developer keys, as before. Set them in local.conf, or export them
# and add kas/with-oem-trust.yaml:
#
#   PV_OEM_NAME          the OEM name: PANTAVISOR_CONFIG[PV_OEM_NAME]
#   PV_SECUREBOOT_MODE   disabled, audit, lenient or strict
#   PV_TRUST_DIR         a directory with ca-certificates.crt and/or
#                        ca-oem-certificates.crt (what `pvr signing trust`
#                        writes); each file found replaces pantavisor's own
#   PV_SIGN_PLATFORM_KEY, PV_SIGN_PLATFORM_X5C
#                        key and certificate chain signing the BSP and the
#                        _pvskel; they must chain to ca-certificates.crt
#   PV_SIGN_OEM_KEY, PV_SIGN_OEM_X5C
#                        key and chain signing containers; CN PV_OEM_NAME,
#                        chaining to ca-oem-certificates.crt. Without them
#                        containers are signed with the platform key.
#
# Keys are read from the build host and never copied into the image. A
# changed key or bundle with the same path does not rebuild by itself: the
# files' checksums are task dependencies only where noted.

PV_OEM_NAME ??= ""
PV_SECUREBOOT_MODE ??= ""
PV_TRUST_DIR ??= ""
PV_SIGN_PLATFORM_KEY ??= ""
PV_SIGN_PLATFORM_X5C ??= ""
PV_SIGN_OEM_KEY ??= ""
PV_SIGN_OEM_X5C ??= ""

PV_TRUST_BUNDLES = "ca-certificates.crt ca-oem-certificates.crt"

def pv_trust_bundle(d, name):
    """The path of bundle name in PV_TRUST_DIR, or ''."""
    import os
    trust = d.getVar('PV_TRUST_DIR')
    if not trust:
        return ''
    path = os.path.join(trust, name)
    return path if os.path.isfile(path) else ''

def pv_trust_sign_files(d, role):
    """(key, x5c, cacerts) to sign role (platform or oem) with, '' each when
    the image keeps the default developer keys."""
    platform = (d.getVar('PV_SIGN_PLATFORM_KEY'), d.getVar('PV_SIGN_PLATFORM_X5C'), pv_trust_bundle(d, 'ca-certificates.crt'))
    if role == 'oem' and d.getVar('PV_SIGN_OEM_KEY'):
        return (d.getVar('PV_SIGN_OEM_KEY'), d.getVar('PV_SIGN_OEM_X5C'), pv_trust_bundle(d, 'ca-oem-certificates.crt'))
    if platform[0]:
        return platform
    return ('', '', '')

def pv_trust_sign_env(d, role):
    """Shell exports pointing pvr sig at role's key, for shell tasks."""
    key, x5c, cacerts = pv_trust_sign_files(d, role)
    lines = []
    for var, value in (('PVR_SIG_KEY', key), ('PVR_X5C_PATH', x5c), ('PVR_SIG_CACERTS', cacerts)):
        if value:
            lines.append('export %s="%s"' % (var, value))
    return '\n'.join(lines)

python pv_trust_check() {
    import os
    for role in ('PLATFORM', 'OEM'):
        key, x5c = d.getVar('PV_SIGN_%s_KEY' % role), d.getVar('PV_SIGN_%s_X5C' % role)
        if bool(key) != bool(x5c):
            bb.fatal('PV_SIGN_%s_KEY and PV_SIGN_%s_X5C go together' % (role, role))
        for path in (key, x5c):
            if path and not os.path.isfile(path):
                bb.fatal('%s does not exist' % path)
    trust = d.getVar('PV_TRUST_DIR')
    if trust and not any(pv_trust_bundle(d, n) for n in d.getVar('PV_TRUST_BUNDLES').split()):
        bb.fatal('PV_TRUST_DIR %s has neither ca-certificates.crt nor ca-oem-certificates.crt' % trust)
    if d.getVar('PV_SIGN_OEM_KEY') and not d.getVar('PV_OEM_NAME'):
        bb.warn('PV_SIGN_OEM_KEY is set without PV_OEM_NAME: devices check its signatures against ca-certificates.crt')
}
