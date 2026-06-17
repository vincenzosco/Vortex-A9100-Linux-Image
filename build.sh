#!/bin/bash
#===========================================================
# build.sh - Vortex86 A9100 Custom Linux Image Builder
#
# This script builds a complete bootable Linux image for
# the DM&P Vortex86 A9100 (i486-compatible) SoC.
#
# Requirements:
#   - Linux environment (native or WSL2)
#   - Build dependencies (gcc, make, bison, flex, etc.)
#   - sudo access (for loop device management in post-image)
#   - ~5GB free disk space
#
# Usage:
#   ./build.sh              # Full build
#   ./build.sh clean        # Clean build artifacts
#   ./build.sh menuconfig   # Configure Buildroot
#   ./build.sh linux-config # Configure Linux kernel
#   ./build.sh help         # Show this help
#===========================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDROOT_DIR="${SCRIPT_DIR}/buildroot"
OUTPUT_DIR="${BUILDROOT_DIR}/output"  # Buildroot's actual output directory
BUILDROOT_VERSION="2023.02.11"  # Final 2023.02.x LTS release (EOL)
BUILDROOT_URL="https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.gz"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step()  { echo -e "${BLUE}[STEP]${NC}  $1"; }

# Show help
show_help() {
    cat << EOF
Vortex86 A9100 Linux Image Builder

Usage: ./build.sh [command]

Commands:
  (none)       Full build (download, configure, compile, package)
  clean        Remove all build artifacts
  distclean    Remove everything including downloaded sources
  menuconfig   Open Buildroot configuration menu
  linux-config Open Linux kernel configuration menu
  busybox-config Open BusyBox configuration menu
  help         Show this help

Steps performed by full build:
  1. Check system dependencies
  2. Download Buildroot (${BUILDROOT_VERSION})
  3. Apply custom board configuration
  4. Cross-compile toolchain, kernel, and all packages
  5. Create bootable disk image with GRUB

Output:
  ${OUTPUT_DIR}/images/vortex86_a9100.img  - Bootable disk image
  ${OUTPUT_DIR}/images/bzImage             - Linux kernel
  ${OUTPUT_DIR}/images/rootfs.ext2         - Root filesystem image
  ${OUTPUT_DIR}/images/rootfs.tar          - Root filesystem tarball
EOF
}

# Step 1: Check system dependencies
check_dependencies() {
    step "Checking system dependencies..."

    local missing=""
    local cmds=(
        "gcc" "g++" "make" "bison" "flex" "bc"
        "wget" "tar" "gzip" "bzip2" "xz" "patch"
        "sed" "awk" "find" "file" "cpio" "unzip"
        "rsync" "which" "python3"
    )

    for cmd in "${cmds[@]}"; do
        if ! which "$cmd" >/dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done

    # Check for development libraries (needed by Buildroot packages)
    # uuid-dev + libblkid-dev: required by host-e2fsprogs
    if [ ! -f /usr/include/uuid/uuid.h ] && [ ! -f /usr/include/uuid.h ]; then
        warn "uuid-dev not found (needed by host-e2fsprogs)"
        warn "  Install with: sudo apt-get install uuid-dev"
    fi
    if [ ! -f /usr/include/blkid/blkid.h ] && [ ! -f /usr/include/blkid.h ]; then
        warn "libblkid-dev not found (needed by host-e2fsprogs)"
        warn "  Install with: sudo apt-get install libblkid-dev"
    fi
    # libcrypt-dev: required by host-mkpasswd (for <crypt.h>)
    if [ ! -f /usr/include/crypt.h ]; then
        warn "libcrypt-dev not found (needed by host-mkpasswd)"
        warn "  Install with: sudo apt-get install libcrypt-dev"
    fi

    # Check for QEMU (useful for testing but not required)
    if which qemu-system-i386 >/dev/null 2>&1; then
        info "QEMU found - you can test the image with: qemu-system-i386 -hda output/images/vortex86_a9100.img"
    fi

    if [ -n "$missing" ]; then
        error "Missing required dependencies:$missing"
        echo "  On Debian/Ubuntu:"
        echo "    sudo apt-get install -y build-essential bison flex bc wget tar gzip bzip2 xz-utils \\"
        echo "      patch sed gawk findutils file cpio unzip rsync python3"
        echo "  On Arch Linux:"
        echo "    sudo pacman -S --needed base-devel bison flex bc wget tar gzip bzip2 xz patch \\"
        echo "      sed gawk findutils file cpio unzip rsync python"
        exit 1
    fi

    info "All dependencies satisfied!"
}

# Step 2: Download Buildroot
download_buildroot() {
    step "Downloading Buildroot ${BUILDROOT_VERSION}..."

    # Verify the existing buildroot directory is complete (has Makefile + configs)
    # This catches corrupted/partial directories left behind by failed cleanups
    if [ -d "${BUILDROOT_DIR}" ]; then
        if [ -f "${BUILDROOT_DIR}/Makefile" ] && [ -d "${BUILDROOT_DIR}/configs" ]; then
            info "Buildroot directory already exists. Skipping download."
            info "  To re-download, run: rm -rf ${BUILDROOT_DIR} && ./build.sh"
            return
        else
            warn "Buildroot directory is incomplete or corrupted. Re-downloading..."
            rm -rf "${BUILDROOT_DIR}" 2>/dev/null || true
            if [ -d "${BUILDROOT_DIR}" ]; then
                warn "Could not remove the corrupted directory (likely a WSL path length issue)."
                warn "Please delete it manually, then re-run:"
                warn "  rm -rf \"${BUILDROOT_DIR}\""
                exit 1
            fi
        fi
    fi

    local tarball="/tmp/buildroot-${BUILDROOT_VERSION}.tar.gz"

    if [ ! -f "$tarball" ]; then
        info "Downloading from ${BUILDROOT_URL}..."
        wget -O "$tarball" "${BUILDROOT_URL}" || {
            error "Failed to download Buildroot. Check internet connection."
            exit 1
        }
    fi

    info "Extracting..."
    tar xf "$tarball" -C "${SCRIPT_DIR}"
    mv "${SCRIPT_DIR}/buildroot-${BUILDROOT_VERSION}" "${BUILDROOT_DIR}"
    info "Buildroot extracted to ${BUILDROOT_DIR}"
}

# Step 3: Apply custom board configuration
apply_board_config() {
    step "Applying Vortex86 A9100 board configuration..."

    local config_src="${SCRIPT_DIR}/configs/vortex86_a9100_defconfig"
    local config_dst="${BUILDROOT_DIR}/configs/vortex86_a9100_defconfig"

    if [ ! -f "$config_src" ]; then
        error "Board configuration not found: ${config_src}"
        exit 1
    fi

    cp "$config_src" "$config_dst"

    # Create board directory symlink
    local board_src="${SCRIPT_DIR}/board/dmp"
    local board_dst="${BUILDROOT_DIR}/board/dmp"

    if [ -d "$board_dst" ]; then
        rm -rf "$board_dst"
    fi

    mkdir -p "${BUILDROOT_DIR}/board"
    cp -r "$board_src" "$board_dst"

    # Patches are in board/dmp/vortex86_a9100/patches/ and referenced
    # via BR2_GLOBAL_PATCH_DIR in the defconfig. No additional copy needed.

    info "Board configuration applied!"
}

# Step 4: Configure Buildroot
configure_buildroot() {
    step "Configuring Buildroot..."

    cd "${BUILDROOT_DIR}"

    # Clean any stale .config before applying the new defconfig
    # This avoids legacy option errors when the defconfig changes
    if [ -f ".config" ]; then
        warn "Removing stale configuration..."
        rm -f .config
    fi
    # Also clean any savedefconfig from previous runs
    if [ -f "defconfig" ]; then
        rm -f defconfig
    fi

    make vortex86_a9100_defconfig || {
        error "Failed to configure Buildroot"
        cd "${SCRIPT_DIR}"
        exit 1
    }

    info "Buildroot configured for Vortex86 A9100!"
    cd "${SCRIPT_DIR}"
}

# Step 5: Build
build_image() {
    step "Building Vortex86 A9100 image..."
    info "This will take a LONG time (30-120 minutes depending on system)."
    info "Buildroot will cross-compile: toolchain, kernel, libraries, and all packages."

    cd "${BUILDROOT_DIR}"

    # Use all available CPU cores
    export BR2_JLEVEL=$(nproc 2>/dev/null || echo 4)
    info "Using ${BR2_JLEVEL} parallel jobs"

    # Allow configure scripts to run as root (needed in WSL/containers)
    export FORCE_UNSAFE_CONFIGURE=1

    # Remove irrelevant or1k (OpenRISC) GCC patches that fail on GCC 11.4.0
    # These patches try to create files that already exist in GCC 11.4.0 source
    # and are not needed for our x86 (i486) build.
    GCC_PATCH_DIR="${BUILDROOT_DIR}/package/gcc/11.4.0"
    for patch in 0001-or1k-Add-mcmodel 0002-or1k-Use-cmodel 0003-gcc-define-_REENTRANT 0006-or1k-Only-define; do
        rm -f "${GCC_PATCH_DIR}/${patch}"*.patch 2>/dev/null || true
    done
    info "Removed irrelevant or1k GCC patches"

    # Sanitize PATH: filter out entries with spaces/tabs/newlines
    # Buildroot's dependency check rejects paths with these characters.
    # WSL typically appends Windows paths like /mnt/c/Program Files/...
    OLD_IFS="$IFS"
    IFS=':'
    NEW_PATH=""
    for p in $PATH; do
        case "$p" in
            *[\ \	\"]*) ;;
            *) NEW_PATH="${NEW_PATH}:${p}" ;;
        esac
    done
    IFS="$OLD_IFS"
    export PATH="${NEW_PATH#:}"
    info "Sanitized PATH for Buildroot compatibility"

    # Ensure host-e2fsprogs can find system uuid/blkid libraries via pkg-config
    # Buildroot's configure runs with PKG_CONFIG_LIBDIR pointing to its own host dir,
    # so system .pc files (uuid, blkid) are not found unless linked in.
    HOST_PKG_DIR="${OUTPUT_DIR}/host/lib/pkgconfig"
    mkdir -p "${HOST_PKG_DIR}"
    for pc in uuid blkid; do
        # Find the system .pc file
        SYS_PC=$(find /usr -name "${pc}.pc" -print -quit 2>/dev/null || true)
        if [ -n "$SYS_PC" ] && [ ! -f "${HOST_PKG_DIR}/${pc}.pc" ]; then
            ln -sf "$SYS_PC" "${HOST_PKG_DIR}/${pc}.pc"
            info "Linked ${pc}.pc into Buildroot pkgconfig"
        fi
    done

    # Create GCC wrapper to force C17 standard for all host builds.
    # GCC 15 defaults to C23, which breaks many Buildroot packages (autotools,
    # gnulib, GMP, etc.) that rely on pre-C23 behavior:
    #   - 'void g(){}' meaning "unspecified parameters" (C23 treats as "no params")
    #   - 'bool' as a typedef (C23 makes it a keyword)
    #   - 'nodiscard' attribute (C23 makes it a keyword)
    # Target (cross-compiler) builds are not affected.
    GCC_WRAPPER="${SCRIPT_DIR}/.gcc-wrap"
    GXX_WRAPPER="${SCRIPT_DIR}/.g++-wrap"
    rm -f "${GCC_WRAPPER}" "${GXX_WRAPPER}"
    cat > "${GCC_WRAPPER}" << 'WRAPEOF'
#!/bin/bash
# Force C17 to avoid C23 issues (bool keyword, nodiscard, void(), etc.)
# Downgrade incompatible-pointer-types from error to warning because
# GCC 15+ promotes this to error, breaking older code (e.g. host-gcc libiberty)
exec gcc -std=gnu17 -Wno-error=incompatible-pointer-types "$@"
WRAPEOF
    cat > "${GXX_WRAPPER}" << 'WRAPEOF'
#!/bin/bash
exec g++ -std=gnu++17 -Wno-error=incompatible-pointer-types "$@"
WRAPEOF
    chmod +x "${GCC_WRAPPER}" "${GXX_WRAPPER}"
    export HOSTCC="${GCC_WRAPPER}"
    export HOSTCXX="${GXX_WRAPPER}"
    info "Set HOSTCC/HOSTCXX wrappers for C17 host build compatibility"

    # Patch ncurses.mk to generate terminfo in staging after install.
    # During cross-compilation, the host tic (terminfo compiler) may not run
    # during 'make install', leaving staging without compiled terminfo entries.
    # This causes NCURSES_TARGET_CLEANUP_TERMINFO to fail when it tries to
    # copy terminfo from staging to target.
    NCURSES_MK="${BUILDROOT_DIR}/package/ncurses/ncurses.mk"
    if ! grep -q 'NCURSES_GENERATE_TERMINFO_STAGING' "${NCURSES_MK}" 2>/dev/null; then
        sed -i '/^define NCURSES_TARGET_CLEANUP_TERMINFO$/i\
# Generate terminfo in staging explicitly (host tic may not run during cross-compile)\
define NCURSES_GENERATE_TERMINFO_STAGING\
\tmkdir -p $(STAGING_DIR)/usr/share/terminfo\
\t$(HOST_DIR)/bin/tic -o $(STAGING_DIR)/usr/share/terminfo -x $(@D)/misc/terminfo.src\
endef\
NCURSES_POST_INSTALL_STAGING_HOOKS += NCURSES_GENERATE_TERMINFO_STAGING\
' "${NCURSES_MK}"
        info "Patched ncurses.mk: generate terminfo in staging via host tic"
    else
        info "ncurses.mk already patched for terminfo generation"
    fi

    # Use PIPESTATUS to catch make's exit code (not tee's)
    set +e
    make 2>&1 | tee "${OUTPUT_DIR}/build.log"
    local make_exit=${PIPESTATUS[0]}
    set -e

    if [ $make_exit -ne 0 ]; then
        error "Build failed! Check ${OUTPUT_DIR}/build.log for details."
        error "Common issues:"
        error "  - Missing dependencies (run ./build.sh again after installing them)"
        error "  - Out of disk space (need at least 5GB free)"
        error "  - Network issues (Buildroot downloads many source packages)"
        cd "${SCRIPT_DIR}"
        exit 1
    fi

    cd "${SCRIPT_DIR}"
    info "Build completed successfully!"
}

# Step 6: Create final disk image
create_disk_image() {
    step "Creating bootable disk image..."

    cd "${BUILDROOT_DIR}"

    # Run the post-image script
    if [ -f "board/dmp/vortex86_a9100/post-image.sh" ]; then
        bash "board/dmp/vortex86_a9100/post-image.sh" \
            "${OUTPUT_DIR}/images" \
            "${BUILDROOT_DIR}/staging" \
            "${BUILDROOT_DIR}/target" \
            "${BUILDROOT_DIR}/board/dmp/vortex86_a9100" || {
            warn "Post-image script failed. Raw images are still available."
        }
    fi

    cd "${SCRIPT_DIR}"
}

# Show results
show_results() {
    info "========================================"
    info "Build Complete!"
    info "========================================"
    echo ""
    info "Output files in ${OUTPUT_DIR}/images/:"
    echo ""
    echo "  vortex86_a9100.img  - Complete bootable disk image"
    echo "  bzImage             - Linux kernel (if needed separately)"
    echo "  rootfs.ext2         - Root filesystem image"
    echo "  rootfs.tar          - Root filesystem tarball"
    echo ""
    echo "To write to SD card or USB:"
    echo "  sudo dd if=${OUTPUT_DIR}/images/vortex86_a9100.img of=/dev/sdX bs=4M status=progress"
    echo "  sync"
    echo ""
    echo "To test in QEMU:"
    echo "  qemu-system-i386 -m 256 -hda ${OUTPUT_DIR}/images/vortex86_a9100.img"
    echo ""
    echo "To test in QEMU with serial console:"
    echo "  qemu-system-i386 -m 256 -hda ${OUTPUT_DIR}/images/vortex86_a9100.img -serial stdio"
    echo ""
}

# Clean
do_clean() {
    step "Cleaning build artifacts..."
    if [ -d "${BUILDROOT_DIR}" ]; then
        cd "${BUILDROOT_DIR}"
        make clean 2>/dev/null || true
        cd "${SCRIPT_DIR}"
        warn "Source code is preserved. Run 'distclean' to remove everything."
    fi
    info "Clean complete!"
}

do_distclean() {
    step "Performing full clean..."

    if [ -d "${BUILDROOT_DIR}" ]; then
        cd "${BUILDROOT_DIR}"
        make distclean 2>/dev/null || true
        cd "${SCRIPT_DIR}"

        # Robust deletion: use find to delete from deepest paths first
        # This avoids issues with Windows MAX_PATH on WSL (deeply nested
        # Buildroot output directories can exceed 260 chars)
        if ! rm -rf "${BUILDROOT_DIR}" 2>/dev/null; then
            warn "Standard removal failed, trying deep cleanup..."
            # Delete deepest files first, then directories
            find "${BUILDROOT_DIR}" -depth -type f -delete 2>/dev/null || true
            find "${BUILDROOT_DIR}" -depth -type d -empty -delete 2>/dev/null || true
            rm -rf "${BUILDROOT_DIR}" 2>/dev/null || true
        fi
    fi

    if [ -d "${BUILDROOT_DIR}" ]; then
        warn "Could not fully remove ${BUILDROOT_DIR}"
        warn "Please delete it manually: rm -rf ${BUILDROOT_DIR}"
    fi

    info "Distclean complete!"
}

# Menu config targets
do_menuconfig() {
    if [ ! -d "${BUILDROOT_DIR}" ]; then
        download_buildroot
        apply_board_config
        configure_buildroot
    fi
    cd "${BUILDROOT_DIR}"
    make menuconfig
    make savedefconfig
    cp "defconfig" "${SCRIPT_DIR}/configs/vortex86_a9100_defconfig"
    info "Configuration saved to configs/vortex86_a9100_defconfig"
    cd "${SCRIPT_DIR}"
}

do_linux_config() {
    if [ ! -d "${BUILDROOT_DIR}" ]; then
        error "Buildroot not set up. Run ./build.sh first."
        exit 1
    fi
    cd "${BUILDROOT_DIR}"
    make linux-menuconfig
    cd "${SCRIPT_DIR}"
}

do_busybox_config() {
    if [ ! -d "${BUILDROOT_DIR}" ]; then
        error "Buildroot not set up. Run ./build.sh first."
        exit 1
    fi
    cd "${BUILDROOT_DIR}"
    make busybox-menuconfig
    cd "${SCRIPT_DIR}"
}

# Main
main() {
    local cmd="${1:-build}"

    mkdir -p "${OUTPUT_DIR}"

    case "$cmd" in
        build)
            check_dependencies
            download_buildroot
            apply_board_config
            configure_buildroot
            build_image
            create_disk_image
            show_results
            ;;
        clean)
            do_clean
            ;;
        distclean)
            do_distclean
            ;;
        menuconfig)
            do_menuconfig
            ;;
        linux-config)
            do_linux_config
            ;;
        busybox-config)
            do_busybox_config
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Unknown command: ${cmd}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
