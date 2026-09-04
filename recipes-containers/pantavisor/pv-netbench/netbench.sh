#!/bin/sh
#
# netbench: count Hub traffic on the host uplink with nftables counters and
# publish the totals as device-meta. Object downloads go to another host and
# are not counted.

set -u

# Lowest to highest precedence; a real environment variable wins.
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

devmeta() {
	if ! curl -s --max-time 5 --unix-socket "$PVCTRL" \
		-X PUT -H 'Content-Type: text/plain' --data-binary "$2" \
		"http://localhost/device-meta/$1" >/dev/null 2>&1; then
		log "device-meta PUT $1 failed"
	fi
}

# Hub IPv4: first the established connection in /proc/net/tcp (ports 443,
# 8883, 1883; rem_address is little-endian hex), then device-meta, then DNS.
resolve_ips() {
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

counter_bytes() {
	nft list counter inet "$TABLE" "$1" 2>/dev/null | grep -oE 'bytes [0-9]+' | awk '{print $2}'
}

cleanup() { nft delete table inet "$TABLE" 2>/dev/null; }
trap cleanup EXIT INT TERM

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
