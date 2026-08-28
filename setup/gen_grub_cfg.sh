#!/bin/sh
# OSFinder: generate the full GRUB configuration
# Base OSFinder entries + ISO boot entries generated from oslist.json
# (so ISOs copied to the pen can be booted from the GRUB menu, Ventoy-style).
# Usage: setup/gen_grub_cfg.sh <project_dir> [pen_dir]
#   project_dir  - directory containing oslist.json (override with LIST_FILE)
#   pen_dir      - optional; when given, only emit entries for ISOs present there

if [ -z "$1" ]; then
    echo "Usage: $0 <project_dir> [pen_dir]"
    exit 1
fi
PROJECT_DIR="$1"
PEN_DIR="${2:-}"
LIST_FILE="${LIST_FILE:-$PROJECT_DIR/oslist.json}"

cat <<'GRUB'
set timeout=10
set default=0

set alpine_repo="http://dl-cdn.alpinelinux.org/alpine/latest-stable/main,http://dl-cdn.alpinelinux.org/alpine/latest-stable/community"

menuentry 'OSFinder TUI' {
    search --no-floppy --set=root --file /boot/vmlinuz-lts
    linux /boot/vmlinuz-lts ip=dhcp alpine_repo="$alpine_repo" quiet
    initrd /boot/initramfs-lts
}

menuentry 'OSFinder TUI (verbose)' {
    search --no-floppy --set=root --file /boot/vmlinuz-lts
    linux /boot/vmlinuz-lts ip=dhcp alpine_repo="$alpine_repo"
    initrd /boot/initramfs-lts
}

GRUB

# --- ISO boot entries generated from oslist.json ---
if [ -r "$LIST_FILE" ] && command -v jq >/dev/null 2>&1; then
    printf '\n# === OSFinder ISO boot entries (auto-generated) ===\n'
    jq -r '.[] | select((.type // "none") != "none") | "\(.name)|\(.type)|\(.url | split("/") | last)"' \
        "$LIST_FILE" 2>/dev/null |
    while IFS='|' read -r name type iso; do
        [ -n "$name" ] || continue
        [ -n "$iso" ] || continue
        # When a pen dir is given, only boot ISOs that are actually on the pen
        if [ -n "$PEN_DIR" ] && [ ! -f "$PEN_DIR/$iso" ]; then
            continue
        fi
        case "$type" in
            arch)
                printf "menuentry 'ISO: %s' {\n" "$name"
                printf '    insmod loopback\n'
                printf '    search --no-floppy --set=root --file /%s\n' "$iso"
                printf '    probe --set=osfuuid --fs-uuid "$root"\n'
                printf '    loopback loop0 /%s\n' "$iso"
                printf '    linux (loop0)/arch/boot/x86_64/vmlinuz-linux archisobasedir=arch img_dev=UUID=$osfuuid img_loop=/%s\n' "$iso"
                printf '    initrd (loop0)/arch/boot/x86_64/initramfs-linux.img\n'
                printf '}\n'
                ;;
            ubuntu)
                printf "menuentry 'ISO: %s' {\n" "$name"
                printf '    insmod loopback\n'
                printf '    search --no-floppy --set=root --file /%s\n' "$iso"
                printf '    loopback loop0 /%s\n' "$iso"
                printf '    linux (loop0)/casper/vmlinuz boot=casper iso-scan/filename=/%s quiet splash\n' "$iso"
                printf '    initrd (loop0)/casper/initrd\n'
                printf '}\n'
                ;;
            *)
                echo "  WARNING: unknown ISO type '$type' for '$name' (skipping)" >&2
                ;;
        esac
    done
    printf '# === end ISO boot entries ===\n'
else
    echo "  WARNING: oslist.json or jq unavailable; no ISO boot entries" >&2
fi