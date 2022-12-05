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

echo "INFO: Generate $image.vmdk"
qemu-img convert -O vmdk $image.raw $image.vmdk

[ $keep -eq 1 ] || rm -f $image.raw

echo "INFO: Generate $image.ovf"
$RECIPEDIR/scripts/generate-ovf.sh $image.vmdk

echo "INFO: Generate $image.mf"
$RECIPEDIR/scripts/generate-mf.sh $image.ovf $image.vmdk

if [ $zip -eq 1 ]; then
    echo "INFO: Compress to $image.7z"
    7zr a -sdel -mx=9 $image.7z $image.ovf $image.vmdk $image.mf
fi

for fn in $image.*; do
    [ $(stat -c %Y $fn) -ge $START_TIME ] && echo $fn
done > .artifacts
