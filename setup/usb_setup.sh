#!/bin/sh
# OSFinder USB Setup Script
# Creates a bootable USB that boots Alpine Linux and auto-runs the
# OSFinder TUI for searching/downloading OS ISOs on bare-metal machines.
#
# Layout:
#   Partition 1: BIOS boot partition (1MiB, type bios_grub) - for GRUB BIOS
#   Partition 2: FAT32 ESP/data partition (rest of disk) - GRUB UEFI + OSFinder files
#
# Boot media contents:
#   /boot/vmlinuz-lts, /boot/initramfs-lts, /boot/modloop-lts  (Alpine netboot)
#   /boot/grub/grub.cfg
#   /alpine.apkovl.tar.gz          (config overlay: TUI + auto-start + packages)
#   /.boot_repository              (Alpine repositories, used by nlplug-findfs)
#
# WARNING: This will erase all data on the target USB drive!

# Root check: this script must be run with sudo/root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script requires root privileges."
    echo "Please run it with sudo: sudo $0 /dev/sdX"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: $0 /dev/sdX"
    echo "Example: $0 /dev/sdb"
    exit 1
fi

USB_DEVICE="$1"
MOUNT_POINT="/tmp/osfinder_usb_mount"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ALPINE_BASE="https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/netboot"
APKOVL_NAME="alpine.apkovl.tar.gz"

die() {
    echo "ERROR: $1" >&2
    umount "$MOUNT_POINT" 2>/dev/null || true
    rm -rf /tmp/osfinder_initrd.* /tmp/osfinder_modloop.* /tmp/osfinder_apkovl.* "$MOUNT_POINT" 2>/dev/null || true
    exit 1
}

# Helper: partition device path for a given partition number
partition_path() {
    local dev="$1" num="$2" base
    base=$(basename "$dev")
    case "$base" in
        nvme*|mmcblk*|loop*) echo "${dev}p${num}" ;;
        *) echo "${dev}${num}" ;;
    esac
}

echo "========================================="
echo "  OSFinder: Creating Bootable USB        "
echo "========================================="
echo ""

# Step 1: Verify the device exists
if [ ! -b "$USB_DEVICE" ]; then
    echo "ERROR: Device $USB_DEVICE not found!"
    exit 1
fi

# Step 2: Unmount any partitions
echo "Unmounting $USB_DEVICE partitions..."
PART1=$(partition_path "$USB_DEVICE" 1)
PART2=$(partition_path "$USB_DEVICE" 2)
umount "$PART1" "$PART2" 2>/dev/null || true

# Step 3: Wipe partition table and create GPT layout
echo "Wiping partition table on $USB_DEVICE..."
wipefs -a "$USB_DEVICE" || die "wipefs failed"
echo "Creating GPT partition table..."
parted -s "$USB_DEVICE" mklabel gpt || die "parted mklabel failed"
parted -s "$USB_DEVICE" mkpart primary 1MiB 2MiB || die "parted mkpart (bios) failed"
parted -s "$USB_DEVICE" set 1 bios_grub on || die "parted set bios_grub failed"
parted -s "$USB_DEVICE" mkpart primary 2MiB 100% || die "parted mkpart (data) failed"
parted -s "$USB_DEVICE" set 2 boot on || die "parted set boot failed"

# Step 4: Force the kernel to re-read the partition table, then wait for nodes
echo "Reloading partition table..."
blockdev --rereadpt "$USB_DEVICE" 2>/dev/null || partprobe "$USB_DEVICE" 2>/dev/null || true
udevadm settle 2>/dev/null || true

i=0
while [ ! -b "$PART2" ] && [ "$i" -lt 10 ]; do
    blockdev --rereadpt "$USB_DEVICE" 2>/dev/null || true
    udevadm settle 2>/dev/null || true
    sleep 1
    i=$((i + 1))
done
[ -b "$PART2" ] || die "partition $PART2 was not created"

# Step 5: Format partition 2 as FAT32
echo "Formatting $PART2 as FAT32..."
mkfs.vfat -n PEN "$PART2" || die "mkfs.vfat failed"
sync

# Step 6: Mount partition 2 (retry to avoid stale partition-table race)
echo "Mounting $PART2..."
rm -rf "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT"
i=0
while [ "$i" -lt 5 ]; do
    if mount "$PART2" "$MOUNT_POINT"; then
        break
    fi
    sleep 2
    i=$((i + 1))
done
mountpoint -q "$MOUNT_POINT" || die "could not mount $PART2"

# Step 7: Download Alpine netboot files
echo "Downloading Alpine netboot (kernel, initramfs, modules)..."
mkdir -p "$MOUNT_POINT/boot"
curl -fL --retry 3 -o "$MOUNT_POINT/boot/vmlinuz-lts" "$ALPINE_BASE/vmlinuz-lts" || die "failed to download vmlinuz-lts"
curl -fL --retry 3 -o "$MOUNT_POINT/boot/initramfs-lts" "$ALPINE_BASE/initramfs-lts" || die "failed to download initramfs-lts"
curl -fL --retry 3 -o "$MOUNT_POINT/boot/modloop-lts" "$ALPINE_BASE/modloop-lts" || die "failed to download modloop-lts"

# Step 7b: Augment the initramfs with sd_mod
# The Alpine netboot initramfs is PXE-oriented and omits sd_mod, so the USB
# stick never appears as a block device during initramfs and the boot media
# (and its apkovl) can't be detected. Add sd_mod.ko from modloop-lts.
echo "Augmenting initramfs with USB SCSI support (sd_mod)..."
if ! command -v unsquashfs >/dev/null 2>&1; then
    echo "  installing squashfs-tools (for unsquashfs)..."
    pacman -Sy --noconfirm squashfs-tools >/dev/null 2>&1 || die "failed to install squashfs-tools"
fi
INITRD_DIR="/tmp/osfinder_initrd.$$"
MODEXTRACT="/tmp/osfinder_modloop.$$"
mkdir -p "$INITRD_DIR" "$MODEXTRACT"
(cd "$INITRD_DIR" && zcat "$MOUNT_POINT/boot/initramfs-lts" | cpio -id --quiet) || die "failed to extract initramfs"
KVER=$(ls "$INITRD_DIR/usr/lib/modules/" 2>/dev/null | head -1)
[ -n "$KVER" ] || die "could not determine kernel version from initramfs"
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
(cd "$INITRD_DIR" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9 > "$MOUNT_POINT/boot/initramfs-lts") || die "failed to repack initramfs"
rm -rf "$INITRD_DIR" "$MODEXTRACT"

# Step 8: Write Alpine boot repository file (used by nlplug-findfs to detect the boot media)
echo "Writing .boot_repository..."
cat > "$MOUNT_POINT/.boot_repository" <<'REPO'
http://dl-cdn.alpinelinux.org/alpine/latest-stable/main
http://dl-cdn.alpinelinux.org/alpine/latest-stable/community
REPO

# Step 9: Build the apkovl (Alpine Local Backup) overlay
# Contains the OSFinder TUI, packages to install at boot, and the auto-start hook.
echo "Building Alpine apkovl overlay..."
"$PROJECT_DIR/setup/build_apkovl.sh" "$MOUNT_POINT/$APKOVL_NAME" "$PROJECT_DIR" \
    || die "failed to build apkovl"

# Step 10: Write GRUB configuration (base entries + ISO boot entries)
echo "Writing GRUB configuration..."
mkdir -p "$MOUNT_POINT/boot/grub"
sh "$PROJECT_DIR/setup/gen_grub_cfg.sh" "$PROJECT_DIR" "$MOUNT_POINT" > "$MOUNT_POINT/boot/grub/grub.cfg" \
    || die "failed to generate grub.cfg"

# Step 11: Install GRUB for BIOS and UEFI
echo "Installing GRUB (BIOS + UEFI)..."
grub-install --target=i386-pc --boot-directory="$MOUNT_POINT/boot" "$USB_DEVICE" \
    || die "GRUB BIOS install failed"
grub-install --target=x86_64-efi --efi-directory="$MOUNT_POINT" \
    --boot-directory="$MOUNT_POINT/boot" --removable \
    || die "GRUB UEFI install failed"

# Step 12: Unmount and finalize
sync
umount "$MOUNT_POINT" || die "umount failed"
rm -rf "$MOUNT_POINT"

echo ""
echo "========================================="
echo "  OSFinder USB created successfully!   "
echo "========================================="
echo ""
echo "Instructions:"
echo "  1. Insert USB into target computer"
echo "  2. Boot from USB (F8, F12, Del, or F2 for BIOS/UEFI)"
echo "  3. Select 'OSFinder TUI' in the GRUB menu"
echo "  4. Alpine boots into the OSFinder TUI automatically"
echo "  5. Search for OS by name or code number"
echo "  6. Select and download ISO via Supabase"
echo "  7. ISO downloads to /tmp/ on the target machine"
echo ""
echo "Notes:"
echo "  - Internet is required (both to boot Alpine and to download ISOs)"
echo "  - Downloads save to /tmp/ on the target machine"
echo "  - No ISO files are persisted on the USB after boot"
echo "  - Minimum USB size: 1GB (Alpine netboot files ~350MB)"