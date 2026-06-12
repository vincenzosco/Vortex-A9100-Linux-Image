# Vortex86 A9100 Custom Linux Image Builder

> **Build a complete, bootable Linux distribution for the DM&P Vortex86 A9100**
> (i486-compatible SoC, 300MHz, FPU-less, embedded x86)

[![GitHub](https://img.shields.io/badge/GitHub-Vortex--A9100--Linux--Image-blue?style=flat&logo=github)](https://github.com/vincenzosco/Vortex-A9100-Linux-Image)

**Repository:** [https://github.com/vincenzosco/Vortex-A9100-Linux-Image](https://github.com/vincenzosco/Vortex-A9100-Linux-Image)

## Features

- **Kernel:** Linux 5.10 LTS (last kernel with proper i486 support) with custom CMPXCHG8B emulation patch
- **C Library:** musl (lightweight, optimized for embedded systems)
- **Init System:** BusyBox init (fast, minimal, no systemd overhead)
- **Package Manager:** opkg (with local repository support)
- **GUI:** X.Org + Openbox — lightweight, fast desktop environment
- **Bootloader:** GRUB (supports booting from CF cards, IDE SSDs, USB, hard drives)
- **Network:** DHCP client, SSH server, basic networking tools (RDC R6040 + Realtek 8139)
- **Installer:** Interactive `install.sh` with device detection, safety checks, ETA progress bar

## Quick Start

```bash
# Clone
git clone https://github.com/vincenzosco/Vortex-A9100-Linux-Image.git
cd Vortex-A9100-Linux-Image

# Build the image (30-120 min first time)
./build.sh

# Write to your CF card / USB drive / hard drive
sudo ./install.sh
```

## System Requirements

### Build Host
- **OS:** Linux (native) or WSL2 on Windows
- **Disk:** ~5GB free space
- **RAM:** 2GB+ recommended
- **CPU:** Any x86_64 (cross-compilation)

### Build Dependencies (Linux)
```bash
# Debian/Ubuntu
sudo apt-get install -y build-essential bison flex bc wget tar gzip \
  bzip2 xz-utils patch sed awk findutils file cpio unzip rsync python3

# Arch Linux
sudo pacman -S --needed base-devel bison flex bc wget tar gzip bzip2 \
  xz patch awk findutils file cpio unzip rsync python

# Fedora
sudo dnf install -y @development-tools bison flex bc wget tar gzip \
  bzip2 xz patch sed gawk findutils file cpio unzip rsync python3
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

```bash
cd Vortex-A9100-Linux-Image

# Full build (downloads Buildroot + sources, cross-compiles everything)
./build.sh

# If you need to customize packages first
./build.sh menuconfig
./build.sh

# Clean rebuild
./build.sh distclean && ./build.sh
```

### Build Process

The build system:
1. Downloads Buildroot 2023.02.14 (last version with reliable i486 support)
2. Applies the custom Vortex86 A9100 board configuration
3. Downloads and patches Linux 5.10 LTS kernel (with CMPXCHG8B emulation for i486)
4. Cross-compiles the toolchain (musl libc, GCC)
5. Builds all packages (BusyBox, X.Org, Openbox, OpenSSH, opkg, etc.)
6. Creates a bootable disk image with GRUB

### Output Files

After the build completes, files are in `output/images/`:

| File | Description | Use |
|------|-------------|-----|
| `vortex86_a9100.img` | **Complete bootable disk image** (512MB) | Write directly to storage media |
| `bzImage` | Linux kernel | For partition-based install |
| `rootfs.ext2` | Root filesystem image | For partition-based install |
| `rootfs.tar` | Root filesystem tarball | For partition-based install |

## Installation to Real Hardware

### :zap: Automated Installer (Recommended)

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

#### Installer Features

| Feature | Details |
|---------|---------|
| **Interactive device picker** | Shows all block devices with model, size, and safety warnings |
| **System disk blacklist** | Refuses to write to `sda`, `sdb`, `nvme0`, etc. (can override with `--force`) |
| **Mount detection** | Detects mounted partitions, auto-unmounts them |
| **Size validation** | Checks target is large enough for the image |
| **MBR boot signature check** | Verifies the image is bootable before writing |
| **Triple confirmation** | Requires typing the device name AND "YES" |
| **Progress display** | Live spinner, progress bar `[====>-----] 67%`, ETA, speed |
| **Stall detection** | Warns if device stops responding during write |
| **Post-write verification** | Optional SHA256 checksum comparison |
| **pv support** | Full progress bar if `pv` is installed (`sudo apt-get install pv`) |

#### Installer Progress Display

When writing, you'll see a live-updating single line:
```
  ⠋  45.2MB/s  ETA 0:12  [========>---------]  67%  128MB/512MB
```

### Manual Write (Advanced)

If you prefer to use `dd` directly:

```bash
# Write disk image to SD card / CF card / USB drive
sudo dd if=output/images/vortex86_a9100.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

### Partition-Based Install (Alternative)

For existing partition layouts:

```bash
# Mount root partition
sudo mount /dev/sdb2 /mnt

# Extract rootfs
sudo tar xf output/images/rootfs.tar -C /mnt

# Copy kernel to boot partition
sudo mount /dev/sdb1 /mnt/boot
sudo cp output/images/bzImage /mnt/boot/
```

## Testing in QEMU (Before Deploying to Hardware)

```bash
# Basic test (no hardware required)
qemu-system-i386 -m 256 -hda output/images/vortex86_a9100.img

# With serial console (for debugging)
qemu-system-i386 -m 256 -hda output/images/vortex86_a9100.img -serial stdio

# With VGA display
qemu-system-i386 -m 256 -hda output/images/vortex86_a9100.img -vga std
```

## First Boot on Real Hardware

1. **Prepare your storage media:**
   - CF card via USB adapter, IDE SSD, or USB drive
   - Run: `sudo ./install.sh` and select your device

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

```bash
# Update package lists
opkg update

# Install a package
opkg install <package-name>

# Remove a package
opkg remove <package-name>

# List installed packages
opkg list-installed

# List available packages
opkg list
```

> **Note:** For binary package support, set up your own opkg repository.
> See `/etc/opkg.conf` for configuration. To add packages permanently,
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

## Troubleshooting

### Build Fails
- Check `output/build.log` for error details
- Ensure all dependencies are installed
- Try: `./build.sh distclean && ./build.sh`
- Common: missing network access (Buildroot downloads many packages)

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
- Check: `lsblk -d` — does your device appear?
- For CF card readers: try a different USB port or adapter
- Some USB-to-CF adapters present as `/dev/sdX`

## Project Structure

```
Vortex-A9100-Linux-Image/
├── build.sh                          # Main build orchestrator
├── install.sh                        # Interactive image installer
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
│           │   └── linux/
│           │       └── 0001-i486-cmpxchg8b-emulation.patch
│           └── overlay/
│               ├── etc/
│               │   ├── inittab       # BusyBox init configuration
│               │   ├── profile       # Shell profile
│               │   ├── hostname
│               │   ├── opkg.conf     # Package manager settings
│               │   ├── X11/xorg.conf # X.Org server config
│               │   └── init.d/       # System services
│               └── root/
│                   ├── .bashrc
│                   └── .xinitrc      # X11 session startup
└── output/                           # Created after build
    └── images/
        ├── vortex86_a9100.img        # Bootable disk image
        ├── bzImage                   # Linux kernel
        ├── rootfs.ext2               # Root filesystem
        └── rootfs.tar                # Root filesystem tarball
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
