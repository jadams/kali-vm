#!/bin/sh

set -eu

START_TIME=$(date +%s)

image=
zip=0

while [ $# -gt 0 ]; do
    case $1 in
        -z) zip=1 ;;
        *) image=$1 ;;
    esac
    shift
done

cd $ARTIFACTDIR

echo "INFO: Rename to $image.img"
mv -v $image.raw $image.img
touch $image.img

if [ $zip -eq 1 ]; then
    echo "INFO: Dig holes in the sparse file"
    fallocate -v --dig-holes $image.img

    echo "INFO: Create bmap file $image.img.bmap"
    bmaptool create $image.img > $image.img.bmap

    echo "INFO: Compress to $image.img.xz"
    xz -f $image.img
fi

for fn in $image.*; do
    [ $(stat -c %Y $fn) -ge $START_TIME ] && echo $fn
done > .artifacts
