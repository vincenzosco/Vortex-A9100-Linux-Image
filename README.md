# Vortex86 A9100 Custom Linux Image Builder

> **Build a complete, bootable Linux distribution for the DM&P Vortex86 A9100**
> (i486-compatible SoC, 300MHz, FPU-less, embedded x86)

[![GitHub](https://img.shields.io/badge/GitHub-Vortex--A9100--Linux--Image-blue?style=flat&logo=github)](https://github.com/vincenzosco/Vortex-A9100-Linux-Image)

## Features

- **Kernel:** Linux 5.10 LTS (last kernel with proper i486 support) with custom CMPXCHG8B emulation patch
- **C Library:** musl (lightweight, optimized for embedded systems)
- **Init System:** BusyBox init (fast, minimal, no systemd overhead)
- **Package Manager:** opkg (with GitHub-hosted update feed for OTA updates)
- **GUI:** X.Org + Openbox — lightweight, fast desktop environment
- **Bootloader:** GRUB (supports booting from CF cards, IDE SSDs, USB, hard drives)
- **Network:** DHCP client, SSH server, basic networking tools (RDC R6040 + Realtek 8139)
- **Installer:** Interactive `install.sh` (Linux) / `install.ps1` (Windows) — device detection, safety checks, ETA progress bar
- **Updates:** OTA system updates via `opkg update && opkg install vortex-os-update`

## Quick Start

### Linux
```bash
# Clone
git clone https://github.com/vincenzosco/Vortex-A9100-Linux-Image.git
cd Vortex-A9100-Linux-Image

# Build the image (30-120 min first time)
./build.sh

# Write to your CF card / USB drive / hard drive
sudo ./install.sh
```

### Windows (WSL2)
```batch
:: Clone (use Git for Windows or WSL)
git clone https://github.com/vincenzosco/Vortex-A9100-Linux-Image.git
cd Vortex-A9100-Linux-Image

:: Build the image (runs inside WSL2)
build.bat

:: Write to your USB/CF drive (PowerShell as Administrator)
.\install.ps1
```

> **Prerequisites for Windows:** Windows 10 2004+ / Windows 11, WSL2 with Ubuntu, and
> [Windows Terminal](https://aka.ms/terminal) (recommended). See
> [Building on Windows](#building-on-windows) for detailed setup.

## OTA Updates via opkg

This project includes a complete OTA update system using opkg. After the initial
build, you can create a package feed and deploy it to GitHub Pages. On the target
hardware, the system can then update itself over the internet.

### How it works

1. `./build.sh` produces the kernel, rootfs, and system configs
2. `./scripts/create-opkg-feed.sh` packages them into `.ipk` packages + `Packages.gz`
3. `./scripts/deploy-feed.sh` pushes the feed to the `gh-pages` branch
4. GitHub Actions auto-deploys on every push to `main`
5. On the Vortex86 A9100: `opkg update && opkg install vortex-os-update`

### Packages

| Package | Description |
|---------|-------------|
| `vortex-kernel` | Linux 5.10 kernel + modules + automatic GRUB update |
| `vortex-base-system` | System configs, init scripts, X11 config, Openbox theme |
| `vortex-os-update` | Meta-package — installs both above for a full OS update |

### Usage on target

```bash
# Update package list from GitHub Pages feed
opkg update

# Upgrade ALL vortex packages to latest versions
opkg upgrade

# Or install a specific package
opkg install vortex-os-update

# After installation: reboot
reboot
```

The feed URL is pre-configured in `/etc/opkg.conf` on the built image:
```
src/gz vortex-stable https://vincenzosco.github.io/Vortex-A9100-Linux-Image/opkg/
```

### Manual feed deployment

```bash
# Build packages from the latest build output (auto-versioned from git tags)
./scripts/create-opkg-feed.sh

# Deploy to GitHub Pages
./scripts/deploy-feed.sh
```

Versions are auto-detected from git tags + commit count (e.g., `1.0.0-build42`).
To override: `./scripts/create-opkg-feed.sh --version 2.0.0`

> **Note:** GitHub Pages must be enabled in the repository settings
> (Settings > Pages > Deploy from `gh-pages` branch).

## System Requirements

### Build Host
- **OS:** Linux (native or WSL2) or Windows 10/11 with WSL2
- **Disk:** ~5GB free space
- **RAM:** 2GB+ recommended
- **CPU:** Any x86_64 (cross-compilation)

### Build Dependencies

#### Linux (Native)
```bash
# Debian/Ubuntu
sudo apt-get install -y build-essential bison flex bc wget tar gzip \
  bzip2 xz-utils patch sed gawk findutils file cpio unzip rsync python3 \
  uuid-dev libblkid-dev

# Arch Linux
sudo pacman -S --needed base-devel bison flex bc wget tar gzip bzip2 \
  xz patch gawk findutils file cpio unzip rsync python

# Fedora
sudo dnf install -y @development-tools bison flex bc wget tar gzip \
  bzip2 xz patch sed gawk findutils file cpio unzip rsync python3 \
  libuuid-devel libblkid-devel
```

#### Windows (WSL2)
The build runs inside WSL2. After installing WSL2 + Ubuntu, install the
Linux dependencies listed above inside the WSL environment:

```bash
# Inside WSL2 Ubuntu:
sudo apt-get update && sudo apt-get install -y build-essential bison flex bc \
  wget tar gzip bzip2 xz-utils patch sed gawk findutils file cpio unzip \
  rsync python3 uuid-dev libblkid-dev
```

### Target Hardware (Vortex86 A9100)
| Component | Requirement |
|-----------|-------------|
| **CPU** | i486-compatible (FPU emulated in software) |
| **RAM** | 64MB minimum, 128MB+ recommended for GUI |
| **Storage** | 512MB+ (CF card, IDE SSD, USB drive, or hard disk) |
| **Display** | VGA-compatible (VESA framebuffer) |
| **Network** | RDC R6040 or Realtek 8139 Ethernet (drivers included) |
| **Serial** | ttyS0 at 115200 baud (for debugging) |

## Building the Image

### Linux (Native)

```bash
cd Vortex-A9100-Linux-Image

# Full build (downloads Buildroot + sources, cross-compiles everything)
./build.sh

# If you need to customize packages first
./build.sh menuconfig
./build.sh

# Clean rebuild (removes downloaded Buildroot too)
./build.sh distclean && ./build.sh

# Quick clean (keeps downloaded sources)
./build.sh clean
```

### Windows (WSL2)

```batch
cd Vortex-A9100-Linux-Image

:: Full build — automatically uses WSL2
build.bat

:: Clean build artifacts
build.bat clean

:: Full clean (removes downloaded sources too)
build.bat distclean
```

The `build.bat` script:
1. Verifies WSL2 is installed with Ubuntu
2. Checks build dependencies inside WSL
3. Runs `build.sh` inside the WSL environment
4. The `buildroot/` directory is shared between Windows and WSL

### Build Process

The build system:
1. Downloads Buildroot 2023.02.11 (final 2023.02.x LTS release)
2. Applies the custom Vortex86 A9100 board configuration
3. Downloads and patches Linux 5.10 LTS kernel (with CMPXCHG8B emulation for i486)
4. Cross-compiles the toolchain (musl libc, GCC)
5. Builds all packages (BusyBox, X.Org, Openbox, OpenSSH, opkg, CA certs, etc.)
6. Creates a bootable disk image with GRUB

### Output Files

After the build completes, files are in `buildroot/output/images/`:

| File | Description | Use |
|------|-------------|-----|
| `vortex86_a9100.img` | **Complete bootable disk image** (512MB) | Write directly to storage media |
| `bzImage` | Linux kernel | For partition-based install |
| `rootfs.ext2` | Root filesystem image | For partition-based install |
| `rootfs.tar` | Root filesystem tarball | For partition-based install |

## Installation to Real Hardware

### Linux (install.sh)

The project includes a production-grade interactive installer with safety checks:

```bash
# Interactive mode - lists all devices, guides you through
sudo ./install.sh

# Direct to a specific device (CF card, USB drive, hard disk)
sudo ./install.sh /dev/sdc

# List available devices without installing
./install.sh --list

# Write and verify (read-back checksum)
sudo ./install.sh /dev/sdc --verify
```

#### Installer Features (Linux)

| Feature | Details |
|---------|---------|
| **Interactive device picker** | Shows all block devices with model, size, and safety warnings |
| **System disk blacklist** | Refuses to write to `sda`, `sdb`, `nvme0`, etc. (can override with `--force`) |
| **Mount detection** | Detects mounted partitions, auto-unmounts them |
| **Size validation** | Checks target is large enough for the image |
| **MBR boot signature check** | Verifies the image is bootable before writing |
| **Triple confirmation** | Requires typing the device name AND "YES" |
| **Progress display** | Live progress bar `[====>-----] 67%`, ETA, speed |
| **Stall detection** | Warns if device stops responding during write |
| **Post-write verification** | Optional SHA256 checksum comparison |
| **pv support** | Full progress bar if `pv` is installed (`sudo apt-get install pv`) |

### Windows (install.ps1)

The Windows installer provides equivalent functionality via PowerShell:

```powershell
# Run PowerShell as Administrator, then:
.\install.ps1                      # Interactive mode
.\install.ps1 -Device 2            # Write to PhysicalDrive2
.\install.ps1 -List                # Show available drives
.\install.ps1 -Device 2 -Verify    # Write and verify
```

#### Installer Features (Windows)

| Feature | Details |
|---------|---------|
| **Drive listing** | Shows all physical drives with model, size, interface |
| **System disk protection** | Refuses to write to PhysicalDrive0 (system disk) |
| **Mount detection** | Warns if the drive has mounted partitions |
| **MBR signature check** | Verifies the image is bootable |
| **Dual confirmation** | Requires drive number + "YES" confirmation |
| **Progress display** | Progress bar updated every 5 seconds with ETA |
| **SHA256 verification** | Optional read-back checksum comparison |
| **Direct I/O** | Writes directly via `\\.\PhysicalDriveN` |

> **Note:** The Windows installer writes directly to the physical drive using
> `.NET's System.IO.File`. This is equivalent to `dd` on Linux. All data on
> the target drive will be destroyed.

### Manual Write (Linux)

```bash
# Write disk image to SD card / CF card / USB drive
sudo dd if=buildroot/output/images/vortex86_a9100.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

### Manual Write (Windows)

```powershell
# Use Rufus (recommended GUI tool): https://rufus.ie/
# Or use dd for Windows from the command line
```

### Partition-Based Install (Alternative)

```bash
# Mount root partition
sudo mount /dev/sdb2 /mnt

# Extract rootfs
sudo tar xf buildroot/output/images/rootfs.tar -C /mnt

# Copy kernel to boot partition
sudo mount /dev/sdb1 /mnt/boot
sudo cp buildroot/output/images/bzImage /mnt/boot/
```

## Testing in QEMU (Before Deploying to Hardware)

```bash
# Basic test (no hardware required)
qemu-system-i386 -m 256 -hda buildroot/output/images/vortex86_a9100.img

# With serial console (for debugging)
qemu-system-i386 -m 256 -hda buildroot/output/images/vortex86_a9100.img -serial stdio

# With VGA display
qemu-system-i386 -m 256 -hda buildroot/output/images/vortex86_a9100.img -vga std
```

## First Boot on Real Hardware

1. **Prepare your storage media:**
   - CF card via USB adapter, IDE SSD, or USB drive
   - Linux: `sudo ./install.sh` and select your device
   - Windows: `.\install.ps1` (as Administrator)

2. **Connect to the Vortex86 A9100 board:**
   - VGA display + PS/2 keyboard (for GUI)
   - Serial console (ttyS0, 115200 baud, no parity, 8 data bits, 1 stop bit)

3. **Power on the board**

4. **GRUB boot menu appears** (5 second timeout):
   - Select "Vortex86 A9100 Linux" (default)
   - "Verbose" mode for debugging
   - "Single User" for maintenance

5. **Login:**
   - User: `root`
   - Password: (empty — press Enter)
   - Serial: ttyS0 at 115200 baud
   - VGA: Press Enter on tty1

## Using the System

### Launch the GUI

```bash
# At the command prompt:
startx
```

This launches:
- X.Org server (VESA framebuffer driver)
- Openbox window manager with dark theme
- Right-click desktop for application menu
- Terminal, clock, system monitor available

### Package Manager (opkg)

The built image includes opkg configured with a GitHub Pages feed for OTA updates:

```bash
# Update package lists from the online feed
opkg update

# Install a package from the feed
opkg install <package-name>

# Install full OS update (kernel + system configs)
opkg install vortex-os-update

# Remove a package
opkg remove <package-name>

# List installed packages
opkg list-installed

# List available packages from feed
opkg list
```

> **Note:** The default feed URL is `https://vincenzosco.github.io/Vortex-A9100-Linux-Image/opkg/`.
> See `/etc/opkg.conf` to add custom feeds. To add packages permanently to the image,
> rebuild with: `./build.sh menuconfig` → enable packages → rebuild.

### Network Configuration

```bash
# DHCP (default - auto-starts on boot)
# No configuration needed

# Static IP
ifconfig eth0 192.168.1.100 netmask 255.255.255.0 up
route add default gw 192.168.1.1

# Check status
ifconfig
route -n
ping 8.8.8.8
```

### SSH Access

```bash
# SSH server starts automatically on boot
# Connect from another machine:
ssh root@<vortex-ip-address>
```

### Common Commands

```bash
# System information
htop                    # Process monitor
free -m                 # Memory usage
df -h                   # Disk usage
uname -a                # Kernel version
cat /proc/cpuinfo       # CPU info
dmesg                   # Kernel log

# Files and editing
nano <file>             # Text editor
ls -la                  # List files

# Serial console (if connected)
screen /dev/ttyUSB0 115200
```

## Architecture

### Boot Process

1. BIOS loads GRUB from MBR
2. GRUB loads Linux kernel (`/boot/bzImage`)
3. Kernel boots with: `console=ttyS0,115200n8 console=tty0 root=/dev/sda1`
4. BusyBox init runs `/etc/init.d/rcS`
5. Network, SSH, and X11 services start
6. Login prompt on serial console and VGA

### Partition Layout (512MB disk)

| Partition | Size | Type | Mount | Label |
|-----------|------|------|-------|-------|
| p1 | 50MB | ext2 | `/boot` | `vortex-boot` |
| p2 | ~462MB | ext4 | `/` | `vortex-root` |

### Software Stack

```
┌──────────────────────────────────────────────┐
│  Openbox Window Manager (GUI)                │
├──────────────────────────────────────────────┤
│  X.Org Server (VESA / fbdev drivers)         │
├──────────────────────────────────────────────┤
│  opkg (Package Manager)  │  SSH  │  Network  │
├──────────────────────────────────────────────┤
│  BusyBox (init, shell, coreutils, udhcpc)    │
├──────────────────────────────────────────────┤
│  musl libc (lightweight C library)           │
├──────────────────────────────────────────────┤
│  Linux 5.10 LTS + CMPXCHG8B emulation patch  │
├──────────────────────────────────────────────┤
│  GRUB Bootloader (i386-pc)                   │
└──────────────────────────────────────────────┘
```

## Customization

### Add/Remove Packages

```bash
./build.sh menuconfig

# Navigate to: Target Packages > ...
# Enable/disable packages as needed
# Save and exit
# Rebuild
./build.sh
```

### Kernel Configuration

```bash
./build.sh linux-config

# Modify kernel options
# Save and exit
# Rebuild
./build.sh
```

### Enable GUI Auto-Start on Boot

Edit `board/dmp/vortex86_a9100/overlay/etc/init.d/S60xorg`:
```bash
# Change:
AUTOSTART="no"
# To:
AUTOSTART="yes"
```

Then rebuild: `./build.sh`

## Troubleshooting

### Build Fails
- Check `buildroot/output/build.log` for error details
- Ensure all dependencies are installed
- Try: `./build.sh distclean && ./build.sh`
- Common: missing network access (Buildroot downloads many packages)
- On WSL: long path issues (`Function not implemented` errors) — the `.gitignore` excludes `buildroot/`
- On WSL: if you get `configure: error: you should not run configure as root` — this is fixed by setting `FORCE_UNSAFE_CONFIGURE=1` (already in `build.sh`)

### host-util-linux Build Failure (pidfd_open)
**Error:** `implicit declaration of function 'pidfd_open'` / `'pidfd_send_signal'`

**Cause:** On glibc 2.36+ (e.g., Ubuntu 24.04+), `pidfd_open()` and `pidfd_send_signal()` are
declared in `<sys/pidfd.h>` rather than in `<sys/types.h>`. The util-linux 2.38 `pidfd-utils.h`
only includes `<sys/types.h>`, missing the declaration.

**Fix:** A custom patch (`board/dmp/vortex86_a9100/patches/util-linux/0001-pidfd-utils-include-sys-pidfd.h-when-available.patch`)
adds `#include <sys/pidfd.h>` when available, guarded by `__has_include`. This is applied
automatically during the build.

### Legacy Configuration Error
```
Makefile.legacy:9: *** "You have legacy configuration in your .config!"
```
- The defconfig was updated to remove renamed/deprecated options
- Run `./build.sh distclean && ./build.sh` to start fresh

### Kernel Panic / Boot Failure on Real Hardware
- Connect serial console (ttyS0, 115200) to see kernel messages
- Select "Verbose" mode in GRUB
- Common issues: wrong root partition, missing storage driver
- Try booting from GRUB with: `linux /boot/bzImage root=/dev/hda1`

### GUI Won't Start
- The Vortex86 A9100 uses VESA framebuffer — most VGA chips work
- Try: `Xorg -configure` to generate a custom xorg.conf
- Check: `dmesg | grep -i vesa`
- Try fbdev driver: edit `/etc/X11/xorg.conf`, change `Driver "vesa"` to `Driver "fbdev"`

### No Network
- Check: `dmesg | grep eth`
- Check: `ifconfig eth0`
- The RDC R6040 and Realtek 8139 drivers are included
- For other NICs, enable them via `./build.sh linux-config`

### Installer Won't Detect Device
- **Linux:** Check: `lsblk -d` — does your device appear?
- **Windows:** Check: `Get-WmiObject Win32_DiskDrive` in PowerShell
- For CF card readers: try a different USB port or adapter

### opkg update Fails with SSL Error
- Ensure the target has network access and CA certificates installed
- The built image includes `ca-certificates` for HTTPS support
- Check: `ping github.com`
- The target date/time must be reasonably accurate for TLS handshakes

## Project Structure

```
Vortex-A9100-Linux-Image/
├── build.sh                          # Main build orchestrator (Linux)
├── build.bat                         # Build wrapper (Windows / WSL2)
├── install.sh                        # Interactive image installer (Linux)
├── install.ps1                       # Disk image installer (Windows PowerShell)
├── .gitignore                        # Excludes buildroot/ and output/
├── README.md                         # This file
├── configs/
│   └── vortex86_a9100_defconfig      # Buildroot target configuration
├── board/
│   └── dmp/
│       └── vortex86_a9100/
│           ├── linux.config          # Kernel configuration overlay
│           ├── busybox.config        # BusyBox configuration overlay
│           ├── grub.cfg              # GRUB boot menu configuration
│           ├── openbox-config        # Openbox window manager config
│           ├── post-build.sh         # Post-build filesystem setup
│           ├── post-image.sh         # Bootable disk image creation
│           ├── patches/
│           │   ├── linux/
│           │   │   └── 0001-i486-cmpxchg8b-emulation.patch
│           │   └── util-linux/
│           │       └── 0001-pidfd-utils-include-sys-pidfd.h-when-available.patch
│           └── overlay/
│               ├── etc/
│               │   ├── inittab       # BusyBox init configuration
│               │   ├── profile       # Shell profile
│               │   ├── hostname
│               │   ├── opkg.conf     # Package manager + OTA feed URL
│               │   ├── X11/xorg.conf # X.Org server config
│               │   └── init.d/       # System services
│               └── root/
│                   ├── .bashrc
│                   └── .xinitrc      # X11 session startup
├── scripts/
│   ├── create-opkg-feed.sh           # Build .ipk packages + Packages.gz
│   └── deploy-feed.sh                # Deploy feed to GitHub Pages
├── opkg-feed/
│   ├── README.md                     # Feed documentation
│   └── packages/                     # Package control files
│       ├── kernel/control/           # vortex-kernel metadata
│       ├── base-system/control/      # vortex-base-system metadata
│       └── os-update/control/        # vortex-os-update metadata
└── .github/workflows/
    └── deploy-opkg-feed.yml          # Auto-deploy feed on push
```

## License

This build system includes components under various open-source licenses:
- Linux kernel: GPL v2
- Buildroot: GPL v2+
- BusyBox: GPL v2
- musl: MIT
- Openbox: GPL v2+
- X.Org: MIT
- All other components: their respective licenses
