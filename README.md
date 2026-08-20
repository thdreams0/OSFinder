# OSFinder - Bare Metal ISO Downloader

A lightweight Text User Interface (TUI) tool for searching and downloading
operating system ISOs from Supabase on computers without an OS installed.

## Philosophy

OSFinder is designed to be:
- **Bare-metal compatible**: Boots on any computer without an OS installed
- **Lightweight**: Minimal Alpine Linux boots into RAM (~350MB USB footprint)
- **TUI first**: ASCII-based text interface, no graphics dependencies
- **Download-only**: Downloads ISOs from internet, doesn't persist on USB
- **Supabase-backed**: Uses Supabase database for OS library management

## How It Works

1. **Boot**: Insert USB into bare-metal computer and boot from it
2. **Menu**: GRUB menu presents "OSFinder TUI"
3. **Alpine**: A minimal Alpine Linux boots into RAM (diskless) and auto-starts the TUI
4. **Search**: User types OS name (e.g., "ubuntu", "debian") or code number
5. **Lookup**: Script queries Supabase `list` table for matching OS entries
6. **Download**: `curl -L` downloads selected ISO to `/tmp/`
7. **Progress**: ASCII progress bar shows download status
8. **Result**: ISO available for installation (not saved on USB)

## Supported OS (via Supabase)

Currently configured with integer codes mapping to popular distributions:

| Code | OS | Download Link |
|------|-----|---------------|
| 1 | Ubuntu 22.04 LTS | https://releases.ubuntu.com/22.04/ubuntu-22.04.1-desktop-amd64.iso |
| 2 | Debian 12 AMD64 | https://cd.debian.org/disk1/debian-12.5.0-amd64-netinst.iso |
| 3 | Fedora 38 AMD64 | https://download.fedoraproject.org/pub/fedora/linux/releases/38/Everything/x86_64/iso/Fedora-Server-dvd-38.iso |
| 4 | Kali Linux Rolling | https://cdimage.kali.org/kali-2024.2/kali-linux-2024.2-amd64.iso |

*To add more OS: Insert rows into Supabase `list` table and update OS_MAPPING() in osfinder.sh*

## Requirements

### Hardware
- USB drive (128MB minimum, 2GB recommended)
- BIOS or UEFI firmware (any modern computer)
- Internet connection (required for ISO download)

### Software (target computer, bare-metal)
- BIOS or UEFI firmware
- PXE-capable or USB-bootable firmware
- Internet connection (required to boot Alpine and to download ISOs)
- curl, jq, ncurses terminfo (installed automatically by Alpine at boot)
- Alpine Linux (bundled on the USB, boots into RAM - diskless)

### Development (this project)
- Root/sudo access to create the bootable USB
- GRUB (grub-install with i386-pc and x86_64-efi targets)
- Supabase project with `list` table
- curl, jq available on development machine

## Installation

### Create Bootable USB

```bash
# From the project directory (requires sudo)
sudo ./installer.sh
```

The installer lists available storage devices via `lsblk`, lets you pick
the target USB, verifies the project, and creates the bootable USB with:

- GPT partition table (BIOS boot partition + FAT32 ESP/data partition)
- GRUB bootloader (BIOS and UEFI)
- Alpine Linux netboot kernel/initramfs/modules
- `osfinder.sh` + config bundled as an Alpine `apkovl` overlay

**Warning**: This will erase all data on the specified USB drive!

### First Run

1. Insert USB into target computer and boot from it (F8, F12, Del, or F2)
2. Select 'OSFinder TUI' in the GRUB menu
3. Alpine Linux boots into RAM (diskless) and starts the OSFinder TUI automatically
4. Type OS name (e.g., "ubuntu") or press number keys (1-4) for pre-configured OS
5. Press Enter to search Supabase
6. Select ISO from results list
7. Download begins with progress bar
8. ISO saved to `/tmp/` on completion

## Configuration

Edit `config/.env` to customize:
- `SUPABASE_URL`: Your Supabase project URL
- `SUPABASE_ANON_KEY`: Your Supabase anonymous key
- `MAX_ISO_MB`: Maximum expected ISO size
- `DOWNLOAD_DIR`: Download directory path

## Adding New OS to the Library

1. Add row to Supabase `list` table:
   - `os_name`: integer code (1, 2, 3, etc.)
   - `link_to_download`: integer code (links mapped in osfinder.sh)

2. Update `OS_MAPPING()` function in `src/osfinder.sh`:
   - Add case statement mapping code to download URL

3. Re-create bootable USB or copy updated `osfinder.sh`

## License

MIT License - Free for personal and commercial use.

## Contact

For issues, contributions, or questions, please refer to the project repository.
