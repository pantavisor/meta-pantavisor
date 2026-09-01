#!/bin/sh
#
# netbench: measure how much network a device spends talking to Pantahub, and
# publish the answer as device-meta so it shows up on the Hub for the device.
#
# Runs as a platform-group container that keeps the host network namespace, so
# it sees the real uplink both transports use:
#   - native Pantavisor remote (control.remote=1) talks from the host netns;
#   - pvsm (control.remote=0) talks from a container that also keeps host net;
# either way the bytes cross the same interface to the same Hub IP, so counting
# there is a fair, config-agnostic measurement.
#
# Counting uses nftables counters matched on the Hub's IP at the prerouting and
# postrouting hooks, so it catches traffic whether it originated on the host or
# was forwarded from another container. Object-blob downloads go to a different
# host and are NOT counted: this measures the signalling plane, which is what
# differs between poll and push.
#
# The headline is a cumulative average projected to per-day, honest across the
# poll interval and converging the longer it runs.

set -u

# Config, lowest to highest precedence. /etc/netbench.env is generated at image
# build time with the mode for this variant; /opt/data allows a per-device
# override without rebuilding; a real environment variable wins over all.
for f in /etc/netbench.env /opt/data/netbench.env /var/netbench/.env; do
	[ -f "$f" ] && . "$f"
done

HUB_HOST="${PH_HUB_HOST:-api.pantahub.com}"
IFACE="${PH_BENCH_IFACE:-wlan0}"
MODE="${PH_BENCH_MODE:-unknown}"
INTERVAL="${PH_BENCH_INTERVAL:-120}"
PVCTRL="${PANTAVISOR_CTRL_SOCKET:-/pantavisor/pv-ctrl}"
PVCGI="${PH_PV_CGI:-http://127.0.0.1:12368/cgi-bin}"
TABLE="netbench"

log() { echo "netbench: $*"; }

devmeta() {  # KEY VALUE -> PUT /device-meta/<key> over the pv-ctrl socket
	if ! curl -s --max-time 5 --unix-socket "$PVCTRL" \
		-X PUT -H 'Content-Type: text/plain' --data-binary "$2" \
		"http://localhost/device-meta/$1" >/dev/null 2>&1; then
		log "device-meta PUT $1 failed"
	fi
}

# nf_tables ships as a kernel module and nothing on the host loads it at boot,
# so nft would fail with "Protocol not supported". This container declares
# nf_tables as an OPTIONAL driver (PV_DRIVERS_OPTIONAL) that the bsp defines
# (bsp/drivers.json alias -> module); pantavisor modprobes it best-effort
# before starting this container, so nothing needs to be loaded from in here.
# If it is unavailable the nft guard below still degrades to empty reports.

# Resolve the Hub host to its IPv4 address(es). Tries dig, then busybox
# nslookup (parsing only the answer section after "Name:", so the DNS server's
# own address is not mistaken for an answer).
resolve_ips() {
	# Preferred source: the Hub IP pantavisor is actually connected to, read
	# from /proc/net/tcp. The container keeps the host net namespace, so this
	# lists the host's real sockets, and pantavisor holds a persistent
	# connection to the Hub even while idle. This needs no resolver (the
	# container has neither /etc/resolv.conf nor nslookup) and no CGI (which
	# binds the LAN address, not loopback). rem_address is <hexip>:<hexport>
	# with the IP in reversed byte order, so 96A20F33 -> 51.15.162.150; ports
	# of interest are 443 (01BB), 8883 (22B3) and 1883 (075B). The whole match
	# and hex->dotted conversion is done in awk on purpose: this container's
	# busybox is a minimal build with no cut/sort applets, so shell-side hex
	# slicing would fail ("cut: not found" -> empty -> arithmetic error). awk is
	# always present (used just above), self-contains the parse, and exits on
	# the first Hub connection.
	ip=$(awk '
		function h2d(s,   n,i,c){ n=0; for(i=1;i<=length(s);i++){ c=index("0123456789ABCDEF",toupper(substr(s,i,1)))-1; if(c<0) return -1; n=n*16+c } return n }
		$4=="01" {
			split($3, a, ":")
			if (a[2]!="01BB" && a[2]!="22B3" && a[2]!="075B") next
			if (length(a[1])!=8) next
			o=h2d(substr(a[1],7,2)) "." h2d(substr(a[1],5,2)) "." h2d(substr(a[1],3,2)) "." h2d(substr(a[1],1,2))
			if (o ~ /^(10\.|127\.|0\.|169\.254\.|192\.168\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[01]\.|255\.)/) next
			print o; exit
		}' /proc/net/tcp 2>/dev/null)
	if [ -n "$ip" ]; then echo "$ip"; return 0; fi
	# Fallbacks: the pvr CGI's merged device-meta (has pantahub.address), then
	# DNS. Both usually fail in this container; /proc above is the real path.
	# grep + shell parameter expansion only (no cut/sed in this busybox).
	addr="$(curl -s --max-time 5 "$PVCGI/device-meta" 2>/dev/null \
		| grep -oE '"pantahub\.address":"[0-9.]+' | head -1)"
	addr="${addr##*\"}"
	case "$addr" in
		[0-9]*.[0-9]*.[0-9]*.[0-9]*) echo "$addr"; return 0 ;;
	esac
	if command -v dig >/dev/null 2>&1; then
		dig +short "$HUB_HOST" A 2>/dev/null | grep -E '^[0-9.]+$' && return 0
	fi
	nslookup "$HUB_HOST" 2>/dev/null | awk '
		/^Name:/ { ans = 1 }
		ans && /Address/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $i }
	'
}

setup_counters() {
	nft add table inet "$TABLE" 2>/dev/null
	nft add counter inet "$TABLE" hub_rx 2>/dev/null
	nft add counter inet "$TABLE" hub_tx 2>/dev/null
	nft add chain inet "$TABLE" pre  "{ type filter hook prerouting priority -300 ; }" 2>/dev/null
	nft add chain inet "$TABLE" post "{ type filter hook postrouting priority -300 ; }" 2>/dev/null
	for ip in $HUB_IPS; do
		nft add rule inet "$TABLE" pre  iifname "$IFACE" ip saddr "$ip" counter name hub_rx 2>/dev/null
		nft add rule inet "$TABLE" post oifname "$IFACE" ip daddr "$ip" counter name hub_tx 2>/dev/null
	done
}

counter_bytes() {  # counter-name -> bytes
	nft list counter inet "$TABLE" "$1" 2>/dev/null | grep -oE 'bytes [0-9]+' | awk '{print $2}'
}

cleanup() { nft delete table inet "$TABLE" 2>/dev/null; }
trap cleanup EXIT INT TERM

# Publish identity immediately, before resolving, so the device shows netbench
# is alive even while it is still waiting for the Hub address.
devmeta bench.mode "$MODE"
devmeta bench.hub.host "$HUB_HOST"
devmeta bench.iface "$IFACE"
devmeta bench.status "resolving"

HUB_IPS="$(resolve_ips | sort -u | tr '\n' ' ')"
while [ -z "$HUB_IPS" ]; do
	log "cannot resolve $HUB_HOST -- retrying in 15s"
	sleep 15
	HUB_IPS="$(resolve_ips | sort -u | tr '\n' ' ')"
done
log "measuring $HUB_HOST ($HUB_IPS) on $IFACE, mode=$MODE, report every ${INTERVAL}s"

setup_counters
[ -z "$(counter_bytes hub_rx)" ] && log "WARNING: nft counters unavailable (kernel/caps?) -- reports will be empty"

START="$(date +%s)"
devmeta bench.hub.ip "$(echo "$HUB_IPS" | tr ' ' ',' | sed 's/,$//')"
devmeta bench.status "measuring"

first=1
while true; do
	# A short first interval surfaces a data point in ~20s; steady state then
	# reports every INTERVAL. The per-day projection converges as uptime grows.
	if [ "$first" = 1 ]; then sleep 20; first=0; else sleep "$INTERVAL"; fi

	now="$(date +%s)"
	up=$((now - START))
	[ "$up" -lt 1 ] && up=1

	rx="$(counter_bytes hub_rx)"; : "${rx:=0}"
	tx="$(counter_bytes hub_tx)"; : "${tx:=0}"
	total=$((rx + tx))

	per_hour="$(awk -v t="$total" -v u="$up" 'BEGIN{printf "%.0f", t*3600/u}')"
	per_day="$(awk -v t="$total" -v u="$up" 'BEGIN{printf "%.0f", t*86400/u}')"

	devmeta bench.net.rx_bytes "$rx"
	devmeta bench.net.tx_bytes "$tx"
	devmeta bench.net.total_bytes "$total"
	devmeta bench.net.uptime_seconds "$up"
	devmeta bench.net.avg_per_hour_bytes "$per_hour"
	devmeta bench.net.avg_per_day_bytes "$per_day"
	devmeta bench.updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

	log "up=${up}s rx=${rx} tx=${tx} total=${total}B ~/day=${per_day}B mode=${MODE}"
done
