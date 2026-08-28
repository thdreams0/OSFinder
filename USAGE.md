# osfinder - usage

## join https://discord.gg/QEC6QttWMh for support

**what it is:** a bootable USB that lets you search, download and run OS installers from any machine - even one with no OS, no disk, no desktop. you boot Alpine Linux into RAM, get a text menu, and go.

you don't need an existing OS. just the pen and internet.

## part 1 - creating the pen

you need: a USB pen (2GB+) and either a Linux PC or a Windows 10/11 PC.

### from scratch - linux

```
sudo bash installer.sh
```

it lists your disks (`lsblk`), validates `src/osfinder.sh`, `setup/usb_setup.sh`, checks `sh` + `curl` + `tput` (and optionally `jq`/`oslist.json` - pen still boots without them, list is fetched at runtime), asks for confirmation and builds the pen (FAT32, GRUB for BIOS+UEFI, Alpine).

if you know the device already:

```
sudo bash setup/usb_setup.sh /dev/sdX
```

replace `/dev/sdX` (e.g. `/dev/sdb`). **warning:** wipes the whole device.

### from scratch - windows

no Linux? use Windows 10/11 (needs Administrator):

#### with WSL (recommended - BIOS+UEFI, same as Linux)

```
wsl --install
# reboot once
powershell -ExecutionPolicy Bypass -File installer.ps1
```

it lists your disks via `Get-Disk`, you pick the USB number, confirm. guided, hard to mess up. it mounts the USB into WSL via `wsl --mount \\.\PhysicalDriveN --bare` and runs the same `setup/usb_setup.sh` inside WSL - full BIOS+UEFI pen, identical to Linux.

#### without WSL (UEFI-only fallback - no extra install)

works on most modern PCs (UEFI). won't boot on old BIOS-only machines. no WSL needed - just PowerShell 5+.

1. PowerShell **as Administrator**:
   ```
   Get-Disk
   ```
   find your pen, e.g.:
   ```
   Number FriendlyName        Size BusType
   ------ ------------        ---- -------
   0      NVMe Samsung  476GB NVMe
   1      USB SanDisk 3.2Gen1  29GB USB   <- this one
   ```
2. create the pen (replace `1` with your USB number):
   ```
   powershell -ExecutionPolicy Bypass -File setup\usb_setup.ps1 -DiskNumber 1
   ```
   or via installer (auto-falls back to UEFI-only):
   ```
   powershell -ExecutionPolicy Bypass -File installer.ps1
   ```
   what it does: `diskpart clean / convert gpt / create partition efi / format FAT32` (`setup/usb_setup.ps1:22`), downloads `vmlinuz-lts` / `initramfs-lts` / `modloop-lts` via `Invoke-WebRequest`, builds `alpine.apkovl.tar.gz` with `tar`, writes `boot/grub/grub.cfg` and tries to fetch `EFI\BOOT\BOOTX64.EFI`.

### updating an existing pen

linux / wsl:
```
sudo bash setup/fix_pen.sh /dev/sdX
```
rebuilds boot files without starting over. also the fix if your SATA disk wasn't detected (injects `sd_mod` + `scsi_mod` and rebuilds `grub.cfg`).

windows native pen (UEFI-only) can't run `fix_pen.sh` - re-run `installer.ps1` with WSL for a full fix, or recreate on Linux.

## part 2 - booting

1. plug the pen into the target PC
2. restart, spam **F8 / F12 / Del / F2** to open boot menu
3. select the USB pen
4. in GRUB, pick OSFinder

Alpine boots into RAM, menu appears. if the pen doesn't show, try a rear USB port - front 3.0 ports are flaky on some boards.

```
========================================
OSFinder - Download and install an OS
========================================
Internet: Connected / OFF

  1. Search and download an OS
  2. Set up WiFi
  3. Remove an ISO from the USB pen
  4. Shell (for advanced users)
  5. Power off
```

`Internet: Connected` is green, `OFF` is red. that's your source of truth.

## part 3 - using the menu

### getting online

if there's no internet, osfinder tries ethernet first (`udhcpc` on every non-wifi iface). if that fails it opens the WiFi wizard automatically. you can also trigger it manually with `2`.

### WiFi setup

1. it scans (`iw dev <iface> scan`, parses `SSID:`)
2. lists networks numbered:
   ```
     1. MyWifi
     2. neighbor_wifi
   ```
3. type a number or type the name directly, `q` to go back
4. type password (hidden with `stty -echo`)
5. writes `/etc/wpa_supplicant/wpa_supplicant.conf`, starts `wpa_supplicant`, runs `udhcpc`
6. on success it copies the conf to `<pen>/etc/wpa_supplicant.conf` and it auto-reconnects on next boot when there's no ethernet

wrong password? it tells you and lets you retry. no networks? check BIOS - wireless is often disabled there.

### searching and downloading

pick `1`:

```
What do you want to install?
Type part of the name (e.g. ubuntu, debian, cachyos)
Press Enter with nothing typed to go back.

Search> ubuntu
```

- search is partial and case-insensitive (`ubu` -> `Ubuntu-22.04`, `cachy` -> `CachyOS-260809`). it fetches `oslist.json` from `raw.githubusercontent.com` with a `cdn.jsdelivr.net` fallback, filters with `jq`.
- empty input goes back, no crash.
- results:
  ```
  Available results:
  ---------------------
    1. Ubuntu-22.04
  ---------------------
  Type the number to download
  Select> 1
  ```
- type the number, it downloads to `/tmp/<name>.iso` with a real progress bar (background `curl` + `wc -c` polling, `show_progress` 50 chars wide).

### after download

```
Download complete: /tmp/ubuntu-22.04.iso

What next?
  1. Mount the ISO and open the installer
  2. Copy the ISO to the USB pen
  3. Search another OS
```

- `1` mount and open - `modprobe loop`, creates `/dev/loop*` if needed, `mount -o loop,ro /mnt/iso`, drops you to `sh` inside `/mnt/iso`. look for `install*`, `casper`, `ubiquity`, `calamares` and run it. `exit` returns to osfinder.
- `2` copy to pen - finds pen by `/.boot_repository` marker, `mount -o remount,rw`, checks 4GB FAT32 limit, `cp` to pen root, regenerates GRUB (`gen_grub_cfg.sh` + `oslist.json`). next boot the ISO shows as `ISO: <name>` in GRUB - boots ventoy-style.
- `3` search another - loop back.

### removing an ISO from the pen

pick `3` in main menu:

```
Remove an ISO from the pen:
---------------------
  1. archlinux-2026.08.01-x86_64.iso
---------------------
Type a number to remove it, or 'q' to go back.
Select> 1
```

type number, confirm `y`, it `rm`s the file and regenerates `pen/boot/grub/grub.cfg` so the entry disappears. `q` or empty goes back. shows `There are no ISOs on the pen` if empty.

### shell

`4` opens `/bin/sh` in the live Alpine. check `ip route`, `lsblk`, `iw`, etc. `exit` to return.

### power off

`5` does `poweroff -f`. that's it.

## requirements

**to create:**
- Linux + `sudo` **or** Windows 10/11 + Administrator (WSL for BIOS+UEFI, native is UEFI-only)
- 2GB+ pen
- linux: `sh`, `curl`, `tput` + `parted`, `dosfstools`, `grub` are required; `jq` + `oslist.json` are **optional** at install (checked by `installer.sh`, pen boots without them - list is fetched at runtime) / windows: `PowerShell 5+`, `diskpart`, `Invoke-WebRequest`, `tar` + internet

**to use:**
- PC that boots from USB (BIOS or UEFI - windows native pen is UEFI-only)
- internet (ethernet or WiFi)
- RAM: ISOs live in RAM. 8GB comfortable, 16GB for big ones. FAT32 limit: can't copy >4GB to pen, use mount instead.

## troubleshooting

### "Could not mount the ISO"
loop devices not available in this live session. osfinder tries `modprobe loop` and `mknod`, but if it still fails, use `2. Copy ISO to the pen` and boot it. more reliable.

### no results
- typo? try shorter term
- check `Internet: OFF` at top - reconnect WiFi

### download fails
- check connection, retry. `curl --max-time 14400`, but mirrors throttle.
- `Internet went away` triggers auto `ensure_network` retry.

### SATA/disk not detected
run `sudo bash setup/fix_pen.sh /dev/sdX` from Linux or WSL - injects drivers into boot files. if you created the pen via native Windows (no WSL), re-create it via `installer.ps1` with WSL.

### no WiFi networks
enable wireless in BIOS/UEFI. some laptops have a hardware switch too.

### text too small/big
auto-handled. `set_console_font` reads `/sys/class/graphics/fb0/virtual_size` and picks `solar24x32` (1440p+), `sun12x22` (1080p), `Lat2-Terminus16` (720p+). needs `setfont`.

## good to know

- downloads go to RAM (`/tmp`), not to pen. nothing persists on target unless you copy to pen.
- WiFi password is saved to pen and auto-used next boot when ethernet is absent.
- works BIOS + UEFI.
- ISOs on pen are listed by `ls pen/*.iso` and GRUB is regenerated to only show what's actually there.
- list is public, no auth: `https://raw.githubusercontent.com/thdreams0/OSFinder/main/oslist.json`

---

**osfinder** - search for an .iso in our list and download it, without an OS on your computer.
