#!/usr/bin/env bash
#===========================================================
# create-opkg-feed.sh - Build .ipk packages & Packages.gz feed
#
# Takes the build output from build.sh and creates:
#   - vortex-kernel_<ver>_i486.ipk  (kernel + modules)
#   - vortex-base-system_<ver>_i486.ipk  (configs, init, X11)
#   - Packages.gz (opkg feed index)
#
# Usage:
#   ./scripts/create-opkg-feed.sh              # Build feed from latest output
#   ./scripts/create-opkg-feed.sh --version 1.0.1  # Specify version
#   ./scripts/create-opkg-feed.sh --output ./my-feed  # Output to custom dir
#
# The output can be deployed to GitHub Pages for opkg update/upgrade.
#===========================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDROOT_DIR="${SCRIPT_DIR}/buildroot"
IMAGES_DIR="${BUILDROOT_DIR}/output/images"
TARGET_DIR="${BUILDROOT_DIR}/output/target"
FEED_DIR="${SCRIPT_DIR}/opkg-feed/feed"
# Auto-detect version from git tags + commit count
# Falls back to "0.0.0" if not in a git repo or no tags
if command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null 2>&1; then
    TAG=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^[vV]//' || echo "0.0.0")
    COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 0)
    VERSION="${TAG}-build${COUNT}"
else
    VERSION="0.0.0"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()  { echo -e "${BLUE}[STEP]${NC}  $*"; }

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --output) FEED_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--version X.Y.Z] [--output DIR]"
            echo "  Builds .ipk packages and Packages.gz from Buildroot output."
            exit 0 ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
done

# === Check prerequisites ===
check_prereqs() {
    step "Checking prerequisites..."
    
    if [ ! -d "${BUILDROOT_DIR}" ]; then
        warn "Buildroot directory not found. This is expected in CI."
        warn "Packages will be created with control files and overlay configs only."
        warn "For packages with real binaries (kernel, modules), run ./build.sh locally first."
    elif [ ! -d "${IMAGES_DIR}" ] || [ ! -f "${IMAGES_DIR}/bzImage" ]; then
        warn "Build output not found at ${IMAGES_DIR}"
        warn "The feed will be created with control files only (no binaries)."
        warn "Run './build.sh' first to produce binaries for packaging."
    fi
    
    for cmd in tar gzip ar find; do
        if ! command -v "$cmd" &>/dev/null; then
            error "Required tool not found: $cmd"
            exit 1
        fi
    done
    
    info "Prerequisites satisfied."
}

# === Clean temp directory ===
clean_temp() {
    if [ -d "${TEMP_DIR}" ]; then
        rm -rf "${TEMP_DIR}"
    fi
}

# === Create an .ipk package ===
# $1 = package name, $2 = data directory (files to install), $3 = control directory
create_ipk() {
    local pkg_name="$1"
    local data_dir="$2"
    local control_dir="$3"
    local pkg_file="${FEED_DIR}/${pkg_name}_${VERSION}_i486.ipk"
    
    step "Building ${pkg_name}_${VERSION}_i486.ipk..."
    
    local workdir="${TEMP_DIR}/${pkg_name}"
    mkdir -p "${workdir}"
    
    # debian-binary (required by ipk format)
    echo "2.0" > "${workdir}/debian-binary"
    
    # Create control.tar.gz
    if [ -d "${control_dir}" ]; then
        cd "${control_dir}"
        tar --numeric-owner --group=0 --owner=0 -czf "${workdir}/control.tar.gz" . 2>/dev/null || {
            warn "Could not create control.tar.gz for ${pkg_name}"
            return 1
        }
    else
        warn "Control directory not found: ${control_dir}"
        return 1
    fi
    
    # Create data.tar.gz
    if [ -d "${data_dir}" ] && [ "$(find "${data_dir}" -mindepth 1 -type f 2>/dev/null | head -1)" ]; then
        cd "${data_dir}"
        tar --numeric-owner --group=0 --owner=0 -czf "${workdir}/data.tar.gz" . 2>/dev/null || {
            warn "Could not create data.tar.gz for ${pkg_name}"
            # Create empty data.tar.gz
            tar --numeric-owner --group=0 --owner=0 -czf "${workdir}/data.tar.gz" --files-from /dev/null
        }
    else
        # Empty data tarball (meta-package or no binaries yet)
        tar --numeric-owner --group=0 --owner=0 -czf "${workdir}/data.tar.gz" --files-from /dev/null
    fi
    
    # Assemble .ipk with ar
    cd "${workdir}"
    ar rv "${pkg_file}" debian-binary control.tar.gz data.tar.gz &>/dev/null || {
        error "Failed to create .ipk with ar"
        return 1
    }
    
    local size
    size=$(stat -c%s "${pkg_file}" 2>/dev/null || stat -f%z "${pkg_file}" 2>/dev/null || echo 0)
    info "  Created: $(basename "${pkg_file}") (${size} bytes)"
}

# === Create kernel package ===
build_kernel_package() {
    local pkg_name="vortex-kernel"
    local data_dir="${TEMP_DIR}/kernel-data"
    local control_dir="${TEMP_DIR}/kernel-control"
    
    mkdir -p "${data_dir}/boot"
    mkdir -p "${control_dir}"
    
    # Copy control file from source and update version to match ${VERSION}
    sed "s/^Version: .*/Version: ${VERSION}/" "${SCRIPT_DIR}/opkg-feed/packages/kernel/control/control" > "${control_dir}/control"
    
    # Copy kernel if available
    if [ -f "${IMAGES_DIR}/bzImage" ]; then
        cp "${IMAGES_DIR}/bzImage" "${data_dir}/boot/vmlinuz-${VERSION}-vortex86"
    else
        warn "bzImage not found. Creating placeholder kernel package."
        echo "Placeholder: build kernel with ./build.sh" > "${data_dir}/boot/README-kernel.txt"
    fi
    
    # Copy kernel modules if available
    if [ -d "${TARGET_DIR}/lib/modules" ]; then
        mkdir -p "${data_dir}/lib"
        cp -a "${TARGET_DIR}/lib/modules" "${data_dir}/lib/"
    fi
    
    # Post-install: update GRUB when a new kernel is installed
    cat > "${control_dir}/postinst" << 'POSTINST'
#!/bin/sh
# Post-install: Update GRUB bootloader with the new kernel
if command -v grub-mkconfig >/dev/null 2>&1; then
    echo "Updating GRUB bootloader..."
    grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
fi
exit 0
POSTINST
    chmod 755 "${control_dir}/postinst"
    
    create_ipk "${pkg_name}" "${data_dir}" "${control_dir}"
}

# === Create base-system package ===
build_base_system_package() {
    local pkg_name="vortex-base-system"
    local data_dir="${TEMP_DIR}/base-data"
    local control_dir="${SCRIPT_DIR}/opkg-feed/packages/base-system/control"
    
    mkdir -p "${data_dir}"
    
    # Copy overlay files (system configs)
    local overlay_dir="${SCRIPT_DIR}/board/dmp/vortex86_a9100/overlay"
    if [ -d "${overlay_dir}" ]; then
        cp -a "${overlay_dir}/." "${data_dir}/"
    fi
    
    # Copy post-build output if available
    if [ -d "${TARGET_DIR}/etc" ]; then
        # Capture key config files from the built rootfs
        for dir in etc/modules-load.d etc/sysctl.d; do
            if [ -d "${TARGET_DIR}/${dir}" ]; then
                mkdir -p "${data_dir}/${dir}"
                cp -a "${TARGET_DIR}/${dir}/." "${data_dir}/${dir}/" 2>/dev/null || true
            fi
        done
    fi
    
    # Post-install script (in TEMP_DIR to avoid modifying source control dir)
    local build_control_dir="${TEMP_DIR}/base-control"
    mkdir -p "${build_control_dir}"
    # Copy control file and update version to match ${VERSION}
    sed "s/^Version: .*/Version: ${VERSION}/" "${control_dir}/control" > "${build_control_dir}/control"
    
    cat > "${build_control_dir}/postinst" << 'POSTINST'
#!/bin/sh
# Post-install: Apply base system configuration updates
# (kernel GRUB update is handled by vortex-kernel postinst)
if command -v ldconfig >/dev/null 2>&1; then
    ldconfig 2>/dev/null || true
fi
exit 0
POSTINST
    chmod 755 "${build_control_dir}/postinst"
    
    create_ipk "${pkg_name}" "${data_dir}" "${build_control_dir}"
}

# === Create os-update meta-package ===
build_os_update_package() {
    local pkg_name="vortex-os-update"
    local data_dir="${TEMP_DIR}/os-update-data"
    local control_dir="${SCRIPT_DIR}/opkg-feed/packages/os-update/control"
    
    mkdir -p "${data_dir}"
    
    # Update the version in the control file dependencies to match
    local control_file="${control_dir}/control"
    if [ -f "${control_file}" ]; then
        # Update dependency versions (supports >= or = , and any version format)
        sed -i "s/vortex-kernel ([>=]* [^)]*)/vortex-kernel (>= ${VERSION})/g" "${control_file}"
        sed -i "s/vortex-base-system ([>=]* [^)]*)/vortex-base-system (>= ${VERSION})/g" "${control_file}"
    fi
    
    # Post-install script for the meta-package
    mkdir -p "${TEMP_DIR}/os-update-control"
    cp "${control_file}" "${TEMP_DIR}/os-update-control/control"
    cat > "${TEMP_DIR}/os-update-postinst" << 'POSTINST'
#!/bin/sh
# Post-install: Update GRUB and reboot warning
echo ""
echo "============================================"
echo "  OS Update installed successfully!"
echo "  Run 'update-grub && reboot' to apply."
echo "============================================"
echo ""
# Write a flag so upgrade is detected on next boot
date > /etc/vortex-os-update.stamp 2>/dev/null || true
exit 0
POSTINST
    cp "${TEMP_DIR}/os-update-postinst" "${TEMP_DIR}/os-update-control/postinst"
    chmod 755 "${TEMP_DIR}/os-update-control/postinst"
    
    create_ipk "${pkg_name}" "${data_dir}" "${TEMP_DIR}/os-update-control"
}

# === Generate Packages.gz ===
generate_feed_index() {
    step "Generating opkg feed index (Packages.gz)..."
    
    cd "${FEED_DIR}"
    
    # Generate Packages index
    local packages_file="${FEED_DIR}/Packages"
    > "${packages_file}"
    
    for ipk in *.ipk; do
        [ -f "${ipk}" ] || continue
        
        echo "Package: $(echo "${ipk}" | sed 's/_.*//')" >> "${packages_file}"
        echo "Version: ${VERSION}" >> "${packages_file}"
        echo "Architecture: i486" >> "${packages_file}"
        echo "Filename: ${ipk}" >> "${packages_file}"
        echo "Size: $(stat -c%s "${ipk}" 2>/dev/null || stat -f%z "${ipk}" 2>/dev/null || echo 0)" >> "${packages_file}"
        echo "SHA256sum: $(sha256sum "${ipk}" | cut -d' ' -f1)" >> "${packages_file}"
        echo "Priority: optional" >> "${packages_file}"
        echo "Maintainer: Vortex86 A9100 Project" >> "${packages_file}"
        echo "Description: $(echo "${ipk}" | sed 's/\.ipk$//')" >> "${packages_file}"
        echo "" >> "${packages_file}"
    done
    
    # Compress
    gzip -c9 "${packages_file}" > "${FEED_DIR}/Packages.gz"
    rm -f "${packages_file}"
    
    local count
    count=$(ls -1 "${FEED_DIR}"/*.ipk 2>/dev/null | wc -l)
    info "Feed contains ${count} packages"
    info "Packages.gz created ($(stat -c%s "${FEED_DIR}/Packages.gz" 2>/dev/null || echo "?") bytes)"
}

# === Show feed info ===
show_feed_info() {
    echo ""
    info "========================================"
    info "opkg Feed Created!"
    info "========================================"
    echo ""
    echo "  Feed location: ${FEED_DIR}/"
    echo ""
    ls -lh "${FEED_DIR}/"*.ipk 2>/dev/null || echo "  (no .ipk files)"
    ls -lh "${FEED_DIR}/Packages.gz" 2>/dev/null || true
    echo ""
    echo "  To deploy:"
    echo "    ./scripts/deploy-feed.sh"
    echo ""
    echo "  On the Vortex86 A9100, configure /etc/opkg.conf:"
    echo "    src/gz vortex-stable https://vincenzosco.github.io/Vortex-A9100-Linux-Image/opkg/"
    echo ""
    echo "  Then:"
    echo "    opkg update"
    echo "    opkg list | grep vortex"
    echo "    opkg install vortex-os-update"
    echo ""
}

# === Main ===
main() {
    echo ""
    echo "=============================="
    echo " Vortex86 A9100 opkg Feed Builder"
    echo " Version: ${VERSION}"
    echo "=============================="
    echo ""
    
    TEMP_DIR=$(mktemp -d /tmp/vortex-opkg.XXXXXX)
    trap clean_temp EXIT
    
    check_prereqs
    
    # Create feed directory
    mkdir -p "${FEED_DIR}"
    
    # Build packages
    build_kernel_package
    build_base_system_package
    build_os_update_package
    
    # Generate index
    generate_feed_index
    
    # Show info
    show_feed_info
}

main "$@"
