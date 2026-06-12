#!/bin/bash
# post-image.sh - Create bootable disk image for Vortex86 A9100
#
# This script runs after the rootfs image is built.
# It creates a complete bootable disk image with partition table,
# GRUB bootloader installed, and the root filesystem.
#
# Arguments:
#   $1: output images directory
#   $2: staging directory
#   $3: target directory
#   $4: buildroot board directory

set -e

IMAGES_DIR="${1}"
STAGING_DIR="${2}"
TARGET_DIR="${3}"
BOARD_DIR="${4}"

echo "Post-image: Creating bootable disk image..."

# Configuration
IMAGE_NAME="vortex86_a9100.img"
IMAGE_SIZE_MB=512
BOOT_PART_SIZE_MB=50

# Only proceed if we have the required tools
if ! which grub-install >/dev/null 2>&1 && ! which grub2-install >/dev/null 2>&1; then
    echo "WARNING: grub-install not found. Creating raw rootfs image only."
    echo "You can manually install GRUB on your target media."
    exit 0
fi

# Locate grub tools
GRUB_INSTALL=$(which grub-install 2>/dev/null || which grub2-install 2>/dev/null)
GRUB_MKIMAGE=$(which grub-mkimage 2>/dev/null || which grub2-mkimage 2>/dev/null)

# Create the disk image
echo "  Creating ${IMAGE_SIZE_MB}MB disk image..."
dd if=/dev/zero of="${IMAGES_DIR}/${IMAGE_NAME}" bs=1M count=${IMAGE_SIZE_MB} status=progress

# Partition the disk image
echo "  Partitioning..."
ROOTFS_IMAGE="${IMAGES_DIR}/rootfs.ext2"

# Create a single partition
fdisk "${IMAGES_DIR}/${IMAGE_NAME}" << EOF
o
n
p
1
2048
+${BOOT_PART_SIZE_MB}M
a
n
p
2

t
2
83
w
EOF

# Map the image to loopback device
LOOP_DEV=$(sudo losetup -f --show "${IMAGES_DIR}/${IMAGE_NAME}")
sudo partprobe "${LOOP_DEV}" 2>/dev/null || true

# Wait for partitions to appear
sleep 1

# Format the first partition as ext2 for /boot
echo "  Formatting boot partition..."
sudo mkfs.ext2 -L "vortex-boot" "${LOOP_DEV}p1" 2>/dev/null || \
sudo mkfs.ext2 -L "vortex-boot" "${LOOP_DEV}p1"

# Format the second partition as ext4 for root
echo "  Formatting root partition..."
sudo mkfs.ext4 -L "vortex-root" "${LOOP_DEV}p2" 2>/dev/null || \
sudo mkfs.ext4 -L "vortex-root" "${LOOP_DEV}p2"

# Mount partitions and copy files
echo "  Copying rootfs..."
MOUNT_DIR=$(mktemp -d)

# Mount boot partition
sudo mount "${LOOP_DEV}p1" "${MOUNT_DIR}"
sudo mkdir -p "${MOUNT_DIR}/boot"

# Copy kernel
sudo cp "${IMAGES_DIR}/bzImage" "${MOUNT_DIR}/boot/" 2>/dev/null || echo "WARNING: bzImage not found in images dir"

# Install GRUB
echo "  Installing GRUB..."
sudo mkdir -p "${MOUNT_DIR}/boot/grub"
sudo cp "${BOARD_DIR}/grub.cfg" "${MOUNT_DIR}/boot/grub/" 2>/dev/null || true

# Run grub-install
sudo "${GRUB_INSTALL}" \
    --target=i386-pc \
    --boot-directory="${MOUNT_DIR}/boot" \
    --modules="bios part_msdos ext2 fat" \
    "${LOOP_DEV}" 2>&1 || echo "WARNING: GRUB install failed. You may need to install GRUB manually."

sudo umount "${MOUNT_DIR}"

# Mount root partition and copy rootfs
echo "  Copying root filesystem..."
sudo mount "${LOOP_DEV}p2" "${MOUNT_DIR}"

if [ -f "${IMAGES_DIR}/rootfs.ext2" ]; then
    # Extract rootfs from the ext2 image
    sudo mkdir -p "${MOUNT_DIR}"
    ROOTFS_MOUNT=$(mktemp -d)
    sudo mount -o loop "${IMAGES_DIR}/rootfs.ext2" "${ROOTFS_MOUNT}"
    sudo cp -a "${ROOTFS_MOUNT}"/* "${MOUNT_DIR}/"
    sudo umount "${ROOTFS_MOUNT}"
    rmdir "${ROOTFS_MOUNT}"
elif [ -f "${IMAGES_DIR}/rootfs.tar" ]; then
    sudo tar xf "${IMAGES_DIR}/rootfs.tar" -C "${MOUNT_DIR}"
else
    echo "WARNING: No rootfs image found at ${IMAGES_DIR}"
fi

# Clean up
sudo umount "${MOUNT_DIR}" 2>/dev/null || true
rmdir "${MOUNT_DIR}" 2>/dev/null || true
sudo losetup -d "${LOOP_DEV}" 2>/dev/null || true

echo "Post-image: Complete! Image at ${IMAGES_DIR}/${IMAGE_NAME}"
echo "  Write to media: dd if=${IMAGES_DIR}/${IMAGE_NAME} of=/dev/sdX bs=4M status=progress"
