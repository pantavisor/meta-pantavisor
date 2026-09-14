#!/bin/sh
# Drives one GPIO line high or low - used to pulse a DUT's reset/recovery pin
# from the lab controller. Wraps libgpiod-tools' gpioset (v2 CLI: chip via -c,
# "line=value" pairs) so callers don't need to know its syntax.
set -eu

usage() {
    echo "usage: $(basename "$0") <chip> <line> <high|low|1|0>" >&2
    exit 1
}

[ $# -eq 3 ] || usage

chip="$1"
line="$2"

case "$3" in
    high|1) value=1 ;;
    low|0)  value=0 ;;
    *) usage ;;
esac

exec gpioset -c "$chip" "$line=$value"
