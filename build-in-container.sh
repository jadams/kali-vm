#!/bin/bash

set -eu

CONTAINER=${CONTAINER:-}
IMAGE=kali-rolling/vm-builder
OPTS=()

# Use escape sequences only if both stdout/stderr are opened on a terminal
if [ -t 1 ] && [ -t 2 ]; then
    _bold=$(tput bold) _reset=$(tput sgr0)
else
    _bold= _reset=
fi

b() { echo -n "${_bold}$@${_reset}"; }
fail() { echo "ERROR:" "$@" >&2; exit 1; }
vrun() { echo $(b "$ $@"); "$@"; }
vexec() { echo $(b "$ $@"); exec "$@"; }

if [ -z "$CONTAINER" ]; then
    if [ -x /usr/bin/podman ]; then
        CONTAINER=podman
    elif [ -x /usr/bin/docker ]; then
        CONTAINER=docker
    else
        fail "No container engine detected, aborting."
    fi
fi

if [ -t 0 ]; then
    OPTS+=(--interactive --tty)
fi
OPTS+=(
    --rm --net host
    --device /dev/kvm --group-add $(stat -c "%g" /dev/kvm)
    --security-opt label=disable
    --volume $(pwd):/recipes --workdir /recipes
)

case $CONTAINER in
    docker)
        OPTS+=(--user $(stat -c "%u:%g" .))
        ;;
    podman)
        if [ $(id -u) -eq 0 ]; then
            OPTS+=(--user $(stat -c "%u:%g" .))
        fi
        OPTS+=(--log-driver none)    # we don't want stdout in the journal
        ;;
esac

if ! $CONTAINER inspect --type image $IMAGE >/dev/null 2>&1; then
    vrun $CONTAINER build -t $IMAGE .
    echo
fi

vexec $CONTAINER run "${OPTS[@]}" $IMAGE ./build.sh "$@"
