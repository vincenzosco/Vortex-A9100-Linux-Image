# Vortex86 A9100 opkg Feed

This directory contains the opkg package feed for the Vortex86 A9100 Linux image.
The feed allows you to update the system over the internet using `opkg update` and
`opkg install vortex-os-update`.

## Feed Structure

```
opkg-feed/
├── feed/                    # Generated feed (deployed to GitHub Pages)
│   ├── Packages.gz          # Package index (opkg reads this)
│   ├── version.txt          # Current version
│   ├── deployed.txt         # Deployment timestamp
│   ├── vortex-kernel_*.ipk  # Kernel + modules package
│   ├── vortex-base-system_*.ipk # System configuration package
│   └── vortex-os-update_*.ipk   # Meta-package (depends on above)
├── packages/                # Control files for each package
│   ├── kernel/control/      # vortex-kernel metadata
│   ├── base-system/control/ # vortex-base-system metadata
│   └── os-update/control/   # vortex-os-update metadata
└── README.md                # This file
```

## Packages

| Package | Type | Contents |
|---------|------|----------|
| `vortex-kernel` | Binary | Linux kernel (`/boot/vmlinuz-*`) + kernel modules |
| `vortex-base-system` | Binary | System configs, init scripts, X11 config, Openbox theme |
| `vortex-os-update` | Meta | Depends on the above two — installs a full OS update |

## How to Generate the Feed

```bash
# After building the image with ./build.sh:
./scripts/create-opkg-feed.sh

# Specify a version:
./scripts/create-opkg-feed.sh --version 1.0.1

# Output to a custom directory:
./scripts/create-opkg-feed.sh --output ./my-feed
```

## How to Deploy to GitHub Pages

```bash
# Deploy the feed to the gh-pages branch:
./scripts/deploy-feed.sh

# Dry run to see what would be pushed:
./scripts/deploy-feed.sh --dry-run

# With a version tag:
./scripts/deploy-feed.sh --version 1.0.1
```

## GitHub Actions (Auto-Deploy)

The `.github/workflows/deploy-opkg-feed.yml` workflow automatically
builds and deploys the feed to GitHub Pages whenever changes are pushed
to the `main` branch that affect the `board/`, `configs/`, `scripts/`,
or `opkg-feed/` directories.

## Using on the Vortex86 A9100

Once the feed is deployed, on the target system:

```bash
# Update the package list from the GitHub Pages feed
opkg update

# List available vortex packages
opkg list | grep vortex

# Check what's installed
opkg list-installed | grep vortex

# Install a full OS update
opkg install vortex-os-update

# Or install individual packages
opkg install vortex-kernel
opkg install vortex-base-system
```

After installing `vortex-os-update`, reboot the system:
```bash
reboot
```

## Feed URL

The feed is hosted at:
`https://vincenzosco.github.io/Vortex-A9100-Linux-Image/opkg/`

This is configured in `/etc/opkg.conf` on the target system as:
```
src/gz vortex-stable https://vincenzosco.github.io/Vortex-A9100-Linux-Image/opkg/
```

## Building Packages Manually

If you want to create .ipk packages manually (without the scripts):

```bash
# Each .ipk contains:
#   debian-binary  (contains "2.0")
#   control.tar.gz (contains control file + optional scripts)
#   data.tar.gz    (contains the actual files to install)

# Create the control file:
mkdir -p control
cat > control/control << EOF
Package: my-package
Version: 1.0.0
Architecture: i486
Description: My package
EOF
tar --numeric-owner --group=0 --owner=0 -czf control.tar.gz -C control .

# Create the data files:
mkdir -p data/usr/bin
cp my-binary data/usr/bin/
tar --numeric-owner --group=0 --owner=0 -czf data.tar.gz -C data .

# Assemble:
echo "2.0" > debian-binary
ar rv my-package_1.0.0_i486.ipk debian-binary control.tar.gz data.tar.gz
```
