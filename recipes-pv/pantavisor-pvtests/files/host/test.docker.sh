#!/bin/bash

# pvtest_log, wait_for_status, pvtest_ssh_cmd and pvtest_normalize_cfg are shared
# with the in-container half (pvtest-run/utils) and ship next to this script in
# the distro tarball. Sourced before anything that could log.
PVTEST_LOG_SOURCE=test.docker.sh
PVTEST_LOG_HOST="$(hostname 2>/dev/null || echo host)"
# pvtest/common sits beside this script in the distro tarball, and one level up
# in the meta-pantavisor source tree (files/host/ vs files/pvtest/).
_pvtest_common=
for _c in "$(dirname "$0")/pvtest/common" "$(dirname "$0")/../pvtest/common"; do
	[ -r "$_c" ] && { _pvtest_common="$_c"; break; }
done
if [ -z "$_pvtest_common" ]; then
	echo "ERROR: pvtest shared helpers (pvtest/common) not found next to $0." >&2
	echo "       Run test.docker.sh from the extracted pantavisor-appengine-distro" >&2
	echo "       tarball root, which ships pvtest/common beside this script." >&2
	exit 1
fi
. "$_pvtest_common"

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
	echo "  install-tarballs [path]... Install container tarballs for a target type"
	echo "  ls                         List all tests"
	echo "  run [path]                 Run one to many tests"
	echo ""
	echo "Arguments for 'install-tarballs' command:"
	echo "  -t, --target TYPE     Target type to install for (default appengine)"
	echo "  -s, --scope SCOPE     Install into this scope only (local|remote; default both)"
	echo "  -l, --list            Print the installed overrides and exit"
	echo "      --reset           Restore the shipped tarballs and exit"
	echo ""
	echo "Arguments for 'run' command:"
	echo "  -i, --interactive     Run the test interactively for debugging"
	echo "  -m, --manual          Avoid starting Pantavisor for debugging"
	echo "  -n, --netsim          Use the network simulator (experimental)"
	echo "  -o, --overwrite       Create or overwrite the test output"
	echo "  -p, --parallel N      Number of slots: the cap on concurrent appengine"
	echo "                        containers a single tester keeps busy (default: 1)."
	echo "  --devices FILE        Run against one real device instead of the appengine"
	echo "                        pool (see README.md / docs/overview/testing/automated/devices.md)."
	echo "  --model MODEL         Assignment model: persistent (default) boots every test"
	echo "                        under exactly its config.env (one persistent storage per"
	echo "                        worker); on --devices, a manifest entry with hook=/config="
	echo "                        set re-types the device via that hook when config.env"
	echo "                        doesn't match, otherwise (no hook=) tests are SKIPPED as"
	echo "                        before; volatile boots one fresh container per test,"
	echo "                        straight into that test's revision (incompatible with"
	echo "                        --devices). Run test.docker.sh twice to get both."
	echo "      --fail-on-skip    Exit non-zero if any test is SKIPPED, whatever the reason"
	echo "                        (test.json \"skip\", \"devices\" filter, unmet config, no creds)"
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
	echo "  PVTEST_TARBALLS_PATH      Default source for 'install-tarballs'"
	echo "  PVTEST_TARBALLS_MANIFEST  Override manifest path (default: <dir>/pvtest-tarballs.manifest)"
	echo ""
	echo "Target override environments (unset = local appengine container, set = external target):"
	echo "  PVTEST_EXEC      Command prefix to run pvcontrol/pventer on the target."
	echo "                     Unset (default): test.docker.sh starts a pantavisor-appengine"
	echo "                     container and sets this to \"ssh _pv_@<container>\" (dropbear-pv)."
	echo "                     Real device: \"ssh root@<ip>\" or \"ssh -p <port> user@<ip>\""
	echo "  PVTEST_HOST      Hostname or IP for pvr/HTTP calls to the target (default: localhost)."
	echo "                     Set automatically to the appengine container name when unset."
	echo "  PVTEST_DEVICE_TYPE  Class of target, shared by every runner of the same kind"
	echo "                     (default: appengine; on --devices, the manifest's type=,"
	echo "                     falling back to its name=). Tests with a non-empty"
	echo "                     \"devices\" array only run when this value is listed."
	echo ""
}

# Runner-type = (normalized config.env, needs-claim); see the testing docs.

# Normalize config.env to a stable signature (shared with pvtest-run).
normalize_reqcfg() { pvtest_normalize_cfg "$@"; }

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

# --- container tarball substitution -----------------------------------------
#
# The suites ship with the example containers built for the appengine (x86,
# signed by the build's PVS_VENDOR_NAME CA). Running against a real device of
# another architecture, or one that trusts a different signing CA, needs those
# replaced with tarballs built for that board. Overlaying them here keeps a
# single distro install usable against any target.
#
# Overrides are workspace-local: they live in the *extracted* distro, not in the
# meta-pantavisor source tree, so a rebuild re-stages the pristine ones.

# Which target tree install-tarballs and the override log operate on. Set by
# install-tarballs -t and by run_test once the device type is known; appengine is
# the type a run without --devices resolves to.
_tarball_target=appengine

# Per target: a manifest inside the target tree keeps each target's override history
# self-contained, so --list/--reset never mix two boards' records.
_tarballs_manifest() {
	printf '%s' "${PVTEST_TARBALLS_MANIFEST:-$test_dir/targets/$_tarball_target/pvtest-tarballs.manifest}"
}

# The current override set: last record per (scope,name), minus anything restored.
_tarball_overrides_effective() {
	local mf; mf="$(_tarballs_manifest)"
	[ -f "$mf" ] || return 0
	awk -F'\t' '!/^#/ && NF>=6 { e[$2 FS $3]=$0 }
	            END { for (k in e) if (e[k] !~ /\trestored\t/) print e[k] }' "$mf" \
		| sort -t"$(printf '\t')" -k2,2 -k3,3
}

_tarball_record() {
	local mf; mf="$(_tarballs_manifest)"
	if [ ! -f "$mf" ]; then
		mkdir -p "$(dirname "$mf")"
		printf '# pvtest-tarballs v1\n' > "$mf"
		printf '# format: <epoch>\\t<scope>\\t<name>\\t<action>\\t<sha256-12>\\t<source>\n' >> "$mf"
	fi
	printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$1" "$2" "$3" "$4" "$5" >> "$mf"
}

_tarball_sum() {
	sha256sum "$1" 2>/dev/null | cut -c1-12
}

# Announce substituted tarballs at INFO: this is the one line explaining why a
# run's results differ from a pristine distro, so it must survive a grep -v DEBUG.
_log_tarball_overrides() {
	local wp="$1" n ts scope name action sum src
	n=$(_tarball_overrides_effective | wc -l)
	[ "${n:-0}" -gt 0 ] || return 0
	pvtest_log INFO "tarball overrides: $n (manifest=$(_tarballs_manifest))"
	_tarball_overrides_effective | while IFS="$(printf '\t')" read -r ts scope name action sum src; do
		pvtest_log INFO "  targets/$_tarball_target/$scope/$name <- $src ($action, sha $sum)"
	done
	cp -f "$(_tarballs_manifest)" "$wp/pvtest-tarballs.manifest" 2>/dev/null || true
}

# Scope dirs live under targets/<type>/, which is what test.docker.sh mounts over
# /work/<scope>/common/tarballs. A type that does not exist yet is created: that is
# how a new board target is introduced, without copying the suites.
_tarball_scopes() {
	local want="$1" s
	for s in local remote; do
		[ -z "$want" ] || [ "$want" = "$s" ] || continue
		mkdir -p "$test_dir/targets/$_tarball_target/$s" || continue
		printf '%s\n' "$s"
	done
}

_install_one_tarball() {
	local src="$1" scope="$2" name dest orig action sum prev
	name="$(basename "$src")"
	dest="$test_dir/targets/$_tarball_target/$scope/$name"
	orig="$test_dir/targets/$_tarball_target/$scope/.orig"

	# An entry that is already an override keeps its original action, and is not
	# backed up again: otherwise a second install would record the *previous
	# override* as the pristine copy, and --reset would restore that instead of
	# the shipped tarball (or instead of removing a file the distro never had).
	prev=$(_tarball_overrides_effective | awk -F'\t' -v s="$scope" -v n="$name" '$2==s && $3==n {print $4}')
	if [ -n "$prev" ]; then
		action="$prev"
	elif [ -e "$dest" ]; then
		mkdir -p "$orig"
		cp -p "$dest" "$orig/$name"
		action=replaced
	else
		action=added
	fi

	cp -f "$src" "$dest" || return 1
	sum="$(_tarball_sum "$dest")"
	_tarball_record "$scope" "$name" "$action" "$sum" "$src"
	pvtest_log INFO "targets/$_tarball_target/$scope/$name [$action, sha $sum]"
}

_reset_tarballs() {
	local ts scope name action sum src dest orig
	_tarball_overrides_effective | while IFS="$(printf '\t')" read -r ts scope name action sum src; do
		dest="$test_dir/targets/$_tarball_target/$scope/$name"
		orig="$test_dir/targets/$_tarball_target/$scope/.orig/$name"
		if [ "$action" = replaced ] && [ -e "$orig" ]; then
			mv -f "$orig" "$dest"
			pvtest_log INFO "targets/$_tarball_target/$scope/$name [restored]"
		elif [ "$action" = added ]; then
			rm -f "$dest"
			pvtest_log INFO "targets/$_tarball_target/$scope/$name [removed]"
		else
			pvtest_log WARN "targets/$_tarball_target/$scope/$name: no backup to restore"
			continue
		fi
		_tarball_record "$scope" "$name" restored - -
	done
	rmdir "$test_dir/targets/$_tarball_target"/local/.orig "$test_dir/targets/$_tarball_target"/remote/.orig 2>/dev/null || true
}

install_tarballs() {
	local scope= do_list=false do_reset=false srcs=() found=0
	_tarball_target=appengine

	while [ $# -gt 0 ]; do
		case "$1" in
			-t|--target) _tarball_target="$2"; shift 2 ;;
			-s|--scope) scope="$2"; shift 2 ;;
			-l|--list)  do_list=true; shift ;;
			--reset)    do_reset=true; shift ;;
			-h|--help)  usage; exit 0 ;;
			-*) pvtest_log ERROR "Unknown install-tarballs option: $1"; exit 1 ;;
			*)  srcs+=("$1"); shift ;;
		esac
	done

	if [ -n "$scope" ] && [ "$scope" != local ] && [ "$scope" != remote ]; then
		pvtest_log ERROR "--scope must be 'local' or 'remote'"
		exit 1
	fi

	if [ "$do_list" = true ]; then
		local n; n=$(_tarball_overrides_effective | wc -l)
		if [ "${n:-0}" -eq 0 ]; then
			pvtest_log INFO "no tarball overrides installed"
		else
			pvtest_log INFO "tarball overrides: $n (manifest=$(_tarballs_manifest))"
			_tarball_overrides_effective | while IFS="$(printf '\t')" read -r _ts s nm ac sm sr; do
				pvtest_log INFO "  targets/$_tarball_target/$s/$nm <- $sr ($ac, sha $sm)"
			done
		fi
		return 0
	fi

	if [ "$do_reset" = true ]; then
		_reset_tarballs
		return 0
	fi

	[ ${#srcs[@]} -gt 0 ] || srcs=("${PVTEST_TARBALLS_PATH:-.}")

	local sp f s
	for sp in "${srcs[@]}"; do
		if [ ! -e "$sp" ]; then
			pvtest_log ERROR "no such path: $sp"
			exit 1
		fi
		for f in $([ -d "$sp" ] && find "$sp" -maxdepth 1 -name '*.tgz' | sort || printf '%s\n' "$sp"); do
			case "$f" in *.tgz) ;; *) pvtest_log WARN "skipping non-tarball: $f"; continue ;; esac
			for s in $(_tarball_scopes "$scope"); do
				_install_one_tarball "$f" "$s" || exit 1
				found=$((found+1))
			done
		done
	done

	if [ "$found" -eq 0 ]; then
		pvtest_log ERROR "no *.tgz found in: ${srcs[*]}"
		exit 1
	fi
	pvtest_log INFO "installed $found tarball(s); manifest=$(_tarballs_manifest)"
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

# ^C/TERM handler, installed by run_test once the slot is allocated. Same name
# filters allocate_slot's stale sweep uses, so it reaps every container this
# invocation could have started, in either model.
_abort_run() {
	trap - INT TERM
	pvtest_log WARN "interrupted — tearing down slot ${slot}"

	local p
	for p in $(jobs -p); do kill -TERM "$p" > /dev/null 2>&1 || true; done

	# anchored so slot 1 never reaps slot 10's containers ("-p" runs share a host)
	docker ps -aq \
		--filter "name=pantavisor-tester-${USER}-${slot}$" \
		--filter "name=pantavisor-tester-${USER}-${slot}-" \
		--filter "name=pantavisor-appengine-${USER}-${slot}-" \
		| xargs -r docker rm -f > /dev/null 2>&1 || true
	docker rm -f "pantavisor-netsim-${USER}-${slot}" > /dev/null 2>&1 || true

	exit 130
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

# Slot-pool helpers: retype_service subshell snapshots run_test's/_run_pass's
# locals (work_path, valgrind, pvtest_pubkey, slot, pass_tag, USER).

# Boot appengine $1 with config.env $2 (detached); tester's init_device awaits readiness.
# Optional $3 = storage key: containers re-typed under the same key share one
# storage dir across generations (default: the container name = fresh storage).
# Optional $4/$5 = initial revision name and a host dir of tarballs to build it
# from, on top of the image's own pvtx.d — pv-appengine deploys that revision on
# first boot and boots into it (volatile model; see _volatile_run_one_test).
_boot_appengine() {
	local ae="$1" cfg="$2" storage_key="$3" initial_rev="$4" pvtx_extra_dir="$5"
	local PVTEST_LOG_TAG="$ae"
	local _cfg_env=() _kv
	for _kv in $cfg; do _cfg_env+=(-e "$_kv"); done
	local storage_dir="$work_path/storage/${pass_tag:-main}/${storage_key:-$ae}"
	mkdir -p "$storage_dir"
	local ae_valgrind_args=()
	if [ "$valgrind" = "true" ]; then
		mkdir -p "$work_path/valgrind/$ae"
		ae_valgrind_args=(-v "$work_path/valgrind/$ae":/tmp/valgrind)
	fi
	local ae_seed_args=()
	if [ -n "$initial_rev" ]; then
		ae_seed_args=(
			-e PV_APPENGINE_INITIAL_REV="$initial_rev"
			-v "$pvtx_extra_dir":/usr/lib/pantavisor/pvtx.extra.d:ro
		)
	fi
	touch "$work_path/${ae}.log"
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
		-v "$storage_dir":/var/pantavisor/storage \
		"${ae_valgrind_args[@]}" \
		"${ae_seed_args[@]}" \
		-e VALGRIND="$valgrind" \
		-e PV_DEBUG_SSH=1 \
		-e PV_DEBUG_SSH_AUTHORIZED_KEYS="pvtest-authorized_keys" \
		-e PV_DEBUG_SSH_PUBKEY="$pvtest_pubkey" \
		-e PV_LOG_SERVER_OUTPUTS="filetree,stdout_direct" \
		-e PV_LOG_TIMESTAMP="absolute" \
		"${_cfg_env[@]}" \
		pantavisor-appengine \
			/usr/bin/pv-appengine -c "ph_metadata.devmeta.interval=15" > /dev/null; then
		return 1
	fi
	pvtest_log DEBUG "started appengine (cfg=[${cfg:-<none>}])"
	docker logs -f "$ae" 2>/dev/null \
		| while IFS= read -r _pv_line; do printf '[%s] %s\n' "$ae" "$_pv_line"; done \
		>> "$work_path/${ae}.log" &
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

# flush a manifest stanza's accumulated key=value locals (name/type/ip/exec_cmd/tty/
# baud/hook/config/env, read from the caller's scope via bash's dynamic scoping) into
# the _dev_* arrays. type= defaults to name=, which is right for a one-off board and
# wrong only if a test pins that class — pin-worthy targets set type= explicitly.
_dev_flush_stanza() {
	[ -n "$name" ] || return 0
	if [ -z "$ip" ] || [ -z "$exec_cmd" ] || [ -z "$tty" ]; then
		pvtest_log ERROR "device '$name' in '$file' missing required field(s) (need name/ip/exec/tty)"
		return 1
	fi
	_dev_name+=("$name"); _dev_type+=("${type:-$name}")
	_dev_ip+=("$ip"); _dev_exec+=("$exec_cmd")
	_dev_tty+=("$tty"); _dev_baud+=("${baud:-115200}")
	_dev_hook+=("$hook"); _dev_config+=("$config"); _dev_env+=("$env_base")
	name=; type=; ip=; exec_cmd=; tty=; baud=; hook=; config=; env_base=
	return 0
}

# Parse a --devices manifest (blank-line separated key=value stanzas) into
# parallel arrays: _dev_name (this runner), _dev_type (its class, what a test's
# "devices" list is matched against), _dev_ip, _dev_exec, _dev_tty, _dev_baud,
# plus the config-injection fields _dev_hook/_dev_config/_dev_env (hook= names a host
# command that sets the device's boot env and power-cycles it; config= names its
# config file; env= is the board's base boot env, prepended to every test's own
# tokens). Consumed by _dev_retype_handle/_dev_retype_service when a
# manifest entry sets hook=; a device with no hook= keeps the old SKIP-only
# behavior (see run_test_attempt in pvtest-run.in).
_parse_device_manifest() {
	local file="$1"
	local name= type= ip= exec_cmd= tty= baud= hook= config= env_base= line
	_dev_name=(); _dev_type=(); _dev_ip=(); _dev_exec=(); _dev_tty=(); _dev_baud=()
	_dev_hook=(); _dev_config=(); _dev_env=()

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
			type=*) type="${line#type=}" ;;
			ip=*) ip="${line#ip=}" ;;
			exec=*) exec_cmd="${line#exec=}" ;;
			tty=*) tty="${line#tty=}" ;;
			baud=*) baud="${line#baud=}" ;;
			hook=*) hook="${line#hook=}" ;;
			config=*) config="${line#config=}" ;;
			env=*) env_base="${line#env=}" ;;
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

# Configure the tty and background a raw read into $work_path/<name>.log
# — same file-naming convention _boot_appengine uses for `docker logs -f`, so
# pvtest-run's log lookup needs no device-specific branching.
_start_device_capture() {
	local name="$1" tty="$2" baud="$3"
	touch "$work_path/${name}.log"
	if ! stty -F "$tty" "${baud:-115200}" raw -echo 2>/dev/null; then
		pvtest_log ERROR "failed to configure tty '$tty' for device '$name'"
		return 1
	fi
	cat "$tty" >> "$work_path/${name}.log" 2>/dev/null &
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

# Handle one re-type request id=$2 for slot=$3 to config=$4 (empty = teardown),
# keeping storage under key $5 across generations when non-empty.
# Backgrounded by retype_service; per-slot current container in $1/state/slot<S>.ae.
_retype_handle() {
	local ctrl="$1" id="$2" S="$3" cfg="$4" stor="$5"
	local stf="$ctrl/state/slot${S}.ae" old ae gen
	old=$(cat "$stf" 2>/dev/null)
	[ -n "$old" ] && _stop_appengine "$old"
	: > "$stf"
	if [ -z "$cfg" ] || [ "$cfg" = "__none__" ]; then
		printf 'status=down\n' > "$ctrl/resp/.tmp.$id"
		mv "$ctrl/resp/.tmp.$id" "$ctrl/resp/$id"
		return 0
	fi
	# gives (slot,S) its own 64-wide loop-device range; slot keeps this
	# unique across concurrent test.docker.sh invocations too
	cfg="$cfg PV_LOOP_INDEX_BASE=$(( (slot * 64 + S) * 64 ))"
	gen=$( ( flock -x 8
		local g; g=$(( $(cat "$ctrl/state/gen" 2>/dev/null || echo 0) + 1 ))
		printf '%s' "$g" > "$ctrl/state/gen"; printf '%s' "$g"
	) 8>"$ctrl/state/gen.lock" )
	ae="pantavisor-appengine-${USER}-${slot}-w${S}-g${gen}"
	if _boot_appengine "$ae" "$cfg" "$stor"; then
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
	local req id S cfg stor
	while [ ! -e "$ctrl/stop" ]; do
		for req in "$ctrl"/req/slot*; do
			[ -e "$req" ] || continue
			id=$(basename "$req")
			S=$(sed -n 's/^slot=//p' "$req")
			cfg=$(sed -n 's/^cfg=//p' "$req")
			stor=$(sed -n 's/^storage=//p' "$req")
			rm -f "$req"
			( _retype_handle "$ctrl" "$id" "$S" "$cfg" "$stor" ) &
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

# Handle one device re-type request id=$2 for device=$3 to config=$4 (space-
# separated PV_KEY=VALUE tokens: the device's env= base followed by the test's
# required_env). Looks up the hook=/config= command for $3 in the parsed manifest
# arrays and runs it synchronously — this is the consumer of the config-injection
# seam that _parse_device_manifest/_dev_flush_stanza have carried since parsing but
# nothing invoked. A hook exiting 0 means the hook itself succeeded (set the
# boot env, power-cycled) — it does NOT mean the device is back up; the hook
# only streams a few seconds of boot serial before returning. Confirming the
# device is actually up with the new config is the tester's job (pvtest-run's
# _setup_device_retype), not this function's.
_dev_retype_handle() {
	local ctrl="$1" id="$2" name="$3" cfg="$4"
	local i=-1 j hook= config=
	for j in "${!_dev_name[@]}"; do
		[ "${_dev_name[$j]}" = "$name" ] && { i=$j; break; }
	done
	if [ "$i" -lt 0 ]; then
		printf 'status=hookfail\n' > "$ctrl/resp/.tmp.$id"
		mv "$ctrl/resp/.tmp.$id" "$ctrl/resp/$id"
		return 0
	fi
	hook="${_dev_hook[$i]}"; config="${_dev_config[$i]}"
	if [ -z "$hook" ]; then
		printf 'status=nohook\n' > "$ctrl/resp/.tmp.$id"
		mv "$ctrl/resp/.tmp.$id" "$ctrl/resp/$id"
		return 0
	fi

	# the hook needs exclusive access to the same tty _start_device_capture is
	# tailing — pause capture around the hook call, resume after
	_stop_device_capture "$name"

	local hooklog="$work_path/dev-retype-${name}-${id}.log"
	local -a hookargs=("$hook")
	[ -n "$config" ] && hookargs+=(-c "$config")
	hookargs+=($cfg)
	if "${hookargs[@]}" > "$hooklog" 2>&1; then
		printf 'status=ok\nlog=%s\n' "$hooklog" > "$ctrl/resp/.tmp.$id"
	else
		pvtest_log ERROR "device '$name' hook failed (see $hooklog)"
		printf 'status=hookfail\nlog=%s\n' "$hooklog" > "$ctrl/resp/.tmp.$id"
	fi
	mv "$ctrl/resp/.tmp.$id" "$ctrl/resp/$id"

	_start_device_capture "$name" "${_dev_tty[$i]}" "${_dev_baud[$i]}" \
		|| pvtest_log ERROR "failed to resume tty capture for device '$name' after hook"
}

# Background device re-type service: handles $1/req/<id> requests (cfg=<required_env>)
# for the single device $2 until $1/stop appears. Only started when the manifest's
# device has a hook= configured (see _run_pass) — a device with no hook never spins
# this up, so it stays byte-for-byte today's SKIP-only behavior.
_dev_retype_service() {
	local ctrl="$1" name="$2"
	mkdir -p "$ctrl/req" "$ctrl/resp"
	local req id cfg
	while [ ! -e "$ctrl/stop" ]; do
		for req in "$ctrl"/req/*; do
			[ -e "$req" ] || continue
			id=$(basename "$req")
			cfg=$(sed -n 's/^cfg=//p' "$req")
			rm -f "$req"
			( _dev_retype_handle "$ctrl" "$id" "$name" "$cfg" ) &
		done
		sleep 0.2
	done
	wait
}

# Run one tester pass over the queue: start the re-type service, run the tester,
# stop the service and sweep this slot's appengine containers. $1 = assignment
# model (PVTEST_MODEL), $2 = pass tag namespacing ctrl/, results/, the container
# names and the per-pass log. Reads run_test's locals via dynamic scoping;
# returns the tester's exit code.
_run_pass() {
	local pass_model="$1" pass_tag="$2"
	local res=0

	local ctrl_dir="$work_path/ctrl/$pass_tag"
	if [ -z "$devices_file" ]; then
		mkdir -p "$ctrl_dir/req" "$ctrl_dir/resp" "$ctrl_dir/state"
	fi

	local _nq
	_nq=$(printf '%s\n' $pvtest_queue | grep -c .)
	if [ -n "$devices_file" ]; then
		pvtest_log INFO "=== single device: ${_nq} test(s) against ${dev_name} ==="
	else
		pvtest_log INFO "=== slot pool: ${_nq} test(s) across up to ${parallel} slot(s) ==="
	fi

	# Start the host re-type service (container runs only; never for real devices).
	# Storage lineage is persistent within a pass but always fresh at pass start
	# (covers -w workspace reuse).
	local svc_pid=""
	if [ -z "$PVTEST_EXEC" ] && [ -z "$devices_file" ]; then
		rm -rf "$work_path/storage/$pass_tag"
		retype_service "$ctrl_dir" &
		svc_pid=$!
	fi

	# Start the device re-type service — only when this device's manifest entry
	# has a hook= configured. No hook = today's behavior, byte for byte: no
	# service, no ctrl dir, no PVTEST_DEV_HOOK_CTRL passed to the tester below,
	# so run_test_attempt's SKIP gate sees it unset and mismatched tests SKIP
	# exactly as before.
	local dev_ctrl_dir="$work_path/ctrl-dev/${dev_name:-}"
	local dev_svc_pid=""
	if [ -n "$devices_file" ] && [ -n "$dev_hook" ]; then
		rm -rf "$dev_ctrl_dir"
		_dev_retype_service "$dev_ctrl_dir" "$dev_name" &
		dev_svc_pid=$!
	fi

	mkdir -p "$work_path/results/$pass_tag"

	local -a tester_run_args=(
		--net=test-appengine-net
		--name "${tester_name}"
		-e TEST_PATH="/work/$target_path"
		-e PVTEST_QUEUE="$pvtest_queue"
		-e PVTEST_MODEL="$pass_model"
		-e PVTEST_TESTER_NAME="${tester_name}"
		-e INTERACTIVE="$interactive"
		-e MANUAL="$manual"
		-e OVERWRITE="$overwrite"
		-e VERBOSE="$verbose"
		-e NETSIM="$netsim"
		-e VALGRIND="$valgrind"
		-e PH_USER="$PH_USER"
		-e PH_PASS="$PH_PASS"
		-e PVR_DISABLE_SELF_UPGRADE=true
		-e PVTEST_DEVICE_TYPE="${PVTEST_DEVICE_TYPE:-appengine}"
		-e PV_LOG_SERVER_OUTPUTS="filetree,stdout_direct"
		-e PV_LOG_TIMESTAMP="absolute"
		-e RUN_DIR=/work/results
		-e APPENGINE_LOGS=/work/hostlogs
		--rm
		"${tester_scope_args[@]}"
		-v "$work_path/results/$pass_tag":/work/results
		-v "$work_path":/work/hostlogs:ro
	)

	if [ -n "$devices_file" ]; then
		# Single-device run: pvtest-run's run_single_device drains PVTEST_QUEUE against
		# the one device over PVTEST_EXEC/PVTEST_HOST and SKIPs tests whose config.env
		# the device doesn't satisfy (PVTEST_MODEL=persistent). The later PVTEST_DEVICE_TYPE
		# -e overrides the "appengine" default set in the shared args above.
		tester_run_args+=(
			-e PVTEST_EXEC="$dev_exec"
			-e PVTEST_HOST="$dev_ip"
			-e PVTEST_DEVICE_TYPE="${PVTEST_DEVICE_TYPE:-$dev_type}"
			-e PVTEST_DEVICE_NAME="$dev_name"
			"${tester_device_args[@]}"
		)
		if [ -n "$dev_svc_pid" ]; then
			tester_run_args+=(
				-e PVTEST_DEV_HOOK_CTRL="/work/ctrl-dev"
				-e PVTEST_DEV_ENV_BASE="$dev_env"
				-v "$dev_ctrl_dir":/work/ctrl-dev
			)
		fi
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
	# redirect above and in the per-pass log a multi-pass SUMMARY reads — only the
	# non-interactive/non-manual path reaches the SUMMARY.
	docker run "${tester_run_args[@]}" "$tester_image" 2>&1 \
		| tee -a "$work_path/pass-${pass_tag}.log"
	res=${PIPESTATUS[0]}

	# Stop the re-type service and tear down any remaining slot containers.
	if [ -n "$svc_pid" ]; then
		touch "$ctrl_dir/stop"
		wait "$svc_pid" 2>/dev/null || true
	fi
	if [ -n "$dev_svc_pid" ]; then
		touch "$dev_ctrl_dir/stop"
		wait "$dev_svc_pid" 2>/dev/null || true
	fi
	if [ -z "$PVTEST_EXEC" ] && [ -z "$devices_file" ]; then
		docker ps -aq --filter "name=pantavisor-appengine-${USER}-${slot}-" | xargs -r docker rm -f 2>/dev/null || true
	fi

	return $res
}

# ssh invocation for a volatile-model appengine. Needed here because, unlike pool
# mode (where the tester derives PVTEST_EXEC itself once it learns the re-typed
# container's name over the ctrl protocol), the host already knows the volatile
# model's container name up front and passes PVTEST_EXEC/PVTEST_HOST directly,
# the same way the --devices manifest path does for real hardware.
_volatile_exec_cmd() { pvtest_ssh_cmd "$1" /tmp/pvtest_id; }

# Stage test $1's container tarballs into $2, for mounting as the appengine's
# pvtx.extra.d. Numbered to preserve pvtx add order (a later tarball overrides an
# earlier one) and to keep same-basename tarballs from different dirs apart.
_volatile_seed() {
	local tid="$1" dir="$2"
	local t src n=0

	rm -rf "$dir"; mkdir -p "$dir"
	while IFS= read -r t; do
		[ -n "$t" ] || continue
		case "$t" in
			/*) src="$t" ;;
			*) src="$test_dir/$tid/$t" ;;
		esac
		if [ ! -f "$src" ]; then
			pvtest_log ERROR "tarball '$t' not found for '$tid'"
			return 1
		fi
		cp "$src" "$(printf '%s/%02d-%s' "$dir" "$n" "${src##*/}")" || return 1
		n=$((n + 1))
	done < <(jq -r '.setup.containers.tarballs[]? // empty' "$test_dir/$tid/test.json")
	return 0
}

# One test, fully self-contained: fresh appengine (own storage key, no re-type/
# claim-batching) + one tester invocation against it via pvtest-run's
# run_single_device path (PVTEST_MODEL=volatile, PVTEST_QUEUE with a single
# test + PVTEST_DEVICE_NAME; no PVTEST_CTRL so the tester never enters the
# slot-pool dispatch) + teardown. No retries (removed harness-wide). Reads
# run_test's locals via dynamic scoping, same as _run_pass.
_volatile_run_one_test() {
	local json_path="$1" pass_tag="$2" failed_flag="$3"
	local test_id; test_id=$(echo "$json_path" | sed 's|^/work/||; s|/test\.json$||')
	# short name (this subshell's real PID) — not the full test_id, which
	# doubles the name as a DNS hostname the tester resolves over the docker
	# network, and DNS labels cap out at 63 bytes (RFC 1035); a category/name
	# test_id easily blows past that. Not pass_tag either — $BASHPID alone is
	# already unique, so it'd be redundant. $BASHPID, not $$ — $$ is the
	# top-level script's PID and is IDENTICAL across every concurrent
	# `( ... ) &` subshell _run_volatile_pass backgrounds, which would collide
	# container names at -p>1; $BASHPID is this subshell's own PID.
	local ae="pantavisor-appengine-${USER}-${slot}-${BASHPID}"
	local PVTEST_LOG_TAG="$ae"
	local cfg; cfg=$(normalize_reqcfg "$(jq -r '.setup.config.env // ""' "$test_dir/$test_id/test.json")")

	# The container is fresh and thrown away right after, so the test's own
	# revision is seeded into pv-appengine's first-boot pvtx instead of being
	# installed once pantavisor is up: the image's baked-in pvtx.d (bsp +
	# pvr-sdk, i.e. what the factory revision is made of) plus this test's
	# tarballs, deployed under the same locals/<id> name setup_test would have
	# used. That drops both the install and the commit reboot it ends with —
	# the two pantavisor boot cycles per test that the persistent model pays.
	local rev; rev="locals/$(printf '%s' "$test_id" | tr '/' '_' | tr '-' '_')"
	local seed_dir="$work_path/pvtx-seed/$pass_tag/$BASHPID"

	# binds this container name — the log tag every line below carries — to the
	# test it runs; without it run.log only shows opaque per-test container names
	pvtest_log INFO "running '$test_id'"

	local res=1
	if ! _volatile_seed "$test_id" "$seed_dir"; then
		pvtest_log ERROR "'${test_id}' ABORTED (could not stage container tarballs)"
	elif ! _boot_appengine "$ae" "$cfg" "$test_id" "$rev" "$seed_dir"; then
		pvtest_log ERROR "'${test_id}' ABORTED (appengine boot failed)"
	else
		# Route through pvtest-run's run_single_device (PVTEST_QUEUE +
		# PVTEST_DEVICE_NAME), the only non-pool test path; with
		# PVTEST_MODEL=volatile its setup_test asserts the container came up on
		# $rev rather than installing anything.
		docker run --rm \
			--net=test-appengine-net \
			--name "pantavisor-tester-${USER}-${slot}-${BASHPID}" \
			-e PVTEST_TESTER_NAME="pantavisor-tester-${USER}-${slot}-${BASHPID}" \
			-e PVTEST_QUEUE="/work/$test_id/test.json" \
			-e PVTEST_DEVICE_NAME="$ae" \
			-e PVTEST_DEVICE_TYPE="${PVTEST_DEVICE_TYPE:-appengine}" \
			-e PVTEST_TEST_TIMEOUT=600 \
			-e INTERACTIVE=false \
			-e MANUAL=false \
			-e OVERWRITE="$overwrite" \
			-e VERBOSE="$verbose" \
			-e NETSIM=false \
			-e VALGRIND="$valgrind" \
			-e PH_USER="$PH_USER" \
			-e PH_PASS="$PH_PASS" \
			-e PVR_DISABLE_SELF_UPGRADE=true \
			-e PVTEST_MODEL=volatile \
			-e PVTEST_EXEC="$(_volatile_exec_cmd "$ae")" \
			-e PVTEST_HOST="$ae" \
			-e PV_LOG_SERVER_OUTPUTS="filetree,stdout_direct" \
			-e PV_LOG_TIMESTAMP="absolute" \
			-e RUN_DIR=/work/results \
			"${tester_scope_args[@]}" \
			-v "$work_path/results/$pass_tag":/work/results \
			-v "$shared_ssh_dir/id_ed25519":/tmp/pvtest_id:ro \
			"$tester_image" \
			| tee -a "$work_path/pass-${pass_tag}.log"
		res=${PIPESTATUS[0]}
		_stop_appengine "$ae"
	fi
	rm -rf "$seed_dir"

	pvtest_log INFO "finished '$test_id' (exit $res)"

	[ "$res" -ne 0 ] && [ "$res" -ne 2 ] && touch "$failed_flag"
}

# Volatile-model pass: one fresh appengine + one tester invocation per test,
# capped at $parallel concurrent tests via a semaphore FIFO — the pre-pool
# master behaviour, reusing current building blocks (_boot_appengine,
# setup.config.env, results/<tag>/ namespacing) instead of the old exec_test.
_run_volatile_pass() {
	local pass_tag="$1" res=0
	mkdir -p "$work_path/results/$pass_tag"
	local failed_flag="$work_path/.failed-$pass_tag"

	local sem_fifo; sem_fifo=$(mktemp -u); mkfifo "$sem_fifo"
	exec {SEM_FD}<>"$sem_fifo"; rm -f "$sem_fifo"
	local i; for ((i = 0; i < parallel; i++)); do printf 'x' >&"$SEM_FD"; done

	local _nq
	_nq=$(printf '%s\n' $pvtest_queue | grep -c .)
	pvtest_log INFO "=== volatile pass: ${_nq} test(s), up to ${parallel} concurrent ==="

	local _json
	for _json in $pvtest_queue; do
		read -r -n1 -u"$SEM_FD" _tok
		( _volatile_run_one_test "$_json" "$pass_tag" "$failed_flag"; printf 'x' >&"$SEM_FD" ) &
	done
	for ((i = 0; i < parallel; i++)); do read -r -n1 -u"$SEM_FD" _tok; done
	exec {SEM_FD}>&-

	if [ -f "$failed_flag" ]; then res=1; rm -f "$failed_flag"; fi
	return $res
}

# Print the SUMMARY block for one pass: results scraped from log $1, diffs looked
# up under results/<$2>/. Returns 1 when --fail-on-skip trips.
_print_summary() {
	local logfile="$1" tag="$2"

	set +x

	# Collect results from the pass log; diffs live under results/<tag>/<tid>/.
	# rank() is a tie-break:
	#   FAILED > ABORTED > PASSED > SKIPPED > RECORDED
	local merged_file
	merged_file=$(mktemp)
	awk -v wt="$tag" '
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
				# reason like "(claim failed: ...)" is never shown as a time. For
				# SKIPPED, surface a short reason tag derived from the message.
				if (match(q[3], /\([0-9]+ s\)/)) tm = substr(q[3], RSTART, RLENGTH)
				else if (res == "SKIPPED") {
					if (q[3] ~ /not in:/)              tm = "(devices)"
					else if (q[3] ~ /required-config/) tm = "(env)"
					else if (q[3] ~ /skip:true/)       tm = "(skip)"
					else if (q[3] ~ /PH_USER/)         tm = "(creds)"
					else                               tm = ""
				}
				else tm = ""
				rk = rank(res)
				if (rk > 0) {
					if (rk > best[tid]) { best[tid]=rk; result[tid]=res; wtag[tid]=wt; time[tid]=tm }
				}
			}
		}
		END { for (t in result) printf "%s\t%s\t%s\t%s\n", t, result[t], wtag[t], time[t] }
	' "$logfile" 2>/dev/null | sort > "$merged_file"

	echo "======================================================="
	echo "======================= SUMMARY ======================="
	echo "======================================================="

	# Run-level (non-per-test) ERRORs only — excludes anything already mirrored
	# into a test.log or a per-test result line; timestamps stripped before de-dup.
	local runerr_file test_errs
	runerr_file=$(mktemp); test_errs=$(mktemp)
	find "$work_path/results/$tag" -name test.log -exec \
		grep -hE '^\[[^]]*\] .*ERROR[[:space:]]*-- ' {} + 2>/dev/null \
		| sed -E 's/^\[[^]]*\] (\[pantavisor\] )?[0-9]+ //' | sort -u > "$test_errs"
	grep -hE '^\[[^]]*\] .*ERROR[[:space:]]*-- ' "$logfile" 2>/dev/null \
		| sed -E 's/^\[[^]]*\] (\[pantavisor\] )?[0-9]+ //' | sort -u \
		| grep -vxF -f "$test_errs" 2>/dev/null \
		| grep -vE "ERROR -- \[[^]]*\]: '[^']*' (FAILED|ABORTED|PASSED|SKIPPED|RECORDED)" \
		> "$runerr_file" || true
	if [ -s "$runerr_file" ]; then
		printf -- "--- run errors ---\n"
		cat "$runerr_file"
		printf '%s\n\n' "--- end run errors ---"
	fi
	rm -f "$runerr_file" "$test_errs"

	local skip_fail_seen=0
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
					grep -E '^\[[^]]*\] .*ERROR[[:space:]]*-- ' "$tlog" 2>/dev/null
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

	if [ "$fail_on_skip" = "true" ] && [ "$skip_fail_seen" = "1" ]; then
		pvtest_log ERROR "--fail-on-skip: one or more tests were SKIPPED"
		return 1
	fi
	return 0
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
	local fail_on_skip="false"
	local devices_file=
	local model="persistent" model_explicit="false"

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
			--model)
				model="$2"
				model_explicit="true"
				shift 2
				;;
			--fail-on-skip)
				fail_on_skip="true"
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

	case "$model" in
		persistent|volatile) ;;
		*)
			pvtest_log ERROR "invalid --model '$model' (expected persistent or volatile)"
			usage
			exit 1
			;;
	esac

	# volatile needs a docker container per test — doesn't exist for real
	# hardware, so a device runs persistent only. persistent itself works fine
	# against real devices: run_single_device re-types via the manifest's hook=
	# when configured, otherwise SKIPs any test whose config.env the device
	# doesn't already satisfy.
	if [ -n "$devices_file" ] && [ "$model" != "persistent" ]; then
		if [ "$model_explicit" = "true" ]; then
			pvtest_log ERROR "--model $model is not supported with --devices; use --model persistent"
			exit 1
		fi
		pvtest_log INFO "--devices: selecting --model persistent"
		model="persistent"
	fi

	# single-target modes boot the target test's exact config.env already
	if [ "$model_explicit" = "true" ] && { [ "$interactive" = "true" ] || [ "$manual" = "true" ]; }; then
		pvtest_log ERROR "--model does not apply to -i/-m"
		usage
		exit 1
	fi

	if [ "$model" = "volatile" ] && [ "$netsim" = "true" ]; then
		pvtest_log ERROR "--model volatile is incompatible with -n (no per-test netsim wiring)"
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

	# Allocate slot for all containers in this invocation.
	allocate_slot
	local tester_name="pantavisor-tester-${USER}-${slot}"
	local netsim_name="pantavisor-netsim-${USER}-${slot}"

	# Slot is exclusively ours; any containers with this slot's names are stale
	# from an aborted run — remove them.
	docker ps -aq --filter "name=pantavisor-appengine-${USER}-${slot}-" | xargs -r docker rm -f 2>/dev/null || true
	docker ps -aq --filter "name=pantavisor-tester-${USER}-${slot}" | xargs -r docker rm -f 2>/dev/null || true
	docker rm -f "$netsim_name" 2>/dev/null || true

	# ^C: the tester's PID 1 ignores SIGINT and the appengines are detached, so
	# nothing goes away on its own. Match this slot's whole name prefix — volatile
	# runs one appengine + one tester per test, all suffixed with the subshell's
	# PID — and bail out instead of letting the pass keep spawning containers.
	# The slot lock is an open fd, so exiting releases it.
	trap '_abort_run' INT TERM

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

	# Manual mode: single appengine in interactive shell, booted with the target test's config.env; no tester.
	if [ "$manual" = "true" ]; then
		local manual_cfg_args=() _mkv
		for _mkv in $(normalize_reqcfg "$(jq -r '.setup.config.env // ""' "$test_dir/$target_path/test.json")"); do
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
	local dev_name= dev_type= dev_ip= dev_exec= dev_hook= dev_config= dev_env= tester_device_args=()
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

		dev_name="${_dev_name[0]}"; dev_type="${_dev_type[0]}"
		dev_ip="${_dev_ip[0]}"; dev_exec="${_dev_exec[0]}"
		dev_hook="${_dev_hook[0]}"; dev_config="${_dev_config[0]}"
		dev_env="${_dev_env[0]}"
		local PVTEST_LOG_TAG="$dev_name"

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

	# Resolve the target class and mount its container tarballs over the suites'
	# common/tarballs/. Only the tarballs vary by target (architecture + signing CA),
	# so local/ and remote/ stay shared single-copy trees: the tester always sees
	# /work/<scope>/common/tarballs whichever target supplied it. That is what keeps
	# every test.json's relative ../../common/tarballs/ reference — and the five
	# absolute /work/local/common/tarballs/ references inside test scripts — working
	# unchanged for any target, with no per-target copy of the suites.
	#
	# Docker applies nested bind-mounts by path depth, so these land inside the
	# /work/<scope> mounts built above rather than racing them.
	#
	# Precedence matches the PVTEST_DEVICE_TYPE the tester is handed below: an
	# explicit env override, else the manifest's type=, else appengine.
	local target_type abs_targets_path=
	target_type="${PVTEST_DEVICE_TYPE:-${dev_type:-appengine}}"
	if [ ! -d "$test_dir/targets/$target_type" ]; then
		pvtest_log ERROR "no container tarballs for target type '$target_type'"
		pvtest_log ERROR "  expected: $test_dir/targets/$target_type/{local,remote}"
		pvtest_log ERROR "  available: $(ls "$test_dir/targets" 2>/dev/null | tr '\n' ' ')"
		pvtest_log ERROR "  add one with: ./test.docker.sh install-tarballs -t $target_type <exports>"
		if [ -n "$devices_file" ]; then
			_stop_device_capture "$dev_name"
			_unlock_device "$dev_name"
		fi
		release_slot
		return 1
	fi
	abs_targets_path=$(cd "$test_dir/targets/$target_type" && pwd)
	[ -n "$abs_local_path" ] && [ -d "$abs_targets_path/local" ] \
		&& tester_scope_args+=(-v "$abs_targets_path/local":/work/local/common/tarballs)
	[ -n "$abs_remote_path" ] && [ -d "$abs_targets_path/remote" ] \
		&& tester_scope_args+=(-v "$abs_targets_path/remote":/work/remote/common/tarballs)
	# INFO, not DEBUG: this is the line explaining why a run's container payload
	# differs from a pristine appengine run, so it must survive a grep -v DEBUG.
	_tarball_target="$target_type"
	{
		pvtest_log INFO "target type: $target_type (tarballs from targets/$target_type)"
		_log_tarball_overrides "$work_path"
	} | tee -a "$work_path/run.log"

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
				-e PVTEST_DEVICE_TYPE="${PVTEST_DEVICE_TYPE:-$dev_type}"
				-e PVTEST_DEVICE_NAME="$dev_name"
				"${tester_device_args[@]}"
			)
		else
			local _icfg
			_icfg=$(normalize_reqcfg "$(jq -r '.setup.config.env // ""' "$test_dir/$target_path/test.json")")
			_iae="pantavisor-appengine-${USER}-${slot}-w0-g1"
			_boot_appengine "$_iae" "$_icfg"
			iface_args=(
				-e PVTEST_APPENGINES="$_iae"
				-e PVTEST_SSH_KEY="/tmp/pvtest_id"
				-e PVTEST_DEVICE_TYPE="${PVTEST_DEVICE_TYPE:-appengine}"
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

	local res=0
	if [ "$model" = "volatile" ]; then
		_run_volatile_pass volatile || res=1
	else
		_run_pass "$model" main || res=1
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

	local skip_fail=0
	if [ "$model" = "volatile" ]; then
		_print_summary "$work_path/pass-volatile.log" volatile || skip_fail=1
	else
		_print_summary "$work_path/run.log" main || skip_fail=1
	fi

	# make summary available to the run path for the CI
	[ "${CI:-false}" = "true" ] && cp "$work_path/run.log" ./run.log

	cat > "$work_path/README.md" << 'EOF'
# Test Run Results

## Workspace Layout

```
<workspace>/
  run.log                           <- aggregate output (host + tester) + SUMMARY
  pass-<tag>.log                    <- per-pass tester output; tag is "main", or
                                       "volatile" with --model volatile
  <name>.log                        <- console capture for one target, keyed by name:
                                       appengine mode -> full pantavisor stdout_direct
                                       (docker logs, keyed by container name)
                                       device mode    -> raw serial console (from its tty,
                                       keyed by the --devices manifest name=)
  README.md
  pvtest-tarballs.manifest          <- present only when container tarballs were
                                       substituted via `install-tarballs`; records
                                       which ones, from where, and their checksums
  ctrl/<tag>/                       <- re-type protocol dirs (transient)
  ctrl-dev/<name>/                  <- device re-type protocol dir (transient, only
                                       when the --devices manifest sets hook=)
  pvtx-seed/<tag>/<pid>/            <- volatile model only: the test's tarballs, mounted
                                       into the container's pvtx.extra.d (transient)
  results/
    <tag>/<scope>/<category>/<name>/
      test.log     <- test script output interleaved with target console logs during exec_test
      diff         <- diff (expected vs actual), present only when test failed
  storage/          <- appengine mode only (a real device keeps its own on-device storage)
    <tag>/<key>/   <- persistent pantavisor storage lineage: one per worker in the
                      persistent model (w<N>), one per test in the volatile model
                      (fresh every time, never persistent); fresh at pass start,
                      kept across re-types where the model persists storage at all
      trails/ objects/ logs/ ...
  valgrind/         <- appengine mode only, with -V
    <container>/   <- per-appengine valgrind output
      valgrind.log.<pid>
```

One tester (`pvtest-run`) drives each pool pass; see `docs/overview/testing/automated/devices.md`
for the full model. `--model` picks the assignment model:
- **persistent** (default) — every test runs under exactly its `config.env`:
  `-p` workers each keep ONE storage for the whole pass, settling back to a
  gc'd factory state between tests and re-booting with new config only when
  the next test actually needs it (at most one power cycle between tests).
- **volatile** — master-like: one fresh appengine container per test (own
  storage, no re-typing), `-p` capping how many run concurrently. The test's
  tarballs are seeded into `pvtx.extra.d` so `pv-appengine` deploys the test's
  own `locals/<id>` revision on first boot and boots into it committed, which
  is what makes the model cheap: no install and no commit reboot, one
  pantavisor boot per test instead of three. Incompatible with `--devices`
  and `-n`.
- **device mode (`--devices`)** — persistent only: every selected test runs
  sequentially against the single real device (no pool). If the manifest entry
  sets `hook=` (a host command that sets the device's boot env and
  power-cycles it, with `config=` as that command's config file), a test whose
  `config.env` doesn't match triggers a re-type through the hook instead of
  skipping. The hook gets the entry's `env=` base tokens first and the test's
  own last, so a hook that writes the boot env as a full replacement keeps the
  board bootable. Without `hook=`, tests whose `config.env` the live device doesn't
  satisfy are SKIPPED as before, so run **without** `--fail-on-skip` until each
  test's `"devices"` array is triaged.
- Want both models? Just run `test.docker.sh` twice, once per `--model`.

The SUMMARY collects the per-test results.
EOF

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

	cat >> "$work_path/README.md" << 'EOF'

## Valgrind Logs (appengine mode, -V)

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
	install-tarballs)
		install_tarballs "$@"
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
