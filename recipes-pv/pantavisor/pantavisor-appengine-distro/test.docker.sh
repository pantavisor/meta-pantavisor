#!/bin/bash

usage() {
	echo ""
	echo "Usage: $0 [options] <command> [arguments]"
	echo "Run and create Pantavisor tests"
	echo ""
	echo "Options:"
	echo "  -h, --help    Display this help message"
	echo "  -v, --verbose Print debug logs"
	echo "  -d, --dir         Use directory as pvtest source directory (or PVTEST_DIR env)"
	echo ""
	echo "Commands:"
	echo "  add <scope/category/name>  Create a new test"
	echo "  install-deps               Install dependencies (and docker)"
	echo "  install-docker             Install docker"
	echo "  ls                         List all tests"
	echo "  run [path]                 Run one to many tests"
	echo ""
	echo "Arguments for 'run' command:"
	echo "  -i, --interactive     Run the test interactively for debugging"
	echo "  -m, --manual          Avoid starting Pantavisor for debugging"
	echo "  -n, --netsim          Use the network simulator (experimental)"
	echo "  -o, --overwrite       Create or overwrite the test output"
	echo "  -p, --parallel N      Number of slots: the cap on concurrent appengine"
	echo "                        containers a single tester keeps busy (default: 1)."
	echo "  --devices FILE        Run against a single real device instead of a Docker"
	echo "                        appengine pool. Incompatible with -p>1, -m, -n, -V (but"
	echo "                        -i IS supported: opens the tester console on the device)."
	echo "                        FILE is a 'key=value' stanza (exactly one device):"
	echo "                        name=, ip=, exec=, tty=, baud= (optional, default 115200)."
	echo "                        See docs/testing/device-target.md."
	echo "  -r, --retry N         Retry failed tests up to N times (default: 0)"
	echo "      --fail-on-skip    Exit non-zero if any test is SKIPPED (e.g. no matching runner)"
	echo "      --fail-on-skip-field  Treat a test.json \"skip\":\"true\" as an ERROR (use on CI/master)"
	echo "  -V, --valgrind        Run Pantavisor with valgrind"
	echo "  -w, --work PATH       Set workspace path for logs/storage (default: mktemp)"
	echo ""
	echo "Path selectors for 'run' command:"
	echo "  (none)                         Run all tests"
	echo "  local                          Run all local tests"
	echo "  local/lifecycle                Run all lifecycle tests"
	echo "  local/lifecycle/seq-non-reboot-updates  Run a specific test"
	echo ""
	echo "Environments:"
	echo "  NETSIM_PATH      Path to docker load for netsim container"
	echo "  TESTER_PATH      Path to docker load for tester container"
	echo "  APPENGINE_PATH   Path to docker load for appengine container"
	echo "  PVTEST_DIR       Directory to pvtest sources to run"
	echo ""
	echo "Target override environments (unset = local appengine container, set = external target):"
	echo "  PVTEST_EXEC      Command prefix to run pvcontrol/pventer on the target."
	echo "                     Unset (default): test.docker.sh starts a pantavisor-appengine"
	echo "                     container and sets this to \"ssh _pv_@<container>\" (dropbear-pv)."
	echo "                     Real device: \"ssh root@<ip>\" or \"ssh -p <port> user@<ip>\""
	echo "  PVTEST_HOST      Hostname or IP for pvr/HTTP calls to the target (default: localhost)."
	echo "                     Set automatically to the appengine container name when unset."
	echo "  PVTEST_DEVICE    Device type tag used by the test filter (default: appengine)."
	echo "                     Tests with a non-empty \"devices\" array only run when this"
	echo "                     value matches one of the listed entries."
	echo ""
}

pvtest_log() { local level=$1; shift; printf '[pvtest] %s %s -- [test.docker.sh]: %s\n' "$(date +%s)" "$level" "$*"; }

# Runner-type = (normalized required-config, needs-claim); see docs/testing/device-target.md.

# Normalize required-config: drop PV_LXC_LOG_LEVEL, sort tokens for a stable signature.
normalize_reqcfg() {
	local kv out=()
	for kv in $1; do
		[ -n "$kv" ] || continue
		case "$kv" in PV_LXC_LOG_LEVEL=*) continue ;; esac
		out+=("$kv")
	done
	[ ${#out[@]} -eq 0 ] && return 0
	printf '%s\n' "${out[@]}" | sort | tr '\n' ' ' | sed 's/ *$//'
}

list_tests() {
	printf "%-50s %-10s\n" "test" "description"
	printf "%-50s %-10s\n" "====" "==========="
	find $test_dir/ -name "test.json" | sort | while read -r json_path; do
		test_id=$(echo "$json_path" | sed 's|^\./||; s|/test\.json$||')
		description=$(jq -r '.description' "$json_path")
		printf "%-50s %-10s\n" "$test_id" "$description"
	done
}

add_test() {
	local test_path=

	if [ -z "$1" ]; then
		pvtest_log ERROR "Missing test path (scope/category/name)"
		usage
		exit 1
	fi
	test_path="$1"
	shift

	while [ $# -gt 0 ]; do
		case "$1" in
			*)
				pvtest_log ERROR "Unknown argument: $1"
				usage
				exit 1
				;;
		esac
	done

	local full_path="$test_dir/$test_path"
	local scope=$(echo "$test_path" | cut -d'/' -f1)

	if [ -e "$full_path" ]; then
		pvtest_log ERROR "'$full_path' already exists"
		exit 1
	fi

	local common_path="$test_dir/$scope/common"
	if [ ! -d "$common_path" ]; then
		pvtest_log ERROR "common directory '$common_path' missing"
		exit 1
	fi

	mkdir -p "$full_path/resources"
	cp "$common_path/templates/template.test.json" "$full_path/test.json"
	cp "$common_path/templates/template.test" "$full_path/resources/test"
	chmod +x "$full_path/resources/test"
	cp "$common_path/templates/template.ready" "$full_path/resources/ready"
	chmod +x "$full_path/resources/ready"

	pvtest_log INFO "New test created at: $full_path"
}

install_docker() {

	# install app engine docker containers
	NETSIM_PATH=${NETSIM_PATH:-"pantavisor-appengine-netsim-docker.tar"}
	if [ -f "$NETSIM_PATH" ]; then
		docker load -i "$NETSIM_PATH"
		docker image inspect --format '{{.Id}}' pantavisor-appengine-netsim \
			> "$(dirname "$0")/netsim.imgid" 2>/dev/null || true
	fi
	TESTER_PATH=${TESTER_PATH:-"pantavisor-appengine-tester-docker.tar"}
	if [ -f "$TESTER_PATH" ]; then
		docker load -i "$TESTER_PATH"
		docker image inspect --format '{{.Id}}' pantavisor-appengine-tester \
			> "$(dirname "$0")/tester.imgid" 2>/dev/null || true
	fi
	APPENGINE_PATH=${APPENGINE_PATH:-"pantavisor-appengine-docker.tar"}
	if [ -f "$APPENGINE_PATH" ]; then
		docker load -i "$APPENGINE_PATH"
	fi
}

install_deps() {
echo "This will install some packages in your system. Do you want to continue? [y/N]"
    if [[ "$CI_MODE" == "true" ]]; then
       answer="y"
    else
       read -n1 answer
    fi
    case "$answer" in
        y|Y)
            ;;
        *)
			exit 0
            ;;
    esac

	sudo -v

	# install and setup apt dependencies
	sudo apt update
	sudo apt install binfmt-support \
		docker.io \
		git \
		jq \
		iw \
		bc \
		linux-modules-`uname -r` \
		linux-modules-extra-`uname -r`
	sudo groupadd docker
	sudo usermod -aG docker $USER

	# install and setup qemu
	sudo apt remove qemu-user-static
	mkdir ~/bin
	wget https://pantavisor-ci.s3.amazonaws.com/qemu/1303841432/qemu-arm -O ~/bin/qemu-arm
	wget https://pantavisor-ci.s3.amazonaws.com/qemu/1303841432/qemu-aarch64 -O ~/bin/qemu-aarch64
	chmod +x ~/bin/qemu-arm
	chmod +x ~/bin/qemu-aarch64
	sudo update-binfmts --install qemu-arm ~/bin/qemu-arm --offset 0 --magic "\x7f\x45\x4c\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00" --mask "\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff" --fix-binary yes
	sudo update-binfmts --install qemu-aarch64 ~/bin/qemu-aarch64 --offset 0 --magic "\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00" --mask "\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff" --fix-binary yes

	install_docker

	pvtest_log INFO "Dependency installation complete"

	exit 0
}

wait_for_status() {
    local cmd="$1"
    local status="$2"
    local timeout="$3"

    local counter=0
    while [ $counter -lt $timeout ]; do
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

setup_network0() {
	# flock serializes inspect/create so concurrent callers don't race on docker network create.
	local lockfile=/tmp/pv_appengine.network0.lock
	exec {NET0_FD}>"$lockfile"
	flock "$NET0_FD"

	if ! docker network inspect test-appengine-net >/dev/null 2>&1; then
		docker network create --driver=bridge --opt com.docker.network.container_iface_prefix=lxcbrdock test-appengine-net >/dev/null 2>&1 || :
	fi

	eval "exec ${NET0_FD}>&-"
}

# Lowest free slot = lowest N with no other flock held on slot.N.lock (auto-released on exit/crash).
# Sets: slot, SLOT_LOCK_FD
allocate_slot() {
	slot=0
	while true; do
		local sf="/tmp/pv_appengine.slot.${slot}.lock"
		exec {SLOT_LOCK_FD}>"$sf"
		if flock -nx "$SLOT_LOCK_FD"; then
			return 0
		fi
		eval "exec ${SLOT_LOCK_FD}>&-"
		SLOT_LOCK_FD=
		slot=$((slot + 1))
	done
}

release_slot() {
	[ -z "$SLOT_LOCK_FD" ] && return
	eval "exec ${SLOT_LOCK_FD}>&-"
	SLOT_LOCK_FD=
}

setup_network() {
	local tester_name="${1:-pantavisor-tester}"
	local netsim_name="${2:-pantavisor-netsim}"
	sleep 1
	sudo -n modprobe -r mac80211_hwsim

	local before_phy=$(iw dev | grep -oP '(?<=phy#)\d+')
	sudo -n modprobe mac80211_hwsim radios=3
	local after_phy=$(iw dev | grep -oP '(?<=phy#)\d+')
	local new_phys=$(comm -13 <(echo "$before_phy" | sort) <(echo "$after_phy" | sort))

	wait_for_status "docker inspect -f '{{.State.Pid}}' $netsim_name" 0 5 > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		pvtest_log ERROR "$netsim_name not responding"
		exit 1
	fi
	local pid=$(docker inspect -f '{{.State.Pid}}' "$netsim_name")

	local ap_phy=$(echo "$new_phys" | sed -n '1p')
	sudo -n iw phy "phy$ap_phy" set netns "$pid"

	wait_for_status "docker inspect -f '{{.State.Pid}}' $tester_name" 0 5 > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		pvtest_log ERROR "$tester_name not responding"
		exit 1
	fi
	local pid=$(docker inspect -f '{{.State.Pid}}' "$tester_name")

	local cl_phy=$(echo "$new_phys" | sed -n '2p')
	sudo -n iw phy "phy$cl_phy" set netns "$pid"
}

teardown_network() {
	sudo -n modprobe -r mac80211_hwsim
}

# Slot-pool helpers: retype_service subshell snapshots run_test's locals (work_path, valgrind, pvtest_pubkey, slot, USER).

# Boot appengine $1 with required-config $2 (detached); tester's init_device awaits readiness.
_boot_appengine() {
	local ae="$1" cfg="$2"
	local _cfg_env=() _kv
	for _kv in $cfg; do _cfg_env+=(-e "$_kv"); done
	mkdir -p "$work_path/storage/$ae"
	local ae_valgrind_args=()
	if [ "$valgrind" = "true" ]; then
		mkdir -p "$work_path/valgrind/$ae"
		ae_valgrind_args=(-v "$work_path/valgrind/$ae":/tmp/valgrind)
	fi
	touch "$work_path/appengine-${ae}.log"
	if ! docker run \
		--name "$ae" \
		--net=test-appengine-net \
		-d \
		--rm \
		--cgroupns host \
		--cap-add NET_ADMIN \
		--cap-add SYS_ADMIN \
		--cap-add SYS_PTRACE \
		--cap-add MKNOD \
		--device /dev/kmsg \
		--device /dev/hwrng \
		--device /dev/loop-control \
		--device-cgroup-rule 'b 7:* rmw' \
		--security-opt apparmor=unconfined \
		--security-opt seccomp=unconfined \
		--volume "/sys/fs":"/sys/fs" \
		--mount type=tmpfs,target="/usr/lib/lxc/rootfs" \
		--mount type=tmpfs,target="/volumes" \
		--mount type=tmpfs,target="/configs" \
		-v "$work_path/storage/$ae":/var/pantavisor/storage \
		"${ae_valgrind_args[@]}" \
		-e VALGRIND="$valgrind" \
		-e PV_DEBUG_SSH=1 \
		-e PV_DEBUG_SSH_AUTHORIZED_KEYS="pvtest-authorized_keys" \
		-e PV_DEBUG_SSH_PUBKEY="$pvtest_pubkey" \
		-e PV_LOG_SERVER_OUTPUTS="filetree,stdout_direct" \
		"${_cfg_env[@]}" \
		pantavisor-appengine \
			/usr/bin/pv-appengine -c "ph_metadata.devmeta.interval=15" > /dev/null; then
		return 1
	fi
	pvtest_log DEBUG "started appengine $ae (cfg=[${cfg:-<none>}])"
	docker logs -f "$ae" 2>/dev/null \
		| while IFS= read -r _pv_line; do printf '[%s] %s\n' "$ae" "$_pv_line"; done \
		>> "$work_path/appengine-${ae}.log" &
	echo $! > "$work_path/.logpid.$ae"
	return 0
}

# Stop appengine container $1: wait briefly for a graceful exit (the tester has
# already powered it off), force-stop if still running, kill its log tail.
_stop_appengine() {
	local ae="$1"
	local _grace=30 _elapsed=0 _status=
	while _status=$(docker inspect -f '{{.State.Status}}' "$ae" 2>/dev/null) \
	      && [ "$_status" = "running" ] && [ "$_elapsed" -lt "$_grace" ]; do
		sleep 1
		_elapsed=$((_elapsed + 1))
	done
	if [ "${_status:-}" = "running" ]; then
		docker stop --time 5 "$ae" > /dev/null 2>&1 || true
	fi
	if [ -f "$work_path/.logpid.$ae" ]; then
		kill "$(cat "$work_path/.logpid.$ae")" 2>/dev/null || true
		rm -f "$work_path/.logpid.$ae"
	fi
}

# --- Device-target helpers (real hardware, --devices FILE) ---
# Unlike an appengine container, a device is fixed (no boot/re-type/env-injection);
# these helpers parse a device manifest, lock each device against concurrent runs,
# and capture its serial console the same way _boot_appengine tails `docker logs -f`.

# flush a manifest stanza's accumulated key=value locals (name/ip/exec_cmd/tty/baud,
# read from the caller's scope via bash's dynamic scoping) into the _dev_* arrays.
_dev_flush_stanza() {
	[ -n "$name" ] || return 0
	if [ -z "$ip" ] || [ -z "$exec_cmd" ] || [ -z "$tty" ]; then
		pvtest_log ERROR "device '$name' in '$file' missing required field(s) (need name/ip/exec/tty)"
		return 1
	fi
	_dev_name+=("$name"); _dev_ip+=("$ip"); _dev_exec+=("$exec_cmd")
	_dev_tty+=("$tty"); _dev_baud+=("${baud:-115200}")
	name=; ip=; exec_cmd=; tty=; baud=
	return 0
}

# Parse a --devices manifest (blank-line separated key=value stanzas) into
# parallel arrays: _dev_name, _dev_ip, _dev_exec, _dev_tty, _dev_baud.
_parse_device_manifest() {
	local file="$1"
	local name= ip= exec_cmd= tty= baud= line
	_dev_name=(); _dev_ip=(); _dev_exec=(); _dev_tty=(); _dev_baud=()

	if [ ! -f "$file" ]; then
		pvtest_log ERROR "--devices file '$file' not found"
		return 1
	fi

	while IFS= read -r line || [ -n "$line" ]; do
		if [ -z "$line" ]; then
			_dev_flush_stanza || return 1
			continue
		fi
		case "$line" in
			name=*) name="${line#name=}" ;;
			ip=*) ip="${line#ip=}" ;;
			exec=*) exec_cmd="${line#exec=}" ;;
			tty=*) tty="${line#tty=}" ;;
			baud=*) baud="${line#baud=}" ;;
			\#*) ;;
			*) pvtest_log WARN "ignoring unrecognized line in '$file': $line" ;;
		esac
	done < "$file"
	_dev_flush_stanza || return 1

	if [ ${#_dev_name[@]} -eq 0 ]; then
		pvtest_log ERROR "no devices found in '$file'"
		return 1
	fi
	return 0
}

# Acquire an exclusive flock for device $1 (fails fast if another test.docker.sh
# run already holds it — a physical board can't be double-booked like an
# ephemeral Docker container). Releases nothing on failure other than its own fd.
_lock_device() {
	local name="$1" safe lockfile fd
	safe=$(printf '%s' "$name" | tr -c 'A-Za-z0-9_' '_')
	lockfile="/tmp/pvtest_device.${safe}.lock"
	exec {fd}>"$lockfile"
	if ! flock -n "$fd"; then
		eval "exec ${fd}>&-"
		pvtest_log ERROR "device '$name' is already locked by another test.docker.sh run"
		return 1
	fi
	eval "_dev_lock_fd_${safe}=${fd}"
	return 0
}

_unlock_device() {
	local name="$1" safe fd
	safe=$(printf '%s' "$name" | tr -c 'A-Za-z0-9_' '_')
	eval "fd=\${_dev_lock_fd_${safe}:-}"
	[ -n "$fd" ] || return 0
	eval "exec ${fd}>&-"
	eval "unset _dev_lock_fd_${safe}"
}

# Configure the tty and background a raw read into $work_path/appengine-<name>.log
# — same file-naming convention _boot_appengine uses for `docker logs -f`, so
# pvtest-run's log lookup needs no device-specific branching.
_start_device_capture() {
	local name="$1" tty="$2" baud="$3"
	touch "$work_path/appengine-${name}.log"
	if ! stty -F "$tty" "${baud:-115200}" raw -echo 2>/dev/null; then
		pvtest_log ERROR "failed to configure tty '$tty' for device '$name'"
		return 1
	fi
	cat "$tty" >> "$work_path/appengine-${name}.log" 2>/dev/null &
	echo $! > "$work_path/.logpid.$name"
	return 0
}

_stop_device_capture() {
	local name="$1"
	if [ -f "$work_path/.logpid.$name" ]; then
		kill "$(cat "$work_path/.logpid.$name")" 2>/dev/null || true
		rm -f "$work_path/.logpid.$name"
	fi
}

# Handle one re-type request id=$2 for slot=$3 to config=$4 (empty = teardown).
# Backgrounded by retype_service; per-slot current container in $1/state/slot<S>.ae.
_retype_handle() {
	local ctrl="$1" id="$2" S="$3" cfg="$4"
	local stf="$ctrl/state/slot${S}.ae" old ae gen
	old=$(cat "$stf" 2>/dev/null)
	[ -n "$old" ] && _stop_appengine "$old"
	: > "$stf"
	if [ -z "$cfg" ] || [ "$cfg" = "__none__" ]; then
		printf 'status=down\n' > "$ctrl/resp/.tmp.$id"
		mv "$ctrl/resp/.tmp.$id" "$ctrl/resp/$id"
		return 0
	fi
	gen=$( ( flock -x 8
		local g; g=$(( $(cat "$ctrl/state/gen" 2>/dev/null || echo 0) + 1 ))
		printf '%s' "$g" > "$ctrl/state/gen"; printf '%s' "$g"
	) 8>"$ctrl/state/gen.lock" )
	ae="pantavisor-appengine-${USER}-${slot}-w${S}-g${gen}"
	if _boot_appengine "$ae" "$cfg"; then
		printf '%s' "$ae" > "$stf"
		printf 'ae=%s\nstatus=ready\n' "$ae" > "$ctrl/resp/.tmp.$id"
	else
		printf 'status=failed\n' > "$ctrl/resp/.tmp.$id"
	fi
	mv "$ctrl/resp/.tmp.$id" "$ctrl/resp/$id"
}

# Background re-type service: handles $1/req/slot<S> requests until $1/stop appears,
# then tears down all slots.
retype_service() {
	local ctrl="$1"
	mkdir -p "$ctrl/req" "$ctrl/resp" "$ctrl/state"
	local req id S cfg
	while [ ! -e "$ctrl/stop" ]; do
		for req in "$ctrl"/req/slot*; do
			[ -e "$req" ] || continue
			id=$(basename "$req")
			S=$(sed -n 's/^slot=//p' "$req")
			cfg=$(sed -n 's/^cfg=//p' "$req")
			rm -f "$req"
			( _retype_handle "$ctrl" "$id" "$S" "$cfg" ) &
		done
		sleep 0.2
	done
	wait
	local st ae
	for st in "$ctrl"/state/slot*.ae; do
		[ -e "$st" ] || continue
		ae=$(cat "$st" 2>/dev/null)
		[ -n "$ae" ] && _stop_appengine "$ae"
	done
}

run_test() {
	local target_path=
	local overwrite="false"
	local interactive="false"
	local manual="false"
	local parallel=0
	local work_path=$(mktemp -d -t pv_appengine.XXXXXX)
	local netsim="false"
	local valgrind="false"
	local max_retries=0
	local fail_on_skip="false"
	local fail_on_skip_field="false"
	local devices_file=

	if [ -n "$1" ] && [ "$(printf '%s' "$1" | cut -c1)" != "-" ]; then
		target_path="$1"
		shift
	fi

	# "all" -> empty target, so discovery searches both local/ and remote/.
	[ "$target_path" = "all" ] && target_path=

	while [ $# -gt 0 ]; do
		case "$1" in
			-o|--overwrite)
				overwrite="true"
				shift
				;;
			-i|--interactive)
				interactive="true"
				shift
				;;
			-m|--manual)
				interactive="true"
				manual="true"
				shift
				;;
			-w|--work)
				work_path="$2"
				shift 2
				;;
			-n|--netsim)
				netsim="true"
				shift
				;;
			-V|--valgrind)
				valgrind="true"
				shift
				;;
			-p|--parallel)
				parallel="$2"
				shift 2
				;;
			--devices)
				devices_file="$2"
				shift 2
				;;
			-r|--retry)
				max_retries="$2"
				shift 2
				;;
			--fail-on-skip)
				fail_on_skip="true"
				shift
				;;
			--fail-on-skip-field)
				fail_on_skip_field="true"
				shift
				;;
			*)
				pvtest_log ERROR "Unknown argument: $1"
				usage
				exit 1
				;;
		esac
	done

	# -p caps concurrent runners; unset/<=0 defaults to 1 (serial).
	if [ "$parallel" -le 0 ] 2>/dev/null; then
		parallel=1
	fi

	if [ "$parallel" -gt 1 ] && { [ "$interactive" = "true" ] || [ "$manual" = "true" ]; }; then
		pvtest_log ERROR "-p is incompatible with -i and -m"
		usage
		exit 1
	fi

	if [ "$parallel" -gt 1 ] && [ "$overwrite" = "true" ]; then
		pvtest_log ERROR "-p is incompatible with -o"
		usage
		exit 1
	fi

	if [ "$netsim" = "true" ] && [ "$parallel" -gt 1 ]; then
		pvtest_log ERROR "-n netsim is incompatible with -p > 1"
		usage
		exit 1
	fi

	# -i IS supported against a device (opens the tester console wired to it); -m
	# boots a container so it isn't, and -p>1/-n/-V don't apply to a single board.
	if [ -n "$devices_file" ] && { [ "$parallel" -gt 1 ] || [ "$manual" = "true" ] || [ "$netsim" = "true" ] || [ "$valgrind" = "true" ]; }; then
		pvtest_log ERROR "--devices is incompatible with -p>1, -m, -n, -V"
		usage
		exit 1
	fi

	if [ -n "$devices_file" ] && { [ -n "$PVTEST_EXEC" ] || [ -n "$PVTEST_HOST" ]; }; then
		pvtest_log ERROR "--devices is incompatible with pre-set PVTEST_EXEC/PVTEST_HOST"
		exit 1
	fi

	if [ -n "$devices_file" ] && [ ! -f "$devices_file" ]; then
		pvtest_log ERROR "--devices file '$devices_file' not found"
		exit 1
	fi

	if [ "$interactive" = true ] && [ -z "$target_path" ]; then
		pvtest_log ERROR "Interactive mode requires a specific test path"
		usage
		exit 1
	fi

	if [ "$interactive" = true ] && [ ! -f "$test_dir/$target_path/test.json" ]; then
		pvtest_log ERROR "'$target_path' is not a leaf test (no test.json found)"
		usage
		exit 1
	fi

	if [ "$overwrite" = "true" ] && [ "$interactive" = "true" ]; then
		pvtest_log ERROR "Cannot use overwrite and interactive at the same time"
		usage
		exit 1
	fi

	mkdir -p "$work_path"
	{
	pvtest_log DEBUG "workspace=$work_path"
	pvtest_log DEBUG "readme=$work_path/README.md"
	pvtest_log DEBUG "run log=$work_path/run.log"
	pvtest_log DEBUG "test log=$work_path/results/<scope>/<category>/<name>/test.log"
	if [ "$valgrind" = "true" ]; then
		pvtest_log DEBUG "valgrind log=$work_path/storage/<scope>/<category>/<name>/valgrind/valgrind.log.<pid>"
	fi
	pvtest_log DEBUG "diff=$work_path/results/<scope>/<category>/<name>/diff"
	} | tee -a "$work_path/run.log"

	# Allocate slot for all containers in this invocation.
	allocate_slot
	local tester_name="pantavisor-tester-${USER}-${slot}"
	local netsim_name="pantavisor-netsim-${USER}-${slot}"

	# Slot is exclusively ours; any containers with this slot's names are stale
	# from an aborted run — remove them.
	docker ps -aq --filter "name=pantavisor-appengine-${USER}-${slot}-" | xargs -r docker rm -f 2>/dev/null || true
	docker ps -aq --filter "name=pantavisor-tester-${USER}-${slot}" | xargs -r docker rm -f 2>/dev/null || true
	docker rm -f "$netsim_name" 2>/dev/null || true

	# Resolve absolute paths for test scope dirs (local/ and remote/)
	local abs_local_path= abs_remote_path=
	if [ -d "$test_dir/local" ]; then
		cd "$test_dir/local"; abs_local_path=$(pwd); cd - > /dev/null
	fi
	if [ -d "$test_dir/remote" ]; then
		cd "$test_dir/remote"; abs_remote_path=$(pwd); cd - > /dev/null
	fi

	local _script_dir
	_script_dir="$(cd "$(dirname "$0")" && pwd)"
	local tester_image="pantavisor-appengine-tester"
	[ -f "$_script_dir/tester.imgid" ] && tester_image=$(cat "$_script_dir/tester.imgid")
	local netsim_image="pantavisor-appengine-netsim"
	[ -f "$_script_dir/netsim.imgid" ] && netsim_image=$(cat "$_script_dir/netsim.imgid")

	# Non-interactive: tee stdout/stderr to run.log so terminal and log stay in sync.
	if [ "$interactive" = "false" ] && [ "$manual" = "false" ]; then
		exec > >(tee -a "$work_path/run.log") 2>&1
	fi

	setup_network0

	if [ "$netsim" = "true" ]; then
		docker run \
			--name "$netsim_name" \
			--net=test-appengine-net \
			-d \
			-e VERBOSE="$verbose" \
			--rm \
			--cap-add NET_ADMIN \
			"$netsim_image" > /dev/null

		setup_network "$tester_name" "$netsim_name" &
	fi

	# Manual mode: single appengine in interactive shell, booted with the target test's required-config; no tester.
	if [ "$manual" = "true" ]; then
		local manual_cfg_args=() _mkv
		for _mkv in $(normalize_reqcfg "$(jq -r '.setup."required-config" // ""' "$test_dir/$target_path/test.json")"); do
			manual_cfg_args+=(-e "$_mkv")
		done
		docker run -it --rm \
			--name "pantavisor-appengine-${USER}-${slot}-0" \
			--net=test-appengine-net \
			--cgroupns host \
			--cap-add NET_ADMIN \
			--cap-add SYS_ADMIN \
			--cap-add SYS_PTRACE \
			--cap-add MKNOD \
			--device /dev/kmsg \
			--device /dev/hwrng \
			--device /dev/loop-control \
			--device-cgroup-rule 'b 7:* rmw' \
			--security-opt apparmor=unconfined \
			--security-opt seccomp=unconfined \
			--volume "/sys/fs":"/sys/fs" \
			--mount type=tmpfs,target="/usr/lib/lxc/rootfs" \
			--mount type=tmpfs,target="/volumes" \
			--mount type=tmpfs,target="/configs" \
			-v "$work_path/storage/0":/var/pantavisor/storage \
			"${manual_cfg_args[@]}" \
			pantavisor-appengine \
			/usr/bin/pv-appengine -m
		release_slot
		return
	fi

	# Generate SSH keypair once; shared by all appengine containers for this run.
	# Not needed in device mode — real devices are reached via each manifest
	# entry's own exec=, not a bootstrap key we generate and inject at boot.
	local shared_ssh_dir= pvtest_pubkey=
	if [ -z "$PVTEST_EXEC" ] && [ -z "$devices_file" ]; then
		shared_ssh_dir=$(mktemp -d)
		ssh-keygen -t ed25519 -f "$shared_ssh_dir/id_ed25519" -N "" -q
		chmod 600 "$shared_ssh_dir/id_ed25519"
		# Public key is passed as PV_DEBUG_SSH_PUBKEY env var; pv-appengine writes
		# it to /etc/pantavisor/ssh/ as root, avoiding the need for host sudo.
		pvtest_pubkey=$(cat "$shared_ssh_dir/id_ed25519.pub")
	fi

	# Tester-shared mounts (SSH key) and scope mounts (local/remote test trees)
	# are the same for every slot — compute once.
	local tester_shared_args=()
	if [ -z "$PVTEST_EXEC" ] && [ -z "$devices_file" ]; then
		tester_shared_args=(-v "$shared_ssh_dir/id_ed25519":/tmp/pvtest_id:ro)
	fi
	local tester_scope_args=()
	[ -n "$abs_local_path" ] && tester_scope_args+=(-v "$abs_local_path":/work/local)
	[ -n "$abs_remote_path" ] && tester_scope_args+=(-v "$abs_remote_path":/work/remote)

	# Device mode (downgraded to a single device): parse the manifest, require
	# exactly one device, lock it and start its tty capture. The tester reaches it
	# via PVTEST_EXEC/PVTEST_HOST taken straight from the manifest — no stripped map
	# is staged anymore. Bind-mount the manifest's directory read-only at the same
	# absolute path so any key path referenced in exec= resolves unchanged inside
	# the tester container.
	local dev_name= dev_ip= dev_exec= tester_device_args=()
	if [ -n "$devices_file" ]; then
		if ! _parse_device_manifest "$devices_file"; then
			release_slot
			return 1
		fi
		if [ "${#_dev_name[@]}" -ne 1 ]; then
			pvtest_log ERROR "--devices supports exactly one device (found ${#_dev_name[@]} in '$devices_file')"
			release_slot
			return 1
		fi

		dev_name="${_dev_name[0]}"; dev_ip="${_dev_ip[0]}"; dev_exec="${_dev_exec[0]}"

		if ! _lock_device "$dev_name"; then
			release_slot
			return 1
		fi

		_start_device_capture "$dev_name" "${_dev_tty[0]}" "${_dev_baud[0]}" \
			|| pvtest_log ERROR "failed to start tty capture for device '$dev_name'"

		local _devfile_abs_dir
		_devfile_abs_dir="$(cd "$(dirname "$devices_file")" && pwd)"
		tester_device_args=(-v "$_devfile_abs_dir":"$_devfile_abs_dir":ro)
	fi

	local docker_it_opt=
	[ "$interactive" = "true" ] && docker_it_opt="-it"

	# Interactive (non-manual): drop into the tester's single-target console. The
	# only difference between an appengine and a real device is what the tester
	# talks to: an appengine we boot here and reach over the shared SSH key, a
	# device is already up and reached over PVTEST_EXEC/PVTEST_HOST from the
	# manifest. So it's one docker run parameterised by a target-specific arg set,
	# not a second copy. No PVTEST_QUEUE is passed, so pvtest-run runs
	# exec_interactive instead of the test loop.
	if [ "$interactive" = "true" ]; then
		local _iae= iface_args=()
		if [ -n "$devices_file" ]; then
			iface_args=(
				-e PVTEST_EXEC="$dev_exec"
				-e PVTEST_HOST="$dev_ip"
				-e PVTEST_DEVICE="${PVTEST_DEVICE:-$dev_name}"
				-e PVTEST_DEVICE_TARGET="$dev_name"
				"${tester_device_args[@]}"
			)
		else
			local _icfg
			_icfg=$(normalize_reqcfg "$(jq -r '.setup."required-config" // ""' "$test_dir/$target_path/test.json")")
			_iae="pantavisor-appengine-${USER}-${slot}-w0-g1"
			_boot_appengine "$_iae" "$_icfg"
			iface_args=(
				-e PVTEST_APPENGINES="$_iae"
				-e PVTEST_SSH_KEY="/tmp/pvtest_id"
				-e PVTEST_DEVICE="${PVTEST_DEVICE:-appengine}"
				"${tester_shared_args[@]}"
			)
		fi
		docker run -it --rm \
			--net=test-appengine-net \
			--name "$tester_name" \
			-e TEST_PATH="/work/$target_path" \
			-e INTERACTIVE=true \
			-e MANUAL="$manual" \
			-e VERBOSE="$verbose" \
			-e VALGRIND="$valgrind" \
			-e PH_USER="$PH_USER" \
			-e PH_PASS="$PH_PASS" \
			-e PVR_DISABLE_SELF_UPGRADE=true \
			"${iface_args[@]}" \
			"${tester_scope_args[@]}" \
			"$tester_image"
		if [ -n "$devices_file" ]; then
			_stop_device_capture "$dev_name"
			_unlock_device "$dev_name"
		else
			_stop_appengine "$_iae"
			[ -z "$PVTEST_EXEC" ] && rm -rf "$shared_ssh_dir"
		fi
		release_slot
		return
	fi

	local ctrl_dir="$work_path/ctrl"
	if [ -z "$devices_file" ]; then
		mkdir -p "$ctrl_dir/req" "$ctrl_dir/resp" "$ctrl_dir/state"
	fi

	# Flat queue of /work test.json paths (stable order; the tester regroups by
	# runner-type and schedules them across slots, or across devices in device mode).
	local pvtest_queue="" _json _rel
	while IFS= read -r _json; do
		[ -n "$_json" ] || continue
		_rel=${_json#"$test_dir"/}; _rel=${_rel#./}
		pvtest_queue="${pvtest_queue:+$pvtest_queue }/work/$_rel"
	done < <(find "$test_dir/${target_path:-.}" -name test.json 2>/dev/null | sort)

	if [ -z "$pvtest_queue" ]; then
		pvtest_log WARN "no tests found under '${target_path:-<all>}'"
		if [ -n "$devices_file" ]; then
			for _i in "${!_dev_name[@]}"; do
				_stop_device_capture "${_dev_name[$_i]}"
				_unlock_device "${_dev_name[$_i]}"
			done
		fi
		release_slot
		[ -z "$PVTEST_EXEC" ] && [ -z "$devices_file" ] && rm -rf "$shared_ssh_dir"
		return 0
	fi

	local _nq res=0
	_nq=$(printf '%s\n' $pvtest_queue | grep -c .)
	if [ -n "$devices_file" ]; then
		pvtest_log INFO "=== single device: ${_nq} test(s) against ${dev_name} ==="
	else
		pvtest_log INFO "=== slot pool: ${_nq} test(s) across up to ${parallel} slot(s) ==="
	fi

	# Start the host re-type service (container runs only; never for real devices).
	local svc_pid=""
	if [ -z "$PVTEST_EXEC" ] && [ -z "$devices_file" ]; then
		retype_service "$ctrl_dir" &
		svc_pid=$!
	fi

	mkdir -p "$work_path/results/main"

	local -a tester_run_args=(
		--net=test-appengine-net
		--name "${tester_name}"
		-e TEST_PATH="/work/$target_path"
		-e PVTEST_QUEUE="$pvtest_queue"
		-e INTERACTIVE="$interactive"
		-e MANUAL="$manual"
		-e OVERWRITE="$overwrite"
		-e VERBOSE="$verbose"
		-e NETSIM="$netsim"
		-e VALGRIND="$valgrind"
		-e PH_USER="$PH_USER"
		-e PH_PASS="$PH_PASS"
		-e PVR_DISABLE_SELF_UPGRADE=true
		-e PVTEST_DEVICE="${PVTEST_DEVICE:-appengine}"
		-e MAX_RETRIES="$max_retries"
		-e FAIL_ON_SKIP_FIELD="$fail_on_skip_field"
		-e PV_LOG_SERVER_OUTPUTS="filetree,stdout_direct"
		-e RUN_DIR=/work/results
		-e APPENGINE_LOGS=/work/hostlogs
		--rm
		"${tester_scope_args[@]}"
		-v "$work_path/results/main":/work/results
		-v "$work_path":/work/hostlogs:ro
	)

	if [ -n "$devices_file" ]; then
		# Single-device run: pvtest-run's run_single_device drains PVTEST_QUEUE against
		# the one device over PVTEST_EXEC/PVTEST_HOST and SKIPs tests whose required-
		# config the device doesn't satisfy (PVTEST_MATCH_REQCFG). The later PVTEST_DEVICE
		# -e overrides the "appengine" default set in the shared args above.
		tester_run_args+=(
			-e PVTEST_EXEC="$dev_exec"
			-e PVTEST_HOST="$dev_ip"
			-e PVTEST_DEVICE="${PVTEST_DEVICE:-$dev_name}"
			-e PVTEST_DEVICE_TARGET="$dev_name"
			-e PVTEST_MATCH_REQCFG=true
			"${tester_device_args[@]}"
		)
	else
		tester_run_args+=(
			-e PVTEST_SLOTS="$parallel"
			-e PVTEST_CTRL="/work/ctrl"
			-e PVTEST_SSH_KEY="/tmp/pvtest_id"
			-e PVTEST_EXEC="${PVTEST_EXEC:-}"
			-e PVTEST_HOST="${PVTEST_HOST:-}"
			"${tester_shared_args[@]}"
			-v "$ctrl_dir":/work/ctrl
		)
	fi

	# Tester output (incl. the '<tid>' RESULT lines) lands in run.log via the exec
	# redirect above — only the non-interactive/non-manual path reaches the SUMMARY.
	docker run "${tester_run_args[@]}" "$tester_image" 2>&1
	res=$?

	# Stop the re-type service and tear down any remaining slot containers.
	if [ -n "$svc_pid" ]; then
		touch "$ctrl_dir/stop"
		wait "$svc_pid" 2>/dev/null || true
	fi
	if [ -z "$PVTEST_EXEC" ] && [ -z "$devices_file" ]; then
		docker ps -aq --filter "name=pantavisor-appengine-${USER}-${slot}-" | xargs -r docker rm -f 2>/dev/null || true
	fi

	[ -z "$PVTEST_EXEC" ] && [ -z "$devices_file" ] && rm -rf "$shared_ssh_dir"

	# Storage is written as root inside the container; chown back to the caller
	# (best-effort) so the host user can read it.
	if [ -z "$PVTEST_EXEC" ] && [ -z "$devices_file" ] && [ -d "$work_path/storage" ]; then
		docker run --rm -v "$work_path/storage":/storage pantavisor-appengine \
			-c "chown -R $(id -u):$(id -g) /storage" > /dev/null 2>&1 || true
	fi

	# Device mode: no docker teardown/poweroff — release the tty capture and the
	# device lock only, so the board stays reachable after the run.
	if [ -n "$devices_file" ]; then
		for _i in "${!_dev_name[@]}"; do
			_stop_device_capture "${_dev_name[$_i]}"
			_unlock_device "${_dev_name[$_i]}"
		done
	fi

	if [ "$netsim" = "true" ]; then
		docker stop "$netsim_name" > /dev/null 2>&1
		docker wait "$netsim_name" > /dev/null 2>&1
		teardown_network
	fi

	release_slot

	if [ "$interactive" = "true" ]; then
		return
	fi

	set +x

	# Collect results from run.log; diffs live under results/main/<tid>/, so the
	# tag is always "main". rank() is a tie-break:
	#   FAILED > ABORTED > PASSED > SKIPPED > RECORDED
	local merged_file
	merged_file=$(mktemp)
	awk '
		BEGIN { sq = sprintf("%c", 39) }       # single quote
		function rank(r){ if(r=="FAILED")return 5; if(r=="ABORTED")return 4;
			if(r=="PASSED")return 3; if(r=="SKIPPED")return 2;
			if(r=="RECORDED")return 1;
			# Slot device claims show in the SUMMARY next to the test results too.
			if(r=="claimed")return 1; return 0 }
		{
			n = split($0, q, sq)               # "...: \x27tid\x27 RESULT (..)"
			if (n >= 3) {
				tid = q[2]
				split(q[3], a, " ")            # " RESULT (..)" -> a[1]=RESULT
				res = a[1]
				# Keep the parenthetical only when it is a duration "(N s)", so a
				# reason like "(claim failed: ...)" is never shown as a time.
				if (match(q[3], /\([0-9]+ s\)/)) tm = substr(q[3], RSTART, RLENGTH)
				else tm = ""
				rk = rank(res)
				if (rk > 0) {
					if (rk > best[tid]) { best[tid]=rk; result[tid]=res; wtag[tid]="main"; time[tid]=tm }
				}
			}
		}
		END { for (t in result) printf "%s\t%s\t%s\t%s\n", t, result[t], wtag[t], time[t] }
	' "$work_path/run.log" 2>/dev/null | sort > "$merged_file"

	echo "======================================================="
	echo "======================= SUMMARY ======================="
	echo "======================================================="

	# Run-level (non-per-test) ERRORs only — excludes anything already mirrored
	# into a test.log or a per-test result line; timestamps stripped before de-dup.
	local runerr_file test_errs
	runerr_file=$(mktemp); test_errs=$(mktemp)
	find "$work_path/results" -name test.log -exec \
		grep -hE '^\[pvtest\] .* ERROR -- ' {} + 2>/dev/null \
		| sed -E 's/^\[pvtest\] [0-9]+ //' | sort -u > "$test_errs"
	grep -hE '^\[pvtest\] .* ERROR -- ' "$work_path/run.log" 2>/dev/null \
		| sed -E 's/^\[pvtest\] [0-9]+ //' | sort -u \
		| grep -vxF -f "$test_errs" 2>/dev/null \
		| grep -vE "ERROR -- \[[^]]*\]: '[^']*' (FAILED|ABORTED|PASSED|SKIPPED|RECORDED)" \
		> "$runerr_file" || true
	if [ -s "$runerr_file" ]; then
		printf -- "--- run errors ---\n"
		cat "$runerr_file"
		printf '%s\n\n' "--- end run errors ---"
	fi
	rm -f "$runerr_file" "$test_errs"

	local skip_fail=0 skip_fail_seen=0
	if [ -s "$merged_file" ]; then
		# Single pass in test order: print each test's diff/error block right before its result line.
		while IFS=$'\t' read -r test_id result wtag time; do
			[ -n "$test_id" ] || continue
			if [ "$result" = "FAILED" ] || [ "$result" = "ABORTED" ]; then
				local diff_file="$work_path/results/$wtag/$test_id/diff"
				local tlog="$work_path/results/$wtag/$test_id/test.log"
				if [ -s "$diff_file" ]; then
					printf -- "--- diff: %s ---\n" "$test_id"
					cat "$diff_file"
					printf '%s\n\n' "--- end diff ---"
				elif [ -s "$tlog" ]; then
					# No diff (the ABORT case, or a FAILED with no diff): surface the
					# test's own pvtest_log ERROR lines so the reason is inline.
					printf -- "--- errors: %s ---\n" "$test_id"
					grep -E '^\[pvtest\] .* ERROR -- ' "$tlog" 2>/dev/null
					printf '%s\n\n' "--- end errors ---"
				fi
			fi
			printf "'%s' %s%s\n" "$test_id" "$result" "${time:+ $time}"
			# --fail-on-skip: a SKIPPED result is final (the test ran once and the
			# runner skipped it, e.g. device filter or missing Hub creds).
			[ "$result" = "SKIPPED" ] && skip_fail_seen=1
		done < "$merged_file"
	fi
	# Nothing dispatched (claim/setup failure before any test ran) is covered by
	# the run-errors block above, which surfaces the ERROR messages regardless.
	rm -f "$merged_file"
	echo "======================================================="

	if [ "$fail_on_skip" = "true" ] && [ "${skip_fail_seen:-0}" = "1" ]; then
		skip_fail=1
		pvtest_log ERROR "--fail-on-skip: one or more tests were SKIPPED"
	fi

	# make summary available to the run path for the CI
	[ "${CI:-false}" = "true" ] && cp "$work_path/run.log" ./run.log

	if [ -n "$devices_file" ]; then
		cat > "$work_path/README.md" << 'EOF'
# Test Run Results (device mode)

## Workspace Layout

```
<workspace>/
  run.log                           <- aggregate output (host + tester) + SUMMARY
  appengine-<name>.log              <- raw serial console capture for one device
                                       (keyed by its manifest name=, read from its tty)
  README.md
  results/
    main/<scope>/<category>/<name>/
      test.log     <- test script output interleaved with device console logs during exec_test
      diff         <- diff (expected vs actual), present only when test failed
```

One tester (`pvtest-run`) runs every selected test sequentially against the
single device in the `--devices` manifest; it binds once for the whole run (no
pool, no re-typing, no env injection at boot — see
`docs/testing/device-target.md`). There is no `storage/<container>/` directory in
device mode (a real device keeps its own on-device storage; nothing is mirrored
to the host). Tests whose `required-config` the live device doesn't satisfy are
SKIPPED (the device's config can't be injected), so run device mode **without**
`--fail-on-skip` until every test's `"devices"` array has been audited for
hardware safety.
EOF
	else
		cat > "$work_path/README.md" << 'EOF'
# Test Run Results

## Workspace Layout

```
<workspace>/
  run.log                           <- aggregate output (host + tester) + SUMMARY
  appengine-<container>.log         <- full pantavisor stdout_direct for one appengine
                                       container (keyed by its full name)
  README.md
  results/
    main/<scope>/<category>/<name>/
      test.log     <- test script output interleaved with pantavisor logs during exec_test
      diff         <- diff (expected vs actual), present only when test failed
  storage/
    <container>/   <- per-appengine pantavisor storage (keyed by container name)
      trails/ objects/ logs/ ...
  valgrind/
    <container>/   <- per-appengine valgrind output
      valgrind.log.<pid>   <- present only when run with -V
```

One tester (`pvtest-run`) dispatches the test queue across `-p` slots, re-typing
each slot's appengine container as needed; see `docs/testing/device-target.md`
for the full slot-pool model. Each test runs exactly once; the SUMMARY collects
the per-test results.
EOF
	fi

	cat >> "$work_path/README.md" << 'EOF'

## Log Format

All structured log lines follow the pantavisor log convention:

```
[pvtest] <epoch> LEVEL -- [source]: message
```

Sources: `test.docker.sh`, `pvtest-run`, `pv-appengine`.

## run.log

The single aggregate log: host orchestrator (`test.docker.sh`) and tester
(`pvtest-run`) output interleaved — distinguishable by the `[source]` tag — plus
one structured line per test result and a SUMMARY section at the end.

Log levels used in `run.log`:

| Level | When |
|-------|------|
| `DEBUG` | Test launch and workspace setup diagnostics |
| `INFO` | PASSED, ABORTED, SKIPPED, retry |
| `ERROR` | FAILED |

On failure the diff is printed inline after the `ERROR` line, and also saved to
`results/<scope>/<category>/<name>/diff`. Retry attempts get their own directory
(`<name>.1/`, `<name>.2/`).

Quick scan for failures:

    grep ERROR run.log

## test.log

`test.log` is a single interleaved stream of everything that happened during a test run.
It mixes output from four sources:

**1. `test.docker.sh`**
Host-side orchestrator. With `-v` produces `set -x` traces (`++ docker run ...`,
`++ allocate_slot`, etc.) covering container startup and network setup.
Structured messages use `[pvtest] LEVEL -- [test.docker.sh]: message`.

**2. `pvtest-run` + `resources/test`**
Inner test runner inside the tester container. Parses `test.json`, connects to the
appengine via PVTEST_EXEC (SSH), then runs the test script (with `set -x` injected).
Structured messages use `[pvtest] LEVEL -- [pvtest-run]: message`.
The test script output is captured and diffed against the stored `output` file.

**3. `pv-appengine`**
Pantavisor runtime launcher inside the appengine container. Sets up cgroups and storage
mounts, then runs the `pantavisor` binary in a restart loop (simulating device reboots).
Structured messages use `[pvtest] LEVEL -- [pv-appengine]: message`.

**4. Pantavisor (`stdout_direct`)**
Started with `PV_LOG_SERVER_OUTPUTS=filetree,stdout_direct`. Streams internal logs
directly to stdout without buffering:
`[pantavisor] TIMESTAMP LEVEL -- [module]: message`.

To filter by source:

    grep '\[pvtest-run\]'   test.log    # pvtest-run messages only
    grep '\[pv-appengine\]' test.log    # pv-appengine messages only
    grep '\[pantavisor\]'   test.log    # pantavisor messages only
    grep 'WARN\|ERROR'      test.log    # all warnings and errors

In GHA, WARN and ERROR lines from `test.log` are automatically surfaced in the
job step summary under **Test log issues**.
EOF

	if [ -z "$devices_file" ]; then
		cat >> "$work_path/README.md" << 'EOF'

## Valgrind Logs

Valgrind output is under `valgrind/<N>/valgrind.log.<pid>`. The main worker is typically
the largest file. Check with:

    grep -E "definitely lost|possibly lost|ERROR SUMMARY" valgrind/<N>/valgrind.log.<largest-pid>

- `definitely lost` — real leaks, investigate
- `possibly lost` — typically PV buffer pools; consistent at ~3.7 MB, not a regression
- `ERROR SUMMARY` — mostly `Syscall param` warnings from liblxc, not pantavisor code
EOF
	fi

	if [ $res -ne 0 ] || [ "${skip_fail:-0}" -ne 0 ]; then
		return 1
	fi
	return 0
}

RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NOCOLOR='\033[0m'

verbose="false"
command=
test_dir=.

while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help)
		usage
		exit 0
		;;
		-v|--verbose)
		set -x
		verbose="true"
		shift
		;;
		-d|--dir)
		test_dir="$2"
		shift 2
		;;
	*)
		break
		;;
	esac
done

if [ $# -eq 0 ]; then
	pvtest_log ERROR "Missing command"
	usage
	exit 1
fi

command="$1"
shift

case "$command" in
	add)
		add_test "$@"
		;;
	install-deps)
		install_deps
		;;
	install-docker)
		install_docker
		;;
	ls)
		list_tests
		;;
	run)
		run_test "$@"
		;;
	*)
		pvtest_log ERROR "Unknown command: $command"
		usage
		exit 1
		;;
esac
