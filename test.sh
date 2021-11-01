#!/bin/bash

cd "$(dirname "$0")"
set -e
set -v

shellcheck backcheck ./*.sh ./*.bats
bats ./*.bats
./bats-CentOS7.sh ./*.bats
./bats-RockyLinux8.sh ./*.bats

cd -
