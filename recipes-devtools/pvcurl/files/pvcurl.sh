#!/bin/sh
# curl.sh - Hardened BusyBox/Pantavisor curl replacement
# No dependencies on 'timeout' or 'wc'

# --- 1. PROBE HANDLERS ---
# Fixes pvcontrol feature detection hangs/errors
case "$1" in
    --help*)
        echo "Usage: curl.sh --unix-socket [SOCK] [URL]"
        echo "Options: -X, -H, --data, --upload-file, -s, -i, -w, --connect-timeout"
        exit 0 ;;
    --version)
        echo "curl.sh 1.0 (nc wrapper)"
        exit 0 ;;
esac

set -e

# --- 2. DEFAULTS ---
METHOD="GET"
DATA=""
UPLOAD_FILE=""
SOCKET=""
URL=""
HEADERS=""
SHOW_HEADERS=false
SILENT=false
WRITE_OUT=""
CONNECT_TIMEOUT=5

# Ensure basic path is available
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

log_err() { [ "$SILENT" = false ] && echo "$@" >&2; }

# --- 3. ARGUMENT PARSER ---
while [ "$#" -gt 0 ]; do
    case "$1" in
        -X) METHOD="$2"; shift 2 ;;
        -H|--header) HEADERS="${HEADERS}${2}\r\n"; shift 2 ;;
        --data|--data-binary) DATA="$2"; shift 2 ;;
        --upload-file) UPLOAD_FILE="$2"; shift 2 ;;
        --unix-socket) SOCKET="$2"; shift 2 ;;
        --connect-timeout) CONNECT_TIMEOUT="$2"; shift 2 ;;
        --max-time) shift 2 ;; # Ignore to prevent background process hangs
        -s|--silent) SILENT=true; shift ;;
        -i|--include) SHOW_HEADERS=true; shift ;;
        -w|--write-out) WRITE_OUT="$2"; shift 2 ;;
        --no-progress-meter) shift ;; # Ignore curl noise
        *) 
            case "$1" in -*) log_err "Error: Unrecognized option '$1'"; exit 1 ;; esac
            if [ -z "$URL" ]; then
                # Strip http://localhost or http:// prefixes
                URL=$(echo "$1" | sed -e 's|^http://localhost||' -e 's|^http://||')
            fi
            shift ;;
    esac
done

URL="${URL:-/}"
[ "${URL#/}" = "$URL" ] && URL="/$URL"

if [ -z "$SOCKET" ]; then
    log_err "Error: --unix-socket is required."
    exit 1
fi

# Set default Content-Type if not provided
if ! echo "$HEADERS" | grep -qi "Content-Type:"; then
    HEADERS="${HEADERS}Content-Type: application/json\r\n"
fi

# --- 4. REQUEST ASSEMBLY ---
# We build the request in a file to handle binary data and calc lengths
{
    printf "%s %s HTTP/1.0\r\n" "$METHOD" "$URL"
    printf "Host: localhost\r\n"
    printf "%b" "$HEADERS"
    
    if [ -n "$UPLOAD_FILE" ]; then
        # Try stat for file size, fallback to ls -l if stat is missing
        if ! FILE_SIZE=$(stat -c%s "$UPLOAD_FILE" 2>/dev/null); then
            FILE_SIZE=$(ls -l "$UPLOAD_FILE" | awk '{print $5}')
        fi
        printf "Content-Length: %s\r\n\r\n" "$FILE_SIZE"
        cat "$UPLOAD_FILE"
    elif [ -n "$DATA" ]; then
        # Native shell string length (replaces wc -c)
        printf "Content-Length: %s\r\n\r\n" "${#DATA}"
        printf "%s" "$DATA"
    else
        printf "Content-Length: 0\r\n\r\n"
    fi
} > /tmp/http_req

# --- 5. EXECUTION ---
# Synchronous execution to prevent zombie/orphan hangs
# nc -N ensures it sends FIN after stdin is exhausted
NC_EXIT=0
nc -N -w "$CONNECT_TIMEOUT" -U "$SOCKET" < /tmp/http_req > /tmp/http_res 2>/tmp/nc_err || NC_EXIT=$?

if [ "$NC_EXIT" -ne 0 ]; then
    [ "$SILENT" = false ] && [ -f /tmp/nc_err ] && cat /tmp/nc_err >&2
    rm -f /tmp/http_req /tmp/http_res /tmp/nc_err
    exit "$NC_EXIT"
fi

# --- 6. OUTPUT HANDLING ---
if [ "$SHOW_HEADERS" = true ]; then
    cat /tmp/http_res
else
    # Strip headers: delete everything from line 1 until the first empty line
    sed '1,/^\r\{0,1\}$/d' /tmp/http_res
fi

# Handle --write-out "%{http_code}"
if [ -n "$WRITE_OUT" ]; then
    HTTP_STATUS_LINE=$(head -n 1 /tmp/http_res)
    HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
    OUT_STR=$(echo "$WRITE_OUT" | sed "s/%{http_code}/${HTTP_CODE:-000}/g")
    printf "%b" "$OUT_STR"
fi

# Cleanup
rm -f /tmp/http_req /tmp/http_res /tmp/nc_err
