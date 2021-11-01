#!/bin/bash
# shellcheck disable=SC1004,SC2016

RUNTIME=podman
if ! command -v podman >/dev/null 2>&1; then
        RUNTIME=docker
fi

cd "$(dirname "$0")" || exit 255
$RUNTIME build --tag backcheck-rockylinux-8 -f Dockerfile .
cd - || exit 255

echo
# shellcheck disable=SC2016
$RUNTIME run --privileged --volume "$(pwd)":/cwd:ro --security-opt label=disable --rm -v .:/srv:ro backcheck-rockylinux-8 bash -c \
	'cd /cwd; echo "As root:"; bats "$@" && echo "As nobody:" && sudo -u nobody bats "$@"' -- "$@"
