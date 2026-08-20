#!/bin/sh
# OSFinder: fix an existing USB without re-downloading the Alpine netboot files
#
# Fixes two issues on the installed pen:
#   1. Adds sd_mod.ko to the initramfs (the netboot initramfs omits it, so the
#      USB stick is invisible during boot and the apkovl is never applied)
#   2. Ensures grub.cfg passes the Alpine mirror as alpine_repo (instead of
#      'auto', which treats the pen itself as a package repository)
#
# Usage: sudo ./setup/fix_pen.sh /dev/sdX

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run with sudo: sudo $0 /dev/sdX"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: sudo $0 /dev/sdX"
    exit 1
fi

USB_DEVICE="$1"
MOUNT_POINT="/tmp/osfinder_fix_mount"
PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)

partition_path() {
    local dev="$1" num="$2" base
    base=$(basename "$dev")
    case "$base" in
        nvme*|mmcblk*|loop*) echo "${dev}p${num}" ;;
        *) echo "${dev}${num}" ;;
    esac
}

die() {
    echo "ERROR: $1" >&2
    umount "$MOUNT_POINT" 2>/dev/null || true
    rm -rf /tmp/osfinder_fix_initrd.* /tmp/osfinder_fix_modloop.* /tmp/osfinder_fix_mount 2>/dev/null || true
    exit 1
}

PART2=$(partition_path "$USB_DEVICE" 2)
echo "Mounting $PART2..."
rm -rf "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT"
mount "$PART2" "$MOUNT_POINT" || die "could not mount $PART2"

[ -f "$MOUNT_POINT/boot/initramfs-lts" ] || die "initramfs-lts not found on pen"
[ -f "$MOUNT_POINT/boot/modloop-lts" ] || die "modloop-lts not found on pen"

# --- 1. Augment initramfs with sd_mod ---
echo "Augmenting initramfs with sd_mod..."
if ! command -v unsquashfs >/dev/null 2>&1; then
    echo "  installing squashfs-tools..."
    pacman -Sy --noconfirm squashfs-tools >/dev/null 2>&1 || die "failed to install squashfs-tools"
fi
INITRD_DIR="/tmp/osfinder_fix_initrd.$$"
MODEXTRACT="/tmp/osfinder_fix_modloop.$$"
mkdir -p "$INITRD_DIR" "$MODEXTRACT"
(cd "$INITRD_DIR" && zcat "$MOUNT_POINT/boot/initramfs-lts" | cpio -id --quiet) || die "failed to extract initramfs"
KVER=$(ls "$INITRD_DIR/usr/lib/modules/" 2>/dev/null | head -1)
[ -n "$KVER" ] || die "could not determine kernel version"

if [ ! -f "$INITRD_DIR/usr/lib/modules/$KVER/kernel/drivers/scsi/sd_mod.ko" ]; then
    SDMOD_ML=$(unsquashfs -ll "$MOUNT_POINT/boot/modloop-lts" 2>/dev/null \
        | grep -oE '[^ ]*sd_mod\.ko[^ ]*' | head -1 \
        | sed 's|^squashfs-root/||')
    [ -n "$SDMOD_ML" ] || die "sd_mod.ko not found in modloop"
    unsquashfs -q -f -d "$MODEXTRACT" "$MOUNT_POINT/boot/modloop-lts" "$SDMOD_ML" \
        >/dev/null 2>&1 || die "failed to extract sd_mod.ko from modloop"
    SDMOD=$(find "$MODEXTRACT" -name "sd_mod.ko*" 2>/dev/null | head -1)
    [ -n "$SDMOD" ] || die "sd_mod.ko not found after extraction"
    if echo "$SDMOD" | grep -q '\.gz$'; then
        gzip -dc "$SDMOD" > "$INITRD_DIR/usr/lib/modules/$KVER/kernel/drivers/scsi/sd_mod.ko" \
            || die "failed to decompress sd_mod.ko"
    else
        cp "$SDMOD" "$INITRD_DIR/usr/lib/modules/$KVER/kernel/drivers/scsi/sd_mod.ko" \
            || die "failed to copy sd_mod.ko"
    fi
fi
depmod -b "$INITRD_DIR" "$KVER" || die "depmod failed"
(cd "$INITRD_DIR" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9 > "$MOUNT_POINT/boot/initramfs-lts") \
    || die "failed to repack initramfs"
rm -rf "$INITRD_DIR" "$MODEXTRACT"

# --- 1b. Rebuild the apkovl (TUI runs via inittab on tty1, network-only local hook) ---
echo "Rebuilding apkovl overlay..."
"$PROJECT_DIR/setup/build_apkovl.sh" "$MOUNT_POINT/alpine.apkovl.tar.gz" "$PROJECT_DIR" \
    || die "failed to rebuild apkovl"

# --- 2. Regenerate grub.cfg (alpine_repo fix + ISO boot entries) ---
echo "Regenerating grub.cfg (alpine_repo + ISO boot entries)..."
mkdir -p "$MOUNT_POINT/boot/grub"
sh "$PROJECT_DIR/setup/gen_grub_cfg.sh" "$PROJECT_DIR" > "$MOUNT_POINT/boot/grub/grub.cfg" \
    || die "failed to regenerate grub.cfg"
grep -q 'alpine_repo=' "$MOUNT_POINT/boot/grub/grub.cfg" \
    || die "grub.cfg has no alpine_repo entry - please re-run the installer"

sync
umount "$MOUNT_POINT" || die "umount failed"
rm -rf "$MOUNT_POINT"
echo ""
echo "Pen fixed. Eject it and boot again."