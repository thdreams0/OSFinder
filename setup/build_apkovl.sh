#!/bin/sh
# OSFinder: build the Alpine apkovl overlay
# Usage: setup/build_apkovl.sh <output.tar.gz> <project_dir>
#
# The overlay contains:
#   /usr/local/bin/osfinder.sh      - the OSFinder TUI
#   /etc/apk/world                  - packages to install at boot (curl, jq, ncurses)
#   /etc/inittab                    - tty1 runs the TUI (respawn), kiosk-style
#   /etc/local.d/osfinder.start     - brings up networking via DHCP
#   /etc/runlevels/*                - standard OpenRC runlevels (defaults are
#                                     skipped when an apkovl is present)

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <output.tar.gz> <project_dir>"
    exit 1
fi

OUT="$1"
PROJECT_DIR="$2"

OVL_DIR="/tmp/osfinder_apkovl.$$"
mkdir -p "$OVL_DIR/etc/local.d" \
         "$OVL_DIR/etc/runlevels/sysinit" \
         "$OVL_DIR/etc/runlevels/boot" \
         "$OVL_DIR/etc/runlevels/default" \
         "$OVL_DIR/etc/runlevels/shutdown" \
         "$OVL_DIR/etc/apk" \
         "$OVL_DIR/usr/local/bin" \
         "$OVL_DIR/usr/bin" \
         "$OVL_DIR/usr/sbin" \
         "$OVL_DIR/usr/lib"

# Bundle the tools the TUI needs (curl, jq, wpa_supplicant, iw) directly into
# the apkovl, so no network is required at first boot (no apk add). This also
# means WiFi-only machines work with no ethernet at all. We use apk-tools-static
# (2.x, from an older Alpine release) with --allow-untrusted to resolve and
# install the packages into a temporary rootfs, then copy the binaries/libs in.
APKSTATIC_URL=""
for v in v3.21 v3.22 v3.23; do
    APKSTATIC_URL="https://dl-cdn.alpinelinux.org/alpine/$v/main/x86_64"
    APKSTATIC_NAME=$(curl -s "$APKSTATIC_URL/" | grep -oE 'apk-tools-static-[0-9]+\.[0-9]+\.[0-9]+-r[0-9]+\.apk' | sort -uV | tail -1)
    [ -n "$APKSTATIC_NAME" ] && break
done
[ -n "$APKSTATIC_NAME" ] || { echo "  WARNING: could not find apk-tools-static; falling back to apk add at boot"; APKSTATIC_URL=""; }
if [ -n "$APKSTATIC_URL" ]; then
    echo "  fetching $APKSTATIC_NAME..."
    curl -sfL --retry 3 -o /tmp/osfinder_apkstatic.apk "$APKSTATIC_URL/$APKSTATIC_NAME" || APKSTATIC_URL=""
fi
PKGROOT="/tmp/osfinder_pkgroot.$$"
if [ -n "$APKSTATIC_URL" ] && [ -s /tmp/osfinder_apkstatic.apk ]; then
    rm -rf "$PKGROOT"
    mkdir -p "$PKGROOT/etc/apk"
    printf '%s\n' \
        "https://dl-cdn.alpinelinux.org/alpine/latest-stable/main" \
        "https://dl-cdn.alpinelinux.org/alpine/latest-stable/community" > "$PKGROOT/etc/apk/repositories"
    mkdir -p /tmp/osfinder_apkstatic_extract.$$
    tar -C /tmp/osfinder_apkstatic_extract.$$ -xzf /tmp/osfinder_apkstatic.apk 2>/dev/null
    APKSTATIC=$(find /tmp/osfinder_apkstatic_extract.$$ -name apk.static)
    rm -f /tmp/osfinder_apkstatic.apk
    if [ -n "$APKSTATIC" ]; then
        echo "  installing curl/jq/wpa_supplicant/iw/kbd into bundle root..."
        "$APKSTATIC" --root "$PKGROOT" --initdb --allow-untrusted --update \
            add curl jq wpa_supplicant iw kbd kbd-misc >/dev/null 2>&1 \
            || echo "  WARNING: apk add failed; falling back to apk add at boot"
        if [ -x "$PKGROOT/usr/bin/curl" ] && [ -x "$PKGROOT/usr/bin/jq" ]; then
            cp -a "$PKGROOT/usr/bin/." "$OVL_DIR/usr/bin/" 2>/dev/null
            cp -a "$PKGROOT/usr/sbin/." "$OVL_DIR/usr/sbin/" 2>/dev/null
            cp -a "$PKGROOT/usr/lib/." "$OVL_DIR/usr/lib/" 2>/dev/null
            mkdir -p "$OVL_DIR/lib"
            cp -a "$PKGROOT/lib/"*.so* "$OVL_DIR/lib/" 2>/dev/null
            cp -a "$PKGROOT/lib/"ld-musl* "$OVL_DIR/lib/" 2>/dev/null
            [ -f "$PKGROOT/sbin/wpa_supplicant" ] && cp -a "$PKGROOT/sbin/wpa_supplicant" "$OVL_DIR/usr/sbin/"
            [ -d "$PKGROOT/etc/wpa_supplicant" ] && cp -a "$PKGROOT/etc/wpa_supplicant" "$OVL_DIR/etc/"
            # larger console fonts for high-resolution monitors (bigger letters)
            if [ -d "$PKGROOT/usr/share/consolefonts" ]; then
                mkdir -p "$OVL_DIR/usr/share/consolefonts"
                for f in Lat2-Terminus16 sun12x22 solar24x32; do
                    [ -f "$PKGROOT/usr/share/consolefonts/$f.psfu.gz" ] \
                        && cp "$PKGROOT/usr/share/consolefonts/$f.psfu.gz" "$OVL_DIR/usr/share/consolefonts/"
                done
            fi
            find "$OVL_DIR/usr/bin" -type l -delete 2>/dev/null
            find "$OVL_DIR/usr/sbin" -type l -delete 2>/dev/null
            echo "  bundled curl, jq, wpa_supplicant, iw"
        else
            echo "  WARNING: bundle root missing tools; falling back to apk add at boot"
        fi
    fi
    rm -rf "$PKGROOT" /tmp/osfinder_apkstatic_extract.$$
fi
if [ ! -x "$OVL_DIR/usr/bin/curl" ]; then
    # Fallback: install via apk at boot (needs ethernet on first boot)
    printf 'curl\njq\nwpa_supplicant\niw\n' > "$OVL_DIR/etc/apk/world"
fi

# Bring up any network interface via DHCP (wired first), then reconnect to a
# saved WiFi network (config stored on the pen by the TUI's 'wifi' command)
cat > "$OVL_DIR/etc/local.d/osfinder.start" <<'EOF'
#!/bin/sh
for iface in /sys/class/net/*; do
    name=${iface##*/}
    [ "$name" = "lo" ] && continue
    ip link set "$name" up 2>/dev/null
    udhcpc -i "$name" -b -q >/dev/null 2>&1 || true
done

if ! ip route show 2>/dev/null | grep -q '^default'; then
    PEN=""
    for d in /media/*; do
        [ -d "$d" ] && [ -f "$d/.boot_repository" ] && PEN="$d"
    done
    if [ -n "$PEN" ] && [ -f "$PEN/etc/wpa_supplicant.conf" ]; then
        mkdir -p /etc/wpa_supplicant
        cp "$PEN/etc/wpa_supplicant.conf" /etc/wpa_supplicant/wpa_supplicant.conf
        for d in /sys/class/net/*; do
            n=${d##*/}
            [ "$n" = "lo" ] && continue
            iw dev "$n" info >/dev/null 2>&1 || continue
            ip link set "$n" up 2>/dev/null
            wpa_supplicant -B -i "$n" -c /etc/wpa_supplicant/wpa_supplicant.conf >/dev/null 2>&1
            sleep 6
            udhcpc -i "$n" -b -q >/dev/null 2>&1
            break
        done
    fi
fi
EOF
chmod +x "$OVL_DIR/etc/local.d/osfinder.start"

# inittab: run the TUI on the main console (tty1), respawn on exit
cat > "$OVL_DIR/etc/inittab" <<'INITTAB'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default

tty1::respawn:/usr/local/bin/osfinder.sh

::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/rc shutdown
INITTAB

# Standard OpenRC runlevels (defaults are skipped when an apkovl is present)
for s in devfs dmesg mdev hwdrivers modloop; do
    ln -s /etc/init.d/$s "$OVL_DIR/etc/runlevels/sysinit/$s"
done
for s in modules sysctl hostname bootmisc syslog; do
    ln -s /etc/init.d/$s "$OVL_DIR/etc/runlevels/boot/$s"
done
ln -s /etc/init.d/local "$OVL_DIR/etc/runlevels/default/local"
for s in mount-ro killprocs savecache; do
    ln -s /etc/init.d/$s "$OVL_DIR/etc/runlevels/shutdown/$s"
done

# Copy the OSFinder TUI into the overlay
cp "$PROJECT_DIR/src/osfinder.sh" "$OVL_DIR/usr/local/bin/osfinder.sh"
chmod +x "$OVL_DIR/usr/local/bin/osfinder.sh"

# Bake the Supabase credentials into the overlay (from config/.env, not git)
if [ -r "$PROJECT_DIR/config/.env" ]; then
    cp "$PROJECT_DIR/config/.env" "$OVL_DIR/etc/osfinder.env"
else
    echo "  WARNING: config/.env not found; TUI will not have Supabase credentials"
fi

# Pack the overlay
tar -C "$OVL_DIR" -czf "$OUT" . || { rm -rf "$OVL_DIR"; exit 1; }
rm -rf "$OVL_DIR"
echo "apkovl built: $OUT"