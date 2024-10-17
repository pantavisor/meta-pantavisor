EXTRA_OECONF += " \
	--without-nistbeacon \
	--without-pkcs11 \
	--without-rtlsdr \
	"

PACKAGECONFIG:remove = "libjitterentropy"
