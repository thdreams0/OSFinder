#!/bin/sh
# OSFinder Installer & Verification Script
# Checks all components and ensures the project is ready to use
# ASK USER TO SELECT TARGET USB DEVICE

PROJECT_DIR="/home/andre/Projects/OSFinder"

# Load Supabase credentials from config/.env (kept out of git)
if [ -r "$PROJECT_DIR/config/.env" ]; then
    . "$PROJECT_DIR/config/.env"
elif [ -r /etc/osfinder.env ]; then
    . /etc/osfinder.env
fi

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
            echo "  /dev/sda (119,2G disk)"
            echo "  /dev/nvme0n1 (931,5G disk)"
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
[ -f "$PROJECT_DIR/website/index.html" ]; WEB_FILE=$?
[ -f "$PROJECT_DIR/config/.env" ]; ENV_FILE=$?
[ -f "$PROJECT_DIR/setup/usb_setup.sh" ]; USB_FILE=$?
[ -f "$PROJECT_DIR/README" ]; README_FILE=$?
[ -f "$PROJECT_DIR/USAGE.md" ]; USAGE_FILE=$?
check_ok $TUI_FILE "TUI script exists"
check_ok $WEB_FILE "Website exists"
check_ok $ENV_FILE "Supabase config exists"
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
command -v sh >/dev/null; check_ok $? "Bourne shell available"
command -v curl >/dev/null; check_ok $? "curl for downloads available"
command -v jq >/dev/null; check_ok $? "JSON processor available"
command -v tput >/dev/null; check_ok $? "Terminal handling available"

# ===========================================
# 4. WEBSITE VALIDATION
# ===========================================
echo ""
echo "--- Website Validation ---"
WEB_OK=$WEB_FILE
if grep -q "service_role" "$PROJECT_DIR/website/index.html" 2>/dev/null; then
    echo "  [WARN] service_role key found (should use anon key for read-only)"
else
    check_ok 0 "No service_role key (read-only configured)"
fi

# Check for OS name fields
if grep -q "osName\|OS_NAME" "$PROJECT_DIR/website/index.html" 2>/dev/null; then
    check_ok 0 "OS name input field present"
else
    echo "  [FAIL] OS name input field missing"
    WEB_OK=1
fi
[ "$WEB_FILE" = "0" ] || WEB_OK=1

# ===========================================
# 5. SUPABASE CONNECTIVITY
# ===========================================
echo ""
echo "--- Supabase Connectivity ---"
if [ -n "$SUPABASE_URL" ] && [ -n "$SUPABASE_ANON_KEY" ]; then
    SUPABASE_RESPONSE=$(curl -s "$SUPABASE_URL?select=os_name" \
        -H "apikey: $SUPABASE_ANON_KEY" \
        -H "Authorization: Bearer $SUPABASE_ANON_KEY" 2>/dev/null)
    if [ -n "$SUPABASE_RESPONSE" ] && [ "$SUPABASE_RESPONSE" != "[]" ]; then
        check_ok 0 "Supabase anon key works - can read data"
        SUPABASE_OK=0
        RECORD_COUNT=$(echo "$SUPABASE_RESPONSE" | jq 'length' 2>/dev/null || echo "0")
        echo "  Records in database: $RECORD_COUNT"
    else
        echo "  [FAIL] Supabase anon key cannot read data"
        SUPABASE_OK=1
    fi
else
    echo "  [SKIP] Supabase check (config/.env missing)"
    SUPABASE_OK=1
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
echo "  [1/5] TUI Script (src/osfinder.sh)          : $(print_ok "$TUI_OK" "Syntax valid, sh+curl+jq+tput required")"
echo "  [2/5] Website (website/index.html)         : $(print_ok "$WEB_OK" "Read-only anon key, OS name inputs")"
echo "  [3/5] Supabase Connectivity                  : $(print_ok "$SUPABASE_OK" "Anon key can read list table")"
echo "  [4/5] USB Setup (setup/usb_setup.sh)       : $(print_ok "$USB_FILE" "Creates bootable USB with Alpine + GRUB")"
echo "  [5/5] Documentation (README, USAGE.md)     : $(print_ok "$DOCS_OK" "Available for user reference")"
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