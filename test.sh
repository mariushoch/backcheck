#!/bin/bash

cd "$(dirname "$0")"
set -e
set -v

shellcheck backcheck ./*.sh ./*.bats
bats --jobs "$(nproc)" ./*.bats
./bats-RockyLinux8.sh --jobs "$(nproc)" ./*.bats
./bats-RockyLinux9.sh --jobs "$(nproc)" ./*.bats

cd -
