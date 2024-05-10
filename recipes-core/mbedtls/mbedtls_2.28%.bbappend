FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

OVERRIDES =. "${DISTRO_CODENAME}:"

PATCHES ?= ""

PATCHES:kirkstone += " \
	file://0001-make-pk_wrap.c-support-validating-ANSI-X9.62-FIPS-18.patch \
	"

PATCHES:scarthgap += " \
	file://0001-make-pk_wrap.c-support-validating-ANSI-X9.62-FIPS-18.scarthgap.patch \
	"

SRC_URI += " \
	${PATCHES} \
	"

TARGET_CFLAGS += " \
        -I${S}/configs \
        -DMBEDTLS_CONFIG_FILE='<config-mini-tls1_1.h>' \
        -DMBEDTLS_SSL_PROTO_TLS1_2 \
        -DMBEDTLS_SHA512_C \
        -DMBEDTLS_SSL_SERVER_NAME_INDICATION \
        -DMBEDTLS_REMOVE_ARC4_CIPHERSUITES \
        -DMBEDTLS_REMOVE_3DES_CIPHERSUITES \
        -DMBEDTLS_ECP_NIST_OPTIM \
        -DMBEDTLS_ECP_C \
        -DMBEDTLS_ECDSA_C \
        -DMBEDTLS_PK_PARSE_EC_EXTENDED \
        -DMBEDTLS_ECP_DP_SECP192R1_ENABLED \
        -DMBEDTLS_ECP_DP_SECP224R1_ENABLED \
        -DMBEDTLS_ECP_DP_SECP256R1_ENABLED \
        -DMBEDTLS_ECP_DP_SECP384R1_ENABLED \
        -DMBEDTLS_ECP_DP_SECP521R1_ENABLED \
        -DMBEDTLS_ECP_DP_SECP192K1_ENABLED \
        -DMBEDTLS_ECP_DP_SECP224K1_ENABLED \
        -DMBEDTLS_ECP_DP_SECP256K1_ENABLED \
        -DMBEDTLS_ECP_DP_BP256R1_ENABLED \
        -DMBEDTLS_ECP_DP_BP384R1_ENABLED \
        -DMBEDTLS_ECP_DP_BP512R1_ENABLED \
        -DMBEDTLS_ECP_DP_CURVE25519_ENABLED \
        -DMBEDTLS_ECP_DP_CURVE448_ENABLED \
        -DMBEDTLS_DEBUG_C \
"

