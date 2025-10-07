#!/bin/bash

usage() {
	echo ""
	echo "Usage: $0 [options] <command> [arguments]"
	echo "Run and create Pantavisor tests"
	echo ""
	echo "Options:"
	echo "  -h, --help    Display this help message"
	echo "  -v, --verbose Print debug logs"
	echo ""
	echo "Commands:"
	echo "  add <group>          Create a new test"
	echo "  install-deps         Install dependencies"
	echo "  ls                   List all tests"
	echo "  run [group[:number]] Run one to many tests"
	echo ""
	echo "Arguments for 'run' command:"
	echo "  -i, --interactive Run the test interactively for debugging"
	echo "  -l, --logs        Set a path for logs"
	echo "  -m, --manual      Avoid starting Pantavisor for debugging"
	echo "  -n, --netsim      Use the network simulator (experimental)"
	echo "  -o, --overwrite   Create or overwrite the test output"
	echo ""
}

list_tests() {
	printf "%-15s %-10s\n" "test" "description"
	printf "%-15s %-10s\n" "====" "==========="
	find tests/ -name "test.json" | sort  | while read -r json_path; do
		IFS="/" 
		set -- $json_path
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
	
	if [ ! -d "tests/$group" ]; then
		echo "Error: 'tests/$group' directory missing"
		exit 1
	fi

	test_number=0
	test_dir="tests/$group/data"
	if [ -d "$test_dir" ]; then
		last_test_number=$(find "$test_dir" -maxdepth 1 -type d -name "[0-9]*" | sed 's#.*/##' | sort -n | tail -1)
		if [ ! -z "$last_test_number" ]; then
			test_number=$((last_test_number + 1))
		fi
	fi

	mkdir -p "$test_dir"
	test_dir="$test_dir/$test_number"
	mkdir "$test_dir"
	cp "$test_dir/../../common/templates/template.test.json" "$test_dir/test.json"

	mkdir "$test_dir/resources"
	cp "$test_dir/../../common/templates/template.test" "$test_dir/resources/test"
	chmod +x "$test_dir/resources/test"
	cp "$test_dir/../../common/templates/template.ready" "$test_dir/resources/ready"
	chmod +x "$test_dir/resources/ready"

	echo "Info: New test created at: $test_dir"
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

	# install app engine docker containers
	netsim_path="docker/x64-appengine-netsim.tar"
	if [ -f "$netsim_path" ]; then
		docker load -i "$netsim_path"
	fi
	tester_path="docker/x64-appengine-tester.tar"
	if [ -f "$tester_path" ]; then
		docker load -i "$tester_path"
	fi

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

	if ! test -n "`docker network inspect test-appengine-net >/dev/null 2>&1 | jq -r '.[].Options | select ( .["com.docker.network.container_iface_prefix"] == "lxcbrdock")'`"; then
		docker network remove test-appengine-net >/dev/null 2>&1
		docker network create --driver=bridge --opt com.docker.network.container_iface_prefix=lxcbrdock test-appengine-net >/dev/null
	fi
}

setup_network() {
	sleep 1
	sudo modprobe -r mac80211_hwsim

	local before_phy=$(iw dev | grep -oP '(?<=phy#)\d+')
	sudo modprobe mac80211_hwsim radios=3
	local after_phy=$(iw dev | grep -oP '(?<=phy#)\d+')
	local new_phys=$(comm -13 <(echo "$before_phy" | sort) <(echo "$after_phy" | sort))

	wait_for_status "docker inspect -f '{{.State.Pid}}' pantavisor-netsim" 0 5 > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Error: pantavisor-netsim not responding"
		exit 1
	fi
	local pid=$(docker inspect -f '{{.State.Pid}}' pantavisor-netsim)

	local ap_phy=$(echo "$new_phys" | sed -n '1p')
	sudo iw phy "phy$ap_phy" set netns "$pid"

	wait_for_status "docker inspect -f '{{.State.Pid}}' pantavisor-tester" 0 5 > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Error: pantavisor-tester not responding"
		exit 1
	fi
	local pid=$(docker inspect -f '{{.State.Pid}}' pantavisor-tester)

	local cl_phy=$(echo "$new_phys" | sed -n '2p')
	sudo iw phy "phy$cl_phy" set netns "$pid"
}

teardown_network() {
	sudo modprobe -r mac80211_hwsim
}

exec_test() {
	local json_path=$1
	local interactive=$2
	local manual=$3
	local overwrite=$4
	local logs_path=$5
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
	mkdir -p "$logs_path/$2/$4/"
	cd "$logs_path/$2/$4/"; abs_logs_path=$(pwd); cd - > /dev/null

	sudo -v
	sudo losetup -D
	unused_lo=$(losetup -f)

	start=$(date +%s)

	setup_network0

	if [ "$netsim" = "true" ]; then

		docker run \
			--name "pantavisor-netsim" \
			--net=test-appengine-net \
			-d \
			-e VERBOSE="$verbose" \
			--rm \
			--cap-add NET_ADMIN \
			pantavisor-netsim > /dev/null

		setup_network &
	fi
 	# for multiple instsances --name would need to be a name unique per instance
	# TEST_PATH results folder would need to be instance namespaced as well to not overwrite each other
	# for sudo maybe unused_lo creation and assignment can go inside docker with CAPs
	docker run \
		--net=test-appengine-net \
		--name "pantavisor-tester" \
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
		--mount type=tmpfs,target="/usr/lib/lxc/rootfs" \
		--mount type=tmpfs,target="/volumes" \
		--mount type=tmpfs,target="/configs" \
		-p 8222:8222 \
		--volume "/sys/fs":"/sys/fs" \
		-v "$abs_test_path":"/work/$test_path" \
		-v "$abs_common_path":"/work/$test_path/../../common" \
		-v "$abs_logs_path":/storage/logs \
		pantavisor-tester
	res=$?

	if [ "$netsim" = "true" ]; then
		docker stop "pantavisor-netsim" > /dev/null 2>&1
		docker wait "pantavisor-netsim" > /dev/null 2>&1

		teardown_network
	fi

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
	local logs_path=$(mktemp -d /tmp/pv_appengine_logs.XXXXXX)
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
				manual="true"
				shift
				;;
			-l|--logs)
				logs_path="$2"
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

	if [ "$overwrite" = "true" ] && [ -z "$number" ]; then
		echo "Error: Missing number argument"
		usage
		exit 1
	fi

	if [ "$interactive" = true ] && [ -z "$number" ]; then
		echo "Error: Missing number argument"
		usage
		exit 1
	fi

	if [ "$manual" = true ] && [ "$interactive" = "false" ]; then
		echo "Error: Cannot use manual without interactive"
		usage
		exit 1
	fi

	if [ "$overwrite" = "true" ] && [ "$interactive" = "true" ]; then
		echo "Error: Cannot use overwrite and interactive at the same time"
		usage
		exit 1
	fi

	common_path="tests/common"
	echo "Info: Logs can be found in $logs_path"
	if [ -z "$group" ]; then
		find tests/ -name "test.json" | sort | while read -r json_path; do
			skip_test "$json_path"
			if [ $? -ne 0 ]; then continue; fi
			exec_test "$json_path" "$interactive" "$manual" "$overwrite" "$logs_path" "$netsim"
		done
	elif [ -z "$number" ]; then
		find "tests/$group" -name "test.json" | sort  | while read -r json_path; do
			skip_test "$json_path"
			if [ $? -ne 0 ]; then continue; fi
			exec_test "$json_path" "$interactive" "$manual" "$overwrite" "$logs_path" "$netsim"
		done
	else
		json_path="tests/$group/data/$number/test.json"
		exec_test "$json_path" "$interactive" "$manual" "$overwrite" "$logs_path" "$netsim"
	fi
}

RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NOCOLOR='\033[0m'

verbose="false"
command=

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
