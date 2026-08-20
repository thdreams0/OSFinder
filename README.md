# OSFinder

**Search for an .iso in our list and download it, without an OS on your computer.**

A lightweight tool that turns any USB stick into a bootable "ISO finder": boot it on
any computer — even one with no OS installed — and search, download and run
operating system installers, using just a text menu.

No installation on the target computer. No need for an existing OS. Just the USB pen
and an internet connection.

## What you get

Boot the pen and you land in a simple menu:

```
  1. Search and download an OS
  2. Set up WiFi
  3. Shell (for advanced users)
  4. Power off
```

- **Search** by typing part of an OS name (e.g. `ubuntu`, `cachyos`).
- **Download** ISOs straight to the computer's RAM with a live progress bar.
- **Mount** a downloaded ISO and open its installer immediately.
- **WiFi** setup built in — works even without ethernet.
- Works on both **BIOS (legacy)** and **UEFI** computers.

## Quick start

### 1. Create the USB pen (on any Linux PC)

```bash
sudo bash installer.sh
```

The installer lists the available disks, checks the project, asks for confirmation
and creates the bootable pen for you.

If you already know the device name, you can use the setup script directly:

```bash
sudo bash setup/usb_setup.sh /dev/sdX
```

Replace `/dev/sdX` with your pen (e.g. `/dev/sdb`).
**Warning**: all data on that device is erased.

Already have a pen? Update it with new versions of OSFinder:

```bash
sudo bash setup/fix_pen.sh /dev/sdX
```

### 2. Boot the target computer

1. Plug the pen in and restart.
2. Open the boot menu (usually **F8**, **F12**, **Del** or **F2**).
3. Select the USB pen.
4. Pick the OSFinder entry in the GRUB menu.

Alpine Linux loads into RAM and the menu appears automatically. That's it.

### 3. Use it

- No internet? OSFinder tries ethernet, then guides you through **WiFi** setup.
- Pick **1. Search and download an OS**, type part of a name, press Enter.
- Pick a result by number. The ISO downloads with a progress bar.
- After the download, choose what to do next:
  1. **Mount the ISO and open the installer** — run the OS installer right away;
  2. **Copy the ISO to the pen** — save it for later or for another machine; on the
     next boot the GRUB menu boots it directly (Ventoy-style);
  3. **Search another OS**.

## Requirements

### To create the pen
- A Linux computer with `sudo`
- A USB pen with at least 2 GB

### To boot and use it (target computer)
- A computer with BIOS or UEFI that boots from USB
- Internet connection (WiFi or ethernet)
- Enough RAM — ISOs are stored in RAM while downloading (8 GB is comfortable,
  16 GB recommended for large ISOs)

## Troubleshooting

| Problem | Fix |
|---|---|
| "Could not mount the ISO" | Use option **2. Copy ISO to the pen** and boot from the pen instead. |
| No results on search | Check the name matches a listed OS; check the internet status at the top. |
| Download fails | Check your connection and try again. |
| SATA disk not detected at boot | Run `sudo bash setup/fix_pen.sh /dev/sdX` (injects the SATA drivers). |
| No WiFi networks listed | Enable the wireless card in the computer's firmware (BIOS/UEFI). |
| Text too small or too big | OSFinder picks a larger console font automatically based on your screen resolution. |

See [**USAGE.md**](https://github.com/thdreams0/OSFinder/blob/733da91b2c60f41dca40a14c5eb3f85ed13c2f1c/USAGE.md) for the full step-by-step guide.

---

Search for an .iso in our list and download it, without an OS on your computer.
