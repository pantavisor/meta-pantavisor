SUMMARY = "Root CA subset used by Pantavisor for TLS"
DESCRIPTION = "A subset of the Mozilla root CA bundle, installed as flat PEM files in /etc/thttp/certs, the directory Pantavisor reads its TLS truststore from."
HOMEPAGE = "https://www.mozilla.org/en-US/about/governance/policies/security-group/certs/"
SECTION = "base"
LICENSE = "MPL-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MPL-2.0;md5=815ca599c9df247a0c7f619bab123dad"

PV = "1.0"

DEPENDS = "ca-certificates-native openssl-native"

SRC_URI = "file://excluded-certs.txt"
S = "${WORKDIR}"
B = "${WORKDIR}/build"

inherit allarch

# Where the certificates land on the device; Pantavisor reads every file here.
CA_CERTIFICATES_PV_DIR ?= "${sysconfdir}/thttp/certs"

# Names without .crt, as in ca-certificates-native's mozilla directory.
# Replace or extend this list from a distro, BSP or local.conf.
# Left out because Mozilla no longer trusts them for TLS servers, so
# ca-certificates does not install them: GTS Root R2, DigiCert Global Root CA,
# GlobalSign Root CA (R1).
CA_CERTIFICATES_PV ??= "\
    ISRG_Root_X1 \
    ISRG_Root_X2 \
    \
    GTS_Root_R1 \
    GTS_Root_R3 \
    GTS_Root_R4 \
    \
    Amazon_Root_CA_1 \
    Amazon_Root_CA_2 \
    Amazon_Root_CA_3 \
    Amazon_Root_CA_4 \
    Starfield_Services_Root_Certificate_Authority_-_G2 \
    \
    DigiCert_Global_Root_G2 \
    DigiCert_Global_Root_G3 \
    \
    USERTrust_RSA_Certification_Authority \
    USERTrust_ECC_Certification_Authority \
    Sectigo_Public_Server_Authentication_Root_R46 \
    Sectigo_Public_Server_Authentication_Root_E46 \
    \
    GlobalSign_Root_CA_-_R3 \
    GlobalSign_Root_CA_-_R6 \
    GlobalSign_ECC_Root_CA_-_R5 \
    \
    Go_Daddy_Root_Certificate_Authority_-_G2 \
"

CERTS_WORK_DIR = "${B}/certs"
MOZILLA_CERTS_DIR = "${STAGING_DATADIR_NATIVE}/ca-certificates/mozilla"

# Set to 0 to skip the check that the left-out roots did not change.
CA_CERTIFICATES_PV_CHECK_EXCLUDED ??= "1"

# Rebuild when the list or the check setting changes.
do_compile[vardeps] += "CA_CERTIFICATES_PV CA_CERTIFICATES_PV_CHECK_EXCLUDED"

# Paths in error messages are relative to the directory kas runs in, so they
# work on the host; a file outside that directory keeps its absolute path.
def ca_certs_shown_path(d, path):
    import os
    kas_dir = os.path.dirname(os.path.realpath(d.getVar('TOPDIR')))
    real_path = os.path.realpath(path)
    if real_path.startswith(kas_dir + os.sep):
        return os.path.relpath(real_path, kas_dir)
    # The kas directory can be mounted under another name (e.g. /work), so
    # compare existing directories by identity instead of by name.
    parent = os.path.dirname(real_path)
    while parent != os.path.dirname(parent):
        if os.path.exists(parent) and os.path.samefile(parent, kas_dir):
            return os.path.relpath(real_path, parent)
        parent = os.path.dirname(parent)
    return real_path

# The excluded-certs.txt in use, so the message names the right file when a bbappend overrides it.
EXCLUDED_CERTS_SRC_SHOWN = "${@ca_certs_shown_path(d, bb.utils.which(d.getVar('FILESPATH'), 'excluded-certs.txt'))}"
EXCLUDED_CERTS_GENERATED_SHOWN = "${@ca_certs_shown_path(d, d.getVar('B') + '/excluded-certs.txt')}"
do_compile[vardepsexclude] += "EXCLUDED_CERTS_SRC_SHOWN EXCLUDED_CERTS_GENERATED_SHOWN"

# Fail early if a wanted name is gone, so a Mozilla removal is noticed.
check_wanted_certs_exist() {
    for name in ${CA_CERTIFICATES_PV}; do
        if [ ! -f "${CERTS_WORK_DIR}/${name}.crt" ]; then
            bbfatal "${name} is not in the Mozilla bundle of ca-certificates-native; drop it from CA_CERTIFICATES_PV"
        fi
    done
}

# A new ca-certificates release can add roots. Compare the roots we leave out
# with the committed list, so every change gets a human decision.
check_excluded_certs_unchanged() {
    if [ "${CA_CERTIFICATES_PV_CHECK_EXCLUDED}" = "0" ]; then
        bbwarn "ca-certificates-pv: check of left-out roots is skipped (CA_CERTIFICATES_PV_CHECK_EXCLUDED = 0)"
        return 0
    fi

    generated_file="${B}/excluded-certs.txt"
    committed_file="${B}/excluded-certs.committed"

    # Bundle names that are not in CA_CERTIFICATES_PV, sorted.
    for cert_file in ${CERTS_WORK_DIR}/*.crt; do
        name=$(basename "${cert_file}" .crt)
        case " ${CA_CERTIFICATES_PV} " in
            *" ${name} "*) ;;
            *) echo "${name}" ;;
        esac
    done | LC_ALL=C sort > "${generated_file}"

    # The committed list without comment and blank lines.
    grep -v -e '^#' -e '^$' ${WORKDIR}/excluded-certs.txt | LC_ALL=C sort > "${committed_file}"

    if cmp -s "${generated_file}" "${committed_file}"; then
        return 0
    fi

    new_names=$(LC_ALL=C comm -13 "${committed_file}" "${generated_file}" | sed 's/^/    /')
    gone_names=$(LC_ALL=C comm -23 "${committed_file}" "${generated_file}" | sed 's/^/    /')

    message="ca-certificates-pv: the roots in the Mozilla bundle changed since excluded-certs.txt was last reviewed."
    if [ -n "${new_names}" ]; then
        message="${message}\n\nNew in the bundle (not in CA_CERTIFICATES_PV, not yet reviewed):\n${new_names}"
    fi
    if [ -n "${gone_names}" ]; then
        message="${message}\n\nListed in excluded-certs.txt but no longer left out (gone from the bundle, or now in CA_CERTIFICATES_PV):\n${gone_names}"
    fi

    copy_command="cp ${EXCLUDED_CERTS_GENERATED_SHOWN} ${EXCLUDED_CERTS_SRC_SHOWN}"
    message="${message}\n\nWhat to do (run from the directory you start kas in):"
    if [ -n "${new_names}" ]; then
        message="${message}\n  1. Look at each new root and decide whether Pantavisor devices need it."
        message="${message}\n  2. To ship it: add its name to CA_CERTIFICATES_PV in recipes-pv/ca-certificates-pv/ca-certificates-pv.bb (or your distro/BSP conf)."
        message="${message}\n     If you ship some new roots and leave out others, add the shipped ones to CA_CERTIFICATES_PV first, rebuild, then do step 3 for the rest."
        message="${message}\n  3. To leave it out: ${copy_command}"
        message="${message}\n  4. Commit the change and rebuild. Details: docs/overview/truststore.md\n"
    else
        message="${message}\n  Nothing to decide. Accept the change: ${copy_command}"
        message="${message}\n  Then commit it and rebuild. Details: docs/overview/truststore.md\n"
    fi

    bbfatal "$(printf '%b' "${message}")"
}

# Start from the full bundle and delete what is not wanted.
remove_unlisted_certs() {
    for cert_file in ${CERTS_WORK_DIR}/*.crt; do
        name=$(basename "${cert_file}" .crt)
        case " ${CA_CERTIFICATES_PV} " in
            *" ${name} "*) ;;
            *) rm -f "${cert_file}" ;;
        esac
    done
}

# An expired root is useless and a sign the list needs a refresh.
check_cert_not_expired() {
    cert_file="$1"
    if ! openssl x509 -in "${cert_file}" -noout -checkend 0 > /dev/null; then
        bbfatal "$(basename ${cert_file}) is expired; drop it from CA_CERTIFICATES_PV"
    fi
}

# Pantavisor's mbedtls reads RSA and EC P-256/384/521 only. A file it cannot
# parse makes every TLS request fail, so refuse such roots at build time.
check_cert_key_supported() {
    cert_file="$1"
    cert_text=$(openssl x509 -in "${cert_file}" -noout -text)

    if echo "${cert_text}" | grep -q "Public Key Algorithm: rsaEncryption"; then
        return 0
    fi
    if echo "${cert_text}" | grep -q "Public Key Algorithm: id-ecPublicKey"; then
        if echo "${cert_text}" | grep -Eq "ASN1 OID: (prime256v1|secp384r1|secp521r1)"; then
            return 0
        fi
    fi
    bbfatal "$(basename ${cert_file}) uses a key type Pantavisor cannot read (only RSA, P-256, P-384, P-521); drop it from CA_CERTIFICATES_PV"
}

do_compile() {
    rm -rf ${CERTS_WORK_DIR}
    mkdir -p ${CERTS_WORK_DIR}
    cp ${MOZILLA_CERTS_DIR}/*.crt ${CERTS_WORK_DIR}/

    check_wanted_certs_exist
    check_excluded_certs_unchanged
    remove_unlisted_certs

    for cert_file in ${CERTS_WORK_DIR}/*.crt; do
        check_cert_not_expired "${cert_file}"
        check_cert_key_supported "${cert_file}"
    done

    kept_count=$(ls ${CERTS_WORK_DIR}/*.crt | wc -l)
    bbnote "ca-certificates-pv: keeping ${kept_count} certificates"
}

do_install() {
    install -d ${D}${CA_CERTIFICATES_PV_DIR}
    install -m 0644 ${CERTS_WORK_DIR}/*.crt ${D}${CA_CERTIFICATES_PV_DIR}/
}

FILES:${PN} = "${CA_CERTIFICATES_PV_DIR}"
