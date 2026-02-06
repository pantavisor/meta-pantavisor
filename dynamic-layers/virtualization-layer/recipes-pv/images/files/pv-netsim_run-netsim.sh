#!/bin/sh

usage() {
	echo ""
	echo "Usage: $0 <verbose>"
	echo ""
}

wait_for_status() {
    local cmd="$1"
    local status="$2"
    local timeout="$3"
    
    local counter=0
    while [ $counter -lt $timeout ]; do
		sh -c "$cmd"
        eval "$cmd"
        if [ "$?" = "$status" ]; then
            return 0
        else
            sleep 1
            counter=$((counter+1))
        fi
    done
    return 1
}

start_hwsim() {

	wait_for_status "iw dev wlan0 info" 0 5 > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Error: Could not setup wlan0 interface for netsim"
		exit 1
	fi

	ip addr add 192.168.200.1/24 dev wlan0
	dnsmasq -i wlan0 --dhcp-range=192.168.200.128,192.168.200.200 &
	hostapd /etc/hostapd/hostapd.conf &
}

verbose=${VERBOSE}

if [ "$verbose" = "true" ]; then set -x; fi

if [ -z "$verbose" ]; then
	echo "Error: missing arguments"
	usage
fi

start_hwsim

while true; do sleep 1; done
