#!/bin/bash

set -ouex pipefail

# ==============================================================================
# 1. REPOSITORIES & PACKAGES
# ==============================================================================

# --- COPRs ---
dnf5 -y copr enable bieszczaders/kernel-cachyos
dnf5 -y copr enable bieszczaders/kernel-cachyos-addons
dnf5 -y copr enable ilyaz/LACT
dnf5 -y copr enable jackgreiner/lsfg-vk-git
dnf5 -y copr enable codifryed/CoolerControl
dnf5 -y copr enable hikariknight/looking-glass-kvmfr

# --- Third Party Repos ---
curl -fsSL https://github.com/terrapkg/subatomic-repos/raw/main/terra.repo -o /etc/yum.repos.d/terra.repo
curl -fsSL https://repository.mullvad.net/rpm/stable/mullvad.repo -o /etc/yum.repos.d/mullvad.repo
curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo -o /etc/yum.repos.d/cloudflare-warp.repo

dnf5 install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# --- Remove Stock Kernel ---
# We remove the packages, but artifacts (like old initramfs) might remain. 
# We will clean those up at the end.
dnf5 remove -y \
    kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra \
    zram-generator-defaults hhd-ui hhd

# Workaround for container build hooks
mkdir -p /etc/kernel/install.d
ln -s /dev/null /etc/kernel/install.d/05-rpmostree.install
ln -s /dev/null /etc/kernel/install.d/50-dracut.install
ln -s /dev/null /etc/kernel/install.d/90-loaderentry.install

# --- Install New Kernel & Build Tools ---
dnf5 install -y --allowerasing \
    kernel-cachyos \
    kernel-cachyos-devel-matched \
    cachyos-settings \
    cachyos-ksm-settings \
    git make gcc gcc-c++ rpm-build \
    dnf-plugins-core elfutils-libelf-devel

# ==============================================================================
# 2. BUILD ENVIRONMENT SETUP
# ==============================================================================

KERNEL_VERSION=$(rpm -qa kernel-cachyos --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')
KERNEL_DIR="/usr/src/kernels/${KERNEL_VERSION}"
INSTALL_MOD_DIR="/usr/lib/modules/${KERNEL_VERSION}/extra"

RPMBUILD_DIR="/var/tmp/rpmbuild"
AKMOD_DL_DIR="/var/tmp/akmod_downloads"

# Setup Directory Structure
mkdir -p "$AKMOD_DL_DIR"
mkdir -p "${RPMBUILD_DIR}"/{SPECS,SOURCES,BUILD,RPMS,SRPMS}
mkdir -p "$INSTALL_MOD_DIR"

echo "--- Preparing to build for Kernel: ${KERNEL_VERSION} ---"

# Download Source RPMs (contained inside the akmod binaries)
dnf5 download -y --destdir="$AKMOD_DL_DIR" --resolve \
    --arch x86_64 --arch noarch \
    akmod-xpadneo \
    akmod-xpad-noone \
    akmod-kvmfr

# Install them (skipping scripts) to place .src.rpm in /usr/src/akmods
rpm -Uvh --force --nopost "$AKMOD_DL_DIR"/*.rpm

# Extract Sources to our build temp
echo "--- Extracting Sources ---"
rpm -ivh --define "_topdir ${RPMBUILD_DIR}" /usr/src/akmods/*.src.rpm

# ==============================================================================
# 3. MODULE BUILD: KVMFR (Looking Glass)
# ==============================================================================
echo "--- Building KVMFR ---"

# 1. Prep source
rpmbuild -bp --define "_topdir ${RPMBUILD_DIR}" "${RPMBUILD_DIR}/SPECS/kvmfr-kmod.spec" --nodeps

# 2. Enter Build Wrapper
cd "${RPMBUILD_DIR}/BUILD"
WRAPPER_DIR=$(find . -maxdepth 1 -type d -name "*kvmfr*" | head -n 1)
cd "$WRAPPER_DIR"

# 3. Enter Actual Source Dir (avoiding SPECPARTS)
SRC_DIR=$(find . -maxdepth 1 -mindepth 1 -type d -not -name "SPECPARTS" | head -n 1)
cd "$SRC_DIR"

# 4. Enter Nested Module Dir
cd LookingGlass-master/module

# 5. Compile
make -C "$KERNEL_DIR" M="$PWD" modules

# 6. Install (Dynamic Find)
#    We use 'find' because the module name might be kvmfr.ko or kvmfr-kmod.ko
echo "Installing KVMFR module..."
find . -type f -name "*.ko" -exec install -Dm644 {} "${INSTALL_MOD_DIR}/" \;

# ==============================================================================
# 4. MODULE BUILD: XPADNEO
# ==============================================================================
echo "--- Building XPADNEO ---"

# 1. Prep source
rpmbuild -bp --define "_topdir ${RPMBUILD_DIR}" "${RPMBUILD_DIR}/SPECS/xpadneo-kmod.spec" --nodeps

# 2. Enter Build Wrapper
cd "${RPMBUILD_DIR}/BUILD"
WRAPPER_DIR=$(find . -maxdepth 1 -type d -name "*xpadneo*" | head -n 1)
cd "$WRAPPER_DIR"

# 3. Enter Actual Source Dir
SRC_DIR=$(find . -maxdepth 1 -mindepth 1 -type d -not -name "SPECPARTS" | head -n 1)
cd "$SRC_DIR"

# 4. Enter Module Subdir
cd hid-xpadneo

# 5. Compile
echo "Compiling xpadneo in $(pwd)..."
make -C "$KERNEL_DIR" M="$PWD" modules

# 6. Install with explicit 'src' check
echo "Looking for xpadneo module..."
MODULE_FOUND=$(find . -type f -name "*.ko" | head -n 1)

if [[ -z "$MODULE_FOUND" ]]; then
    # Fallback: Sometimes the Makefile expects us to be inside 'src' directly
    if [[ -d "src" ]]; then
        echo "Module not found in root. Trying to build inside 'src' subdirectory..."
        cd src
        make -C "$KERNEL_DIR" M="$PWD" modules
        MODULE_FOUND=$(find . -type f -name "*.ko" | head -n 1)
    fi
fi

# 7. Final Verification & Install
if [[ -n "$MODULE_FOUND" ]]; then
    echo "Found module at: $MODULE_FOUND"
    install -Dm644 "$MODULE_FOUND" "${INSTALL_MOD_DIR}/hid-xpadneo.ko"
else
    echo "ERROR: xpadneo build failed! No .ko file found."
    echo "Directory contents:"
    ls -R
    exit 1
fi

# ==============================================================================
# 5. MODULE BUILD: XPAD-NOONE
# ==============================================================================
echo "--- Building XPAD-NOONE ---"

# 1. Prep source
rpmbuild -bp --define "_topdir ${RPMBUILD_DIR}" "${RPMBUILD_DIR}/SPECS/xpad-noone-kmod.spec" --nodeps

# 2. Enter Build Wrapper
cd "${RPMBUILD_DIR}/BUILD"
WRAPPER_DIR=$(find . -maxdepth 1 -type d -name "*xpad-noone*" | head -n 1)
cd "$WRAPPER_DIR"

# 3. Enter Actual Source Dir
SRC_DIR=$(find . -maxdepth 1 -mindepth 1 -type d -not -name "SPECPARTS" | head -n 1)
cd "$SRC_DIR"

# 4. Compile
make -C "$KERNEL_DIR" M="$PWD" modules

# 5. Install (Dynamic Find)
echo "Installing XPAD-NOONE module..."
find . -type f -name "*.ko" -exec install -Dm644 {} "${INSTALL_MOD_DIR}/" \;

# ==============================================================================
# 6. CONFIGURATION & FINALIZATION
# ==============================================================================

echo "--- Configuring Modules ---"
echo "blacklist xpad" > /usr/lib/modprobe.d/xpad-blacklist.conf
echo 'KERNEL=="kvmfr0", OWNER="root", GROUP="kvm", MODE="0660"' > /etc/udev/rules.d/99-kvmfr.rules

# --- Install User Packages ---

PKGS_SCHEDULERS="scx-scheds scx-tools scx-manager ananicy-cpp cachyos-ananicy-rules"
PKGS_VIRT="kvmfr virt-manager podman-compose"
PKGS_MEDIA="mpv yt-dlp lsfg-vk lsfg-vk-ui goverlay gpu-screen-recorder-ui gpu-screen-recorder-gtk"
PKGS_GAMING="steam-devices inputplumber openrgb antimicrox scopebuddy mangohud vkbasalt"
PKGS_HARDWARE="coolercontrol lact"
PKGS_NET="mullvad-vpn cloudflare-warp"
PKGS_FONTS="jetbrains-mono-fonts-all nerd-fonts"
PKGS_CLI="zoxide bat ripgrep ugrep fd-find tealdeer atuin byobu"

dnf5 install -y --allowerasing --skip-unavailable \
    $PKGS_SCHEDULERS \
    $PKGS_VIRT \
    $PKGS_MEDIA \
    $PKGS_GAMING \
    $PKGS_HARDWARE \
    $PKGS_NET \
    $PKGS_FONTS \
    $PKGS_CLI

# --- Custom Configs ---
install -Dm755 /ctx/system_files/bin/* /usr/bin/
install -Dm644 /ctx/system_files/lib/modprobe.d/* /usr/lib/modprobe.d/
install -Dm644 /ctx/system_files/lib/modules-load.d/* /usr/lib/modules-load.d/
install -Dm644 /ctx/system_files/lib/tuned/recommend.conf /usr/lib/tuned/recommend.d/70-bopp-os.conf
install -Dm644 /ctx/system_files/lib/systemd/ksmd.service /usr/lib/systemd/system/ksmd.service
install -Dm644 /ctx/system_files/etc/mpv.conf /etc/mpv/

# --- Configure SCX Loader (LAVD) ---
# Ensure the loader knows to use the 'lavd' scheduler
mkdir -p /etc/default
echo "SCX_SCHEDULER=scx_lavd" > /etc/default/scx

# --- Services ---
systemctl enable ksmd.service libvirtd.service scx_loader.service inputplumber.service openrgb.service ananicy-cpp.service
systemctl disable lactd.service coolercontrold.service mullvad-daemon.service tailscaled.service warp-svc.service

# ==============================================================================
# 7. CLEANUP & INITRAMFS
# ==============================================================================

# Unmask hooks
rm -f /etc/kernel/install.d/05-rpmostree.install
rm -f /etc/kernel/install.d/50-dracut.install
rm -f /etc/kernel/install.d/90-loaderentry.install

# 1. Clean up old/stock kernel artifacts
#    We remove any module directory that does NOT contain 'cachyos' in the name.
echo "Cleaning up old kernel modules..."
find /usr/lib/modules -maxdepth 1 -mindepth 1 -type d -not -name "*cachyos*" -exec rm -rf {} +

# 2. Generate Initramfs for the NEW kernel
if [[ -n "$KERNEL_VERSION" ]]; then
    TARGET_KERNEL="/usr/lib/modules/${KERNEL_VERSION}/vmlinuz"
    
    # SAFETY CHECK: Only delete /boot if the kernel exists in the target
    if [[ -f "$TARGET_KERNEL" ]]; then
        echo "Kernel found at $TARGET_KERNEL. Cleaning redundant files in /boot..."
        rm -rf /boot/*
    else
        echo "WARNING: Kernel missing from $TARGET_KERNEL! Moving from /boot..."
        # Fallback: If it wasn't there, rescue it from /boot
        cp -a /boot/vmlinuz-"${KERNEL_VERSION}" "$TARGET_KERNEL"
        chmod 755 "$TARGET_KERNEL"
        rm -rf /boot/*
    fi

    # Generate Initramfs (Required for Boot)
    echo "Generating Initramfs..."
    depmod -a "$KERNEL_VERSION"
    dracut --no-hostonly --kver "$KERNEL_VERSION" --reproducible -v --add ostree -f "/usr/lib/modules/$KERNEL_VERSION/initramfs.img"
    chmod 0600 "/usr/lib/modules/$KERNEL_VERSION/initramfs.img"
fi

# 3. Deep Clean (Fixes 'sysusers' and 'var-tmpfiles' lint warnings)
#    Remove build tools
#dnf5 remove -y gcc make rpm-build
dnf5 clean all

#    Clear DNF caches and temp files
rm -rf /var/lib/dnf
rm -rf /var/cache/*
rm -rf /var/tmp/*
rm -rf "$RPMBUILD_DIR" "$AKMOD_DL_DIR" /usr/src/akmods

#    Remove the akmods user (Fixes lint warning about 'akmods' user existing)
if id "akmods" &>/dev/null; then
    userdel -r akmods || true
fi

echo "Build Complete!"
