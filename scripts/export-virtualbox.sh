#!/bin/sh

set -eu

START_TIME=$(date +%s)

keep=0
image=
zip=0

while [ $# -gt 0 ]; do
    case $1 in
        -k) keep=1 ;;
        -z) zip=1 ;;
        *) image=$1 ;;
    esac
    shift
done

cd $ARTIFACTDIR

echo "INFO: Generate $image.vdi"
qemu-img convert -O vdi $image.raw $image.vdi
[ $keep -eq 1 ] || rm -f $image.raw

echo "INFO: Generate $image.vbox"
$RECIPEDIR/scripts/generate-vbox.sh $image.vdi

if [ $zip -eq 1 ]; then
    echo "INFO: Compress to $image.7z"
    mkdir $image
    mv $image.vdi $image.vbox $image
    7zr a -sdel -mx=9 $image.7z $image
fi

for fn in $image.*; do
    [ $(stat -c %Y $fn) -ge $START_TIME ] && echo $fn
done > .artifacts
