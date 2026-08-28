# osfinder

search for an .iso in our list and download it, without an OS on your computer.

## join https://discord.gg/QEC6QttWMh for support

**how it works:** you boot a tiny Alpine Linux from a USB stick. no OS needed on the target machine at all - it loads into RAM and gives you a text menu. you search by name (`ubuntu`, `cachyos`, `arch`), pick one, and it downloads the ISO straight to RAM with a progress bar. then you either mount it and run the installer right there, or copy it to the pen so it boots directly next time (ventoy-style).

**status:** working on both BIOS (legacy) and UEFI. list is public (`oslist.json` on github, fetched via jsdelivr with raw fallback). downloads go to `/tmp` in RAM - nothing touches the target disk unless you tell it to.

**important:** creating the pen **erases everything on it**. and ISOs are downloaded to RAM, so you need enough RAM - 8GB is comfortable, 16GB recommended for big ISOs. FAT32 pen can't hold files over 4GB, use mount option for those.

## setup

no dependencies on the target machine - just a Linux PC to create the pen (needs `sudo`).

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

2. already have a pen and want to update it:
   ```
   sudo bash setup/fix_pen.sh /dev/sdX
   ```
   also fixes the SATA driver issue if your disk isn't detected.

3. boot the target machine:
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
- a Linux computer with `sudo`
- a USB pen with at least 2GB

**to boot and use it:**
- any PC that boots from USB (BIOS or UEFI)
- internet (ethernet works automatically, or WiFi via option 2)
- enough RAM for the ISO

## troubleshooting

**"Could not mount the ISO"** - live session loop devices are flaky. use `2. Copy ISO to the pen` and boot from it instead.

**no results on search** - check your spelling (search is partial, `ubu` finds `ubuntu`), and check the `Internet: Connected / OFF` at the top.

**download fails** - check connection and try again, mirrors are slow sometimes.

**SATA disk not detected at boot** - run `sudo bash setup/fix_pen.sh /dev/sdX` from your Linux PC (injects `sd_mod`/`scsi_mod`).

**no WiFi networks listed** - wireless card is probably disabled in BIOS/UEFI. enable it and reboot.

**text too small/big** - it auto-picks a console font based on your screen resolution. nothing to configure.

full step-by-step with all edge cases in [USAGE.md](USAGE.md).

## disclaimer

this just fetches public ISOs and mounts/copies them. it doesn't bypass anything, doesn't touch the target disk unless you run the installer or copy to pen. provided as-is with no warranty.

## license

released under the MIT license. see [LICENSE](LICENSE).
