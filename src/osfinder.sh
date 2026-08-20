#!/bin/sh
# OSFinder TUI - Text User Interface for searching and downloading ISOs
# Bare-metal compatible: uses only sh, curl, jq, tput
# Runs on Alpine Linux (busybox ash) booted from the OSFinder USB
#
# The OS library is a public JSON file hosted in the GitHub repository
# (oslist.json), served via jsDelivr CDN with a GitHub raw fallback.

# Public OS list (name|url entries). No credentials needed - anyone can view.
OS_LIST_URL="https://raw.githubusercontent.com/thdreams0/OSFinder/main/oslist.json"
OS_LIST_FALLBACK_URL="https://cdn.jsdelivr.net/gh/thdreams0/OSFinder@main/oslist.json"

# Result temp file (one per process, reused across recursive calls)
RESULTS_FILE="/tmp/osf_results_$$"

# ANSI colors - kept minimal: only green (success) and red (errors)
GREEN="$(printf '\033[32m')"
RED="$(printf '\033[31m')"
RESET="$(printf '\033[0m')"
YELLOW=""
BLUE=""
CYAN=""
MAGENTA=""
BOLD=""
DIM=""
WHITE=""

# Show ASCII progress bar (POSIX/busybox compatible)
show_progress() {
    local pct="$1" i
    local width=50
    local filled=$((pct * width / 100))
    printf "\r["
    i=0
    while [ "$i" -lt "$filled" ]; do
        printf "="
        i=$((i + 1))
    done
    while [ "$i" -lt "$width" ]; do
        printf " "
        i=$((i + 1))
    done
    printf "] %d%%" "$pct"
}

# Fetch the public OS list from GitHub and filter locally (partial, case-insensitive).
# Returns name|url entries. Return codes: 0=found, 1=no results, 2=no network/list unreachable
search_os() {
    local query="$1"
    local result url

    if ! ip route show 2>/dev/null | grep -q '^default'; then
        return 2
    fi

    for url in "$OS_LIST_URL" "$OS_LIST_FALLBACK_URL"; do
        result=$(curl -sL --max-time 15 "$url" 2>/dev/null)
        [ -n "$result" ] && break
    done
    if [ -z "$result" ]; then
        return 2
    fi

    result=$(printf '%s' "$result" | jq -r --arg q "$query" \
        '.[] | select((.name | ascii_downcase) | contains(($q | ascii_downcase))) | "\(.name)|\(.url)"' 2>/dev/null)

    if [ -z "$result" ]; then
        echo ""
        return 1
    fi
    echo "$result"
    return 0
}

# Find the USB pen mount (used to persist WiFi config)
find_pen() {
    local d
    for d in /media/*; do
        [ -d "$d" ] && [ -f "$d/.boot_repository" ] && echo "$d" && return 0
    done
    return 1
}

# Detect the wireless interface name (wlan0 etc.), or empty
wifi_iface() {
    local d n
    for d in /sys/class/net/*; do
        n=${d##*/}
        [ "$n" = "lo" ] && continue
        if iw dev "$n" info >/dev/null 2>&1; then
            echo "$n"
            return 0
        fi
    done
    return 1
}

# Report current network state as a short string
net_status() {
    if ip route show 2>/dev/null | grep -q '^default'; then
        echo "Connected"
    else
        echo "No internet"
    fi
}

# Retry wired DHCP on all ethernet interfaces
try_wired() {
    local d n
    for d in /sys/class/net/*; do
        n=${d##*/}
        [ "$n" = "lo" ] && continue
        iw dev "$n" info >/dev/null 2>&1 && continue
        ip link set "$n" up 2>/dev/null
        udhcpc -i "$n" -b -q >/dev/null 2>&1 || true
    done
    sleep 3
    ip route show 2>/dev/null | grep -q '^default'
}

# WiFi setup wizard: scan, pick a network, enter password, connect, save.
wifi_wizard() {
    local iface="" ssid="" pass="" pen="" conf="/etc/wpa_supplicant/wpa_supplicant.conf"
    local netlist="" line i=1 n

    iface=$(wifi_iface) || {
        echo "${RED}No WiFi hardware was found on this machine.${RESET}"
        echo "${YELLOW}Please plug in an ethernet cable instead.${RESET}"
        sleep 2
        return 1
    }
    ip link set "$iface" up 2>/dev/null

    while :; do
        tput clear 2>/dev/null || printf '\033[2J\033[H'
        echo "${MAGENTA}===== WiFi setup =====${RESET}"
        echo "${DIM}Scanning for wireless networks...${RESET}"
        sleep 1
        netlist=$(iw dev "$iface" scan 2>/dev/null | grep -o 'SSID: .*' | sed 's/SSID: //' | sort -u)

        if [ -z "$netlist" ]; then
            echo "${RED}No networks found.${RESET}"
            echo "${YELLOW}Check that WiFi is switched on and try again.${RESET}"
            printf "${DIM}Press Enter to rescan, or 'q' to go back...${RESET}"
            read -r n || return 1
            case "$n" in
                q|Q|quit|sair) return 1 ;;
                *) continue ;;
            esac
        fi

        i=1
        printf '%s\n' "$netlist" | while IFS= read -r line; do
            printf "  ${WHITE}%d.${RESET} %s\n" "$i" "$line"
            i=$((i + 1))
        done
        echo ""
        echo "${DIM}Type a number to pick a network, type the name, or 'q' to go back.${RESET}"
        printf "${BLUE}Choose a network> ${RESET}"
        read -r ssid || return 1
        case "$ssid" in
            q|Q|quit|sair) return 1 ;;
        esac
        if [ "$ssid" -eq "$ssid" ] 2>/dev/null; then
            picked=$(printf '%s\n' "$netlist" | sed -n "${ssid}p")
            [ -n "$picked" ] || { echo "${RED}Invalid number.${RESET}"; sleep 1; continue; }
            ssid="$picked"
        fi

        printf "${BLUE}Password for ${WHITE}${ssid}${BLUE}> ${RESET}"
        stty -echo 2>/dev/null || true
        read -r pass
        stty echo 2>/dev/null || true
        echo ""

        mkdir -p /etc/wpa_supplicant
        cat > "$conf" <<EOF
ctrl_interface=/var/run/wpa_supplicant
update_config=1
network={
    ssid="$ssid"
    psk="$pass"
}
EOF
        killall wpa_supplicant 2>/dev/null || true
        sleep 1
        wpa_supplicant -B -i "$iface" -c "$conf" >/dev/null 2>&1 || {
            echo "${RED}Could not start the WiFi connection.${RESET}"
            sleep 2
            continue
        }
        echo "${DIM}Connecting to ${WHITE}${ssid}${DIM}...${RESET}"
        sleep 5
        udhcpc -i "$iface" -b -q >/dev/null 2>&1
        sleep 2

        if ip route show 2>/dev/null | grep -q '^default'; then
            if pen=$(find_pen); then
                mkdir -p "$pen/etc"
                cp "$conf" "$pen/etc/wpa_supplicant.conf" 2>/dev/null
            fi
            echo "${GREEN}Connected to ${WHITE}${ssid}${GREEN}! Saved for next boot.${RESET}"
            sleep 2
            return 0
        else
            echo "${RED}Could not connect to '${ssid}'. Wrong password?${RESET}"
            printf "${DIM}Press Enter to try again, or 'q' to go back...${RESET}"
            read -r n || return 1
            case "$n" in
                q|Q|quit|sair) return 1 ;;
                *) continue ;;
            esac
        fi
    done
}

# Make sure we have internet before doing anything that needs it.
# If there is none, this walks the user through WiFi setup automatically.
ensure_network() {
    if ip route show 2>/dev/null | grep -q '^default'; then
        return 0
    fi
    echo "${YELLOW}No internet detected.${RESET}"
    echo "${DIM}Trying ethernet one more time...${RESET}"
    if try_wired; then
        echo "${GREEN}Ethernet connected!${RESET}"
        return 0
    fi
    echo "${YELLOW}No ethernet either. Let's set up WiFi.${RESET}"
    echo "${DIM}If you plug in an ethernet cable now, it will work automatically.${RESET}"
    printf "${DIM}Press Enter to set up WiFi...${RESET}"
    read -r n || return 1
    wifi_wizard
}

# Download ISO with a real progress bar (background curl + size polling)
download_iso() {
    local url="$1" dest="$2"
    local filename total size pct cpid rc
    filename=$(basename "$url")
    mkdir -p "$(dirname "$dest")"

    echo "${YELLOW}Downloading: ${WHITE}${filename}${RESET}"
    echo "${YELLOW}From: ${WHITE}${url}${RESET}"

    total=$(curl -sIL --max-time 20 "$url" 2>/dev/null | tr -d '\r' \
        | awk -F': ' 'tolower($1)=="content-length"{v=$2} END{print v+0}')
    [ "$total" -ge 0 ] 2>/dev/null || total=0

    rm -f "$dest"
    curl -sL --max-time 14400 -o "$dest" "$url" &
    cpid=$!

    while kill -0 "$cpid" 2>/dev/null; do
        if [ -f "$dest" ]; then
            size=$(wc -c < "$dest" 2>/dev/null)
            if [ "$total" -gt 0 ]; then
                pct=$((size * 100 / total))
            else
                pct=0
            fi
            show_progress "$pct"
        fi
        sleep 1
    done
    show_progress 100
    wait "$cpid"
    rc=$?
    echo ""
    if [ "$rc" -eq 0 ] && [ -f "$dest" ] && [ -s "$dest" ]; then
        size=$(du -h "$dest" 2>/dev/null | cut -f1)
        echo "${GREEN}Downloaded: ${WHITE}${filename} (${size})${RESET}"
        return 0
    else
        rm -f "$dest"
        echo "${RED}Download failed${RESET}"
        return 1
    fi
}

# Mount the ISO and open a shell inside it to run the installer
mount_and_open() {
    local iso="$1" i
    if [ ! -f "$iso" ]; then
        echo "${RED}ISO not found: ${iso}${RESET}"
        echo "${DIM}It may have been cleaned up. Download it again.${RESET}"
        sleep 3
        return 1
    fi
    # The live session may not have loop devices/module loaded yet
    modprobe loop 2>/dev/null || true
    for i in 0 1 2 3 4 5 6 7; do
        [ -e "/dev/loop$i" ] || mknod -m 600 "/dev/loop$i" b 7 "$i" 2>/dev/null
    done
    mkdir -p /mnt/iso
    if ! mount -o loop,ro "$iso" /mnt/iso 2>/dev/null; then
        echo "${RED}Could not mount the ISO.${RESET}"
        echo "${DIM}Loop devices are unavailable in this live session.${RESET}"
        echo "${DIM}Use option 2 (copy to pen) and boot from the pen instead.${RESET}"
        sleep 3
        return 1
    fi
    tput clear 2>/dev/null || printf '\033[2J\033[H'
    echo "${GREEN}ISO mounted at /mnt/iso${RESET}"
    echo ""
    echo "${DIM}Look for the installer inside (e.g. ./install*, casper,${RESET}"
    echo "${DIM}ubiquity, calamares) and run it. This is the same as if the${RESET}"
    echo "${DIM}ISO were in the drive. Type 'exit' to return to OSFinder.${RESET}"
    echo ""
    (cd /mnt/iso && sh)
    umount /mnt/iso 2>/dev/null || true
    echo ""
    return 0
}

# Copy the downloaded ISO onto the USB pen so it can be booted elsewhere
copy_to_pen() {
    local iso="$1" pen=""
    for d in /media/*; do
        [ -d "$d" ] && [ -f "$d/.boot_repository" ] && pen="$d"
    done
    if [ -z "$pen" ]; then
        echo "${RED}USB pen not found.${RESET}"
        sleep 2
        return 1
    fi
    echo "Copying ISO to $pen (this can take a while)..."
    if cp "$iso" "$pen/" 2>/dev/null; then
        echo "${GREEN}Saved to ${WHITE}${pen}/$(basename "$iso")${RESET}"
    else
        echo "${RED}Copy failed.${RESET}"
    fi
    sleep 2
    return 0
}

# Post-download menu
post_download_menu() {
    local iso="$1" choice

    while :; do
        tput clear 2>/dev/null || printf '\033[2J\033[H'
        echo "${GREEN}Download complete: ${WHITE}${iso}${RESET}"
        echo ""
        echo "${BOLD}What next?${RESET}"
        echo "  1. Mount the ISO and open the installer"
        echo "  2. Copy the ISO to the USB pen"
        echo "  3. Search another OS"
        echo ""
        printf "${BLUE}Select> ${RESET}"
        read -r choice || return 0
        case "$choice" in
            1) mount_and_open "$iso" ;;
            2) copy_to_pen "$iso" ;;
            3|"") return 0 ;;
            *) echo "${RED}Invalid selection.${RESET}"; sleep 1 ;;
        esac
    done
}

# Show title banner
show_title() {
    tput clear 2>/dev/null || printf '\033[2J\033[H'
    echo "${CYAN}========================================${RESET}"
    echo "${MAGENTA}OSFinder - Download and install an OS${RESET}"
    echo "========================================"
    echo ""
    if ip route show 2>/dev/null | grep -q '^default'; then
        echo "${GREEN}Internet: ${WHITE}Connected${RESET}"
    else
        echo "${RED}Internet: ${WHITE}OFF${RESET}"
        echo "${DIM}We'll help you connect when you need it.${RESET}"
    fi
}

# Pick the entry matching a given result index (1-based) and echo its download link
pick_result() {
    local idx="$1" i=1 os_name_code link selected=""
    printf '%s\n' "$results" > "$RESULTS_FILE"
    while IFS='|' read -r os_name_code link; do
        if [ "$i" -eq "$idx" ]; then
            selected="$link"
            break
        fi
        i=$((i + 1))
    done < "$RESULTS_FILE"
    echo "$selected"
}

# Show search interface with results
show_search() {
    local query="$1"
    local results="$2"
    local i=1 display_name link

    tput clear 2>/dev/null || printf '\033[2J\033[H'
    show_title
    echo ""
    echo "${BOLD}Search OS: ${WHITE}${query}${RESET}"

    if [ -n "$results" ]; then
        echo "${BOLD}Available results:${RESET}"
        echo "---------------------"
        printf '%s\n' "$results" > "$RESULTS_FILE"
        while IFS='|' read -r os_name_code link; do
            display_name=$(printf '%s' "$os_name_code" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ ${#display_name} -gt 50 ]; then
                display_name=$(printf '%.47s...' "$display_name")
            fi
            printf "  %d. %s\n" "$i" "$display_name"
            i=$((i + 1))
        done < "$RESULTS_FILE"
        echo "---------------------"
        echo "${YELLOW}Type the number to download${RESET}"
    else
        echo "${RED}No results found for: '${query}'${RESET}"
        echo "${DIM}Try another name (e.g. ubuntu, debian, cachyos)${RESET}"
    fi
}

# Download and report result; returns 0 if downloaded
do_download() {
    local url="$1"
    local iso_name dest

    if [ -z "$url" ]; then
        echo "${RED}Could not get a download link for that entry.${RESET}"
        return 1
    fi

    iso_name=$(basename "$url")
    dest="/tmp/${iso_name}"

    if download_iso "$url" "$dest"; then
        echo ""
        post_download_menu "$dest"
        return 0
    else
        echo "${RED}Download failed.${RESET}"
        echo "${DIM}Press Enter to try again...${RESET}"
        read -r enter
        return 1
    fi
}

# Pick a larger console font based on the monitor resolution so text stays
# readable on big screens. Larger font = bigger letters. No-op if unavailable.
set_console_font() {
    local res="" h="" font=""
    res=$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null)
    h=$(printf '%s' "$res" | tr ' ,' '\n' | tail -1 | tr -cd '0-9')
    case "$h" in
        ""|0) return 1 ;;
    esac
    if [ "$h" -ge 1440 ]; then
        font="solar24x32"
    elif [ "$h" -ge 1080 ]; then
        font="sun12x22"
    elif [ "$h" -ge 900 ]; then
        font="Lat2-Terminus16"
    elif [ "$h" -ge 720 ]; then
        font="Lat2-Terminus16"
    else
        return 1
    fi
    if command -v setfont >/dev/null 2>&1; then
        setfont "/usr/share/consolefonts/${font}.psfu.gz" 2>/dev/null
    fi
}

# Search + download flow
search_flow() {
    local query="" results="" choice="" selected_link="" rc="" enter=""

    ensure_network || return 1

    while :; do
        tput clear 2>/dev/null || printf '\033[2J\033[H'
        show_title
        echo ""
        echo "${BOLD}What do you want to install?${RESET}"
        echo "${DIM}Type part of the name (e.g. ubuntu, debian, cachyos)${RESET}"
        echo "${DIM}Press Enter with nothing typed to go back.${RESET}"
        echo ""
        printf "${BLUE}Search> ${RESET}"
        read -r query || return 1
        case "$query" in
            q|Q|quit|sair|voltar|"") return 0 ;;
        esac

        results=$(search_os "$query")
        rc=$?
        if [ "$rc" -eq 2 ]; then
            echo ""
            echo "${YELLOW}Internet went away. Let's reconnect...${RESET}"
            ensure_network || { echo "${RED}Still no internet.${RESET}"; sleep 2; return 1; }
            continue
        fi

        show_search "$query" "$results"
        echo ""
        printf "${BLUE}Select> ${RESET}"
        read -r choice || return 1
        [ -n "$choice" ] || continue

        if [ "$choice" -eq "$choice" ] 2>/dev/null; then
            selected_link=$(pick_result "$choice")
            if [ -n "$selected_link" ]; then
                do_download "$selected_link"
            else
                echo "${RED}Invalid selection.${RESET}"
                sleep 2
            fi
        else
            echo "${RED}Type the number of the OS you want.${RESET}"
            sleep 2
        fi
    done
}

# Main menu (iterative - no recursion, so empty input can't overflow the stack)
main() {
    local choice="" enter="" first=1

    set_console_font

    while :; do
        if [ "$first" -eq 1 ]; then
            first=0
            if ! ip route show 2>/dev/null | grep -q '^default'; then
                echo "${YELLOW}Welcome! Let's get you online first.${RESET}"
                echo "${DIM}If you have ethernet plugged in, it connects automatically.${RESET}"
                echo ""
                ensure_network
                echo ""
            fi
        fi

        show_title
        echo ""
        echo "${BOLD}What do you want to do?${RESET}"
        echo "  1. ${WHITE}Search and download an OS${RESET}"
        echo "  2. ${WHITE}Set up WiFi${RESET}"
        echo "  3. ${WHITE}Shell (for advanced users)${RESET}"
        echo "  4. ${WHITE}Power off${RESET}"
        echo ""
        printf "${BLUE}Choose an option> ${RESET}"
        read -r choice || break

        case "$choice" in
            1|"") search_flow ;;
            2)
                wifi_wizard
                echo "${DIM}Press Enter to continue...${RESET}"
                read -r enter || break
                ;;
            3|"shell")
                echo "${YELLOW}Shell (type 'exit' to go back).${RESET}"
                /bin/sh
                ;;
            4|"poweroff"|"quit"|"exit")
                echo "${YELLOW}Powering off...${RESET}"
                sleep 1
                poweroff -f 2>/dev/null || busybox poweroff -f 2>/dev/null || true
                exit 0
                ;;
            *) echo "${RED}Type 1, 2, 3 or 4.${RESET}"; sleep 1 ;;
        esac
    done
}

# Run main function
main "$@"