#!/bin/bash

set -eu

IMAGE=kali-rolling/vm-builder

OPTS=()
if [ -t 0 ]; then
    OPTS+=(--interactive --tty)
fi
OPTS+=(
    --rm --net host
    --device /dev/kvm --group-add $(stat -c "%g" /dev/kvm)
    --security-opt label=disable
    --volume $(pwd):/recipes --workdir /recipes
)

if [ -x /usr/bin/podman ]; then
    PODMAN=podman
    if [ $(id -u) -eq 0 ]; then
        OPTS+=(--user $(stat -c "%u:%g" .))
    fi
    OPTS+=(--log-driver none)    # we don't want stdout in the journal
elif [ -x /usr/bin/docker ]; then
    PODMAN=docker
    OPTS+=(--user $(stat -c "%u:%g" .))
else
    echo "ERROR: No container engine detected, aborting." >&2
    exit 1
fi

# Output bold only if both stdout/stderr are opened on a terminal
if [ -t 1 -a -t 2 ]; then
    bold() { tput bold; echo "$@"; tput sgr0; }
else
    bold() { echo "$@"; }
fi
vrun() { bold "$" "$@"; "$@"; }
vexec() { bold "$" "$@"; exec "$@"; }

if ! $PODMAN inspect --type image $IMAGE >/dev/null 2>&1; then
    vrun $PODMAN build -t $IMAGE .
    echo
fi

vexec $PODMAN run "${OPTS[@]}" $IMAGE ./build.sh "$@"
