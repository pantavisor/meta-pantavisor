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
	echo "  -r, --retry N         Retry failed tests up to N times (default: 0)"
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
		echo "Error: Missing test path (scope/category/name)"
		usage
		exit 1
	fi
	test_path="$1"
	shift

	while [ $# -gt 0 ]; do
		case "$1" in
			*)
				echo "Error: Unknown argument: $1"
				usage
				exit 1
				;;
		esac
	done

	local full_path="$test_dir/$test_path"
	local scope=$(echo "$test_path" | cut -d'/' -f1)

	if [ -e "$full_path" ]; then
		echo "Error: '$full_path' already exists"
		exit 1
	fi

	local common_path="$test_dir/$scope/common"
	if [ ! -d "$common_path" ]; then
		echo "Error: common directory '$common_path' missing"
		exit 1
	fi

	mkdir -p "$full_path/resources"
	cp "$common_path/templates/template.test.json" "$full_path/test.json"
	cp "$common_path/templates/template.test" "$full_path/resources/test"
	chmod +x "$full_path/resources/test"
	cp "$common_path/templates/template.ready" "$full_path/resources/ready"
	chmod +x "$full_path/resources/ready"

	echo "Info: New test created at: $full_path"
}

install_docker() {

	# install app engine docker containers
	NETSIM_PATH=${NETSIM_PATH:-"pantavisor-appengine-netsim-docker.tar"}
	if [ -f "$NETSIM_PATH" ]; then
		docker load -i "$NETSIM_PATH"
	fi
	TESTER_PATH=${TESTER_PATH:-"pantavisor-appengine-tester-docker.tar"}
	if [ -f "$TESTER_PATH" ]; then
		docker load -i "$TESTER_PATH"
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

	echo "Dependency installation complete"

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
		echo "Error: $netsim_name not responding"
		exit 1
	fi
	local pid=$(docker inspect -f '{{.State.Pid}}' "$netsim_name")

	local ap_phy=$(echo "$new_phys" | sed -n '1p')
	sudo -n iw phy "phy$ap_phy" set netns "$pid"

	wait_for_status "docker inspect -f '{{.State.Pid}}' $tester_name" 0 5 > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Error: $tester_name not responding"
		exit 1
	fi
	local pid=$(docker inspect -f '{{.State.Pid}}' "$tester_name")

	local cl_phy=$(echo "$new_phys" | sed -n '2p')
	sudo -n iw phy "phy$cl_phy" set netns "$pid"
}

teardown_network() {
	sudo -n modprobe -r mac80211_hwsim
}

exec_test() {
	local json_path=$1
	local interactive=$2
	local manual=$3
	local overwrite=$4
	local work_path=$5
	local netsim=$6
	local valgrind=$7

	if [ ! -f "$json_path" ]; then
		echo "Error: '$json_path' missing"
		exit 1
	fi

	docker_it_opt=
	if [ "$interactive" = "true" ]; then
		docker_it_opt="-it"
	fi

	env=$(jq -r '.setup.env' "$json_path")

	test_path=$(dirname "$json_path")
	cd "$test_path"; abs_test_path=$(pwd); cd - > /dev/null
	cd "$test_path/../../common"; abs_common_path=$(pwd); cd - > /dev/null

	test_id=$(echo "$json_path" | sed 's|^\./||; s|/test\.json$||')

	mkdir -p "$work_path/storage/$test_id/"
	cd "$work_path/storage/$test_id/"; abs_storage_path=$(pwd); cd - > /dev/null
	mkdir -p "$work_path/valgrind/$test_id/"
	cd "$work_path/valgrind/$test_id/"; abs_valgrind_path=$(pwd); cd - > /dev/null

	# Per-run slot used to disambiguate container names and host ports so
	# multiple test.docker.sh invocations can run concurrently. Slot 0 keeps
	# the original 8222 host port for backwards compatibility. allocate_slot
	# sets `slot` and `SLOT_LOCK_FD` globals; the lock is held until
	# release_slot or process exit.
	allocate_slot
	tester_name="pantavisor-tester-${slot}"
	netsim_name="pantavisor-netsim-${slot}"
	host_port=$((8222 + slot))
	# losetup -D would detach loop devices used by sibling parallel runs, so
	# we no longer call it. losetup -f needs root on CI runners where
	# /dev/loop* is not world-readable — match the privilege the previous
	# `sudo -n losetup -D` line ran with. The race between concurrent callers
	# is benign: the container also gets /dev/loop-control + a 'b 7:* rmw'
	# device-cgroup rule, so it can allocate its own loop devices internally
	# regardless of which one we preview here.
	unused_lo=$(sudo -n losetup -f)

	start=$(date +%s)

	setup_network0

	if [ "$netsim" = "true" ]; then

		docker run \
			--name "$netsim_name" \
			--net=test-appengine-net \
			-d \
			-e VERBOSE="$verbose" \
			--rm \
			--cap-add NET_ADMIN \
			pantavisor-appengine-netsim > /dev/null

		setup_network "$tester_name" "$netsim_name" &
	fi
	docker run \
		--net=test-appengine-net \
		--name "$tester_name" \
		-e TEST_PATH="/work/$test_path" \
		-e INTERACTIVE="$interactive" \
		-e MANUAL="$manual" \
		-e OVERWRITE="$overwrite" \
		-e VERBOSE="$verbose" \
		-e NETSIM="$netsim" \
		-e VALGRIND="$valgrind" \
		-e PH_USER="$PH_USER" \
		-e PH_PASS="$PH_PASS" \
		-e PVR_DISABLE_SELF_UPGRADE=true \
		-e PV_LOG_SERVER_OUTPUTS="filetree,stdout_direct" \
		--env-file <(echo "$env" | tr ' ' '\n') \
		$docker_it_opt \
		--rm \
		--cgroupns host \
		--cap-add MKNOD \
		--cap-add NET_ADMIN \
		--cap-add SYS_ADMIN \
		--cap-add SYS_PTRACE \
		--device /dev/kmsg \
		--device /dev/hwrng \
		--device "$unused_lo" \
		--device /dev/loop-control \
		--device /dev/mapper \
		--device-cgroup-rule 'b 7:* rmw' \
		--device-cgroup-rule 'a 252:0 rmw' \
		--security-opt apparmor=unconfined \
		--security-opt seccomp=unconfined \
		--volume "/sys/fs":"/sys/fs" \
		--mount type=tmpfs,target="/usr/lib/lxc/rootfs" \
		--mount type=tmpfs,target="/volumes" \
		--mount type=tmpfs,target="/configs" \
		-p ${host_port}:8222 \
		-v "$abs_test_path":"/work/$test_path" \
		-v "$abs_common_path":"/work/$test_path/../../common" \
		-v "$abs_storage_path":/var/pantavisor/storage \
		-v "$abs_valgrind_path":/tmp/valgrind \
		pantavisor-appengine-tester
	res=$?

	sudo -n chmod -R a+rX "$work_path/storage/$test_id/" 2>/dev/null || true

	# Detach only loop devices whose backing file lives under this run's
	# storage tree. Targets exactly what we created — leaves sibling parallel
	# runs (and any unrelated host loop devices) untouched.
	sudo -n losetup -nO NAME,BACK-FILE 2>/dev/null \
		| awk -v p="$abs_storage_path/" '$2 ~ "^"p {print $1}' \
		| while read -r lo; do
			[ -n "$lo" ] && sudo -n losetup -d "$lo" 2>/dev/null || :
		done

	if [ "$netsim" = "true" ]; then
		docker stop "$netsim_name" > /dev/null 2>&1
		docker wait "$netsim_name" > /dev/null 2>&1

		teardown_network
	fi

	release_slot "$slot"

	end=$(date +%s)
	runtime=$(echo "$end - $start" | bc)

	if [ "$interactive" = "true" ] || [ "$manual" = "true" ]; then
		return
	fi

	if [ $res -eq 0 ]; then
		echo -e "Info: '$test_id' ${GREEN}PASSED${NOCOLOR} ($runtime s)"
		return 0
	elif [ $res -eq 2 ]; then
		echo -e "Info: '$test_id' ${ORANGE}ABORTED${NOCOLOR} ($runtime s)"
		return 2
	else
		echo -e "Info: '$test_id' ${RED}FAILED${NOCOLOR} ($runtime s)"
			return 1
	fi
}

run_with_retry() {
	local json_path=$1
	local attempt=0
	local result test_id
	while true; do
		exec_test "$json_path" "$interactive" "$manual" "$overwrite" "$work_path" "$netsim" "$valgrind"
		result=$?
		[ $result -eq 0 ] && return 0
		attempt=$((attempt + 1))
		if [ $result -ne 1 ] || [ $attempt -gt $max_retries ]; then
			return 1
		fi
		test_id=$(echo "$json_path" | sed 's|^\./||; s|/test\.json$||')
		echo "Retry: '$test_id' attempt $attempt/$max_retries after failure..."
		sleep 5
	done
}

skip_test () {
	local json_path="$1"
	local work_path=$2

	test_id=$(echo "$json_path" | sed 's|^\./||; s|/test\.json$||')

	skip=$(jq -r '.skip' "$json_path")
	if [ "$skip" = "true" ]; then
		echo -e "Info: '$test_id' ${ORANGE}SKIPPED${NOCOLOR}"
		return 1
	fi

	return 0
}

run_test() {
	local target_path=
	local overwrite="false"
	local interactive="false"
	local manual="false"
	local work_path=$(mktemp -d -t pv_appengine.XXXXXX)
	local netsim="false"
	local valgrind="false"
	local max_retries=0
	local failed_flag="$work_path/.failed"

	if [ -n "$1" ] && [ "$(printf '%s' "$1" | cut -c1)" != "-" ]; then
		target_path="$1"
		shift
	fi

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
			-r|--retry)
				max_retries="$2"
				shift 2
				;;
			*)
				echo "Error: Unknown argument: $1"
				usage
				exit 1
				;;
		esac
	done

	if [ "$interactive" = true ] && [ -z "$target_path" ]; then
		echo "Error: Interactive mode requires a specific test path"
		usage
		exit 1
	fi

	if [ "$interactive" = true ] && [ ! -f "$test_dir/$target_path/test.json" ]; then
		echo "Error: '$target_path' is not a leaf test (no test.json found)"
		usage
		exit 1
	fi

	if [ "$overwrite" = "true" ] && [ "$interactive" = "true" ]; then
		echo "Error: Cannot use overwrite and interactive at the same time"
		usage
		exit 1
	fi

	mkdir -p "$work_path"
	echo "Info: test logs can be found at $work_path/test.docker.log"
	exec > >(tee -a "$work_path/test.docker.log") 2>&1

	if [ -z "$target_path" ]; then
		find $test_dir/ -name "test.json" | sort | while read -r json_path; do
			skip_test "$json_path" "$work_path"
			if [ $? -ne 0 ]; then continue; fi
			run_with_retry "$json_path"
			if [ $? -ne 0 ]; then touch "$failed_flag"; fi
		done
	elif [ -f "$test_dir/$target_path/test.json" ]; then
		json_path="$test_dir/$target_path/test.json"
		run_with_retry "$json_path"
		if [ $? -ne 0 ]; then touch "$failed_flag"; fi
	else
		find "$test_dir/$target_path" -name "test.json" | sort | while read -r json_path; do
			skip_test "$json_path" "$work_path"
			if [ $? -ne 0 ]; then continue; fi
			run_with_retry "$json_path"
			if [ $? -ne 0 ]; then touch "$failed_flag"; fi
		done
	fi

	set +x
	echo "======================================================="
	echo "======================= SUMMARY ======================="
	echo "======================================================="
	if [ "$verbose" = "true" ]; then
		echo "Info: workspace=$work_path"
		echo "Info: logs=$work_path/test.docker.log"
		if [ "$valgrind" = "true" ]; then
			echo "Info: valgrind results=$work_path/valgrind"
		fi
		echo "Info: Pantavisor storage=$work_path/storage"
		echo ""
	fi
	grep "^Info: 'local\|^Info: 'remote" "$work_path/test.docker.log"
	grep "^Info: '.*FAILED" "$work_path/test.docker.log" \
		| sed "s/^Info: '//; s/'[[:space:]].*//" \
		| sort -u \
		| while read -r test_id; do
			diff_file="$work_path/storage/$test_id/diff"
			[ -s "$diff_file" ] || continue
			printf "\n--- diff: %s ---\n" "$test_id"
			cat "$diff_file"
			printf "--- end diff ---\n"
		done
	echo "======================================================="
	set -h

	# make summary available to the run path for the CI
	cp $work_path/test.docker.log ./test.docker.log

	if [ -f "$failed_flag" ]; then
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
	echo "Error: Missing command"
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
		echo "Error: Unknown command: $command"
		usage
		exit 1
		;;
esac
