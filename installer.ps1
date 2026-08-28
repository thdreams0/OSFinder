# OSFinder Windows Installer
# creates the bootable USB from Windows using WSL (full BIOS+UEFI) or native PowerShell (UEFI-only fallback)
# run as Administrator: powershell -ExecutionPolicy Bypass -File installer.ps1

$ErrorActionPreference = "Stop"

function Test-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host "ERROR: run as Administrator." -ForegroundColor Red
    Write-Host "right-click PowerShell -> Run as Administrator, then:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File installer.ps1"
    exit 1
}

$ProjectDir = $PSScriptRoot
if (-not $ProjectDir) { $ProjectDir = Get-Location }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OSFinder Installer (Windows)           " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# list disks
Write-Host "Available disks:" -ForegroundColor Yellow
Write-Host "----------------------------------------"
try {
    Get-Disk | Select-Object Number, FriendlyName, Size, BusType, PartitionStyle | Format-Table -AutoSize | Out-Host
} catch {
    Write-Host "  (could not list via Get-Disk, try diskpart -> list disk)" -ForegroundColor DarkGray
}

$diskNum = Read-Host "Enter disk Number for your USB pen (e.g. 1) or 'q' to quit"
if ($diskNum -eq "q" -or $diskNum -eq "Q") { Write-Host "cancelled."; exit 1 }
if (-not ($diskNum -match "^\d+$")) { Write-Host "invalid number." -ForegroundColor Red; exit 1 }

$disk = Get-Disk -Number $diskNum -ErrorAction SilentlyContinue
if (-not $disk) { Write-Host "disk $diskNum not found." -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "Selected: Disk $diskNum - $($disk.FriendlyName) - $([math]::Round($disk.Size/1GB,2)) GB" -ForegroundColor Yellow
Write-Host "This will ERASE ALL DATA on this disk." -ForegroundColor Red
$confirm = Read-Host "Proceed? (y/n)"
if ($confirm -ne "y" -and $confirm -ne "Y") { Write-Host "cancelled."; exit 1 }

# check WSL
$hasWSL = $null -ne (Get-Command wsl -ErrorAction SilentlyContinue)
$wslReady = $false
if ($hasWSL) {
    try { wsl --status | Out-Null; $wslReady = $true } catch { $wslReady = $false }
}

if ($hasWSL -and $wslReady) {
    Write-Host ""
    Write-Host "--- WSL detected -> full install (BIOS+UEFI) ---" -ForegroundColor Green
    Write-Host "mounting PhysicalDrive$diskNum into WSL..." -ForegroundColor DarkGray

    # unmount if already mounted
    wsl --unmount "\\.\PhysicalDrive$diskNum" 2>$null | Out-Null

    $mountOut = wsl --mount "\\.\PhysicalDrive$diskNum" --bare 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "wsl --mount failed: $mountOut" -ForegroundColor Red
        Write-Host "falling back to native UEFI-only mode..." -ForegroundColor Yellow
        $hasWSL = $false
    } else {
        Start-Sleep 2
        # find device inside WSL (usually /dev/sdX, last added)
        $wslDev = wsl bash -c "lsblk -d -o NAME,TYPE | awk '`$2==`"disk`"`{print `"/dev/`"`$1}' | tail -1" 2>$null
        $wslDev = $wslDev.Trim()
        if (-not $wslDev) { $wslDev = "/dev/sdb" } # fallback
        Write-Host "WSL device: $wslDev" -ForegroundColor DarkGray

        # translate Windows project path to WSL path: C:\foo -> /mnt/c/foo
        $winPath = $ProjectDir.ToString().Replace("\","/")
        if ($winPath -match "^([A-Za-z]):/(.*)") {
            $drive = $matches[1].ToLower()
            $rest = $matches[2]
            $wslProject = "/mnt/$drive/$rest"
        } else {
            $wslProject = $winPath
        }

        Write-Host "running Linux installer inside WSL: $wslProject/setup/usb_setup.sh $wslDev" -ForegroundColor DarkGray
        wsl bash -c "sudo bash '$wslProject/setup/usb_setup.sh' '$wslDev'"
        $rc = $LASTEXITCODE

        Write-Host "unmounting..." -ForegroundColor DarkGray
        wsl --unmount "\\.\PhysicalDrive$diskNum" 2>$null | Out-Null

        if ($rc -eq 0) {
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Green
            Write-Host "  OSFinder USB created successfully!   " -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Green
            exit 0
        } else {
            Write-Host "WSL installer failed (code $rc)." -ForegroundColor Red
            exit 1
        }
    }
}

# --- native fallback: UEFI-only, no WSL ---
Write-Host ""
Write-Host "--- native Windows mode (UEFI-only) ---" -ForegroundColor Yellow
Write-Host "BIOS boot will NOT work from this mode. For BIOS+UEFI use WSL or a Linux PC." -ForegroundColor DarkGray
Write-Host "requires: PowerShell 5+, internet" -ForegroundColor DarkGray

$confirm2 = Read-Host "Continue with UEFI-only pen? (y/n)"
if ($confirm2 -ne "y" -and $confirm2 -ne "Y") { exit 1 }

# delegate to native script
$native = Join-Path $ProjectDir "setup\usb_setup.ps1"
if (Test-Path $native) {
    & $native -DiskNumber $diskNum -ProjectDir $ProjectDir
} else {
    Write-Host "native script not found: $native" -ForegroundColor Red
    Write-Host "fallback: use WSL or run on Linux: sudo bash installer.sh" -ForegroundColor Yellow
    exit 1
}
