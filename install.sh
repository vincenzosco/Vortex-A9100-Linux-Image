#!/usr/bin/env bash
#===========================================================
# install.sh - Vortex86 A9100 Image Installer
#
# Safely writes the built disk image to a target storage
# device (hard drive, CF card, USB drive, SD card, etc.)
#
# Features:
#   - Interactive device selection with detailed info
#   - Multiple safety layers (blacklist, mounts, size check)
#   - Triple-confirmation before writing
#   - Progress display during write
#   - Post-write verification
#   - Supports direct image write and partition-based install
#
# Usage:
#   ./install.sh                          # Interactive mode
#   ./install.sh /dev/sdb                 # Direct to device
#   ./install.sh /dev/sdb --force         # Skip some checks
#   ./install.sh --list                   # List available devices
#   ./install.sh --help                   # Show help
#
# Requirements:
#   - Linux (native or WSL2)
#   - root/sudo access
#   - dd, lsblk, findmnt, fdisk
#===========================================================

set -euo pipefail

# === Configuration ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output/images"
DEFAULT_IMAGE="${OUTPUT_DIR}/vortex86_a9100.img"
ALTERNATIVE_IMAGE="${OUTPUT_DIR}/vortex86_a9100.img.gz"

# Colors (FE-safe, no -e needed)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

# === Helper Functions ===
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header(){ echo -e "\n${BOLD}${BLUE}=== $* ===${NC}\n"; }
step()  { echo -e "${CYAN}[STEP]${NC}  $*"; }

# System disk blacklist - NEVER allow writing to these
SYSTEM_DISKS_BLACKLIST=(
    "sda" "sdb"  # typical SATA boot drives
    "nvme0" "nvme1"
    "mmcblk0" "mmcblk1"
    "vda" "vdb"  # virtual disk
    "xdva" "xda" # Xen
)

# === Check root ===
check_root() {
    if [[ $EUID -ne 0 ]]; then
        # Try to re-exec with sudo
        if command -v sudo &>/dev/null; then
            warn "This script needs root privileges to write to block devices."
            info "Re-executing with sudo..."
            exec sudo "$0" "$@"
        else
            error "This script must be run as root (or with sudo)."
            error "Usage: sudo $0 [options]"
            exit 1
        fi
    fi
}

# === Show help ===
show_help() {
    cat << EOF
${BOLD}Vortex86 A9100 Image Installer${NC}

${BOLD}Description:${NC}
  Writes the built Vortex86 A9100 disk image to a target storage
  device (hard drive, CF card, USB drive, SD card, etc.) with
  extensive safety checks.

${BOLD}Usage:${NC}
  $0 [OPTIONS] [DEVICE]

${BOLD}Modes:${NC}
  Interactive     Run with no arguments - lists devices and guides you
  Direct          Pass a device path: $0 /dev/sdc
  Forced          Pass --force to skip non-critical checks
  List            $0 --list to show available devices

${BOLD}Options:${NC}
  -h, --help      Show this help
  -l, --list      List available storage devices and exit
  -f, --force     Skip blacklist check (use with extreme caution!)
  -c, --check     Only check if a device is suitable (no write)
      --image PATH Use a specific image file instead of the default
      --verify    Verify the write by reading back and checksumming
      --no-verify Skip verification

${BOLD}Examples:${NC}
  $0                          Interactive mode
  $0 /dev/sdc                 Write directly to /dev/sdc
  $0 --list                   Show available devices
  $0 /dev/sdc --verify        Write and verify
  $0 --image ../backup.img /dev/sdc  Use a specific image

${BOLD}Target devices:${NC}
  CF cards:       /dev/sdX (via USB adapter)
  USB drives:     /dev/sdX
  IDE/PATA disks: /dev/hdX or /dev/sdX
  SD cards:       /dev/mmcblkX
  Virtual:        /dev/vdX (QEMU/KVM)

${BOLD}Note:${NC}
  - The disk image MUST be 512MB or smaller than the target device
  - ALL DATA on the target device will be DESTROYED
  - The image contains GRUB bootloader + Linux kernel + rootfs
EOF
    exit 0
}

# === List available devices ===
list_devices() {
    header "Available Storage Devices"

    if ! command -v lsblk &>/dev/null; then
        error "lsblk not found. Install util-linux."
        exit 1
    fi

    echo -e "${BOLD}DISK  MODEL                        SIZE  TYPE   REMOVABLE  TRAN${NC}"
    echo "────  ─────                        ────  ────  ─────────  ────"

    lsblk -d -o NAME,SIZE,TYPE,TRAN,ROTA,RM,MODEL -n -e 7,11 2>/dev/null | \
    while IFS= read -r line; do
        local name size type tran rota rm model
        name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        type=$(echo "$line" | awk '{print $3}')
        tran=$(echo "$line" | awk '{print $4}')
        rota=$(echo "$line" | awk '{print $5}')
        rm=$(echo "$line" | awk '{print $6}')
        model=$(echo "$line" | cut -d' ' -f7-)

        local flag=""
        local color="${NC}"
        if [[ "$rm" == "1" ]]; then
            flag=" ⚡REMOVABLE"
            color="${GREEN}"
        fi
        if is_system_disk "$name"; then
            flag=" ⛔SYSTEM"
            color="${RED}"
        fi
        if is_mounted "/dev/$name"; then
            flag+=" 🔗MOUNTED"
            color="${YELLOW}"
        fi

        printf "${color}%-6s %-28s %-6s %-6s %s${NC}\n" \
            "/dev/$name" "${model:0:28}" "$size" "$tran" "$flag"
    done

    echo ""
    echo -e "${GREEN}  ⚡REMOVABLE${NC} = Safe to use (USB/SD/CF)"
    echo -e "${RED}  ⛔SYSTEM${NC}    = System/boot disk - DO NOT USE"
    echo -e "${YELLOW}  🔗MOUNTED${NC}   = Has mounted partitions"
    echo ""
}

# === Check if device is a system disk ===
is_system_disk() {
    local dev="$1"
    # Strip /dev/ prefix if present
    dev="${dev#/dev/}"
    # Strip partition numbers
    dev="${dev%%[0-9]*}"

    for blacklisted in "${SYSTEM_DISKS_BLACKLIST[@]}"; do
        if [[ "$dev" == "$blacklisted" ]]; then
            return 0
        fi
    done

    # Safety: also check if this device has the rootfs mounted
    if findmnt -n -o SOURCE / 2>/dev/null | grep -q "/dev/$dev"; then
        return 0
    fi

    return 1
}

# === Check if device is mounted ===
is_mounted() {
    local dev="$1"
    if findmnt --source "$dev" &>/dev/null; then
        return 0
    fi
    # Also check if any partition of this device is mounted
    if lsblk -n -o NAME "$dev" 2>/dev/null | tail -n +2 | while read -r part; do
        if findmnt --source "/dev/$part" &>/dev/null; then
            return 0
        fi
    done 2>/dev/null; then
        :
    fi
    return 1
}

# === Get device size in bytes ===
get_device_size() {
    local dev="$1"
    local size=0
    if command -v blockdev &>/dev/null; then
        size=$(blockdev --getsize64 "$dev" 2>/dev/null || echo 0)
    fi
    if [[ "$size" -eq 0 ]]; then
        size=$(lsblk -b -n -o SIZE "$dev" 2>/dev/null | head -1 || echo 0)
    fi
    echo "$size"
}

# === Find the image file ===
find_image() {
    local specified="$1"

    # If a specific image was provided, use it
    if [[ -n "$specified" ]]; then
        if [[ -f "$specified" ]]; then
            echo "$specified"
            return 0
        else
            error "Specified image not found: $specified"
            exit 1
        fi
    fi

    # Check default paths
    if [[ -f "$DEFAULT_IMAGE" ]]; then
        echo "$DEFAULT_IMAGE"
        return 0
    fi

    if [[ -f "$ALTERNATIVE_IMAGE" ]]; then
        echo "$ALTERNATIVE_IMAGE"
        return 0
    fi

    # Search in output directory
    if [[ -d "$OUTPUT_DIR" ]]; then
        local found
        found=$(find "$OUTPUT_DIR" -name "*.img" -o -name "*.img.gz" -o -name "*.iso" 2>/dev/null | head -5)
        if [[ -n "$found" ]]; then
            echo "$found" | head -1
            return 0
        fi
    fi

    return 1
}

# === Interactive device selection ===
select_device_interactive() {
    header "Select Target Device"
    echo "Available storage devices:"
    echo ""

    # Build device list (exclude loop, ram)
    local devices=()
    local device_names=()
    while IFS= read -r dev; do
        devices+=("$dev")
        local name size model rm
        name=$(echo "$dev" | awk '{print $1}')
        size=$(lsblk -d -n -o SIZE "/dev/$name" 2>/dev/null || echo "?")
        model=$(lsblk -d -n -o MODEL "/dev/$name" 2>/dev/null || echo "Unknown")
        rm=$(lsblk -d -n -o RM "/dev/$name" 2>/dev/null || echo "0")

        local label=""
        if [[ "$rm" == "1" ]]; then
            label="[REMOVABLE]"
        fi
        if is_system_disk "$name"; then
            label="[SYSTEM]"
        fi
        if is_mounted "/dev/$name"; then
            label+="[MOUNTED]"
        fi

        device_names+=("$label $name - ${model:0:30} (${size})")
    done < <(lsblk -d -n -o NAME -e 7,11 2>/dev/null)

    if [[ ${#devices[@]} -eq 0 ]]; then
        error "No block devices found!"
        exit 1
    fi

    # Display devices with numbers
    for i in "${!devices[@]}"; do
        local name="${devices[$i]}"
        name="${name#/dev/}"
        local size model rm
        size=$(lsblk -d -n -o SIZE "/dev/$name" 2>/dev/null || echo "?")
        model=$(lsblk -d -n -o MODEL "/dev/$name" 2>/dev/null || echo "Unknown")
        rm=$(lsblk -d -n -o RM "/dev/$name" 2>/dev/null || echo "0")

        local flag=""
        local color="${NC}"
        if [[ "$rm" == "1" ]]; then
            flag="⚡ REMOVABLE"
            color="${GREEN}"
            flag="${GREEN}⚡ REMOVABLE${NC}"
        fi
        if is_system_disk "$name"; then
            flag="${RED}⛔ SYSTEM DISK${NC}"
            color="${RED}"
        fi
        if is_mounted "/dev/$name"; then
            flag="${YELLOW}🔗 MOUNTED${NC}"
            color="${YELLOW}"
            flag="${YELLOW}🔗 MOUNTED${NC}"
        fi

        printf "  %2d)  ${color}/dev/%-8s${NC} %-6s  %-30s  %b\n" \
            $((i+1)) "$name" "$size" "${model:0:30}" "$flag"
    done

    echo ""
    read -r -p "Select device number (1-${#devices[@]}) or 'q' to quit: " selection

    if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
        echo "Aborted."
        exit 0
    fi

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#devices[@]} ]]; then
        error "Invalid selection."
        exit 1
    fi

    local idx=$((selection - 1))
    local selected_name="${devices[$idx]}"
    echo "/dev/$selected_name"
}

# === Validate device ===
validate_device() {
    local dev="$1"
    local force="${2:-false}"

    step "Validating target device: ${BOLD}$dev${NC}"

    # Check that device exists
    if [[ ! -b "$dev" ]]; then
        error "Device does not exist or is not a block device: $dev"
        error "Use '$0 --list' to see available devices."
        exit 1
    fi

    # Get the base device (strip partition number)
    local base_dev
    if [[ "$dev" =~ ^/dev/(mmcblk[0-9]+)p[0-9]+$ ]]; then
        base_dev="/dev/${BASH_REMATCH[1]}"
    elif [[ "$dev" =~ ^/dev/(nvme[0-9]+n[0-9]+)p[0-9]+$ ]]; then
        base_dev="/dev/${BASH_REMATCH[1]}"
    elif [[ "$dev" =~ ^/dev/(sd[a-z]+)[0-9]*$ ]]; then
        base_dev="/dev/${BASH_REMATCH[1]}"
    elif [[ "$dev" =~ ^/dev/(hd[a-z]+)[0-9]*$ ]]; then
        base_dev="/dev/${BASH_REMATCH[1]}"
    elif [[ "$dev" =~ ^/dev/(vd[a-z]+)[0-9]*$ ]]; then
        base_dev="/dev/${BASH_REMATCH[1]}"
    else
        # Assume it's already a base device
        base_dev="$dev"
    fi

    local dev_name="${base_dev#/dev/}"

    # Check: is this a system disk?
    if ! $force && is_system_disk "$dev_name"; then
        error "REFUSING to write to system disk: $base_dev"
        error "  This appears to be your system's boot/root disk."
        error "  Using --force would override this check (NOT recommended)."
        exit 1
    fi

    # Check: is it mounted?
    if is_mounted "$base_dev"; then
        error "Device $base_dev (or its partitions) is currently MOUNTED."
        error "Please unmount it first:"
        error "  sudo umount ${base_dev}*"
        # Try to unmount automatically
        warn "Attempting to unmount automatically..."
        sudo umount "${base_dev}"* 2>/dev/null || true
        if is_mounted "$base_dev"; then
            error "Could not unmount. Please unmount manually and try again."
            exit 1
        fi
        info "Successfully unmounted $base_dev"
    fi

    # Check: is this a partition (not the whole disk)?
    if [[ "$base_dev" != "$dev" ]]; then
        warn "You specified a partition ($dev), not the whole disk."
        warn "For a bootable image, write to the whole disk: $base_dev"
        read -r -p "Write to whole disk $base_dev instead? [Y/n]: " yn
        if [[ "$yn" =~ ^[Nn] ]]; then
            error "Aborted. Re-run with the whole disk device."
            exit 1
        fi
        dev="$base_dev"
    fi

    echo "$dev"
}

# === Validate image ===
validate_image() {
    local image="$1"

    step "Validating image: ${BOLD}$image${NC}"

    if [[ ! -f "$image" ]]; then
        error "Image file not found: $image"
        error "Have you built the image yet? Run: ./build.sh"
        exit 1
    fi

    # Check if it's gzipped
    local actual_image="$image"
    if [[ "$image" == *.gz ]]; then
        info "Image is gzip-compressed. Will decompress on-the-fly."
    fi

    # Get image size
    local image_size
    if [[ "$image" == *.gz ]]; then
        image_size=$(zcat "$image" 2>/dev/null | wc -c || echo 0)
    else
        image_size=$(stat -c%s "$image" 2>/dev/null || stat -f%z "$image" 2>/dev/null || echo 0)
    fi

    if [[ "$image_size" -eq 0 ]]; then
        warn "Could not determine image size."
    else
        local image_size_mb=$((image_size / 1024 / 1024))
        info "Image size: ${image_size_mb}MB ($(numfmt --to=iec "$image_size" 2>/dev/null || echo "${image_size} bytes"))"
    fi

    # Check that it's a valid disk image (has MBR/GPT signature)
    local magic
    if [[ "$image" == *.gz ]]; then
        magic=$(zcat "$image" 2>/dev/null | dd bs=512 count=1 2>/dev/null | xxd -l 4 -p 2>/dev/null || echo "")
    else
        magic=$(dd if="$image" bs=512 count=1 2>/dev/null | xxd -l 4 -p 2>/dev/null || echo "")
    fi

    if [[ "$magic" == "0000"* ]]; then
        # Check for MBR signature at offset 0x1FE
        local mbr_sig
        if [[ "$image" == *.gz ]]; then
            mbr_sig=$(zcat "$image" 2>/dev/null | dd bs=512 count=1 2>/dev/null | tail -c 2 | xxd -p 2>/dev/null)
        else
            mbr_sig=$(dd if="$image" bs=1 skip=510 count=2 2>/dev/null | xxd -p 2>/dev/null)
        fi
        if [[ "$mbr_sig" == "55aa" ]]; then
            info "Image has valid MBR boot signature ✓"
        else
            warn "Image does NOT have a valid MBR signature! Is this a bootable disk image?"
            warn "MBR signature: $mbr_sig (expected: 55aa)"
            read -r -p "Continue anyway? [y/N]: " yn
            if [[ ! "$yn" =~ ^[Yy] ]]; then
                echo "Aborted."
                exit 1
            fi
        fi
    else
        warn "Could not verify MBR signature (image may be empty or have GPT)."
    fi

    echo "$image"
    echo "$image_size"
}

# === Check device has enough space ===
check_device_space() {
    local dev="$1"
    local image_size="$2"

    local dev_size=$(get_device_size "$dev")

    if [[ "$dev_size" -eq 0 ]]; then
        warn "Could not determine device size. Skipping size check."
        return 0
    fi

    local dev_size_mb=$((dev_size / 1024 / 1024))
    local image_size_mb=$((image_size / 1024 / 1024))

    info "Device: ${dev} = ${dev_size_mb}MB"
    info "Image:              ${image_size_mb}MB"

    if [[ "$dev_size" -lt "$image_size" ]]; then
        error "Target device is TOO SMALL!"
        error "  Device: ${dev_size_mb}MB"
        error "  Image:  ${image_size_mb}MB"
        error "  Need at least ${image_size_mb}MB"
        exit 1
    fi

    if [[ "$dev_size" -gt $((image_size * 10)) ]]; then
        # Device is much larger than image - warn but allow
        warn "Device is ${dev_size_mb}MB but image is only ${image_size_mb}MB."
        warn "You'll have ${dev_size_mb - image_size_mb}MB of unpartitioned space after writing."
        info "You can resize the partition later with: sudo parted /dev/sdX resizepart 2 100%"
    fi

    info "Size check passed ✓"
}

# === Final confirmation ===
confirm_write() {
    local dev="$1"
    local image="$2"
    local image_size="$3"
    local dev_size=$(get_device_size "$dev")
    local dev_size_mb=$((dev_size / 1024 / 1024))
    local image_size_mb=$((image_size / 1024 / 1024))

    header "!!! DESTRUCTIVE OPERATION WARNING !!!"

    echo -e "${RED}${BOLD}"
    echo "  You are about to PERMANENTLY DESTROY ALL DATA on:"
    echo ""
    echo "    Device:   ${BOLD}${dev}${NC}${RED}${BOLD}"
    echo "    Size:     ${dev_size_mb}MB${NC}"
    echo ""
    lsblk -d -o MODEL,VENDOR,TRAN,SIZE "$dev" 2>/dev/null | tail -n +2
    echo ""
    echo -e "${YELLOW}  Writing image:${NC}"
    echo "    $(basename "$image") (${image_size_mb}MB)"
    echo ""

    # Show device info in a table
    echo -e "${BOLD}Device details:${NC}"
    echo "  Path:            $dev"
    echo "  Capacity:        ${dev_size_mb}MB ($(numfmt --to=iec "$dev_size" 2>/dev/null || echo "$dev_size bytes"))"
    echo "  Image size:      ${image_size_mb}MB"
    echo "  After write:     $((dev_size_mb - image_size_mb))MB unpartitioned"
    echo ""

    # Check if this looks like the right device
    local model
    model=$(lsblk -d -n -o MODEL "$dev" 2>/dev/null | head -1)
    local tran
    tran=$(lsblk -d -n -o TRAN "$dev" 2>/dev/null | head -1)

    echo -e "${BOLD}Target info:${NC}"
    echo "  Model:    ${model:-Unknown}"
    echo "  Interface: ${tran:-Unknown}"
    echo ""

    echo -e "${RED}${BOLD}This operation CANNOT be undone!${NC}"
    echo ""

    # Multi-step confirmation
    read -r -p "Type the device name to confirm (e.g., ${dev#/dev/}): " confirm_name
    if [[ "/dev/$confirm_name" != "$dev" ]]; then
        error "Device name mismatch. Aborted."
        exit 1
    fi

    read -r -p "Type 'YES' to verify you want to destroy all data on ${dev}: " confirm_yes
    if [[ "$confirm_yes" != "YES" ]]; then
        echo "Aborted."
        exit 1
    fi

    echo ""
    info "Confirmation accepted. Proceeding..."
}

# === Write the image ===
write_image() {
    local dev="$1"
    local image="$2"
    local do_verify="${3:-false}"

    header "Writing Image to ${dev}"

    # Flush any cached writes to the device
    blockdev --flushbufs "$dev" 2>/dev/null || true

    # Determine dd options
    local dd_opts=(
        "if=$image"
        "of=$dev"
        "bs=4M"
        "status=progress"
        "conv=fsync"
    )

    # Add O_DIRECT for better performance (if supported)
    if blockdev --getopt "$dev" 2>/dev/null | grep -q "RO"; then
        :
    else
        dd_opts+=("oflag=direct")
    fi

    step "Writing ${image} to ${dev}..."
    echo ""

    local start_time=$SECONDS

    if [[ "$image" == *.gz ]]; then
        # Compressed image - pipe through gunzip
        info "Decompressing and writing in one pass..."
        sudo bash -c "zcat '$image' | dd of='$dev' bs=4M status=progress conv=fsync oflag=direct" || {
            error "Write failed!"
            exit 1
        }
    else
        # Direct write
        sudo dd "${dd_opts[@]}" || {
            # Retry without O_DIRECT if it failed
            warn "Direct write failed, retrying without O_DIRECT..."
            sudo dd if="$image" of="$dev" bs=4M status=progress conv=fsync || {
                error "Write failed!"
                exit 1
            }
        }
    fi

    local elapsed=$((SECONDS - start_time))
    local dev_size=$(get_device_size "$dev")
    local dev_size_mb=$((dev_size / 1024 / 1024))
    local speed=$((dev_size_mb / (elapsed > 0 ? elapsed : 1)))

    echo ""
    info "Write complete in ${elapsed}s (${speed}MB/s)"
}

# === Verify the write ===
verify_write() {
    local dev="$1"
    local image="$2"

    header "Verifying Write"

    step "Flushing device buffers..."
    sudo blockdev --flushbufs "$dev" 2>/dev/null || true
    sync
    sleep 1

    step "Reading back from ${dev} and computing checksums..."
    echo ""

    local image_checksum
    local dev_checksum

    if [[ "$image" == *.gz ]]; then
        info "Image is compressed. Computing SHA256 of decompressed image..."
        image_checksum=$(zcat "$image" | sha256sum | awk '{print $1}')
        info "Reading back from device..."
        dev_checksum=$(sudo dd if="$dev" bs=4M count=$(zcat "$image" 2>/dev/null | wc -c | awk '{print int($1/4194304)+1}') 2>/dev/null | sha256sum | awk '{print $1}')
    else
        info "Computing SHA256 of image file..."
        image_checksum=$(sha256sum "$image" | awk '{print $1}')
        local image_size=$(stat -c%s "$image" 2>/dev/null || stat -f%z "$image" 2>/dev/null || echo 0)
        local count=$(( (image_size / 4194304) + 1 ))
        info "Reading ${count} blocks back from device..."
        dev_checksum=$(sudo dd if="$dev" bs=4M count=$count 2>/dev/null | sha256sum | awk '{print $1}')
    fi

    echo ""
    echo -e "${BOLD}Image checksum:${NC}  $image_checksum"
    echo -e "${BOLD}Device checksum:${NC} $dev_checksum"

    if [[ "$image_checksum" == "$dev_checksum" ]]; then
        echo ""
        info "${GREEN}✓ VERIFICATION PASSED - Written data matches the image exactly${NC}"
        return 0
    else
        echo ""
        warn "${RED}✗ VERIFICATION FAILED - Written data does NOT match the image${NC}"
        warn "  The device may be faulty or the write was interrupted."
        warn "  Try writing again to a different device."
        return 1
    fi
}

# === Post-write info ===
show_post_write_info() {
    local dev="$1"

    header "Installation Complete!"

    echo -e "${GREEN}${BOLD}The Vortex86 A9100 image has been written to ${dev}${NC}"
    echo ""

    echo -e "${BOLD}Next steps:${NC}"
    echo ""
    echo "  1. Safely remove the device:"
    echo "     sync && sudo umount ${dev}* 2>/dev/null"
    echo ""
    echo "  2. Insert the CF card / connect the drive to your Vortex86 A9100"
    echo ""
    echo "  3. Connect:"
    echo "     - Serial console (ttyS0, 115200 baud)"
    echo "     - VGA display + PS/2 keyboard"
    echo ""
    echo "  4. Power on the Vortex86 A9100"
    echo ""
    echo "  5. The system should boot to GRUB, then to the login prompt"
    echo "     Login: root (no password)"
    echo "     Start GUI: startx"
    echo ""

    if command -v qemu-system-i386 &>/dev/null; then
        echo -e "${BOLD}Test in QEMU before deploying to hardware:${NC}"
        echo "  qemu-system-i386 -m 256 -hda ${dev} -serial stdio"
        echo ""
    fi
}

# === Main ===
main() {
    local target_dev=""
    local force=false
    local do_verify=true
    local specified_image=""
    local list_only=false
    local check_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                ;;
            -l|--list)
                list_only=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -c|--check)
                check_only=true
                shift
                ;;
            --image)
                specified_image="$2"
                shift 2
                ;;
            --verify)
                do_verify=true
                shift
                ;;
            --no-verify)
                do_verify=false
                shift
                ;;
            -*)
                error "Unknown option: $1"
                echo "Use --help for usage."
                exit 1
                ;;
            *)
                if [[ -z "$target_dev" ]]; then
                    target_dev="$1"
                else
                    error "Unexpected argument: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # List mode
    if $list_only; then
        list_devices
        exit 0
    fi

    # Banner
    header "Vortex86 A9100 Image Installer"

    # Check root
    check_root "$@"

    # Check required tools
    for cmd in dd lsblk findmnt; do
        if ! command -v "$cmd" &>/dev/null; then
            error "Required tool not found: $cmd"
            exit 1
        fi
    done

    # Find the image
    local image
    image=$(find_image "$specified_image") || {
        error "No disk image found!"
        error ""
        error "Expected at: ${DEFAULT_IMAGE}"
        error "Have you built the image? Run: ./build.sh"
        error "Or specify a custom path: $0 --image /path/to/image.img /dev/sdX"
        exit 1
    }
    info "Using image: ${BOLD}$image${NC}"

    # Validate image
    local image_info
    image_info=$(validate_image "$image")
    local actual_image
    local image_size
    actual_image=$(echo "$image_info" | head -1)
    image_size=$(echo "$image_info" | tail -1)

    # Select or validate target device
    if [[ -z "$target_dev" ]]; then
        list_devices
        echo ""
        target_dev=$(select_device_interactive)
    fi

    target_dev=$(validate_device "$target_dev" "$force")
    check_device_space "$target_dev" "$image_size"

    if $check_only; then
        info "Check passed. Device is suitable for installation."
        exit 0
    fi

    # Show device info in detail
    header "Installation Summary"
    echo -e "  ${BOLD}Image:${NC}         $actual_image ($(numfmt --to=iec "$image_size" 2>/dev/null || echo "$image_size bytes"))"
    echo -e "  ${BOLD}Target device:${NC}  $target_dev"
    echo -e "  ${BOLD}Size:${NC}          $(numfmt --to=iec "$(get_device_size "$target_dev")" 2>/dev/null || echo "?")"
    echo ""

    # Confirm
    confirm_write "$target_dev" "$actual_image" "$image_size"

    # Write
    write_image "$target_dev" "$actual_image" "$do_verify"

    # Verify
    if $do_verify; then
        echo ""
        read -r -p "Verify the write (read-back checksum comparison)? [Y/n]: " verify_choice
        if [[ ! "$verify_choice" =~ ^[Nn] ]]; then
            verify_write "$target_dev" "$actual_image"
        fi
    fi

    # Show post-write info
    show_post_write_info "$target_dev"

    # Eject suggestion
    echo -e "${BOLD}To eject safely:${NC}"
    echo "  sync"
    if command -v eject &>/dev/null; then
        echo "  sudo eject $target_dev"
    fi
    echo ""
}

main "$@"
