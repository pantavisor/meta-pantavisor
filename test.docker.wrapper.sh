#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KAS_CONFIG="${KAS_CONFIG:-kas/build-configs/release/docker-x86_64-scarthgap.yaml}"
WORKDIR="$SCRIPT_DIR/workdir/appengine"
DEPLOY_DIR="$SCRIPT_DIR/build/tmp-scarthgap/deploy/images/docker-x86_64"
PVTESTS_LOCAL_REPO="${PVTESTS_LOCAL_REPO:-git@gitlab.com:pantacor/pvtests-local.git}"
PVTESTS_REMOTE_REPO="${PVTESTS_REMOTE_REPO:-git@gitlab.com:pantacor/pvtests-remote.git}"
PH_USER="${PH_USER:-}"
PH_PASS="${PH_PASS:-}"

usage() {
	echo ""
	echo "Usage: $0 [options] <command> [arguments]"
	echo "Build, prepare, and run pantavisor appengine docker tests"
	echo ""
	echo "Options:"
	echo "  -h, --help        Display this help message"
	echo "  -s, --skip-build  Skip the kas build step (for run command)"
	echo "  -v, --verbose     Pass verbose flag to test.docker.sh"
	echo "  -k, --kas-config  KAS config file (default: $KAS_CONFIG)"
	echo ""
	echo "Commands:"
	echo "  ls                List all available tests"
	echo "  run [test-name]   Run a test, e.g. pvtests-local:4 or pvtests-remote:0"
	echo "                    If test-name is omitted, runs all tests"
	echo ""
	echo "Extra arguments after '--' are passed directly to test.docker.sh"
	echo ""
	echo "Environment:"
	echo "  PH_USER           Pantahub username (required for remote tests)"
	echo "  PH_PASS           Pantahub password (required for remote tests)"
	echo ""
	echo "Examples:"
	echo "  $0 ls"
	echo "  $0 run pvtests-remote:0"
	echo "  $0 -v run pvtests-local:4"
	echo "  $0 -s run pvtests-remote:0        # skip build, just run test"
	echo "  $0 -v run pvtests-local:4 -- -i   # interactive mode"
	echo ""
}

ensure_workdir() {
	if [ ! -d "$WORKDIR" ] || [ ! -x "$WORKDIR/test.docker.sh" ]; then
		echo "Error: workdir not prepared. Run '$0 run' first to build and extract artifacts."
		exit 1
	fi
}

skip_build=false
verbose=""
extra_args=()
command=""

while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help)
			usage
			exit 0
			;;
		-s|--skip-build)
			skip_build=true
			shift
			;;
		-v|--verbose)
			verbose="-v"
			shift
			;;
		-k|--kas-config)
			KAS_CONFIG="$2"
			shift 2
			;;
		--)
			shift
			extra_args=("$@")
			break
			;;
		-*)
			echo "Error: Unknown option: $1"
			usage
			exit 1
			;;
		*)
			command="$1"
			shift
			break
			;;
	esac
done

if [ -z "$command" ]; then
	echo "Error: Missing command"
	usage
	exit 1
fi

case "$command" in
	ls)
		ensure_workdir
		cd "$WORKDIR"
		./test.docker.sh $verbose ls
		;;
	run)
		test_name=""
		# Parse remaining args for run command
		while [ $# -gt 0 ]; do
			case "$1" in
				--)
					shift
					extra_args=("$@")
					break
					;;
				-*)
					echo "Error: Unknown option: $1 (put extra flags after '--')"
					usage
					exit 1
					;;
				*)
					if [ -z "$test_name" ]; then
						test_name="$1"
					else
						echo "Error: Unexpected argument: $1"
						usage
						exit 1
					fi
					shift
					;;
			esac
		done

		# Step 1: Build
		if [ "$skip_build" = false ]; then
			echo "==> Building pantavisor-appengine-distro..."
			cd "$SCRIPT_DIR"
			"$SCRIPT_DIR/kas-container" shell "$KAS_CONFIG" -c \
				'bitbake -c cleansstate pantavisor-appengine-distro && bitbake -c build pantavisor-appengine-distro'
		else
			echo "==> Skipping build (--skip-build)"
		fi

		# Step 2: Prepare workdir
		echo "==> Preparing workdir at $WORKDIR..."
		mkdir -p "$WORKDIR"
		cd "$WORKDIR"

		# Step 3: Extract build artifacts
		TARBALL=$(ls -t "$DEPLOY_DIR"/pantavisor-appengine-distro-docker-x86_64*.tar.gz 2>/dev/null | head -n 1)
		if [ -z "$TARBALL" ]; then
			echo "Error: No appengine tarball found in $DEPLOY_DIR"
			exit 1
		fi
		echo "==> Extracting $TARBALL..."
		tar -xf "$TARBALL"

		# Step 4: Install docker images
		if [ ! -x "./test.docker.sh" ]; then
			echo "Error: test.docker.sh not found or not executable in $WORKDIR"
			exit 1
		fi
		echo "==> Loading docker images..."
		./test.docker.sh install-docker

		# Step 5: Clone test repos if needed
		if [ ! -d "pvtests-local" ]; then
			echo "==> Cloning pvtests-local..."
			git clone "$PVTESTS_LOCAL_REPO"
		else
			echo "==> pvtests-local already exists, skipping clone"
		fi
		if [ ! -d "pvtests-remote" ]; then
			echo "==> Cloning pvtests-remote..."
			git clone "$PVTESTS_REMOTE_REPO"
		else
			echo "==> pvtests-remote already exists, skipping clone"
		fi

		# Step 6: Cache sudo credentials and ensure loop devices exist
		echo "==> Caching sudo credentials..."
		sudo -v
		echo "==> Ensuring loop devices are available..."
		if ! sudo modprobe loop 2>/dev/null; then
			echo "Error: Cannot load 'loop' kernel module."
			echo "       Your running kernel ($(uname -r)) may not have matching modules installed."
			echo "       Try rebooting into a kernel with available modules."
			ls /lib/modules/ 2>/dev/null && echo "       Available module dirs: $(ls /lib/modules/)"
			exit 1
		fi
		sudo losetup -D
		# Ensure at least one loop device node exists (needed by losetup -f / docker --device)
		if [ ! -e /dev/loop0 ]; then
			sudo mknod /dev/loop0 b 7 0
			sudo chown root:disk /dev/loop0
			sudo chmod 0660 /dev/loop0
		fi

		# Step 7: Validate credentials for remote tests
		if [ -n "$test_name" ] && echo "$test_name" | grep -q "^pvtests-remote"; then
			if [ -z "$PH_USER" ] || [ -z "$PH_PASS" ]; then
				echo "Error: PH_USER and PH_PASS must be set for remote tests"
				echo "       e.g. PH_USER=user PH_PASS=pass $0 run $test_name"
				exit 1
			fi
		fi

		# Step 8: Run test
		echo "==> Running test..."
		if [ -n "$test_name" ]; then
			./test.docker.sh $verbose run "$test_name" "${extra_args[@]}"
		else
			./test.docker.sh $verbose run "${extra_args[@]}"
		fi
		;;
	*)
		echo "Error: Unknown command: $command"
		usage
		exit 1
		;;
esac
