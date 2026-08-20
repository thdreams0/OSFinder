# OSFinder - User Guide

## What it is

OSFinder is a TUI (Text User Interface) that boots from a USB pen, loads a minimal
Alpine Linux into RAM and lets you search, download and mount operating system ISOs.
Ideal for computers without an OS installed.

## Creating the USB pen

### From scratch

```bash
# From the project directory (requires sudo)
sudo bash setup/usb_setup.sh /dev/sdX
```

Replace `/dev/sdX` with your pen (e.g. `/dev/sdb`).
**Warning**: all data on the device is erased.

### Updating an existing pen

After changing `src/osfinder.sh` or `oslist.json`, rebuild the overlay without
recreating the pen from scratch:

```bash
sudo bash setup/fix_pen.sh /dev/sdX
```

### Verifying the project

```bash
sudo bash installer.sh
```

Checks the TUI syntax, the presence of the project files, the OS list (`oslist.json`)
and the documentation.

## Booting on the target computer

1. Plug in the pen and boot from it (boot key: **F8**, **F12**, **Del** or **F2**).
2. In the GRUB menu, pick the OSFinder entry.
3. Alpine boots into RAM and the TUI opens automatically on screen.

## The TUI

### Main menu

```
========================================
OSFinder - Download and install an OS
========================================
Internet: Connected / OFF

  1. Search and download an OS
  2. Set up WiFi
  3. Shell (for advanced users)
  4. Power off
```

The internet status is shown at the top (green = connected, red = off).

### Automatic network setup

- **No internet at boot**: the TUI tries ethernet (DHCP) and, if that doesn't work,
  opens the WiFi wizard for you to connect manually. If you decline, you can connect
  later with **2. Set up WiFi**.

### WiFi wizard

1. The TUI scans the available networks.
2. Pick a network by **number** (or type its name).
3. Type the password (it stays hidden).
4. If the password is wrong, you can try again.
5. The config is **saved on the pen** (`etc/wpa_supplicant.conf`) and the TUI
   reconnects automatically on later boots, when there's no ethernet.

### Searching and downloading an OS

Pick option **1** in the menu. Then:

```
What do you want to install?
Type part of the name (e.g. ubuntu, debian, cachyos)
Press Enter with nothing typed to go back.

Search> ubuntu
```

- The search is **partial** (by name): `ubuntu` matches any entry containing "ubuntu".
- **Enter with an empty field** goes back to the menu.
- With results, a numbered list appears:

```
Available results:
---------------------
  1. Ubuntu-22.04
---------------------
Type the number to download
Select> 1
```

- The download shows a **progress bar** and stores the ISO at `/tmp/<name>.iso` (RAM).

### Post-download

```
Download complete: /tmp/ubuntu-22.04.iso

What next?
  1. Mount the ISO and open the installer
  2. Copy the ISO to the USB pen
  3. Search another OS
```

- **1 — Mount the ISO**: mounts the ISO at `/mnt/iso` and opens a shell. Look for
  the installer inside (e.g. `./install*`, `casper`, `ubiquity`, `calamares`) and
  run it. Type `exit` to return to the TUI.
- **2 — Copy ISO to the pen**: writes the ISO to the pen (detected by the
  `.boot_repository` marker) to boot on another machine.
- **3 — Search another OS**: returns to the search.

### Shell (advanced)

Option **3** opens a shell in the Alpine live environment (useful for diagnosing
network, partitions, etc.). Type `exit` to return to the TUI.

### Power off

Option **4** shuts down the computer.

## Adding an OS to the library

ISOs are stored in a public JSON file in this repository, `oslist.json`:

```json
[
  { "name": "Ubuntu-22.04", "url": "https://releases.ubuntu.com/.../ubuntu.iso" },
  { "name": "Debian-12", "url": "https://.../debian.iso" }
]
```

Anybody can view the list. To add an OS, edit `oslist.json` and open a pull request
(or commit on `main`). The TUI fetches the file from the jsDelivr CDN (fallback:
GitHub raw) and filters it locally by name — no codes, no mapping, no credentials.

The list URL used by the TUI is defined in `src/osfinder.sh` (`OS_LIST_URL` and
`OS_LIST_FALLBACK_URL`) — point them at your own fork if you host your own list.

## Configuration

There is nothing to configure for the OS list: it is a public file, no API keys
needed. If you fork the repository, update the two list URLs in `src/osfinder.sh`
before building the pen.

## Troubleshooting

### "Could not mount the ISO"
The TUI tries to load the `loop` module and create the `/dev/loop*` devices. If it
still fails, use **2. Copy the ISO to the USB pen** and boot from the pen.

### No results on search
- Check the name matches an entry in `oslist.json` (partial search).
- Check the connection (the `Internet` status at the top).
- Check the list URLs in `src/osfinder.sh` are reachable (CDN / GitHub raw).

### Download fails
- Check the internet (WiFi/ethernet).
- Check that the entry's `url` points to a valid URL.

### SATA / disk not detected at boot
Run `sudo bash setup/fix_pen.sh /dev/sdX` — the script injects `sd_mod`/`scsi_mod`
into the initramfs for SATA disks.

### Text too small or too big
The TUI detects the monitor resolution and picks a larger console font
(e.g. `sun12x22` on 1080p screens, `solar24x32` on 1440p+).

## Important notes

- The download goes to **RAM** (`/tmp`), never to the pen automatically.
- No internet needed on 1st boot: the required tools are bundled in the overlay.
- WiFi works without ethernet: built-in wizard + automatic reconnection.
- BIOS legacy and UEFI supported (GRUB).
- RAM: large ISOs need free RAM in `/tmp` (tmpfs). For multi-GB ISOs,
  8–16 GB of RAM on the target computer is recommended.
- No credentials: the OS list is a public file anyone can view and contribute to.

---

**OSFinder** - Bare-metal friendly ISO downloads from a public GitHub list.