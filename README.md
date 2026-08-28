# osfinder

search for an .iso in our list and download it, without an OS on your computer.



**how it works:** you boot a tiny Alpine Linux from a USB stick. no OS needed on the target machine at all - it loads into RAM and gives you a text menu. you search by name, pick one, and it downloads the ISO straight to RAM. then you either mount it and run the installer right there, or copy it to the pen so it boots directly next time (ventoy-style).

**status:** list is public (`oslist.json` on github, fetched via jsdelivr with raw fallback). downloads go to `/tmp` in RAM - nothing touches the target disk unless you tell it to. may break if Alpine netboot changes.

**important:** creating the pen **erases everything on it**. ISOs are downloaded to RAM, so you need enough RAM - 8GB is comfortable, 16GB recommended for big ISOs. FAT32 pen can't hold files over 4GB, use mount option for those.

## setup

no dependencies on the target machine - the pen itself is the system. to *create* the pen you need either Linux or Windows.

### linux

1. create the pen:
   ```
   sudo bash installer.sh
   ```
   it lists your disks, checks the project files, asks for confirmation, and builds the bootable pen. guided, hard to mess up.

   if you already know the device:
   ```
   sudo bash setup/usb_setup.sh /dev/sdX
   ```
   replace `/dev/sdX` with your pen (e.g. `/dev/sdb`).

2. already have a pen and want to update/fix it:
   ```
   sudo bash setup/fix_pen.sh /dev/sdX
   ```
   also fixes the SATA driver issue if your disk isn't detected.

### windows

I still didn't tested on windows but you can (if you have an windows pc).
if you

1. run as Administrator:
   ```
   powershell -ExecutionPolicy Bypass -File installer.ps1
   ```
   it lists your disks, you pick the USB pen number, asks for confirmation.

   - if **WSL** is installed (WSL2), it uses it automatically via `wsl --mount` and runs the same Linux installer inside WSL - you get full **BIOS+UEFI** support, same as Linux. this is the recommended path.
   - if no WSL, it falls back to native PowerShell mode (`setup/usb_setup.ps1`) - **UEFI-only**. works on most modern PCs, but won't boot on old BIOS-only machines.

   you can also run the native script directly:
   ```
   powershell -ExecutionPolicy Bypass -File setup/usb_setup.ps1 -DiskNumber 1
   ```
   replace `1` with your USB disk number (see `Get-Disk`).

2. no WSL and need BIOS? install WSL first (`wsl --install` then reboot) and re-run `installer.ps1`, or create the pen from a Linux PC/VM/live USB.

### boot the target machine
   - plug the pen, restart, spam **F8 / F12 / Del / F2** for boot menu
   - select the USB pen, then pick OSFinder in GRUB
   - Alpine loads into RAM and the menu shows up automatically

that's it. no install, no existing OS.

## menu

- `1` search and download an OS - type part of a name, pick a number, watch it download
- `2` set up WiFi - scans, you pick a network, type password (saved to pen for next boot)
- `3` remove an ISO from the USB pen - lists ISOs on the pen, pick one to delete (GRUB entry removed automatically)
- `4` shell - drops you to sh in the live session (`exit` to return)
- `5` power off

after a download you get:
- `1` mount the ISO and open the installer - mounts at `/mnt/iso`, opens a shell, look for `install*`, `calamares`, `ubiquity`, etc.
- `2` copy the ISO to the USB pen - saves to pen, shows as `ISO: ...` in GRUB on next boot
- `3` search another OS

## requirements

**to create the pen:**
- a Linux PC with `sudo` **or** a Windows 10/11 PC with Administrator (WSL recommended for full BIOS+UEFI, native PowerShell is UEFI-only)
- a USB pen with at least 2GB

**to boot and use it:**
- any PC that boots from USB (BIOS or UEFI - Windows native pen is UEFI-only)
- internet (ethernet works automatically, or WiFi via option 2)
- enough RAM for the ISO

## troubleshooting

**"Could not mount the ISO"** - live session loop devices are flaky. use `2. Copy ISO to the pen` and boot from it instead.

**no results on search** - check your spelling, and check the `Internet: Connected / OFF` at the top.

**download fails** - check connection and try again, mirrors are slow sometimes.

**SATA disk not detected at boot** - run `sudo bash setup/fix_pen.sh /dev/sdX` from your Linux PC or WSL (injects `sd_mod`/`scsi_mod`). native Windows pen can't fix this - re-run `installer.ps1` with WSL.

**no WiFi networks listed** - wireless card is probably disabled in BIOS/UEFI. enable it and reboot.


full step-by-step with all edge cases in [USAGE.md](USAGE.md).

## disclaimer

this just fetches public ISOs and mounts/copies them. it doesn't bypass anything, doesn't touch the target disk unless you run the installer or copy to pen. provided as-is with no warranty.

## license

released under the MIT license. see [LICENSE](LICENSE).
