
PANTAVISOR_FEATURES ??= " \
	dm-crypt \
	dm-verity \
	autogrow \
	runc \
	tailscale \
	debug \
	rngdaemon \
	pvcontrol \
	xconnect \
	xconnect-dbus-systembus \
	container-mdev \
"

# Available, off by default:
# PANTAVISOR_FEATURES:append = " lxc-next"
# PANTAVISOR_FEATURES:append = " console-logging"
# PM wakelocks + autosleep
# PANTAVISOR_FEATURES:append = " wakelocks"


