# Vortex86 A9100 Custom Linux Image Builder

> **Build a complete, bootable Linux distribution for the DM&P Vortex86 A9100**
> (i486-compatible SoC, 300MHz, FPU-less, embedded x86)

## Features

- **Kernel:** Linux 5.10 LTS (last kernel with proper i486 support)
- **C Library:** musl (lightweight, optimized for embedded systems)
- **Init System:** BusyBox init (fast, minimal, no systemd overhead)
- **Package Manager:** opkg (with local repository support)
- **GUI:** X.Org + Openbox — lightweight, usable desktop
- **Bootloader:** GRUB (supports booting from CF cards, IDE SSDs, USB)
- **Network:** DHCP client, SSH server, basic networking tools
- **Disk Image:** Pre-partitioned with GRUB, bootable on real hardware

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
- **CPU:** i486-compatible (FPU emulated)
- **RAM:** 64MB minimum (128MB+ recommended for GUI)
- **Storage:** 512MB+ (CF card, IDE SSD, or USB)
- **Display:** VGA-compatible (VESA framebuffer)
- **Network:** RDC R6040 or Realtek 8139 Ethernet (drivers included)

## Quick Start

### Clone and Build
```bash
# Clone the build system
git clone <your-repo-url> vortex-a9100-build
cd vortex-a9100-build

# Start the build
./build.sh
```

### Build Duration
- **First build:** 30–120 minutes (downloads and compiles everything)
- **Subsequent builds:** 5–20 minutes (only changed packages)

### Output Files
After the build completes, files are in `output/images/`:

| File | Description |
|------|-------------|
| `vortex86_a9100.img` | **Complete bootable disk image** (512MB) |
| `bzImage` | Linux kernel (standalone) |
| `rootfs.ext2` | Root filesystem image |
| `rootfs.tar` | Root filesystem tarball |

## Installation

### Automated Installer (Recommended)

The project includes an interactive installer script with built-in safety checks:

```bash
# Interactive mode - lists all devices, guides you through
sudo ./install.sh

# Direct to a specific device (with safety checks)
sudo ./install.sh /dev/sdc

# List available devices without installing
./install.sh --list

# Full help
./install.sh --help
```

The installer provides:
- **Interactive device selection** — shows all disks with size, model, and safety warnings
- **System disk blacklist** — refuses to write to your boot/root drive
- **Mount detection** — warns if the target is mounted and auto-unmounts it
- **Size validation** — checks the target is large enough for the image
- **MBR signature check** — verifies the image is actually bootable
- **Triple confirmation** — requires typing the device name AND "YES"
- **Progress display** — shows write speed and estimated time
- **Optional verification** — reads back and checksums the written data
- **Post-install guidance** — next steps and QEMU test command

### Manual Write (Advanced)

If you prefer to use `dd` directly:

```bash
# Write disk image to SD card / CF card / USB drive
# WARNING: Make sure /dev/sdX is your target device!
sudo dd if=output/images/vortex86_a9100.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

### Partition-Based Install (Alternative)

If you have an existing partition layout and only want to replace the rootfs:

```bash
# Mount your target root partition (e.g., /dev/sdb2)
sudo mount /dev/sdb2 /mnt

# Extract the rootfs tarball
sudo tar xf output/images/rootfs.tar -C /mnt

# Copy the kernel to your boot partition
sudo mount /dev/sdb1 /mnt/boot
sudo cp output/images/bzImage /mnt/boot/

# Clean up
sudo umount /mnt/boot /mnt
```

### Burn to CF Card (adapter via USB)
```bash
sudo ./install.sh /dev/sdb          # Using the installer (safer)
# or
sudo dd if=output/images/vortex86_a9100.img of=/dev/sdb bs=4M status=progress
```

## Testing

### Test in QEMU (No Hardware Required)
```bash
# Basic test
qemu-system-i386 -m 256 -hda output/images/vortex86_a9100.img

# With serial console (for debugging)
qemu-system-i386 -m 256 -hda output/images/vortex86_a9100.img -serial stdio

# With VGA display
qemu-system-i386 -m 256 -hda output/images/vortex86_a9100.img -vga std
```

## Usage Guide

### First Boot
1. Connect VGA display and PS/2 keyboard
2. Optionally connect serial console (ttyS0, 115200 baud)
3. Power on the Vortex86 A9100 board
4. GRUB boot menu appears (5 second timeout)
5. System boots to login prompt

### Login
- **User:** `root`
- **Password:** (empty — press Enter)
- **Serial login:** ttyS0 at 115200 baud
- **VGA login:** Press Enter on tty1

### Start the GUI
```bash
# At the command prompt, type:
startx
```

This launches:
- X.Org server (VESA framebuffer driver)
- Openbox window manager with dark theme
- Taskbar at bottom with clock
- Right-click desktop for application menu

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

# Upgrade all packages
opkg upgrade
```

> **Note:** You must set up your own opkg repository for binary packages.
> See `/etc/opkg.conf` for configuration. Alternatively, rebuild the image
> with `./build.sh menuconfig` to add packages permanently.

### Network Configuration
```bash
# DHCP (default - auto-starts)
# No configuration needed — eth0 gets IP via DHCP

# Static IP (edit /etc/network/interfaces)
ifconfig eth0 192.168.1.100 netmask 255.255.255.0 up
route add default gw 192.168.1.1

# Check network status
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
# System info
htop                    # Process monitor
free -m                 # Memory usage
df -h                   # Disk usage
uname -a                # Kernel version
cat /proc/cpuinfo       # CPU info
dmesg                   # Kernel log

# Files and editing
nano <file>             # Text editor
mc                      # File manager (if installed)
ls -la                  # List files

# Serial console (if connected)
cu -l /dev/ttyS0 -s 115200
```

## Customization

### Add/Remove Packages
```bash
# Open Buildroot menuconfig
./build.sh menuconfig

# Navigate to: Target Packages > ...
# Enable/disable packages as needed
# Save and exit
# Rebuild: ./build.sh clean && ./build.sh
```

### Change Kernel Configuration
```bash
# Open Linux kernel menuconfig
./build.sh linux-config

# Modify kernel options
# Save and exit
# Rebuild: ./build.sh
```

### Enable X11 Auto-Start
```bash
# Edit the overlay file before building:
# board/dmp/vortex86_a9100/overlay/etc/init.d/S60xorg

# Change:
#   AUTOSTART="no"
# To:
#   AUTOSTART="yes"
```

## Architecture Details

### Boot Process
1. BIOS loads GRUB from MBR
2. GRUB loads Linux kernel (`/boot/bzImage`)
3. Kernel boots with: `console=ttyS0,115200n8 console=tty0 root=/dev/sda1`
4. BusyBox init runs `/etc/init.d/rcS`
5. System services start: networking, SSH, optionally X11
6. Login prompt on serial console and VGA

### Partition Layout (512MB disk)
| Partition | Size | Type | Mount | Label |
|-----------|------|------|-------|-------|
| p1 (boot) | 50MB | ext2 | `/boot` | `vortex-boot` |
| p2 (root) | ~462MB | ext4 | `/` | `vortex-root` |

### Software Stack
```
┌──────────────────────────────────────────────┐
│  Openbox Window Manager (GUI)                    │
├──────────────────────────────────────────────┤
│  X.Org Server (VESA/fbdev drivers)           │
├──────────────────────────────────────────────┤
│  opkg (Package Manager) / SSH / Networking    │
├──────────────────────────────────────────────┤
│  BusyBox (init, shell, coreutils, udhcpc)     │
├──────────────────────────────────────────────┤
│  musl libc (lightweight C library)           │
├──────────────────────────────────────────────┤
│  Linux 5.10 LTS (patched for i486/CMPXCHG8B) │
├──────────────────────────────────────────────┤
│  GRUB Bootloader (i386-pc)                   │
└──────────────────────────────────────────────┘
```

## Troubleshooting

### Build Fails
- Check `output/build.log` for error details
- Ensure all dependencies are installed
- Try: `./build.sh distclean && ./build.sh`

### Kernel Panic / Boot Failure
- Check serial console output
- Try booting from GRUB "Verbose" mode
- Common issues: wrong root partition, missing driver

### GUI Won't Start
- The Vortex86 A9100 uses VESA framebuffer
- Try: `Xorg -configure` to generate an xorg.conf
- Check: `dmesg | grep -i vesa`
- Try the fbdev driver instead: edit `/etc/X11/xorg.conf`

### No Network
- Check: `dmesg | grep eth`
- Check: `ifconfig eth0`
- The RDC R6040 driver is included; if your board uses a different NIC,
  you'll need to enable it via `./build.sh linux-config`

## License
This build system includes components under various open-source licenses:
- Linux kernel: GPL v2
- Buildroot: GPL v2+
- BusyBox: GPL v2
- musl: MIT
- Openbox: MIT
- X.Org: MIT
- All other components: their respective licenses
