#!/bin/sh

target=$1
command=$2
bbargs=$3

echo Target: $target
echo Command: $command
echo BBARGS: $bbargs
echo Workspace: $GITHUB_WORKSPACE

ls $GITHUB_WORKSPACE/

