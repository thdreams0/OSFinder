# OSFinder

A lightweight TUI (Text User Interface) tool that boots from a USB stick and lets you
search, download and mount operating system ISOs on any computer — including machines
with no OS installed (bare metal). The OS library is a public JSON file (`oslist.json`)
hosted in this GitHub repository — no database, no credentials.

## How it works

1. **Boot**: plug the USB stick into a computer and boot from it.
2. **Alpine in RAM**: a minimal Alpine Linux boots into RAM (diskless) and starts the TUI automatically.
3. **Network**: if there's no internet, the TUI sets itself up — it tries ethernet (DHCP) and, if that fails, opens the WiFi wizard so you can connect.
4. **Search**: type part of the OS name (e.g. `ubuntu`, `cachyos`) and the TUI fetches `oslist.json` from GitHub and filters it locally (partial, case-insensitive).
5. **Download**: pick a result; the ISO is downloaded to `/tmp` (RAM) with a progress bar.
6. **Post-download**: mount the ISO and open the installer, copy it to the pen, or search another OS.

No internet needed on first boot: `curl`, `jq`, `wpa_supplicant`, `iw` and the console
fonts are bundled in the overlay — it works on WiFi-only machines, without ethernet.

## Structure

```
OSFinder/
├── src/osfinder.sh           # The TUI (menu, search, download, WiFi)
├── installer.sh              # Verification/install script (requires sudo)
├── oslist.json               # Public OS list (name + URL) - the "database"
├── setup/
│   ├── usb_setup.sh          # Creates the bootable pen from scratch (wipes everything!)
│   ├── fix_pen.sh            # Updates an existing pen (rebuilds the overlay)
│   └── build_apkovl.sh       # Builds just the Alpine overlay (apkovl)
└── .website/index.html       # Optional web page
```

## Create the USB pen

```bash
# From scratch (wipes all data on the pen!)
sudo bash setup/usb_setup.sh /dev/sdX

# Update an existing pen (after changing osfinder.sh/config)
sudo bash setup/fix_pen.sh /dev/sdX
```

Replace `/dev/sdX` with your pen (e.g. `/dev/sdb`). **Warning**: all data on the
specified device is erased.

Verify the project (components, syntax, OS list):

```bash
sudo bash installer.sh
```

## Using the TUI

Main menu:

```
  1. Search and download an OS
  2. Set up WiFi
  3. Shell (for advanced users)
  4. Power off
```

- **No internet at boot**: the TUI tries ethernet, then opens the WiFi wizard by itself.
- **Search**: type part of the name and press Enter. Enter with an empty field goes back.
  Pick a result by number.
- **Download**: progress bar; the ISO is stored at `/tmp/<name>.iso` (RAM).
- **Post-download**:
  1. *Mount the ISO* — mounts at `/mnt/iso` and opens a shell to run the installer;
  2. *Copy ISO to the pen* — saves the ISO to the pen (marked with `.boot_repository`);
  3. *Search another OS* — new search.
- **WiFi**: the wizard scans, lists networks by number, asks for the password
  (hidden) and saves the config on the pen (`etc/wpa_supplicant.conf`) for automatic
  reconnection on the next boot.

## The OS list

The library is just a public JSON file in this repository — anyone can view it:

```json
[
  { "name": "Ubuntu-22.04", "url": "https://.../ubuntu.iso" }
]
```

The TUI fetches it from jsDelivr CDN (fallback: GitHub raw), no credentials needed.
To point it at your own fork, edit the URLs in `src/osfinder.sh`.

## Adding an OS to the library

Edit `oslist.json` and open a pull request (or just commit on `main`):

```json
{ "name": "Debian-12", "url": "https://.../debian.iso" }
```

The TUI searches by name (partial match) and uses `url` for the download — no codes
or mapping.

## Requirements

### To create the pen
- Linux with `sudo` (setup uses `parted`/`sgdisk`-compatible, `grub-install`, `unsquashfs`, `curl`)
- USB pen with at least 2 GB (Alpine + overlay footprint is < 400 MB)
- Internet on the build machine (to download Alpine netboot and the tools)

### To boot (target computer)
- BIOS or UEFI firmware with USB boot
- Enough RAM: the ISO is downloaded to `/tmp` (RAM). For a 4 GB ISO you need
  equivalent free RAM (8 GB is comfortable, 16 GB recommended)
- Internet to download ISOs (WiFi or ethernet)

## Troubleshooting

- **"Could not mount the ISO"**: the live session tries to load the `loop` module and
  create `/dev/loop*` automatically; if it fails, use *Copy ISO to the pen* and boot from the pen.
- **No results on search**: check the name matches an entry in `oslist.json`; check the
  internet connection (the `Internet` status at the top).
- **"No internet and no WiFi listed"**: check the firmware has the wireless interface
  enabled; you may need to enable the card in the firmware.
- **Stuck at boot / SATA not detected**: run `sudo bash setup/fix_pen.sh /dev/sdX`
  (injects `sd_mod`/`scsi_mod` into the initramfs).
- **Colors/style**: the TUI only uses green (success) and red (errors); the rest is plain text.
- **Text too small/big**: the TUI picks a larger console font automatically based on the
  monitor resolution (via `setfont`).

## Notes

- The download goes to **RAM** (`/tmp`), never to the pen — nothing persists on the target PC.
- No numeric codes needed: search is by name (partial match).
- No credentials: the OS list is a public file anyone can view and contribute to.