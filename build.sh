#!/bin/bash

set -eu

WELL_KNOWN_CACHING_PROXIES="\
3142 apt-cacher-ng
8000 squid-deb-proxy"
DETECTED_CACHING_PROXY=

SUPPORTED_ARCHITECTURES="amd64 i386"
SUPPORTED_BRANCHES="kali-dev kali-last-snapshot kali-rolling"
SUPPORTED_DESKTOPS="e17 gnome i3 kde lxde mate none xfce"
SUPPORTED_TOOLSETS="default everything headless large none"

SUPPORTED_FORMATS="ova ovf raw qemu virtualbox vmware"
SUPPORTED_VARIANTS="generic qemu rootfs virtualbox vmware"

DEFAULT_ARCH=amd64
DEFAULT_BRANCH=kali-rolling
DEFAULT_DESKTOP=xfce
DEFAULT_LOCALE=en_US.UTF-8
DEFAULT_MIRROR=http://http.kali.org/kali
DEFAULT_TIMEZONE=US/Eastern
DEFAULT_TOOLSET=default
DEFAULT_USERPASS=kali:kali

ARCH=
BRANCH=
DESKTOP=
FORMAT=
KEEP=false
LOCALE=
MIRROR=
OUTDIR=
PACKAGES=
PASSWORD=
ROOTFS=
SIZE=86
TIMEZONE=
TOOLSET=
USERNAME=
USERPASS=
VARIANT=generic
VERSION=
ZIP=false

default_toolset() { [ ${DESKTOP:-$DEFAULT_DESKTOP} = none ] && echo headless || echo default; }
default_version() { echo ${BRANCH:-$DEFAULT_BRANCH} | sed "s/^kali-//"; }
get_locale() { [ -v $LANG ] && echo $LANG || echo $DEFAULT_LOCALE; }
get_timezone() { [ -h /etc/localtime ] \
    && realpath --relative-to /usr/share/zoneinfo /etc/localtime \
    || echo $DEFAULT_TIMEZONE; }

# Use escape sequences only if both stdout/stderr are opened on a terminal
if [ -t 1 ] && [ -t 2 ]; then
    _bold=$(tput bold) _reset=$(tput sgr0)
else
    _bold= _reset=
fi

b() { echo -n "${_bold}$@${_reset}"; }
warn() { echo "WARNING:" "$@" >&2; }
fail() { echo "ERROR:" "$@" >&2; exit 1; }

fail_invalid() {
    local msg="Invalid value '$2' for option $1"
    shift 2; [ $# -gt 0 ] && msg="$msg ($@)"
    fail "$msg"
}

fail_mismatch() {
    local msg="Option mismatch, $1 can't be used together with $2"
    shift 2; [ $# -gt 0 ] && msg="$msg ($@)"
    fail "$msg"
}

in_list() {
    local word=$1 && shift
    local item=
    for item in "$@"; do
        [ "$item" = "$word" ] && return 0
    done
    return 1
}

kali_message() {
    local line=
    echo "┏━━($(b $@))"
    while IFS= read -r line; do echo "┃ $line"; done
    echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

ask_confirmation() {
    local question=${1:-"Do you want to continue?"}
    local default=yes
    local default_verbing=
    local choices=
    local grand_timeout=60
    local timeout=20
    local time_left=
    local answer=
    local ret=

    # If stdin is closed, no need to ask, assume yes
    [ -t 0 ] || return 0

    # Set variables that depend on default
    if [ $default = yes ]; then
        default_verbing=proceeding
        choices="[Y/n]"
    else
        default_verbing=aborting
        choices="[y/N]"
    fi

    # Discard chars pending on stdin
    while read -r -t 0; do read -r; done

    # Ask the question, allow for X timeouts before proceeding anyway
    grand_timeout=$((grand_timeout - timeout))
    for time_left in $(seq $grand_timeout -$timeout 0); do
        ret=0
        read -r -t $timeout -p "$question $choices " answer || ret=$?
        if [ $ret -gt 128 ]; then
            if [ $time_left -gt 0 ]; then
                echo "$time_left seconds left before $default_verbing"
            else
                echo "No answer, assuming $default, $default_verbing"
            fi
            continue
        elif [ $ret -gt 0 ]; then
            exit $ret
        else
            break
        fi
    done

    # Process the answer
    [ "$answer" ] && answer=${answer,,} || answer=$default
    case "$answer" in
        (y|yes) return 0 ;;
        (*)     return 1 ;;
    esac
}

# No need to be root, but the message doesn't make much sense in containers
if [ $(id -u) -eq 0 ] && [ ! -e /run/.containerenv ] && [ ! -e /.dockerenv ]; then
    warn "This script does not require root privileges."
    warn "Please consider running it as a non-root user."
fi

USAGE="Usage: $(basename $0) [<option>...] [-- <debos option>...]

Build a Kali Linux OS image.

Build options:
  -a ARCH     Build an image for this architecture, default: $(b $DEFAULT_ARCH)
              Supported values: $SUPPORTED_ARCHITECTURES
  -b BRANCH   Kali branch used to build the image, default: $(b $DEFAULT_BRANCH)
              Supported values: $SUPPORTED_BRANCHES
  -f FORMAT   Format to export the image to, default depends on the VARIANT
              Supported values: $SUPPORTED_FORMATS
  -k          Keep raw disk image and other intermediary build artifacts
  -m MIRROR   Mirror used to build the image, default: $(b $DEFAULT_MIRROR)
  -r ROOTFS   Rootfs to use to build the image, default: $(b none)
  -s SIZE     Size of the disk image in GB, default: $(b $SIZE)
  -v VARIANT  Variant of image to build (see below for details), default: $(b $VARIANT)
              Supported values: $SUPPORTED_VARIANTS
  -z          Zip images and metadata files after the build

Customization options:
  -D DESKTOP  Desktop environment installed in the image, default: $(b $DEFAULT_DESKTOP)
              Supported values: $SUPPORTED_DESKTOPS
  -L LOCALE   Set locale, default: $(b $DEFAULT_LOCALE)
  -P PACKAGES Install extra packages (comma/space separated list)
  -T TOOLSET  The selection of tools to include in the image, default: $(b $(default_toolset))
              Supported values: $SUPPORTED_TOOLSETS
  -U USERPASS Username and password, separated by a colon, default: $(b $DEFAULT_USERPASS)
  -Z TIMEZONE Set timezone, default: $(b $DEFAULT_TIMEZONE)

The different variants of images are:
  generic     Image with all virtualization support pre-installed, default format: raw
  qemu        Image with QEMU and SPICE guest agents pre-installed, default format: qemu
  rootfs      Not an image, a root filesystem (no bootloader/kernel), packed in a .tar.gz
  virtualbox  Image with VirtualBox guest utilities pre-installed, default format: virtualbox
  vmware      Image with Open VM Tools pre-installed, default format: vmware

The different formats are:
  ova         streamOptimized VMDK disk image, OVF metadata file, packed in a OVA archive
  ovf         monolithicSparse VMDK disk image, OVF metadata file
  raw         sparse disk image, no metadata
  qemu        QCOW2 disk image, no metadata
  virtualbox  VDI disk image, .vbox metadata file
  vmware      2GbMaxExtentSparse VMDK disk image, VMX metadata file

Supported environment variables:
  http_proxy  HTTP proxy URL, refer to the README for more details.

Refer to the README for examples.
"

while getopts ":a:b:D:f:hkL:m:P:r:s:T:U:v:x:zZ:" opt; do
    case $opt in
        (a) ARCH=$OPTARG ;;
        (b) BRANCH=$OPTARG ;;
        (D) DESKTOP=$OPTARG ;;
        (f) FORMAT=$OPTARG ;;
        (h) echo "$USAGE"; exit 0 ;;
        (k) KEEP=true ;;
        (L) LOCALE=$OPTARG ;;
        (m) MIRROR=$OPTARG ;;
        (P) PACKAGES="$PACKAGES $OPTARG" ;;
        (r) ROOTFS=$OPTARG ;;
        (s) SIZE=$OPTARG ;;
        (T) TOOLSET=$OPTARG ;;
        (U) USERPASS=$OPTARG ;;
        (v) VARIANT=$OPTARG ;;
        (x) VERSION=$OPTARG ;;
        (z) ZIP=true ;;
        (Z) TIMEZONE=$OPTARG ;;
        (*) echo "$USAGE" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

# What's left on the command-line are optional arguments for debos.
# Let's check if user wants to use a particular artifact directory.
ARTIFACTDIR_ARG=$(echo "$@" | grep -o -- "--artifactdir[= ][^ ]\+" || :)
if [ "$ARTIFACTDIR_ARG" ]; then
    OUTDIR=$(echo "$ARTIFACTDIR_ARG" | sed "s/^.*[= ]//")
else
    OUTDIR=images
    set -- "$@" --artifactdir=$OUTDIR
fi

# Set some options for debos, unless it was already set by the caller.
# Regarding the scratch size needed to build a Kali Linux image from scratch
# (ie. in one step, no intermediary rootfs), using the kali-rolling branch, the
# XFCE desktop, and changing only the toolset: default toolset requires 14G,
# large toolset 24G and everything toolset 40G. That was back in June 2022.
echo "$@" | grep -q -e "-m[= ]" -e "--memory[= ]" \
    || set -- "$@" --memory=4G
echo "$@" | grep -q -e "--scratchsize[= ]" \
    || set -- "$@" --scratchsize=45G

# Validate the variant.
in_list $VARIANT $SUPPORTED_VARIANTS || fail_invalid -v $VARIANT

# If format was not set, choose a sensible default according to the variant.
# Moreover, there should be no format when building a rootfs.
if [ $VARIANT != rootfs ]; then
    if [ -z "$FORMAT" ]; then
        case $VARIANT in
            (generic)    FORMAT=raw ;;
            (qemu)       FORMAT=qemu ;;
            (virtualbox) FORMAT=virtualbox ;;
            (vmware)     FORMAT=vmware ;;
            (*) fail_invalid -v $VARIANT ;;
        esac
    fi
    in_list $FORMAT $SUPPORTED_FORMATS || fail_invalid -f $FORMAT
else
    [ -z "$FORMAT" ] || fail_mismatch -f "'-v rootfs'"
fi

# When building an image from an existing rootfs, ARCH and VERSION are picked
# from the rootfs name. Moreover, many options don't apply, as they've been
# set already at the time the rootfs was built.
if [ "$ROOTFS" ]; then
    [ "$ARCH"     ] && fail_mismatch -a -r
    [ "$BRANCH"   ] && fail_mismatch -b -r
    [ "$DESKTOP"  ] && fail_mismatch -D -r
    [ "$LOCALE"   ] && fail_mismatch -L -r
    [ "$MIRROR"   ] && fail_mismatch -m -r
    [ "$TIMEZONE" ] && fail_mismatch -Z -r
    [ "$TOOLSET"  ] && fail_mismatch -T -r
    [ "$USERPASS" ] && fail_mismatch -U -r
    [ "$VERSION"  ] && fail_mismatch -x -r
    [ $VARIANT != rootfs ] || fail_mismatch -r "'-v rootfs'"
    [ "$(dirname $ROOTFS)" = "$OUTDIR" ] || fail "Rootfs must be within '$OUTDIR'"
    ROOTFS=$(basename $ROOTFS)
    ARCH=$(echo $ROOTFS | sed "s/\.tar\.gz$//" | rev | cut -d- -f1 | rev)
    VERSION=$(echo $ROOTFS | sed -E "s/^rootfs-(.*)-$ARCH\.tar\.gz$/\1/")
else
    [ "$ARCH"     ] || ARCH=$DEFAULT_ARCH
    [ "$BRANCH"   ] || BRANCH=$DEFAULT_BRANCH
    [ "$DESKTOP"  ] || DESKTOP=$DEFAULT_DESKTOP
    [ "$LOCALE"   ] || LOCALE=$DEFAULT_LOCALE
    [ "$MIRROR"   ] || MIRROR=$DEFAULT_MIRROR
    [ "$TIMEZONE" ] || TIMEZONE=$DEFAULT_TIMEZONE
    [ "$TOOLSET"  ] || TOOLSET=$(default_toolset)
    [ "$USERPASS" ] || USERPASS=$DEFAULT_USERPASS
    [ "$VERSION"  ] || VERSION=$(default_version)
    # Set locale and timezone
    [ "$LOCALE" = same ] && LOCALE=$(get_locale)
    [ "$TIMEZONE" = same ] && TIMEZONE=$(get_timezone)
    # Validate some options
    in_list $BRANCH $SUPPORTED_BRANCHES || fail_invalid -b $BRANCH
    in_list $DESKTOP $SUPPORTED_DESKTOPS || fail_invalid -D $DESKTOP
    in_list $TOOLSET $SUPPORTED_TOOLSETS || fail_invalid -T $TOOLSET
    # Unpack USERPASS to USERNAME and PASSWORD
    echo $USERPASS | grep -q ":" \
        || fail_invalid -U $USERPASS "must be of the form <username>:<password>"
    USERNAME=$(echo $USERPASS | cut -d: -f1)
    PASSWORD=$(echo $USERPASS | cut -d: -f2-)
fi
unset USERPASS

# Validate architecture
in_list $ARCH $SUPPORTED_ARCHITECTURES || fail_invalid -a $ARCH

# Validate size and add the "GB" suffix
[[ $SIZE =~ ^[0-9]+$ ]] && SIZE=${SIZE}GB \
    || fail_invalid -s $SIZE "must contain only digits"

# Order packages alphabetically, separate each package with ", "
PACKAGES=$(echo $PACKAGES | sed "s/[, ]\+/\n/g" | LC_ALL=C sort -u \
    | awk 'ORS=", "' | sed "s/[, ]*$//")

# Attempt to detect well-known http caching proxies on localhost,
# cf. bash(1) section "REDIRECTION". This is not bullet-proof.
if ! [ -v http_proxy ]; then
    while read port proxy; do
        (</dev/tcp/localhost/$port) 2>/dev/null || continue
        DETECTED_CACHING_PROXY="$port $proxy"
        export http_proxy="http://10.0.2.2:$port"
        break
    done <<< "$WELL_KNOWN_CACHING_PROXIES"
fi

# Print a summary
{
echo "# Proxy configuration:"
if [ "$DETECTED_CACHING_PROXY" ]; then
    read port proxy <<< $DETECTED_CACHING_PROXY
    echo "Detected caching proxy $(b $proxy) on port $(b $port)."
fi
if [ "${http_proxy:-}" ]; then
    echo "Using proxy via environment variable: $(b http_proxy=$http_proxy)."
else
    echo "No http proxy configured, all packages will be downloaded from Internet."
fi

echo "# Build options:"
if [ $VARIANT = rootfs ]; then
    echo "Build a Kali Linux $(b $VARIANT) for the $(b $ARCH) architecture."
else
    if [ "$ROOTFS" ]; then
        echo "Build a Kali Linux $(b $VARIANT) image based on $(b $ROOTFS)."
    else
        echo "Build a Kali Linux $(b $VARIANT) image for the $(b $ARCH) architecture."
    fi
    echo "Export the image to the $(b $FORMAT) format. Disk size: $(b $SIZE)."
fi
[ "$MIRROR"   ] && echo "* mirror: $(b $MIRROR)"
[ "$BRANCH"   ] && echo "* branch: $(b $BRANCH)"
[ "$DESKTOP"  ] && echo "* desktop environment: $(b $DESKTOP)"
[ "$TOOLSET"  ] && echo "* tool selection: $(b $TOOLSET)"
[ "$PACKAGES" ] && echo "* additional packages: $(b $PACKAGES)"
[ "$USERNAME" ] && echo "* username & password: $(b $USERNAME $PASSWORD)"
[ "$LOCALE"   ] && echo "* locale: $(b $LOCALE)"
[ "$TIMEZONE" ] && echo "* timezone: $(b $TIMEZONE)"
} | kali_message "Kali Linux VM Build"

# Ask for confirmation before starting the build
ask_confirmation || { echo "Abort."; exit 1; }

mkdir -p $OUTDIR

if [ $VARIANT = rootfs ]; then
    ROOTFS=rootfs-$VERSION-$ARCH
    IMAGENAME=
elif [ "$ROOTFS" ]; then
    ROOTFS=${ROOTFS%.tar.*}
    IMAGENAME=kali-linux-$VERSION-$VARIANT-$ARCH
else
    ROOTFS=
    IMAGENAME=kali-linux-$VERSION-$VARIANT-$ARCH
fi

debos "$@" \
    -t arch:$ARCH \
    -t branch:$BRANCH \
    -t desktop:$DESKTOP \
    -t format:$FORMAT \
    -t imagename:$IMAGENAME \
    -t imagesize:$SIZE \
    -t keep:$KEEP \
    -t locale:$LOCALE \
    -t mirror:$MIRROR \
    -t packages:"$PACKAGES" \
    -t password:"$PASSWORD" \
    -t rootfs:$ROOTFS \
    -t timezone:$TIMEZONE \
    -t toolset:$TOOLSET \
    -t username:$USERNAME \
    -t variant:$VARIANT \
    -t zip:$ZIP \
    main.yaml

cat << EOF
..............
            ..,;:ccc,.
          ......''';lxO.
.....''''..........,:ld;
           .';;;:::;,,.x,
      ..'''.            0Xxoc:,.  ...
  ....                ,ONkc;,;cokOdc',.
 .                   OMo           ':$(b dd)o.
                    dMc               :OO;
                    0M.                 .:o.
                    ;Wd
                     ;XO,
                       ,d0Odlc;,..
                           ..',;:cdOOd::,.
                                    .:d;.':;.
                                       'd,  .'
                                         ;l   ..
                                          .o
                                            c
                                            .'
                                             .

Successful build! The following build artifacts were produced:
EOF
cat $OUTDIR/.artifacts | sed "s:^:* $OUTDIR/:"
