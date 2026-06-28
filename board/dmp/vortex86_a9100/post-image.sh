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

# Calculate partition boundaries
BOOT_START=2048
BOOT_SIZE_SECTORS=$((BOOT_PART_SIZE_MB * 2048))
BOOT_END=$((BOOT_START + BOOT_SIZE_SECTORS - 1))
ROOT_START=$((BOOT_END + 1))

# Create MBR partition table with fdisk
#   p1: ${BOOT_PART_SIZE_MB}MB ext2 boot partition (bootable)
#   p2: remaining space as root partition
fdisk "${IMAGES_DIR}/${IMAGE_NAME}" << FDISKEOF
o
n
p
1
${BOOT_START}
+${BOOT_PART_SIZE_MB}M
a
1
n
p
2
${ROOT_START}

w
FDISKEOF

# Map the image to loopback device with partition scan
LOOP_DEV=$(sudo losetup -f -P --show "${IMAGES_DIR}/${IMAGE_NAME}")
sleep 1

# Determine partition device names
case "${LOOP_DEV}" in
    /dev/loop*)
        BOOT_PART="${LOOP_DEV}p1"
        ROOT_PART="${LOOP_DEV}p2"
        ;;
    *)
        BOOT_PART="${LOOP_DEV}1"
        ROOT_PART="${LOOP_DEV}2"
        ;;
esac

# Verify partition devices exist
if [ ! -e "${BOOT_PART}" ]; then
    echo "WARNING: ${BOOT_PART} not found, trying kpartx..."
    sudo kpartx -a "${LOOP_DEV}" 2>/dev/null || true
    sleep 1
    BOOT_PART="/dev/mapper/$(basename ${LOOP_DEV})p1"
    ROOT_PART="/dev/mapper/$(basename ${LOOP_DEV})p2"
fi

# Format the first partition as ext2 for /boot
# NOTE: Disable modern ext2 features that GRUB's ext2 module doesn't support.
# GRUB 2's ext2 module predates metadata_csum, 64bit, dir_index, etc.
# Without these flags, GRUB produces 'chunk error' while reading large files.
echo "  Formatting boot partition (GRUB-compatible ext2)..."
sudo mkfs.ext2 -L "vortex-boot" -F -O ^metadata_csum,^64bit,^dir_index,^extents,^flex_bg,^resize_inode "${BOOT_PART}" 2>/dev/null || \
sudo mkfs.ext2 -L "vortex-boot" -F -O ^metadata_csum,^64bit,^dir_index,^extents,^flex_bg,^resize_inode "${BOOT_PART}"

# Format the second partition as ext4 for root
echo "  Formatting root partition..."
sudo mkfs.ext4 -L "vortex-root" -F "${ROOT_PART}" 2>/dev/null || \
sudo mkfs.ext4 -L "vortex-root" -F "${ROOT_PART}"

# Mount partitions and copy files
echo "  Copying rootfs..."
MOUNT_DIR=$(mktemp -d)

# Mount boot partition
sudo mount "${BOOT_PART}" "${MOUNT_DIR}"
sudo mkdir -p "${MOUNT_DIR}/boot"

# Copy kernel
sudo cp "${IMAGES_DIR}/bzImage" "${MOUNT_DIR}/boot/" 2>/dev/null || echo "WARNING: bzImage not found in images dir"

# Install GRUB
echo "  Installing GRUB..."
sudo mkdir -p "${MOUNT_DIR}/boot/grub"
sudo cp "${BOARD_DIR}/grub.cfg" "${MOUNT_DIR}/boot/grub/" 2>/dev/null || true

# Run grub-install with --force (needed for loop devices) and --removable (for USB boot)
echo "  Running grub-install on ${LOOP_DEV}..."
if sudo "${GRUB_INSTALL}" \
    --target=i386-pc \
    --boot-directory="${MOUNT_DIR}/boot" \
    --modules="part_msdos ext2" \
    --removable \
    --force \
    "${LOOP_DEV}" 2>&1; then
    echo "  GRUB installed successfully."
else
    echo "ERROR: grub-install failed! The image will not be bootable."
    echo "Trying alternative method: grub-bios-setup..."
    if which grub-bios-setup >/dev/null 2>&1; then
        sudo grub-bios-setup --force --directory="${MOUNT_DIR}/boot/grub/i386-pc" "${LOOP_DEV}" 2>&1 || true
    fi
    # Don't exit - let the image be created anyway, user can install GRUB manually
fi

# Verify the MBR was written
sudo dd if="${LOOP_DEV}" bs=512 count=1 2>/dev/null | strings | grep -q GRUB && \
    echo "  MBR verified: GRUB boot code present." || \
    echo "  WARNING: GRUB boot code not detected in MBR!"

sudo umount "${MOUNT_DIR}"

# Mount root partition and copy rootfs
echo "  Copying root filesystem..."
sudo mount "${ROOT_PART}" "${MOUNT_DIR}"

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
