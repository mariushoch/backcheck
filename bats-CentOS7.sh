#!/bin/bash
# shellcheck disable=SC1004

batsTestDir=$(realpath "$1")
podman run --privileged --security-opt label=disable --volume "$(dirname "$batsTestDir")":/cwd:ro --rm centos:7 sh -c \
	'echo -n "Preparing image..."; \
	yum -y install epel-release >/dev/null 2>&1; yum -y install bats rsync bubblewrap faketime >/dev/null 2>&1; \
	echo "... done."; \
	cd /cwd; bats "$@"' -- "$@"
