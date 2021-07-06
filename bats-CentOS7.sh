#!/bin/bash
# shellcheck disable=SC1004,SC2016

RUNTIME=podman
if ! command -v podman >/dev/null 2>&1; then
        RUNTIME=docker
fi

$RUNTIME run --privileged --security-opt label=disable --volume "$(pwd)":/cwd:ro --rm centos:7 sh -c \
	'echo -n "Preparing image..."; \
	yum -y install epel-release >/dev/null 2>&1; yum --setopt=install_weak_deps=False -y install bats rsync bubblewrap faketime >/dev/null 2>&1; \
	echo "... done."; \
	cd /cwd; bats "$@"' -- "$@"
