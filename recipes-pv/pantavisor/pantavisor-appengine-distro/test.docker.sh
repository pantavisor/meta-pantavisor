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
	echo "  -p, --parallel N      Global cap on concurrent runners across all types;"
	echo "                        each type fans out to min(its tests, -p) and types are"
	echo "                        scheduled in waves to stay under it (default: nproc)."
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

# ---------------------------------------------------------------------------
# Runner-type model
#
# A runner is an appengine container booted with a specific device configuration,
# passed as PV_* environment variables — the new config format pantavisor reads
# straight from its environment (the same path PV_POLICY used). The set of
# distinct configurations a run needs is derived dynamically from each test's
# setup.required-config; there is no static policy list and no policy file.
#
# A runner-TYPE is keyed by (normalized required-config, needs-claim) where
#   needs-claim = required-config has PV_CONTROL_REMOTE=1 AND test self-claim=true.
# Remote self-claim=true tests need a device claimed once up front (claim pool);
# remote self-claim=false tests (the claim tests) need an UNCLAIMED device of the
# SAME config (their own script claims/unclaims), so config alone can't separate
# them — the claim-role does. Local tests never claim.
# ---------------------------------------------------------------------------

# Normalize a required-config string: drop empty tokens and any PV_LXC_LOG_LEVEL
# (a legacy pool discriminator no longer used), then sort the KEY=VALUE tokens for
# a stable signature. Echoes the normalized space-separated config.
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

# Echo "yes" if (required-config $1, self-claim $2) needs an up-front claim:
# only remote (PV_CONTROL_REMOTE=1) self-claim=true tests. Everything else "no".
reqcfg_needs_claim() {
	case " $1 " in *" PV_CONTROL_REMOTE=1 "*) ;; *) echo no; return ;; esac
	[ "$2" = "true" ] && echo yes || echo no
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
	# Serialize the inspect/remove/create dance so concurrent callers don't
	# race on `docker network create` (which fails noisily if the network was
	# created in the gap between the inspect and the create).
	local lockfile=/tmp/pv_appengine.network0.lock
	exec {NET0_FD}>"$lockfile"
	flock "$NET0_FD"

	if ! docker network inspect test-appengine-net >/dev/null 2>&1; then
		docker network create --driver=bridge --opt com.docker.network.container_iface_prefix=lxcbrdock test-appengine-net >/dev/null 2>&1 || :
	fi

	eval "exec ${NET0_FD}>&-"
}

# Allocate the lowest free slot index by holding a per-slot OS file lock for
# the lifetime of this invocation. Slot N is "free" if no other instance
# currently holds an exclusive flock on /tmp/pv_appengine.slot.N.lock.
#
# The lock fd (SLOT_LOCK_FD) is kept open in the running shell — the kernel
# drops the lock automatically when the process exits, even on crash, so no
# stale-reservation bookkeeping is needed. Gaps from shut-down instances are
# reused naturally because their lock fds are closed.
#
# Sets globals: slot, SLOT_LOCK_FD
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

# ----------------------------------------------------------------------------
# Slot-pool model helpers (single-tester global FIFO + host re-type service).
#
# A single tester (pvtest-run) owns a global semaphore of -p "slots" over one
# flat test queue. A slot maps to one live appengine container; when the next
# pending test needs a different required-config than the slot's current
# container, the tester asks this host to RE-TYPE the slot — stop the old
# container, boot a new one with the new config. Only the host can call docker,
# so it runs a small file-based request/response service over a bind-mounted
# control dir; the semaphore, claim-once and keeping slots busy live in the
# tester. These functions run in run_test's dynamic scope (work_path, valgrind,
# pvtest_pubkey) and globals (slot, USER) — including the backgrounded
# retype_service subshell, which snapshots run_test's locals.
# ----------------------------------------------------------------------------

# Boot one appengine container named $1 with required-config $2 ("KEY=VAL ...").
# Detached; readiness is awaited by the tester's init_device, not here. Starts a
# host-side log tail into appengine-<name>.log and records its pid for teardown.
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

# Background re-type service. Watches $1/req/slot<S> files written by the tester;
# for each, (re)boots the slot's container and writes the new name to
# $1/resp/slot<S>. Exits when $1/stop appears, then tears down all slots.
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

	if [ -n "$1" ] && [ "$(printf '%s' "$1" | cut -c1)" != "-" ]; then
		target_path="$1"
		shift
	fi

	# "all" is a keyword for the whole suite (local/ + remote/), not a directory.
	# Map it to an empty target so discovery searches both scope trees.
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

	# -p is the global cap on concurrent runners across all types: -p 1 runs fully
	# serial, -p N allows up to N concurrent runners (like a master pool). When
	# unset it defaults to nproc (size to the box); modes that must run serially
	# (interactive, manual, overwrite, netsim) default to 1 instead.
	if [ "$parallel" -le 0 ] 2>/dev/null; then
		if [ "$interactive" = "true" ] || [ "$manual" = "true" ] || \
		   [ "$overwrite" = "true" ] || [ "$netsim" = "true" ]; then
			parallel=1
		else
			parallel=$(nproc 2>/dev/null || echo 1)
		fi
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

	# Allocate slot — applies to ALL containers for this invocation so concurrent
	# test.docker.sh runs don't collide on container names or host ports.
	allocate_slot
	local tester_name="pantavisor-tester-${USER}-${slot}"
	local netsim_name="pantavisor-netsim-${USER}-${slot}"

	# Flock guarantees this slot is exclusively ours — any containers with our
	# slot's names are stale from a previous aborted run (possibly with a
	# different -p value). Remove them all before starting new ones.
	docker ps -aq --filter "name=pantavisor-appengine-${USER}-${slot}-" | xargs -r docker rm -f 2>/dev/null || true
	docker ps -aq --filter "name=pantavisor-tester-${USER}-${slot}" | xargs -r docker rm -f 2>/dev/null || true
	docker rm -f "$netsim_name" 2>/dev/null || true

	# Runner-fleet model: tests are grouped into runner-types by their
	# (required-config, needs-claim). Each type fans out to min(its tests, -p)
	# appengine runners (pantavisor-appengine-${USER}-${slot}-t<type>-<0..n-1>)
	# configured via PV_* env. Types are scheduled in waves bounded by the global
	# instance cap (-p); a single tester (pvtest-run) runs per wave and dispatches
	# each test to an idle runner of its type. Each test runs exactly once, so
	# results need no merge.

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

	# Manual mode: start a single appengine in interactive shell mode; no tester.
	# Boot it with the target test's own required-config (as PV_* env), so the
	# shell lands on a device configured the way that test expects.
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
	local shared_ssh_dir= pvtest_pubkey=
	if [ -z "$PVTEST_EXEC" ]; then
		shared_ssh_dir=$(mktemp -d)
		ssh-keygen -t ed25519 -f "$shared_ssh_dir/id_ed25519" -N "" -q
		chmod 600 "$shared_ssh_dir/id_ed25519"
		# Public key is passed as PV_DEBUG_SSH_PUBKEY env var; pv-appengine writes
		# it to /etc/pantavisor/ssh/ as root, avoiding the need for host sudo.
		pvtest_pubkey=$(cat "$shared_ssh_dir/id_ed25519.pub")
	fi

	# Tester-shared mounts (SSH key) and scope mounts (local/remote test trees)
	# are the same for every wave — compute once.
	local tester_shared_args=()
	if [ -z "$PVTEST_EXEC" ]; then
		tester_shared_args=(-v "$shared_ssh_dir/id_ed25519":/tmp/pvtest_id:ro)
	fi
	local tester_scope_args=()
	[ -n "$abs_local_path" ] && tester_scope_args+=(-v "$abs_local_path":/work/local)
	[ -n "$abs_remote_path" ] && tester_scope_args+=(-v "$abs_remote_path":/work/remote)

	local docker_it_opt=
	[ "$interactive" = "true" ] && docker_it_opt="-it"

	# ----------------------------------------------------------------------
	# Interactive (non-manual): boot one container configured for the target
	# test and drop into the tester's single-device interactive shell. The
	# slot-pool path below is for automated runs only.
	# ----------------------------------------------------------------------
	if [ "$interactive" = "true" ]; then
		local _icfg _iae
		_icfg=$(normalize_reqcfg "$(jq -r '.setup."required-config" // ""' "$test_dir/$target_path/test.json")")
		_iae="pantavisor-appengine-${USER}-${slot}-w0-g1"
		_boot_appengine "$_iae" "$_icfg"
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
			-e PVTEST_APPENGINES="$_iae" \
			-e PVTEST_SSH_KEY="/tmp/pvtest_id" \
			-e PVTEST_DEVICE="${PVTEST_DEVICE:-appengine}" \
			"${tester_shared_args[@]}" \
			"${tester_scope_args[@]}" \
			"$tester_image"
		_stop_appengine "$_iae"
		release_slot
		[ -z "$PVTEST_EXEC" ] && rm -rf "$shared_ssh_dir"
		return
	fi

	# ----------------------------------------------------------------------
	# Slot-pool model: enumerate the selected tests into a flat queue and let a
	# single tester (pvtest-run) dispatch them across -p slots, asking the host
	# re-type service (above) to (re)boot each slot's container on demand. The
	# tester owns the semaphore, claim-once, and keeping all slots busy.
	# ----------------------------------------------------------------------
	local ctrl_dir="$work_path/ctrl"
	mkdir -p "$ctrl_dir/req" "$ctrl_dir/resp" "$ctrl_dir/state"

	# Flat queue of /work test.json paths (stable order; the tester regroups by
	# runner-type and schedules them across slots).
	local pvtest_queue="" _json _rel
	while IFS= read -r _json; do
		[ -n "$_json" ] || continue
		_rel=${_json#"$test_dir"/}; _rel=${_rel#./}
		pvtest_queue="${pvtest_queue:+$pvtest_queue }/work/$_rel"
	done < <(find "$test_dir/${target_path:-.}" -name test.json 2>/dev/null | sort)

	if [ -z "$pvtest_queue" ]; then
		pvtest_log WARN "no tests found under '${target_path:-<all>}'"
		release_slot
		[ -z "$PVTEST_EXEC" ] && rm -rf "$shared_ssh_dir"
		return 0
	fi

	local _nq res=0
	_nq=$(printf '%s\n' $pvtest_queue | grep -c .)
	pvtest_log INFO "=== slot pool: ${_nq} test(s) across up to ${parallel} slot(s) ==="

	# Start the host re-type service (container runs only).
	local svc_pid=""
	if [ -z "$PVTEST_EXEC" ]; then
		retype_service "$ctrl_dir" &
		svc_pid=$!
	fi

	mkdir -p "$work_path/results/main"

	local -a tester_run_args=(
		--net=test-appengine-net
		--name "${tester_name}"
		-e TEST_PATH="/work/$target_path"
		-e PVTEST_QUEUE="$pvtest_queue"
		-e PVTEST_SLOTS="$parallel"
		-e PVTEST_CTRL="/work/ctrl"
		-e INTERACTIVE="$interactive"
		-e MANUAL="$manual"
		-e OVERWRITE="$overwrite"
		-e VERBOSE="$verbose"
		-e NETSIM="$netsim"
		-e VALGRIND="$valgrind"
		-e PH_USER="$PH_USER"
		-e PH_PASS="$PH_PASS"
		-e PVR_DISABLE_SELF_UPGRADE=true
		-e PVTEST_SSH_KEY="/tmp/pvtest_id"
		-e PVTEST_EXEC="${PVTEST_EXEC:-}"
		-e PVTEST_HOST="${PVTEST_HOST:-}"
		-e PVTEST_DEVICE="${PVTEST_DEVICE:-appengine}"
		-e MAX_RETRIES="$max_retries"
		-e FAIL_ON_SKIP_FIELD="$fail_on_skip_field"
		-e PV_LOG_SERVER_OUTPUTS="filetree,stdout_direct"
		-e RUN_DIR=/work/results
		--rm
		"${tester_shared_args[@]}"
		"${tester_scope_args[@]}"
		-v "$work_path/results/main":/work/results
		-v "$ctrl_dir":/work/ctrl
	)

	docker run "${tester_run_args[@]}" "$tester_image" 2>&1 | tee -a "$work_path/run.main.log"
	res=${PIPESTATUS[0]}

	# Stop the re-type service and tear down any remaining slot containers.
	if [ -n "$svc_pid" ]; then
		touch "$ctrl_dir/stop"
		wait "$svc_pid" 2>/dev/null || true
	fi
	if [ -z "$PVTEST_EXEC" ]; then
		docker ps -aq --filter "name=pantavisor-appengine-${USER}-${slot}-" | xargs -r docker rm -f 2>/dev/null || true
	fi

	[ -z "$PVTEST_EXEC" ] && rm -rf "$shared_ssh_dir"

	# Make the per-device storage trees readable by the invoking user. The
	# appengine containers write storage (logs/objects/trails) as root via a
	# bind-mounted volume, so afterwards the host user gets "Permission denied"
	# inspecting them. chown the whole tree back to the caller (best-effort).
	if [ -z "$PVTEST_EXEC" ] && [ -d "$work_path/storage" ]; then
		docker run --rm -v "$work_path/storage":/storage pantavisor-appengine \
			-c "chown -R $(id -u):$(id -g) /storage" > /dev/null 2>&1 || true
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

	# Collect results. The single tester run writes per-test result lines to
	# run.main.log and per-test diffs under results/main/<tid>/; the rank()
	# precedence is a harmless tie-break. wtag ("main") gives the diff path.
	#   FAILED > ABORTED > PASSED > SKIPPED > RECORDED
	local merged_file
	merged_file=$(mktemp)
	awk '
		BEGIN { sq = sprintf("%c", 39) }       # single quote
		function rank(r){ if(r=="FAILED")return 5; if(r=="ABORTED")return 4;
			if(r=="PASSED")return 3; if(r=="SKIPPED")return 2;
			if(r=="RECORDED")return 1; return 0 }
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
					tag = FILENAME
					sub(/.*\/run\./, "", tag)
					sub(/\.log$/, "", tag)
					if (rk > best[tid]) { best[tid]=rk; result[tid]=res; wtag[tid]=tag; time[tid]=tm }
				}
			}
		}
		END { for (t in result) printf "%s\t%s\t%s\t%s\n", t, result[t], wtag[t], time[t] }
	' "$work_path"/run.*.log 2>/dev/null | sort > "$merged_file"

	echo "======================================================="
	echo "======================= SUMMARY ======================="
	echo "======================================================="

	# Top of the summary: run-level pvtest_log ERROR lines — configuration,
	# pool-init or claim failures that are not tied to any single test (e.g.
	# PH_USER/PH_PASS not set but required). A per-test error is mirrored into
	# that test's test.log and shown inline below, so exclude any ERROR that
	# also appears in a test.log, and exclude per-test result lines. Timestamps
	# are stripped before de-duping so the same error across policies collapses.
	local runerr_file test_errs
	runerr_file=$(mktemp); test_errs=$(mktemp)
	find "$work_path/results" -name test.log -exec \
		grep -hE '^\[pvtest\] .* ERROR -- ' {} + 2>/dev/null \
		| sed -E 's/^\[pvtest\] [0-9]+ //' | sort -u > "$test_errs"
	grep -hE '^\[pvtest\] .* ERROR -- ' "$work_path"/run.*.log 2>/dev/null \
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
		# Single pass in test order: for each non-passing test that has a diff,
		# print the diff/error block immediately BEFORE its result line, then the
		# result line itself ('<tid>' RESULT (on <policy>)). This interleaves the
		# failure detail with the test it belongs to instead of dumping all diffs
		# in one block up front.
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
			printf "'%s' %s %s(on %s)\n" "$test_id" "$result" "${time:+$time }" "$wtag"
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

	cat > "$work_path/README.md" << 'EOF'
# Test Run Results

## Workspace Layout

```
<workspace>/
  run.log                           <- aggregate output + SUMMARY
  run.main.log                      <- the tester run's per-test result lines
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

The slot-pool model runs one tester (`pvtest-run`) that owns a global semaphore
of `-p` slots over a flat test queue. A slot maps to one live appengine
container; when the next pending test needs a different `required-config`, the
tester asks the host re-type service to stop that slot's container and boot a
new one with the new config (`PV_*` env). Each remote device is claimed once
while a slot stays on its type and deleted once on switch, so claim-once holds
without draining the pool between types. Each test runs exactly once; the
SUMMARY collects the per-test results.

## Log Format

All structured log lines follow the pantavisor log convention:

```
[pvtest] <epoch> LEVEL -- [source]: message
```

Sources: `test.docker.sh`, `pvtest-run`, `pv-appengine`.

## run.log

Contains one structured line per test result plus a SUMMARY section at the end.

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

## Valgrind Logs

Valgrind output is under `valgrind/<N>/valgrind.log.<pid>`. The main worker is typically
the largest file. Check with:

    grep -E "definitely lost|possibly lost|ERROR SUMMARY" valgrind/<N>/valgrind.log.<largest-pid>

- `definitely lost` — real leaks, investigate
- `possibly lost` — typically PV buffer pools; consistent at ~3.7 MB, not a regression
- `ERROR SUMMARY` — mostly `Syscall param` warnings from liblxc, not pantavisor code
EOF

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
