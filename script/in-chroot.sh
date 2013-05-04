#!/bin/bash
#
# This script is part of the the arch-install-script package
#

shopt -s extglob

out() { printf "$1 $2\n" "${@:3}"; }
error() { out "==> ERROR:" "$@"; } >&2
msg() { out "==>" "$@"; }
msg2() { out "  ->" "$@";}
die() { error "$@"; exit 1; }

in_array() {
  local i
  for i in "${@:2}"; do
    [[ $1 = "$i" ]] && return
  done
}

track_mount() {
  mount "$@" && CHROOT_ACTIVE_MOUNTS=("$2" "${CHROOT_ACTIVE_MOUNTS[@]}")
}

api_fs_mount() {
  CHROOT_ACTIVE_MOUNTS=()
  { mountpoint -q "$1" || track_mount "$1" "$1" --bind; } &&
  track_mount proc "$1/proc" -t proc -o nosuid,noexec,nodev &&
  track_mount sys "$1/sys" -t sysfs -o nosuid,noexec,nodev &&
  track_mount udev "$1/dev" -t devtmpfs -o mode=0755,nosuid &&
  track_mount devpts "$1/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec &&
  track_mount shm "$1/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev &&
  track_mount run "$1/run" -t tmpfs -o nosuid,nodev,mode=0755 &&
  track_mount tmp "$1/tmp" -t tmpfs -o mode=1777,strictatime,nodev,nosuid
}

api_fs_umount() {
  umount "${CHROOT_ACTIVE_MOUNTS[@]}"
}

valid_number_of_base() {
  local base=$1 len=${#2} i=

  for (( i = 0; i < len; i++ )); do
    (( (${2:i:1} & ~(base - 1)) == 0 )) || return
  done
}

mangle() {
  local i= chr= out=

  unset {a..f} {A..F}

  for (( i = 0; i < ${#1}; i++ )); do
    chr=${1:i:1}
    case $chr in
      [[:space:]\\])
        printf -v chr '%03o' "'$chr"
        out+=\\
        ;;&
        # fallthrough
      *)
        out+=$chr
        ;;
    esac
  done

  printf '%s' "$out"
}

unmangle() {
  local i= chr= out= len=$(( ${#1} - 4 ))

  unset {a..f} {A..F}

  for (( i = 0; i < len; i++ )); do
    chr=${1:i:1}
    case $chr in
      \\)
        if valid_number_of_base 8 "${1:i+1:3}" ||
            valid_number_of_base 16 "${1:i+1:3}"; then
          printf -v chr '%b' "${1:i:4}"
          (( i += 3 ))
        fi
        ;;&
        # fallthrough
      *)
        out+=$chr
    esac
  done

  printf '%s' "$out${1:i}"
}

dm_name_for_devnode() {
  read dm_name <"/sys/class/block/${1#/dev/}/dm/name"
  if [[ $dm_name ]]; then
    printf '/dev/mapper/%s' "$dm_name"
  else
    # don't leave the caller hanging, just print the original name
    # along with the failure.
    print '%s' "$1"
    error 'Failed to resolve device mapper name for: %s' "$1"
  fi
}

fstype_is_pseudofs() {
  # list taken from util-linux source: libmount/src/utils.c
  local -A pseudofs_types=([anon_inodefs]=1
                           [autofs]=1
                           [bdev]=1
                           [binfmt_misc]=1
                           [cgroup]=1
                           [configfs]=1
                           [cpuset]=1
                           [debugfs]=1
                           [devfs]=1
                           [devpts]=1
                           [devtmpfs]=1
                           [dlmfs]=1
                           [fuse.gvfs-fuse-daemon]=1
                           [fusectl]=1
                           [hugetlbfs]=1
                           [mqueue]=1
                           [nfsd]=1
                           [none]=1
                           [pipefs]=1
                           [proc]=1
                           [pstore]=1
                           [ramfs]=1
                           [rootfs]=1
                           [rpc_pipefs]=1
                           [securityfs]=1
                           [sockfs]=1
                           [spufs]=1
                           [sysfs]=1
                           [tmpfs]=1)
  (( pseudofs_types["$1"] ))
}



usage() {
  cat <<EOF
usage: ${0##*/} chroot-dir [command]

    -h             Print this help message

If 'command' is unspecified, ${0##*/} will launch /bin/sh.

EOF
}

if [[ -z $1 || $1 = @(-h|--help) ]]; then
  usage
  exit $(( $# ? 0 : 1 ))
fi

USER=""
if [ "$1" = "--asuser" ] ; then
  USER="--userspec=$2:users"
  shift 2
fi

(( EUID == 0 )) || die 'This script must be run with root privileges'
chrootdir=$1
shift

[[ -d $chrootdir ]] || die "Can't create chroot on non-directory %s" "$chrootdir"

trap '{ api_fs_umount "$chrootdir"; umount "$chrootdir/etc/resolv.conf"; } 2>/dev/null' EXIT

api_fs_mount "$chrootdir" || die "failed to setup API filesystems in chroot %s" "$chrootdir"
track_mount /etc/resolv.conf "$chrootdir/etc/resolv.conf" --bind

SHELL=/bin/sh chroot $USER "$chrootdir" "$@"
