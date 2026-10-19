
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
	lxc-stable \
"

# Available, off by default:
# PANTAVISOR_FEATURES:append = " console-logging"
# PM wakelocks + autosleep
# PANTAVISOR_FEATURES:append = " wakelocks"

# LXC runtime: lxc-stable (LXC 6, default), lxc-next (LXC 7) or
# lxc-deprecated (LXC 3). When several are set, lxc-deprecated wins over
# lxc-next, and lxc-next wins over lxc-stable. With no lxc-* feature set
# at all, lxc-stable is used.
# PANTAVISOR_FEATURES:append = " lxc-next"
# PANTAVISOR_FEATURES:append = " lxc-deprecated"
def pv_lxc_recipe(d):
    features = (d.getVar('PANTAVISOR_FEATURES') or '').split()
    if 'lxc-deprecated' in features:
        return 'lxc-pv'
    if 'lxc-next' in features:
        return 'lxc7-pv'
    return 'lxc6-pv'

PV_LXC_RECIPE = "${@pv_lxc_recipe(d)}"

# cgroup layout requested from Pantavisor (PV_SYSTEM_CGROUP_VERSION): 1, 2 or
# auto. lxc-deprecated (LXC 3) gets 1, lxc-next (LXC 7, no cgroup v1) gets 2,
# lxc-stable gets auto. Override per machine with
# PANTAVISOR_CGROUP_VERSION:<machine> = "1", or for everything with
# PANTAVISOR_CONFIG[PV_SYSTEM_CGROUP_VERSION] = "1".
def pv_cgroup_version(d):
    lxc = pv_lxc_recipe(d)
    if lxc == 'lxc-pv':
        return '1'
    if lxc == 'lxc7-pv':
        return '2'
    return 'auto'

PANTAVISOR_CGROUP_VERSION ??= "${@pv_cgroup_version(d)}"

