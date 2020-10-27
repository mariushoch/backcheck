#!/bin/bash

cd "$(dirname "$0")"
set -e
set -v

shellcheck ./*.sh ./*.bats
bats ./*.bats
./bats-CentOS7.sh ./*.bats

cd -
