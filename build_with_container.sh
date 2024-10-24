#!/bin/bash

./kas-container --runtime-args "--security-opt seccomp=unconfined" build "$@"

