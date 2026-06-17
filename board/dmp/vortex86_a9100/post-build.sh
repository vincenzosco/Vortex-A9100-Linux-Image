#!/bin/bash
# post-build.sh - Finalize the Vortex86 A9100 root filesystem
#
# This script runs after the root filesystem is built but before
# the final image is created.
#
# Arguments:
#   $1: target directory (root of the built filesystem)
#   $2: board directory
#   $3: output directory

set -e

TARGET_DIR="${1}"
BOARD_DIR="${2}"
OUTPUT_DIR="${3}"

echo "Post-build: Finalizing rootfs for Vortex86 A9100..."

# --- Make all init scripts executable ---
chmod 755 "${TARGET_DIR}/etc/init.d/"*.sh 2>/dev/null || true
chmod 755 "${TARGET_DIR}/etc/init.d/S"* 2>/dev/null || true
chmod 755 "${TARGET_DIR}/etc/init.d/rcS" 2>/dev/null || true

# --- Set root password (empty by default for embedded use) ---
# To set a password, use: echo 'root:$6$salt$hash' > "${TARGET_DIR}/etc/shadow"
# For now, allow passwordless root login on serial console
sed -i 's/^root:[^:]*:/root::/' "${TARGET_DIR}/etc/shadow" 2>/dev/null || true

# --- Copy GRUB configuration ---
if [ -f "${BOARD_DIR}/grub.cfg" ]; then
    mkdir -p "${TARGET_DIR}/boot/grub"
    cp "${BOARD_DIR}/grub.cfg" "${TARGET_DIR}/boot/grub/"
    echo "Post-build: GRUB config installed"
fi

# --- Copy Openbox configuration ---
if [ -f "${BOARD_DIR}/openbox-config" ]; then
    mkdir -p "${TARGET_DIR}/root/.config/openbox"
    cp "${BOARD_DIR}/openbox-config" "${TARGET_DIR}/root/.config/openbox/rc.xml"
    # Create a simple Openbox menu
    cat > "${TARGET_DIR}/root/.config/openbox/menu.xml" << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
<menu id="root-menu" label="Vortex86 A9100">
    <item label="Terminal">
        <action name="Execute"><command>xterm</command></action>
    </item>
    <item label="Clock">
        <action name="Execute"><command>xclock -digital -update 1</command></action>
    </item>
    <item label="System Monitor">
        <action name="Execute"><command>xterm -e htop</command></action>
    </item>
    <separator/>
    <item label="Log Out">
        <action name="Execute"><command>openbox --exit</command></action>
    </item>
</menu>
</openbox_menu>
XMLEOF
    echo "Post-build: Openbox configuration installed"
fi

# --- Copy opkg configuration ---
if [ -f "${TARGET_DIR}/etc/opkg.conf" ]; then
    chmod 644 "${TARGET_DIR}/etc/opkg.conf"
    echo "Post-build: opkg config set"
fi

# --- Set up /var for persistent storage ---
# Ensure opkg lists directory exists
mkdir -p "${TARGET_DIR}/var/lib/opkg/lists"

# --- Make the OS installer executable ---
if [ -f "${TARGET_DIR}/usr/bin/vortex-install" ]; then
    chmod 755 "${TARGET_DIR}/usr/bin/vortex-install"
    echo "Post-build: vortex-install made executable"
fi

# --- Enable live mode: X11 auto-start on tty1 ---
# The live image auto-starts X11+Openbox so users get a GUI immediately.
# Installed systems override this setting to avoid X11 on serial-only setups.
if [ -f "${TARGET_DIR}/etc/init.d/S60xorg" ]; then
    sed -i 's/^AUTOSTART="no"/AUTOSTART="yes"/' "${TARGET_DIR}/etc/init.d/S60xorg"
    echo "Post-build: Live mode enabled (X11 auto-start on tty1)"
fi

# --- Remove unnecessary files to save space ---
rm -rf "${TARGET_DIR}/usr/man/" 2>/dev/null || true
rm -rf "${TARGET_DIR}/usr/doc/" 2>/dev/null || true
rm -rf "${TARGET_DIR}/usr/info/" 2>/dev/null || true
rm -rf "${TARGET_DIR}/usr/share/locale/" 2>/dev/null || true
find "${TARGET_DIR}" -name "*.a" -delete 2>/dev/null || true
find "${TARGET_DIR}" -name "*.la" -delete 2>/dev/null || true

# --- Create /etc/issue with system info ---
cat > "${TARGET_DIR}/etc/issue" << EOF
========================================
  Vortex86 A9100 Embedded Linux    Architecture: i486-compatible
    Kernel: Linux 5.10.x
    C Library: musl
    Package Manager: opkg
    Window Manager: Openbox (auto-start in live mode)
    Installer: type 'vortex-install' to install to a device
========================================

EOF

echo "Post-build: Complete"
