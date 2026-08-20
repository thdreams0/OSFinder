# OSFinder - User Guide

## What it is

OSFinder is a bootable tool that lets you search for, download and run operating
system installers from any computer — even one with no OS installed. It runs from a
USB pen: Alpine Linux loads into RAM and a text menu appears automatically.

You don't need an existing operating system, a hard drive, or a graphics environment.
Just the pen and an internet connection.

## Part 1 - Creating the USB pen

You need: a Linux computer and a USB pen (2 GB or more).

### Create it from scratch

```bash
sudo bash installer.sh
```

The installer lists the available disks, checks the project files, asks for
confirmation and creates the bootable pen for you.

If you already know the device name, you can use the setup script directly:

```bash
sudo bash setup/usb_setup.sh /dev/sdX
```

Replace `/dev/sdX` with your pen (e.g. `/dev/sdb`). **Warning**: everything on that
device is erased.

### Update an existing pen

Newer versions of OSFinder? Rebuild the pen without recreating it:

```bash
sudo bash setup/fix_pen.sh /dev/sdX
```

## Part 2 - Booting

1. Plug the pen into the computer.
2. Restart and open the boot menu (usually **F8**, **F12**, **Del** or **F2**).
3. Select the USB pen.
4. In the GRUB menu, pick the OSFinder entry.

Alpine Linux boots into RAM and the OSFinder menu appears on screen.

## Part 3 - Using the menu

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

The **Internet** status at the top shows whether you're connected
(green = connected, red = off).

### Getting online (automatic)

If there's no internet, OSFinder tries ethernet (DHCP) first. If that fails, it opens
the **WiFi wizard** so you can connect. If you skip it, you can always use option
**2. Set up WiFi**.

### Connecting to WiFi

1. OSFinder scans for available networks.
2. Pick a network by its **number** (or type the name).
3. Type the password (it stays hidden).
4. Wrong password? Try again.
5. The network is **saved on the pen** and reconnects automatically on later boots
   when there's no ethernet.

### Searching and downloading an OS

Choose option **1**. Then:

```
What do you want to install?
Type part of the name (e.g. ubuntu, debian, cachyos)
Press Enter with nothing typed to go back.

Search> ubuntu
```

- Search is by **name** and matches partial words: `ubu` finds Ubuntu, `cachy` finds CachyOS.
- **Enter with an empty field** goes back to the menu.
- Results appear as a numbered list:

```
Available results:
---------------------
  1. Ubuntu-22.04
---------------------
Type the number to download
Select> 1
```

- Type the number and press Enter. The ISO downloads with a **progress bar** and is
  stored in RAM (`/tmp`).

### After the download

```
Download complete: /tmp/ubuntu-22.04.iso

What next?
  1. Mount the ISO and open the installer
  2. Copy the ISO to the USB pen
  3. Search another OS
```

- **1 — Mount the ISO and open the installer**: mounts the ISO and opens a shell.
  Look for the installer inside (for example `./install*`, `casper`, `ubiquity` or
  `calamares`) and run it. Type `exit` to return to OSFinder.
- **2 — Copy the ISO to the pen**: saves the ISO onto the pen so you can boot it on
  another machine.
- **3 — Search another OS**: start a new search.

### Shell (advanced users)

Option **3** opens a shell in the live Alpine environment. Useful for checking the
network, disks, etc. Type `exit` to return to the menu.

### Power off

Option **4** shuts down the computer.

## Requirements

### To create the pen
- A Linux computer with `sudo`
- A USB pen with at least 2 GB

### To boot and use it
- A computer that boots from USB (BIOS legacy or UEFI)
- An internet connection (WiFi or ethernet)
- Enough RAM: ISOs are stored in RAM while downloading. For large ISOs, 8 GB is
  comfortable and 16 GB is recommended.

## Troubleshooting

### "Could not mount the ISO"
OSFinder tries to load the loop device automatically. If it still fails, use option
**2. Copy the ISO to the USB pen** and boot from the pen instead.

### No results on search
- Check the name you typed matches a listed OS (search is partial, so short words work).
- Check the internet status at the top of the menu.

### Download fails
- Check your internet connection (WiFi or ethernet).
- Try again — sometimes mirrors are slow.

### SATA / disk not detected at boot
Run `sudo bash setup/fix_pen.sh /dev/sdX` on your Linux PC — this injects the SATA
drivers (`sd_mod`/`scsi_mod`) into the boot files.

### No WiFi networks listed
Some computers keep the wireless card disabled. Enable it in the firmware
(BIOS/UEFI) and reboot.

### Text too small or too big
OSFinder picks a larger console font automatically based on the monitor resolution.
Nothing to configure.

## Good to know

- The downloaded ISO goes to **RAM**, not to the pen — nothing is saved on the target
  computer unless you choose "Copy the ISO to the pen".
- WiFi works without ethernet.
- Works on BIOS (legacy) and UEFI.

---

**OSFinder** - Download and install an OS on any bare-metal computer.