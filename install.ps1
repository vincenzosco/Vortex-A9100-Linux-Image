<#
.SYNOPSIS
    Vortex86 A9100 Image Installer for Windows
.DESCRIPTION
    Safely writes the built Vortex86 A9100 disk image to a target storage
    device (CF card, USB drive, SD card, hard drive) on Windows.
    Must be run as Administrator.
.PARAMETER Device
    Target physical drive number (e.g., 2 for \\.\PhysicalDrive2)
.PARAMETER Image
    Path to the disk image file (default: searches for vortex86_a9100.img)
.PARAMETER List
    List available physical drives and exit
.PARAMETER Force
    Skip some safety checks
.PARAMETER Verify
    Verify the write by reading back and checksumming
.PARAMETER NoVerify
    Skip post-write verification
.EXAMPLE
    .\install.ps1
    Interactive mode - lists drives and guides you
.EXAMPLE
    .\install.ps1 -Device 2
    Write directly to PhysicalDrive2
.EXAMPLE
    .\install.ps1 -List
    Show available drives
.NOTES
    Run as Administrator: right-click PowerShell → Run as Administrator
    Build the image first with: .\build.bat
#>

param(
    [int]$Device = -1,
    [string]$Image = "",
    [switch]$List = $false,
    [switch]$Force = $false,
    [switch]$Verify = $false,
    [switch]$NoVerify = $false
)

#Requires -RunAsAdministrator
Set-StrictMode -Version Latest

$Host.UI.RawUI.WindowTitle = "Vortex86 A9100 Image Installer"

# ============================================================
# Configuration
# ============================================================
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DefaultImagePaths = @(
    Join-Path $ScriptDir "buildroot\output\images\vortex86_a9100.img"
    Join-Path $ScriptDir "buildroot\output\images\vortex86_a9100.img.gz"
    Join-Path $ScriptDir "output\images\vortex86_a9100.img"
)

# ============================================================
# Color / Formatting Helpers
# ============================================================

function Write-Info {
    Write-Host "[INFO]  " -ForegroundColor Green -NoNewline
    Write-Host "$($args -join ' ')"
}

function Write-Warn {
    Write-Host "[WARN]  " -ForegroundColor Yellow -NoNewline
    Write-Host "$($args -join ' ')"
}

function Write-Error {
    Write-Host "[ERROR] " -ForegroundColor Red -NoNewline
    Write-Host "$($args -join ' ')"
}

function Write-Step {
    Write-Host "[STEP]  " -ForegroundColor Cyan -NoNewline
    Write-Host "$($args -join ' ')"
}

function Write-Header {
    Write-Host ""
    Write-Host "=== $($args -join ' ') ===" -ForegroundColor Blue
    Write-Host ""
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -lt 1KB) { return "$($Bytes)B" }
    if ($Bytes -lt 1MB) { return "$([math]::Round($Bytes/1KB, 1))KB" }
    if ($Bytes -lt 1GB) { return "$([math]::Round($Bytes/1MB, 1))MB" }
    return "$([math]::Round($Bytes/1GB, 2))GB"
}

# ============================================================
# Show help
# ============================================================
function Show-Help {
    Write-Host @"

Vortex86 A9100 Image Installer for Windows

Description:
  Writes the built disk image to a storage device (CF card,
  USB drive, SD card, hard drive) with safety checks.

Usage:
  .\install.ps1 [OPTIONS]

Modes:
  Interactive     Run with no arguments — lists drives and guides you
  Direct          .\install.ps1 -Device 2
  List            .\install.ps1 -List

Options:
  -Device <N>     Target physical drive number (e.g., 2)
  -Image <PATH>   Path to the disk image file
  -List           List available physical drives and exit
  -Force          Skip non-critical safety checks
  -Verify         Verify the write by reading back (checksum)
  -NoVerify       Skip verification

Requirements:
  - Windows 10/11 with Administrator privileges
  - Build the image first: .\build.bat

Examples:
  .\install.ps1                    Interactive mode
  .\install.ps1 -Device 2          Write to PhysicalDrive2
  .\install.ps1 -List              Show available drives

WARNING: ALL DATA on the target device will be DESTROYED!
"@
    exit 0
}

# ============================================================
# List physical drives
# ============================================================
function Get-PhysicalDrives {
    return Get-WmiObject Win32_DiskDrive | Sort-Object Index
}

function Show-DriveList {
    Write-Header "Available Physical Drives"

    $drives = Get-PhysicalDrives
    if ($drives.Count -eq 0) {
        Write-Error "No physical drives found!"
        exit 1
    }

    Write-Host ("{0,-7} {1,-45} {2,-10} {3,-12} {4,-10}" -f "DRIVE", "MODEL", "SIZE", "INTERFACE", "TYPE")
    Write-Host ("{0,-7} {1,-45} {2,-10} {3,-12} {4,-10}" -f "─────", "─────", "────", "─────────", "────")
    Write-Host ""

    foreach ($d in $drives) {
        $sizeStr = Format-Bytes $d.Size
        $interface = if ($d.InterfaceType) { $d.InterfaceType } else { "Unknown" }
        $mediaType = if ($d.MediaType) { $d.MediaType } else { "Fixed" }

        $flags = @()
        if ($d.InterfaceType -eq "USB") { $flags += "[USB]" }
        if ($d.MediaType -match "Removable") { $flags += "[REMOVABLE]" }

        $flagStr = if ($flags.Count -gt 0) { " $($flags -join ' ')" } else { "" }
        $modelTrim = $d.Model.PadRight(45).Substring(0, 45)

        $color = "Gray"
        if ($flags -contains "[REMOVABLE]") { $color = "Green" }

        Write-Host ("  {0,-5} {1,-45} {2,-10} {3,-12} {4}" -f `
            "PD$($d.Index)", $modelTrim, $sizeStr, $interface, $flagStr) -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  [REMOVABLE] = Safe to use (USB/SD/CF)" -ForegroundColor Green
    Write-Host "  System drive is typically PhysicalDrive0" -ForegroundColor Red
    Write-Host ""
}

# ============================================================
# Validate drive
# ============================================================
function Test-DriveSafe {
    param([int]$DriveNumber, [switch]$Force)

    $drives = Get-PhysicalDrives
    $drive = $drives | Where-Object { $_.Index -eq $DriveNumber }

    if (-not $drive) {
        Write-Error "PhysicalDrive$DriveNumber not found!"
        exit 1
    }

    # Check if this is likely the system drive
    if ($DriveNumber -eq 0 -and -not $Force) {
        Write-Error "REFUSING to write to PhysicalDrive0 (system disk)!"
        Write-Error "  This is almost certainly your Windows boot drive."
        Write-Host "  Use -Force to override (EXTREME caution required!)."
        exit 1
    }

    # Check if any partitions on this drive are mounted/in use
    $partitions = Get-WmiObject Win32_DiskPartition | Where-Object {
        $_.DiskIndex -eq $DriveNumber
    }
    $inUse = $false
    foreach ($p in $partitions) {
        $logical = Get-WmiObject Win32_LogicalDisk | Where-Object {
            $_.Name -eq "$($p.Name[0]):"
        }
        if ($logical) {
            Write-Warn "Partition $($p.Name) is mounted as $($logical.Name)"
            $inUse = $true
        }
    }

    if ($inUse -and -not $Force) {
        Write-Error "Drive has mounted partitions! Close any open files and try again."
        Write-Error "Or use -Force to override."
        exit 1
    }

    return $drive
}

# ============================================================
# Find image file
# ============================================================
function Find-Image {
    param([string]$SpecifiedPath)

    if ($SpecifiedPath) {
        if (Test-Path $SpecifiedPath) {
            return (Resolve-Path $SpecifiedPath).Path
        }
        Write-Error "Specified image not found: $SpecifiedPath"
        exit 1
    }

    foreach ($path in $DefaultImagePaths) {
        if (Test-Path $path) {
            return (Resolve-Path $path).Path
        }
    }

    # Search recursively in likely directories
    $searched = Get-ChildItem -Path $ScriptDir -Filter "*.img" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($searched) {
        return $searched.FullName
    }

    return $null
}

# ============================================================
# Validate image
# ============================================================
function Test-Image {
    param([string]$ImagePath)

    Write-Step "Validating image: $ImagePath"

    if (-not (Test-Path $ImagePath)) {
        Write-Error "Image file not found: $ImagePath"
        Write-Error "Have you built the image? Run: .\build.bat"
        exit 1
    }

    $fileInfo = Get-Item $ImagePath
    $imageSize = $fileInfo.Length

    Write-Info "Image size: $(Format-Bytes $imageSize)"
    Write-Info "File: $ImagePath"

    # Basic MBR check: read first 512 bytes and check for 55aa at offset 0x1FE
    try {
        $stream = [System.IO.File]::OpenRead($ImagePath)
        $buffer = New-Object byte[] 512
        $bytesRead = $stream.Read($buffer, 0, 512)
        $stream.Close()

        if ($bytesRead -ge 512 -and $buffer[510] -eq 0x55 -and $buffer[511] -eq 0xAA) {
            Write-Info "Image has valid MBR boot signature (55AA)"
        } else {
            Write-Warn "Image does NOT have a valid MBR boot signature!"
            Write-Warn "This may not be a bootable disk image. Continue with caution."
        }
    } catch {
        Write-Warn "Could not verify MBR signature: $_"
    }

    return @{
        Path = $ImagePath
        Size = $imageSize
    }
}

# ============================================================
# Confirm write
# ============================================================
function Confirm-DestructiveWrite {
    param(
        [int]$DriveNumber,
        [object]$DriveInfo,
        [string]$ImagePath,
        [long]$ImageSize
    )

    Write-Header "!!! DESTRUCTIVE OPERATION WARNING !!!"

    Write-Host ""
    Write-Host "  You are about to PERMANENTLY DESTROY ALL DATA on:" -ForegroundColor Red
    Write-Host ""
    Write-Host "    PhysicalDrive$DriveNumber" -ForegroundColor Red -NoNewline
    Write-Host " ($($DriveInfo.Model))" -ForegroundColor Red
    Write-Host "    Size: $(Format-Bytes $DriveInfo.Size)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Writing image: $(Split-Path $ImagePath -Leaf) ($(Format-Bytes $ImageSize))" -ForegroundColor Yellow
    Write-Host ""

    # Show detailed info
    Write-Host "Drive details:"
    Write-Host "  Model:     $($DriveInfo.Model)"
    Write-Host "  Interface: $($DriveInfo.InterfaceType)"
    Write-Host "  Media:     $($DriveInfo.MediaType)"
    Write-Host "  Serial:    $($DriveInfo.SerialNumber)"
    Write-Host ""

    Write-Host "THIS OPERATION CANNOT BE UNDONE!" -ForegroundColor Red
    Write-Host ""

    # Multi-step confirmation
    $confirmDrive = Read-Host "Type the PhysicalDrive number to confirm (e.g., $DriveNumber)"
    if ($confirmDrive -ne "$DriveNumber") {
        Write-Error "Drive number mismatch. Aborted."
        exit 1
    }

    $confirmYes = Read-Host "Type 'YES' to verify you want to destroy all data on PhysicalDrive$DriveNumber"
    if ($confirmYes -ne "YES") {
        Write-Host "Aborted."
        exit 1
    }

    Write-Info "Confirmation accepted. Proceeding..."
}

# ============================================================
# Write image to physical drive
# ============================================================
function Write-ImageToDrive {
    param(
        [int]$DriveNumber,
        [string]$ImagePath,
        [long]$ImageSize
    )

    Write-Header "Writing Image to PhysicalDrive$DriveNumber"

    $devicePath = "\\.\PhysicalDrive$DriveNumber"

    # Open the physical drive for writing
    try {
        $drive = [System.IO.File]::Open($devicePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    } catch {
        Write-Error "Could not open PhysicalDrive$DriveNumber for writing!"
        Write-Error "  Make sure you're running as Administrator."
        Write-Error "  Error: $_"
        exit 1
    }

    # Open the image file for reading
    try {
        $image = [System.IO.File]::OpenRead($ImagePath)
    } catch {
        $drive.Close()
        Write-Error "Could not open image file: $_"
        exit 1
    }

    $bufferSize = 4MB  # 4 MiB blocks
    $totalBytes = $image.Length
    $bytesWritten = 0
    $buffer = New-Object byte[] $bufferSize

    $startTime = Get-Date
    $lastUpdate = $startTime
    $lastBytes = 0

    Write-Step "Writing (progress every 5 seconds)..."
    Write-Host ""

    try {
        while ($bytesWritten -lt $totalBytes) {
            # Read from image
            $remaining = $totalBytes - $bytesWritten
            $toRead = [math]::Min($bufferSize, $remaining)
            $read = $image.Read($buffer, 0, $toRead)
            if ($read -eq 0) { break }

            # Write to drive
            $drive.Write($buffer, 0, $read)
            $bytesWritten += $read

            # Show progress
            $now = Get-Date
            if (($now - $lastUpdate).TotalSeconds -ge 5) {
                $pct = [math]::Round($bytesWritten / $totalBytes * 100, 1)
                $elapsed = ($now - $startTime).TotalSeconds
                $speed = if ($elapsed -gt 0) { [math]::Round($bytesWritten / $elapsed) } else { 0 }
                $remainingBytes = $totalBytes - $bytesWritten
                $eta = if ($speed -gt 0) { [math]::Round($remainingBytes / $speed) } else { 0 }

                $barWidth = 40
                $filled = [math]::Floor($bytesWritten / $totalBytes * $barWidth)
                $empty = $barWidth - $filled
                $bar = ("=" * $filled) + ">" + (" " * $empty)
                $bar = $bar.Substring(0, [math]::Min($bar.Length, $barWidth))

                $speedStr = Format-Bytes $speed
                $etaStr = if ($eta -gt 0) {
                    $ts = [TimeSpan]::FromSeconds($eta)
                    if ($ts.Hours -gt 0) { "{0}h {1}m" -f $ts.Hours, $ts.Minutes }
                    elseif ($ts.Minutes -gt 0) { "{0}m {1}s" -f $ts.Minutes, $ts.Seconds }
                    else { "{0}s" -f $ts.Seconds }
                } else { "--" }

                $progressStr = "[$bar] $pct%  $(Format-Bytes $bytesWritten)/$(Format-Bytes $totalBytes)  $speedStr/s  ETA $etaStr"
                Write-Host "  $progressStr"

                $lastUpdate = $now
                $lastBytes = $bytesWritten
            }
        }

        $drive.Flush($true)
    } catch {
        Write-Error "Write failed: $_"
        $image.Close()
        $drive.Close()
        exit 1
    }

    $image.Close()
    $drive.Close()

    $elapsed = (Get-Date) - $startTime
    $elapsedSec = [math]::Round($elapsed.TotalSeconds)
    $avgSpeed = if ($elapsedSec -gt 0) { Format-Bytes ([math]::Round($totalBytes / $elapsedSec)) } else { "?" }

    Write-Host ""
    Write-Info "Write complete! Duration: $([math]::Floor($elapsedSec/60))m $($elapsedSec % 60)s  Avg speed: $avgSpeed/s"
}

# ============================================================
# Verify write
# ============================================================
function Verify-Write {
    param(
        [int]$DriveNumber,
        [string]$ImagePath
    )

    Write-Header "Verifying Write"

    Write-Step "Computing SHA256 of image file..."
    $imageHash = Get-FileHash -Path $ImagePath -Algorithm SHA256
    Write-Info "Image hash: $($imageHash.Hash)"

    Write-Step "Reading back from PhysicalDrive$DriveNumber..."

    $devicePath = "\\.\PhysicalDrive$DriveNumber"
    try {
        $drive = [System.IO.File]::OpenRead($devicePath)
    } catch {
        Write-Warn "Could not open drive for verification: $_"
        return $false
    }

    $bufferSize = 4MB
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $buffer = New-Object byte[] $bufferSize
    $totalRead = 0
    $imageSize = (Get-Item $ImagePath).Length

    try {
        while ($totalRead -lt $imageSize) {
            $remaining = $imageSize - $totalRead
            $toRead = [math]::Min($bufferSize, $remaining)
            $read = $drive.Read($buffer, 0, $toRead)
            if ($read -eq 0) { break }
            $sha256.TransformBlock($buffer, 0, $read, $null, 0)
            $totalRead += $read
        }
        $sha256.TransformFinalBlock($buffer, 0, 0)
    } catch {
        Write-Warn "Read-back failed: $_"
        $drive.Close()
        return $false
    }

    $drive.Close()
    $deviceHash = [Bitconverter]::ToString($sha256.Hash).Replace("-", "")

    Write-Info "Device hash: $deviceHash"

    if ($deviceHash -eq $imageHash.Hash) {
        Write-Host ""
        Write-Info "[PASS] VERIFICATION PASSED — Written data matches the image exactly" -ForegroundColor Green
        return $true
    } else {
        Write-Host ""
        Write-Error "[FAIL] VERIFICATION FAILED — Written data does NOT match the image"
        Write-Warn "  The device may be faulty or the write was interrupted."
        return $false
    }
}

# ============================================================
# Post-write info
# ============================================================
function Show-PostWriteInfo {
    param([int]$DriveNumber)

    Write-Header "Installation Complete!"

    Write-Host "The Vortex86 A9100 image has been written to PhysicalDrive$DriveNumber" -ForegroundColor Green
    Write-Host ""

    Write-Host "Next steps:" -NoNewline
    Write-Host ""
    Write-Host ""
    Write-Host "  1. Safely remove the device:"
    Write-Host "     - Open 'Safely Remove Hardware' in system tray"
    Write-Host "     - Select the drive and eject"
    Write-Host ""
    Write-Host "  2. Insert the CF card / connect the drive to your Vortex86 A9100"
    Write-Host ""
    Write-Host "  3. Connect:"
    Write-Host "     - Serial console (ttyS0, 115200 baud)"
    Write-Host "     - VGA display + PS/2 keyboard"
    Write-Host ""
    Write-Host "  4. Power on the Vortex86 A9100"
    Write-Host ""
    Write-Host "  5. The system boots to GRUB, then login prompt"
    Write-Host "     Login: root (no password)"
    Write-Host "     Start GUI: startx"
    Write-Host ""
}

# ============================================================
# Interactive drive selection
# ============================================================
function Select-DriveInteractive {
    Write-Header "Select Target Drive"

    $drives = Get-PhysicalDrives
    if ($drives.Count -eq 0) {
        Write-Error "No physical drives found!"
        exit 1
    }

    for ($i = 0; $i -lt $drives.Count; $i++) {
        $d = $drives[$i]
        $sizeStr = Format-Bytes $d.Size
        $interface = if ($d.InterfaceType) { $d.InterfaceType } else { "Unknown" }

        $flags = @()
        $color = "Gray"
        if ($d.InterfaceType -eq "USB") { $flags += "[USB]"; $color = "Green" }
        if ($d.MediaType -match "Removable") { $flags += "[REMOVABLE]"; $color = "Green" }
        if ($d.Index -eq 0) { $flags += "[SYSTEM]"; $color = "Red" }
        $flagStr = if ($flags.Count -gt 0) { " $($flags -join ' ')" } else { "" }

        Write-Host ("  {0,2}. PhysicalDrive{1,-5} {2,-45} {3,-10} {4,-12}{5}" -f `
            ($i + 1), $d.Index, $d.Model.Substring(0, [math]::Min(45, $d.Model.Length)).PadRight(45),
            $sizeStr, $interface, $flagStr) -ForegroundColor $color
    }

    Write-Host ""
    $selection = Read-Host "Select drive number (1-$($drives.Count)) or 'q' to quit"

    if ($selection -eq 'q' -or $selection -eq 'Q') {
        Write-Host "Aborted."
        exit 0
    }

    $num = 0
    if (-not [int]::TryParse($selection, [ref]$num) -or $num -lt 1 -or $num -gt $drives.Count) {
        Write-Error "Invalid selection."
        exit 1
    }

    return $drives[$num - 1].Index
}

# ============================================================
# Check device size
# ============================================================
function Test-DeviceSize {
    param(
        [object]$DriveInfo,
        [long]$ImageSize
    )

    $driveSize = $DriveInfo.Size
    if ($driveSize -lt $ImageSize) {
        Write-Error "Target drive is TOO SMALL!"
        Write-Error "  Drive: $(Format-Bytes $driveSize)"
        Write-Error "  Image: $(Format-Bytes $ImageSize)"
        exit 1
    }

    Write-Info "Size check passed — drive is large enough"
}

# ============================================================
# Main
# ============================================================
function Main {
    # Process parameters
    if ($List) {
        Show-DriveList
        exit 0
    }

    # Interactive mode (no args) falls through to the interactive drive selection

    # Banner
    Write-Header "Vortex86 A9100 Image Installer for Windows"

    # Find image
    $imageInfo = Find-Image -SpecifiedPath $Image
    if (-not $imageInfo) {
        Write-Error "No disk image found!"
        Write-Error ""
        Write-Error "Expected at: $($DefaultImagePaths[0])"
        Write-Error "Have you built the image? Run: .\build.bat"
        Write-Error "Or specify a custom path: install.ps1 -Image D:\path\to\vortex86_a9100.img"
        exit 1
    }
    Write-Info "Using image: $imageInfo"

    # Validate image
    $imageData = Test-Image -ImagePath $imageInfo

    # Select or validate target drive
    $targetDrive = $Device
    if ($targetDrive -lt 0) {
        Show-DriveList
        $targetDrive = Select-DriveInteractive
    }

    $driveInfo = Test-DriveSafe -DriveNumber $targetDrive -Force:$Force
    Test-DeviceSize -DriveInfo $driveInfo -ImageSize $imageData.Size

    # Confirm
    Confirm-DestructiveWrite -DriveNumber $targetDrive -DriveInfo $driveInfo -ImagePath $imageData.Path -ImageSize $imageData.Size

    # Write
    Write-ImageToDrive -DriveNumber $targetDrive -ImagePath $imageData.Path -ImageSize $imageData.Size

    # Verify
    $shouldVerify = -not $NoVerify
    if ($Verify) { $shouldVerify = $true }
    if ($shouldVerify) {
        Write-Host ""
        $verifyChoice = Read-Host "Verify the write (read-back checksum comparison)? [Y/n]"
        if ($verifyChoice -ne 'n' -and $verifyChoice -ne 'N') {
            Verify-Write -DriveNumber $targetDrive -ImagePath $imageData.Path
        }
    }

    # Post-write info
    Show-PostWriteInfo -DriveNumber $targetDrive
}

# Run main
Main
