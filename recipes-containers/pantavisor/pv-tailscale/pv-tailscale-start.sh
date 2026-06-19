#!/bin/sh

# Bring up tailscaled and join the tailnet. Login material (auth key, hostname,
# extra flags) is provisioned through Pantavisor user-meta — written by pantahub
# after the device registers — so no secret is baked into the read-only squashfs
# image. Values fall back to the container Env (config.json) when meta is absent.

STATE_DIR=${TS_STATE_DIR:-/var/lib/tailscale}
SOCK=${TS_SOCKET:-/var/run/tailscale/tailscaled.sock}
TUN=${TS_TUN:-tailscale0}

mkdir -p "$STATE_DIR" "$(dirname "$SOCK")"

# Read the first line of $1, trimmed, into the variable named $2 (empty if the
# file is missing/empty). Uses the shell builtin `read` rather than `cat|xargs`:
# busybox here has no xargs applet (matches pv-avahi-start.sh).
read_meta_field() {
	eval "$2=''"
	[ -r "$1" ] && read -r "$2" < "$1"
	return 0
}

# The kernel has CONFIG_TUN=y (tailscale-iptables.cfg), but the /dev/net/tun
# node may not have been materialised inside the container yet. Create it so
# tailscaled can open the tun; fall back to userspace networking if we can't.
ensure_tun() {
	[ -c /dev/net/tun ] && return 0
	mkdir -p /dev/net
	mknod /dev/net/tun c 10 200 2>/dev/null && chmod 600 /dev/net/tun 2>/dev/null
	[ -c /dev/net/tun ]
}

if [ "${TS_USERSPACE}" = "true" ] || ! ensure_tun; then
	TUN_ARG="--tun=userspace-networking"
else
	TUN_ARG="--tun=${TUN}"
fi

# shellcheck disable=SC2086
tailscaled \
	--state="$STATE_DIR/tailscaled.state" \
	--statedir="$STATE_DIR" \
	--socket="$SOCK" \
	$TUN_ARG &
tsd=$!

# Wait for the control socket before issuing `tailscale up`.
i=0
while [ ! -S "$SOCK" ] && [ $i -lt 30 ]; do
	sleep 1
	i=$((i + 1))
done

# Resolve provisioning values: prefer Pantavisor user-meta, fall back to Env.
read_login_meta() {
	read_meta_field /pantavisor/user-meta/tailscale-authkey authkey
	[ -n "$authkey" ] || authkey="${TS_AUTHKEY}"

	read_meta_field /pantavisor/user-meta/tailscale-hostname tshostname
	[ -n "$tshostname" ] || read_meta_field /pantavisor/device-nick tshostname
	[ -n "$tshostname" ] || tshostname="${TS_HOSTNAME:-pantavisor}"

	read_meta_field /pantavisor/user-meta/tailscale-extra-args extra
	[ -n "$extra" ] || extra="${TS_EXTRA_ARGS}"
}

up() {
	set -- --socket="$SOCK" up --hostname="$tshostname" --reset
	[ -n "$authkey" ] && set -- "$@" --authkey="$authkey"
	# shellcheck disable=SC2086
	tailscale "$@" $extra
}

# Try once at boot if a key is already present; otherwise leave tailscaled
# running so a key can be provisioned (or `tailscale up` run) later.
read_login_meta
last=""
if [ -n "$authkey" ]; then
	up && last="$authkey"
fi

# user-meta is written asynchronously by Pantavisor (e.g. an operator sets the
# key after the device claims). Re-run `up` when the key appears or changes,
# mirroring pv-avahi-start.sh's metadata re-publish loop.
# ponytail: 5s poll; switch to inotify on /pantavisor only if this proves slow.
while kill -0 "$tsd" 2>/dev/null; do
	sleep 5
	read_login_meta
	if [ -n "$authkey" ] && [ "$authkey" != "$last" ]; then
		up && last="$authkey"
	fi
done
wait "$tsd"
