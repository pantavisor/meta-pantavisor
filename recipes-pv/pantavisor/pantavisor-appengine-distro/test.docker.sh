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
	echo "  add <group>          Create a new test"
	echo "  install-deps         Install dependencies (and docker)"
	echo "  install-docker       Install docker"
	echo "  ls                   List all tests"
	echo "  run [group[:number]] Run one to many tests"
	echo ""
	echo "Arguments for 'run' command:"
	echo "  -i, --interactive Run the test interactively for debugging"
	echo "  -s, --storage     Set a path for /storage"
	echo "  -m, --manual      Avoid starting Pantavisor for debugging"
	echo "  -n, --netsim      Use the network simulator (experimental)"
	echo "  -o, --overwrite   Create or overwrite the test output"
	echo ""
	echo "Environments:"
	echo "  NETSIM_PATH      Path to docker load for netsim container"
	echo "  TESTER_PATH      Path to docker load for tester container"
	echo "  APPENGINE_PATH   Path to docker load for tester container"
	echo "  PVTEST_DIR       Directory to pvtest sources to run"
	echo ""
}

list_tests() {
	printf "%-15s %-10s\n" "test" "description"
	printf "%-15s %-10s\n" "====" "==========="
	find $test_dir/ -name "test.json" | sort  | while read -r json_path; do
		IFS="/" 
		set -- $json_path
		shifts_needed=$(($# - 5))
		shift $shifts_needed
		description=$(jq -r '.description' "$json_path")
		printf "%-15s %-10s\n" $2:$4 $description
	done
}

add_test() {
	local group=

	if [ -z "$1" ]; then
		echo "Error: Missing group"
		usage
		exit 1
	fi
	group="$1"
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
	
	if [ ! -d "$test_dir/$group" ]; then
		echo "Error: '$test_dir/$group' directory missing"
		exit 1
	fi

	test_number=0
	test_data="$test_dir/$group/data"
	if [ -d "$test_data" ]; then
		last_test_number=$(find "$test_data" -maxdepth 1 -type d -name "[0-9]*" | sed 's#.*/##' | sort -n | tail -1)
		if [ ! -z "$last_test_number" ]; then
			test_number=$((last_test_number + 1))
		fi
	fi

	mkdir -p "$test_data"

	test_data="$test_data/$test_number"
	mkdir "$test_data"
	cp "$test_data/../../common/templates/template.test.json" "$test_data/test.json"

	mkdir "$test_data/resources"
	cp "$test_data/../../common/templates/template.test" "$test_data/resources/test"
	chmod +x "$test_data/resources/test"
	cp "$test_data/../../common/templates/template.ready" "$test_data/resources/ready"
	chmod +x "$test_data/resources/ready"

	echo "Info: New test created at: $test_data"
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
    read -n1 answer
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

generate_unique_id() {
	local group=$1
	local number=$2
	echo "${group}_${number}"
}

setup_network0() {
	local unique_id=$1

	if ! test -n "`docker network inspect test-appengine-net-${unique_id} >/dev/null 2>&1 | jq -r '.[].Options | select ( .["com.docker.network.container_iface_prefix"] == "lxcbrdock")'`"; then
		docker network remove test-appengine-net-${unique_id} >/dev/null 2>&1
		docker network create --driver=bridge --opt com.docker.network.container_iface_prefix=lxcbrdock test-appengine-net-${unique_id} >/dev/null
	fi
}

setup_network() {
	local unique_id=$1

	sleep 1
	sudo -n modprobe -r mac80211_hwsim

	local before_phy=$(iw dev | grep -oP '(?<=phy#)\d+')
	sudo -n modprobe mac80211_hwsim radios=3
	local after_phy=$(iw dev | grep -oP '(?<=phy#)\d+')
	local new_phys=$(comm -13 <(echo "$before_phy" | sort) <(echo "$after_phy" | sort))

	wait_for_status "docker inspect -f '{{.State.Pid}}' pantavisor-netsim-${unique_id}" 0 5 > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Error: pantavisor-netsim-${unique_id} not responding"
		exit 1
	fi
	local pid=$(docker inspect -f '{{.State.Pid}}' pantavisor-netsim-${unique_id})

	local ap_phy=$(echo "$new_phys" | sed -n '1p')
	sudo -n iw phy "phy$ap_phy" set netns "$pid"

	wait_for_status "docker inspect -f '{{.State.Pid}}' pantavisor-tester-${unique_id}" 0 5 > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Error: pantavisor-tester-${unique_id} not responding"
		exit 1
	fi
	local pid=$(docker inspect -f '{{.State.Pid}}' pantavisor-tester-${unique_id})

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

	IFS="/" 
	set -- $json_path
	local group=$2
	local number=$4
	local unique_id=$(generate_unique_id "$group" "$number")
	local port=$(echo "$unique_id" | cksum | awk '{print $1 % 50000 + 10000}')

	mkdir -p "$work_path/storage/$2/$4/"
	cd "$work_path/storage/$2/$4/"; abs_storage_path=$(pwd); cd - > /dev/null

	sudo -n losetup -D
	unused_lo=$(losetup -f)

	start=$(date +%s)

	setup_network0 "$unique_id"

	if [ "$netsim" = "true" ]; then

		docker run \
			--name "pantavisor-netsim-${unique_id}" \
			--net=test-appengine-net-${unique_id} \
			-d \
			-e VERBOSE="$verbose" \
			--rm \
			--cap-add NET_ADMIN \
			pantavisor-appengine-netsim > /dev/null

		setup_network "$unique_id" &
	fi

	docker run \
		--net=test-appengine-net-${unique_id} \
		--name "pantavisor-tester-${unique_id}" \
		-e TEST_PATH="/work/$test_path" \
		-e INTERACTIVE="$interactive" \
		-e MANUAL="$manual" \
		-e OVERWRITE="$overwrite" \
		-e VERBOSE="$verbose" \
		-e NETSIM="$netsim" \
		-e PH_USER="$PH_USER" \
		-e PH_PASS="$PH_PASS" \
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
		-p ${port}:8222 \
		-v "$abs_test_path":"/work/$test_path" \
		-v "$abs_common_path":"/work/$test_path/../../common" \
		-v "$abs_storage_path":/var/pantavisor/storage \
		pantavisor-appengine-tester
	res=$?

	sudo losetup -d "$unused_lo" 2>/dev/null

	sudo -n chmod -R a+rx "$work_path/storage/$2/$4/logs"

	if [ "$netsim" = "true" ]; then
		docker stop "pantavisor-netsim-${unique_id}" > /dev/null 2>&1
		docker wait "pantavisor-netsim-${unique_id}" > /dev/null 2>&1

		teardown_network
	fi

	docker network remove "test-appengine-net-${unique_id}" >/dev/null 2>&1

	end=$(date +%s)
	runtime=$(echo "$end - $start" | bc)

	if [ "$interactive" = "true" ] || [ "$manual" = "true" ]; then
		return
	fi

	if [ $res -eq 0 ]; then
		echo -e "Info: '$2:$4' ${GREEN}PASSED${NOCOLOR} ($runtime s)"
	elif [ $res -eq 2 ]; then
		echo -e "Info: '$2:$4' ${ORANGE}ABORTED${NOCOLOR} ($runtime s)"
	else
		echo -e "Info: '$2:$4' ${RED}FAILED${NOCOLOR} ($runtime s)"
	fi
}

skip_test () {
	local json_path="$1"
	local work_path=$2

	IFS="/" 
	set -- $json_path

	skip=$(jq -r '.skip' "$json_path")
	if [ "$skip" = "true" ]; then
		echo -e "Info: '$2:$4' ${ORANGE}SKIPPED${NOCOLOR}"
		return 1
	fi

	return 0
}

run_test() {
	local group=
	local number=
	local overwrite="false"
	local interactive="false"
	local manual="false"
	local work_path=$(mktemp -d -t pv_appengine.XXXXXX)
	local netsim="false"

	if [ -n "$1" ] && [ "$(printf '%s' "$1" | cut -c1)" != "-" ]; then
		group=$(echo "$1" | awk -F':' '{print $1}')
		number=$(echo "$1" | awk -F':' '{print $2}')
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
			*)
				echo "Error: Unknown argument: $1"
				usage
				exit 1
				;;
		esac
	done
	
	if [ -n "$number" ] && [ -z "$group" ]; then
		echo "Error: Missing group argument"
		usage
		exit 1
	fi

	if [ "$interactive" = true ] && [ -z "$number" ]; then
		echo "Error: Missing number argument"
		usage
		exit 1
	fi

	if [ "$overwrite" = "true" ] && [ "$interactive" = "true" ]; then
		echo "Error: Cannot use overwrite and interactive at the same time"
		usage
		exit 1
	fi

	echo "Info: test logs can be found at $work_path/test.docker.log"
	exec > >(tee -a "$work_path/test.docker.log") 2>&1

	common_path="$test_dir/common"
	if [ -z "$group" ]; then
		find $test_dir/ -name "test.json" | sort | while read -r json_path; do
			skip_test "$json_path" "$work_path"
			if [ $? -ne 0 ]; then continue; fi
			exec_test "$json_path" "$interactive" "$manual" "$overwrite" "$work_path" "$netsim"
		done
	elif [ -z "$number" ]; then
		find "$test_dir/$group" -name "test.json" | sort  | while read -r json_path; do
			skip_test "$json_path" "$work_path"
			if [ $? -ne 0 ]; then continue; fi
			exec_test "$json_path" "$interactive" "$manual" "$overwrite" "$work_path" "$netsim"
		done
	else
		json_path="$test_dir/$group/data/$number/test.json"
		exec_test "$json_path" "$interactive" "$manual" "$overwrite" "$work_path" "$netsim"
	fi

	if [ "$verbose" = "true" ]; then
		set +x
		echo "======================================================="
		echo "======================= SUMMARY ======================="
		echo "======================================================="
		echo "Info: workspace=$work_path"
		echo "Info: logs=$work_path/test.docker.log"
		echo "Info: Pantavisor storage=$work_path/storage"
		echo ""
		grep "^Info: 'pvtests-" "$work_path/test.docker.log"
		echo "======================================================="
		set -h
	fi
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
