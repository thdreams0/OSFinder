#!/bin/sh
# OSFinder Installer & Verification Script
# Checks all components and ensures the project is ready to use
# ASK USER TO SELECT TARGET USB DEVICE

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Root check: this script must be run with sudo/root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script requires root privileges."
    echo "Please run it with sudo: sudo $0"
    exit 1
fi

# Function to list storage devices using lsblk
list_devices() {
    echo "Available storage devices for OSFinder USB:"
    echo "------------------------------------------"
    # Use lsblk if available, fall back to /dev/sd* and /dev/nvme*
    if command -v lsblk >/dev/null 2>&1; then
        lsblk -d -o NAME,SIZE,TYPE,MODEL 2>/dev/null | awk 'NR==1 || $3=="disk"'
    else
        DEVICES=""
        for dev in /dev/sd? /dev/nvme?n1; do
            [ -b "$dev" ] && DEVICES="$DEVICES $(basename "$dev")"
        done
        if [ -z "$DEVICES" ]; then
            echo "  No devices detected. Plug in your USB and try again."
            echo "  (expected examples: /dev/sda, /dev/sdb, /dev/nvme0n1)"
        else
            for d in $DEVICES; do echo "  $d"; done
        fi
    fi
    echo ""
    echo "Enter device name (e.g., sda, sdb, nvme0n1) or 'q' to quit:"
    read -r letter
    if [ "$letter" = "q" ] || [ "$letter" = "Q" ]; then
        echo "Operation cancelled."
        exit 1
    fi
    # Validate it's a single device identifier
    if echo "$letter" | grep -qE "^(sd|nvme)[a-z0-9]*$"; then
        SELECTED_DEVICE="$letter"
    else
        echo "Invalid input. Please enter a valid device name or 'q' to quit."
        list_devices
    fi
}

# Function to confirm device
confirm_device() {
    local dev="/dev/$1"
    echo ""
    echo "Selected: $dev"
    echo "This will ERASE ALL DATA on this device."
    echo "Proceed? (y/n)"
    read -r confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo "$1"
    else
        echo "Please select another device."
        list_devices
        confirm_device
    fi
}

# Function to check if something passed
check_ok() {
    if [ $1 -eq 0 ]; then
        echo "  [OK] $2"
    else
        echo "  [FAIL] $2"
    fi
}

# Function to print ok
print_ok() {
    if [ $1 -eq 0 ]; then
        echo "  [OK] $2"
    else
        echo "  [FAIL] $2"
    fi
}

# ===========================================
# HEADER
# ===========================================
clear
echo "========================================"
echo "  OSFinder Installer & Verification"
echo "========================================"
echo ""

# ===========================================
# 1. ASK USER FOR TARGET USB DEVICE
# ===========================================
echo "--- Select Target USB Device ---"
list_devices
if [ -z "$SELECTED_DEVICE" ]; then
    echo "No device selected. Operation cancelled."
    exit 1
fi
TARGET_DEV="/dev/$SELECTED_DEVICE"
confirm_device "$SELECTED_DEVICE"

# ===========================================
# 2. PROJECT STRUCTURE
# ===========================================
clear
echo "========================================"
echo "  OSFinder Installer & Verification"
echo "========================================"
echo ""
echo "--- Project Structure ---"
[ -f "$PROJECT_DIR/src/osfinder.sh" ]; TUI_FILE=$?
[ -f "$PROJECT_DIR/oslist.json" ]; LIST_FILE=$?
[ -f "$PROJECT_DIR/setup/usb_setup.sh" ]; USB_FILE=$?
[ -f "$PROJECT_DIR/README.md" ]; README_FILE=$?
[ -f "$PROJECT_DIR/USAGE.md" ]; USAGE_FILE=$?
check_ok $TUI_FILE "TUI script exists"
check_ok $LIST_FILE "OS list exists"
check_ok $USB_FILE "USB setup script exists"
check_ok $README_FILE "README exists"
check_ok $USAGE_FILE "User guide exists"

# ===========================================
# 3. TUI SCRIPT VALIDATION
# ===========================================
echo ""
echo "--- TUI Script Validation ---"
bash -n "$PROJECT_DIR/src/osfinder.sh" 2>/dev/null; TUI_OK=$?
check_ok $TUI_OK "TUI script syntax check"

# Check for required commands
echo ""
echo "--- Required Commands ---"
command -v sh >/dev/null; SH_OK=$?; check_ok $SH_OK "Bourne shell available"
command -v curl >/dev/null; CURL_OK=$?; check_ok $CURL_OK "curl for downloads available"
command -v jq >/dev/null; JQ_OK=$?; check_ok $JQ_OK "JSON processor available (jq)"
command -v tput >/dev/null; check_ok $? "Terminal handling available"
command -v mkfs.vfat >/dev/null 2>&1 || command -v mkfs.fat >/dev/null 2>&1; FAT_OK=$?; check_ok $FAT_OK "mkfs.vfat (dosfstools) available"
command -v parted >/dev/null; PARTED_OK=$?; check_ok $PARTED_OK "parted available"
command -v grub-install >/dev/null; GRUB_OK=$?; check_ok $GRUB_OK "grub-install available"
command -v wipefs >/dev/null; WIPEFS_OK=$?; check_ok $WIPEFS_OK "wipefs (util-linux) available"

# ===========================================
# 4. OS LIST VALIDATION (public JSON in this repo)
# ===========================================
echo ""
echo "--- OS List Validation ---"
if [ -f "$PROJECT_DIR/oslist.json" ]; then
    LIST_OK=0
    LIST_COUNT=$(jq 'length' "$PROJECT_DIR/oslist.json" 2>/dev/null || echo "0")
    if [ "$LIST_COUNT" -gt 0 ] 2>/dev/null; then
        check_ok 0 "OS list is valid JSON"
        echo "  Entries in list: $LIST_COUNT"
    else
        echo "  [FAIL] oslist.json is not valid JSON or is empty"
        LIST_OK=1
    fi
else
    echo "  [FAIL] oslist.json not found"
    LIST_OK=1
fi

# ===========================================
# 6. FINAL SUMMARY
# ===========================================
clear
echo "========================================"
echo "  OSFinder Installation Summary"
echo "========================================"
echo ""
echo "Target USB Device: $TARGET_DEV"
echo ""
echo "Components:"
DOCS_OK=1
[ "$README_FILE" = "0" ] && [ "$USAGE_FILE" = "0" ] && DOCS_OK=0
DEPS_OK=0
[ "$FAT_OK" != "0" ] && DEPS_OK=1
[ "$PARTED_OK" != "0" ] && DEPS_OK=1
[ "$GRUB_OK" != "0" ] && DEPS_OK=1
[ "$CURL_OK" != "0" ] && DEPS_OK=1
# JQ/LIST are optional for USB creation - pen boots without them, TUI fetches list at runtime
echo "  [1/4] TUI Script (src/osfinder.sh)          : $(print_ok "$TUI_OK" "Syntax valid, sh+curl+jq+tput required")"
echo "  [2/4] OS List (oslist.json)                  : $(print_ok "$LIST_OK" "Public JSON list, optional at install")"
echo "  [3/4] USB Setup (setup/usb_setup.sh)       : $(print_ok "$USB_FILE" "Creates bootable USB with Alpine + GRUB")"
echo "  [4/4] Documentation (README.md, USAGE.md)  : $(print_ok "$DOCS_OK" "Available for user reference")"
if [ "$DEPS_OK" != "0" ] || [ "$TUI_OK" != "0" ]; then
    echo ""
    echo "  [!] Some checks FAILED - install will likely fail."
    if [ "$FAT_OK" != "0" ]; then echo "      - missing mkfs.vfat: sudo pacman -S dosfstools  (or sudo apt install dosfstools)"; fi
    if [ "$PARTED_OK" != "0" ]; then echo "      - missing parted: sudo pacman -S parted  (or sudo apt install parted)"; fi
    if [ "$GRUB_OK" != "0" ]; then echo "      - missing grub: sudo pacman -S grub  (or sudo apt install grub-pc grub-efi-amd64)"; fi
    if [ "$CURL_OK" != "0" ]; then echo "      - missing curl: sudo pacman -S curl"; fi
fi
if [ "$JQ_OK" != "0" ] || [ "$LIST_OK" != "0" ]; then
    echo ""
    echo "  [i] Optional: oslist/jq missing - USB will still be created (list is fetched at boot)."
    if [ "$JQ_OK" != "0" ]; then echo "      - jq not found: sudo pacman -S jq (needed to validate oslist, ISO entries will be empty)"; fi
    if [ "$LIST_OK" != "0" ]; then echo "      - oslist.json not valid/readable - will boot without pre-generated ISO entries"; fi
fi
echo ""
echo "  The USB at $TARGET_DEV will be formatted as FAT32"
echo "  and contain the OSFinder TUI system."
echo "  ALL DATA on this USB will be ERASED."
echo ""
echo "  Press Enter to continue with creating the bootable USB,"
echo "  or 'q' to quit without changes."
read -r key

if [ "$key" = "q" ] || [ "$key" = "Q" ]; then
    echo "Operation cancelled by user."
    exit 1
fi

if [ "$DEPS_OK" != "0" ]; then
    echo ""
    echo "Missing critical deps - trying to install automatically (running as root)..."
    # try auto-install (no prompt) - best effort, falls back to manual message
    if command -v pacman >/dev/null 2>&1; then
        echo "  -> pacman -Sy --noconfirm dosfstools parted grub curl jq"
        pacman -Sy --noconfirm dosfstools parted grub curl jq 2>&1 | tail -20
    elif command -v apt >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1; then
        echo "  -> apt update && apt install dosfstools parted grub-pc grub-efi-amd64-bin curl jq"
        apt update 2>&1 | tail -5
        apt install -y dosfstools parted grub-pc grub-efi-amd64-bin curl jq 2>&1 | tail -20
    elif command -v dnf >/dev/null 2>&1; then
        echo "  -> dnf install dosfstools parted grub2-tools curl jq"
        dnf install -y dosfstools parted grub2-tools curl jq 2>&1 | tail -20
    fi
    # re-check
    command -v mkfs.vfat >/dev/null 2>&1 || command -v mkfs.fat >/dev/null 2>&1; FAT_OK=$?
    command -v parted >/dev/null; PARTED_OK=$?
    command -v grub-install >/dev/null; GRUB_OK=$?
    command -v curl >/dev/null; CURL_OK=$?
    command -v jq >/dev/null; JQ_OK=$?
    DEPS_OK=0
    [ "$FAT_OK" != "0" ] && DEPS_OK=1
    [ "$PARTED_OK" != "0" ] && DEPS_OK=1
    [ "$GRUB_OK" != "0" ] && DEPS_OK=1
    [ "$CURL_OK" != "0" ] && DEPS_OK=1
    if [ "$DEPS_OK" != "0" ]; then
        echo ""
        echo "ERROR: Still missing deps. Install manually and re-run:"
        echo "  Arch: sudo pacman -S dosfstools parted grub curl jq"
        echo "  Debian/Ubuntu: sudo apt update && sudo apt install dosfstools parted grub-pc grub-efi-amd64-bin curl jq"
        echo ""
        echo "Aborting before touching the USB."
        exit 1
    else
        echo "  [OK] Deps auto-installed. Continuing..."
        # re-validate oslist now that jq may exist
        if [ -f "$PROJECT_DIR/oslist.json" ]; then
            LIST_COUNT=$(jq 'length' "$PROJECT_DIR/oslist.json" 2>/dev/null || echo "0")
            if [ "$LIST_COUNT" -gt 0 ] 2>/dev/null; then LIST_OK=0; else LIST_OK=1; fi
        fi
    fi
fi
# oslist/jq is NOT required - TUI fetches it at runtime, grub will just have no ISO entries
if [ "$TUI_OK" != "0" ]; then
    echo "ERROR: TUI script has syntax errors. Fix src/osfinder.sh before installing."
    exit 1
fi

# Run the USB setup
if bash "$PROJECT_DIR/setup/usb_setup.sh" "$TARGET_DEV"; then
    echo ""
    echo "========================================"
    echo "=== OSFinder installation SUCCESSFUL ==="
    echo "========================================"
else
    echo ""
    echo "========================================"
    echo "=== OSFinder installation FAILED     ==="
    echo "========================================"
    exit 1
fi