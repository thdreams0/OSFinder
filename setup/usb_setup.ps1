# OSFinder USB Setup - native Windows (UEFI-only fallback)
# creates a UEFI-bootable pen without WSL. for full BIOS+UEFI use installer.ps1 with WSL or Linux.
param(
    [Parameter(Mandatory=$true)][int]$DiskNumber,
    [string]$ProjectDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

function Test-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) { Write-Host "run as Administrator" -ForegroundColor Red; exit 1 }

$disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
Write-Host "Preparing Disk $DiskNumber ($($disk.FriendlyName))..." -ForegroundColor Cyan

# clear readonly, offline etc, via diskpart
$dpScript = @"
select disk $DiskNumber
clean
convert gpt
create partition efi size=300
format quick fs=fat32 label="OSFinder"
assign
exit
"@
$dpFile = "$env:TEMP\osfinder_diskpart.txt"
$dpScript | Set-Content -Path $dpFile -Encoding ASCII
Write-Host "running diskpart clean + format..." -ForegroundColor DarkGray
diskpart /s $dpFile | Out-Null
Remove-Item $dpFile -Force -ErrorAction SilentlyContinue
Start-Sleep 2

# get drive letter assigned
$vol = Get-Partition -DiskNumber $DiskNumber | Where-Object { $_.Type -eq "System" } | Get-Volume -ErrorAction SilentlyContinue
if (-not $vol) { $vol = Get-Volume | Where-Object { $_.FileSystem -eq "FAT32" -and $_.DriveLetter } | Select-Object -Last 1 }
$drive = $vol.DriveLetter
if (-not $drive) {
    # try to assign manually
    $part = Get-Partition -DiskNumber $DiskNumber | Select-Object -Last 1
    $drive = "E"
    try { $part | Set-Partition -NewDriveLetter $drive -ErrorAction Stop } catch {}
}
if (-not $drive) { Write-Host "could not get drive letter" -ForegroundColor Red; exit 1 }
$drive = "$drive`:"
Write-Host "pen mounted at $drive" -ForegroundColor Green

$ALPINE_BASE = "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/netboot"
$bootDir = "$drive\boot"
$grubDir = "$drive\boot\grub"
$ebootDir = "$drive\EFI\BOOT"

New-Item -ItemType Directory -Force -Path $bootDir | Out-Null
New-Item -ItemType Directory -Force -Path $grubDir | Out-Null
New-Item -ItemType Directory -Force -Path $ebootDir | Out-Null

Write-Host "downloading Alpine netboot (kernel, initramfs, modloop)..." -ForegroundColor Yellow
@(
    @{url="$ALPINE_BASE/vmlinuz-lts"; dst="$bootDir\vmlinuz-lts"},
    @{url="$ALPINE_BASE/initramfs-lts"; dst="$bootDir\initramfs-lts"},
    @{url="$ALPINE_BASE/modloop-lts"; dst="$bootDir\modloop-lts"}
) | ForEach-Object {
    Write-Host "  $($_.url)" -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $_.url -OutFile $_.dst -UseBasicParsing
}

Write-Host "writing .boot_repository..." -ForegroundColor DarkGray
@"
http://dl-cdn.alpinelinux.org/alpine/latest-stable/main
http://dl-cdn.alpinelinux.org/alpine/latest-stable/community
"@ | Set-Content -Path "$drive\.boot_repository" -Encoding ASCII

# download prebuilt apkovl if available, otherwise build minimal one via tar
$apkovl = "$drive\alpine.apkovl.tar.gz"
$prebuilt = "$ProjectDir\setup\apkovl.tar.gz"
if (Test-Path $prebuilt) {
    Write-Host "using prebuilt apkovl..." -ForegroundColor DarkGray
    Copy-Item $prebuilt $apkovl -Force
} else {
    Write-Host "building apkovl (minimal)..." -ForegroundColor Yellow
    $tmp = "$env:TEMP\osfinder_apkovl"
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path "$tmp\usr\local\bin" | Out-Null
    New-Item -ItemType Directory -Force -Path "$tmp\etc\local.d" | Out-Null
    New-Item -ItemType Directory -Force -Path "$tmp\etc\runlevels\sysinit","$tmp\etc\runlevels\boot","$tmp\etc\runlevels\default","$tmp\etc\runlevels\shutdown","$tmp\etc\apk" | Out-Null

    Copy-Item "$ProjectDir\src\osfinder.sh" "$tmp\usr\local\bin\osfinder.sh" -Force
    Copy-Item "$ProjectDir\setup\gen_grub_cfg.sh" "$tmp\usr\local\bin\gen_grub_cfg.sh" -Force -ErrorAction SilentlyContinue

    "curl`njq`nwpa_supplicant`niw" | Set-Content "$tmp\etc\apk\world" -Encoding ASCII

    @'
#!/bin/sh
for iface in /sys/class/net/*; do
    name=${iface##*/}
    [ "$name" = "lo" ] && continue
    ip link set "$name" up 2>/dev/null
    udhcpc -i "$name" -b -q >/dev/null 2>&1 || true
done
'@ | Set-Content "$tmp\etc\local.d\osfinder.start" -Encoding ASCII

    @'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
tty1::respawn:/usr/local/bin/osfinder.sh
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/rc shutdown
'@ | Set-Content "$tmp\etc\inittab" -Encoding ASCII

    # use Windows tar (bsdtar)
    Push-Location $tmp
    tar -czf $apkovl * 2>$null
    Pop-Location
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  apkovl built: $apkovl" -ForegroundColor Green
}

# grub.cfg
Write-Host "writing grub.cfg..." -ForegroundColor DarkGray
$grubCfg = @"
set timeout=10
set default=0
set alpine_repo="http://dl-cdn.alpinelinux.org/alpine/latest-stable/main,http://dl-cdn.alpinelinux.org/alpine/latest-stable/community"
menuentry 'OSFinder TUI' {
    search --no-floppy --set=root --file /boot/vmlinuz-lts
    linux /boot/vmlinuz-lts ip=dhcp alpine_repo="`$alpine_repo" quiet
    initrd /boot/initramfs-lts
}
menuentry 'OSFinder TUI (verbose)' {
    search --no-floppy --set=root --file /boot/vmlinuz-lts
    linux /boot/vmlinuz-lts ip=dhcp alpine_repo="`$alpine_repo"
    initrd /boot/initramfs-lts
}
"@
$grubCfg | Set-Content -Path "$grubDir\grub.cfg" -Encoding ASCII

# UEFI grub efi - try to download prebuilt, otherwise warn
Write-Host "installing UEFI bootloader..." -ForegroundColor Yellow
$efiDst = "$ebootDir\BOOTX64.EFI"
# try to fetch grubx64.efi from Alpine's grub-efi package (extract) - fallback to chainload via bootx64
try {
    $grubApk = "$env:TEMP\grub-efi.apk"
    $repo = Invoke-WebRequest -Uri "https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/x86_64/" -UseBasicParsing
    $apkName = ([regex]::Matches($repo.Content, "grub-efi-[^`"]+\.apk") | ForEach-Object Value | Sort-Object | Select-Object -Last 1)
    if ($apkName) {
        Write-Host "  downloading $apkName ..." -ForegroundColor DarkGray
        Invoke-WebRequest -Uri "https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/x86_64/$apkName" -OutFile $grubApk -UseBasicParsing
        # apk is tar.gz, extract efi
        $extract = "$env:TEMP\grub_efi_extract"
        Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $extract | Out-Null
        tar -xzf $grubApk -C $extract 2>$null
        $efiSrc = Get-ChildItem -Path $extract -Recurse -Filter "grubx64.efi" | Select-Object -First 1
        if ($efiSrc) { Copy-Item $efiSrc.FullName $efiDst -Force; Write-Host "  UEFI bootloader installed" -ForegroundColor Green }
        else { throw "efi not found in apk" }
        Remove-Item $grubApk, $extract -Recurse -Force -ErrorAction SilentlyContinue
    } else { throw "grub apk not found" }
} catch {
    Write-Host "  WARNING: could not fetch GRUB EFI automatically." -ForegroundColor Yellow
    Write-Host "  pen will still work if you copy BOOTX64.EFI manually, or use WSL installer." -ForegroundColor Yellow
    Write-Host "  error: $_" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  OSFinder USB (UEFI) ready at $drive  " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "notes: this native mode is UEFI-only. for BIOS+UEFI run installer.ps1 with WSL," -ForegroundColor DarkGray
Write-Host "       or on Linux: sudo bash installer.sh" -ForegroundColor DarkGray
Write-Host "       SATA fix needs Linux: sudo bash setup/fix_pen.sh /dev/sdX" -ForegroundColor DarkGray
