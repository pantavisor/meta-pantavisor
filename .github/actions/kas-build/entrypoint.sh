#!/bin/sh

set -xe

KAS_BUILD_ACTION_CONFIG_DIR=${KAS_BUILD_ACTION_CONFIG_DIR:-kas-build.configs/}
KAS_BUILD_ACTION_TARGET=${KAS_BUILD_ACTION_TARGET}
KAS_BUILD_ACTION_COMMAND=${KAS_BUILD_ACTION_COMMAND}
KAS_BUILD_ACTION_BBARGS=${KAS_BUILD_ACTION_BBARGS:+ -- $KAS_BUILD_ACTION_BBARGS}

echo Target: $KAS_BUILD_ACTION_TARGET
echo Command: $KAS_BUILD_ACTION_COMMAND
echo Config-Dir: $KAS_BUILD_ACTION_CONFIG_DIR
echo BBARGS: $KAS_BUILD_ACTION_BBARGS

echo WORKSPACE:
ls -la $GITHUB_WORKSPACE
echo workspace '*'
ls -la *

sudo chown -R `id -u`:`id -g` .

err=""
for c in ${KAS_BUILD_ACTION_CONFIG_DIR}/*.yaml; do
	echo "Building $c"
	set +e
	if kas build \
		${KAS_BUILD_ACTION_TARGET:+--target $KAS_BUILD_ACTION_TARGET} \
		${KAS_BUILD_ACTION_COMMAND:+--cmd $KAS_BUILD_ACTION_COMMAND} \
		$c \
		${KAS_BUILD_ACTION_BBARGS}; then
		res=$?
		if test $res -ne 0; then
			err="${err:+$err $res}${err:-$res}"
		fi
	fi
done

if test -n "$err"; then
	echo "Error failed with codes: $err"
	exit 1
fi

