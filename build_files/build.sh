#!/bin/bash

set -ouex pipefail

setsebool -P domain_kernel_load_modules on

### Install packages
# --- CachyOS ---
dnf5 -y copr enable bieszczaders/kernel-cachyos
dnf5 -y copr enable bieszczaders/kernel-cachyos-addons

# --- Kernel Modules ---
dnf5 -y copr enable hikariknight/looking-glass-kvmfr

# --- Tools ---
dnf5 -y copr enable ilyaz/LACT
dnf5 -y copr enable jackgreiner/lsfg-vk-git
dnf5 -y copr enable codifryed/CoolerControl
dnf5 -y copr enable brycensranch/gpu-screen-recorder-git
dnf5 -y copr enable che/nerd-fonts

# --- Mullvad ---
curl -fsSL https://repository.mullvad.net/rpm/stable/mullvad.repo -o /etc/yum.repos.d/mullvad.repo

# Removing stock kernel and drivers to replace with CachyOS
dnf5 remove -y \
    kernel \
    kernel-core \
    kernel-modules \
    kernel-modules-core \
    kernel-modules-extra \
    zram-generator-defaults \
    hhd-ui \
    hhd

# Installation

# Workaround for kernel installation in container:
# Mask kernel install hooks to prevent dracut failure during dnf transaction
# because depmod hasn't run yet. We will run them manually later.
mkdir -p /etc/kernel/install.d
ln -s /dev/null /etc/kernel/install.d/05-rpmostree.install
ln -s /dev/null /etc/kernel/install.d/50-dracut.install
ln -s /dev/null /etc/kernel/install.d/90-loaderentry.install

# --- Packages ---
dnf5 install -y --allowerasing --skip-unavailable \
    kernel-cachyos \
    kernel-cachyos-devel-matched \
    cachyos-settings \
    cachyos-ksm-settings \
    scx-scheds \
    scx-tools \
    scx-manager \
    akmod-v4l2loopback \
    akmod-xpadneo \
    akmod-xpad-noone \
    akmods-kvmfr \
    kvmfr \
    mpv \
    yt-dlp \
    lsfg-vk \
    lsfg-vk-ui \
    goverlay \
    gpu-screen-recorder-ui \
    gpu-screen-recorder-gtk \
    steam-devices \
    inputplumber \
    openrgb \
    antimicrox \
    coolercontrol \
    lact \
    mullvad-vpn \
    virt-manager \
    podman-compose \
    jetbrains-mono-fonts-all \
    nerd-fonts \
    zoxide \
    bat \
    ripgrep \
    ugrep \
    fd-find \
    tealdeer \
    atuin \
    byobu

# Install custom scripts and config files
install -Dm755 /ctx/system_files/bin/game-performance /usr/bin/game-performance
install -Dm644 /ctx/system_files/lib/tuned/recommend.conf /usr/lib/tuned/recommend.d/70-bopp-os.conf
install -Dm644 /ctx/system_files/lib/modprobe.d/amdgpu-overclock.conf /usr/lib/modprobe.d/amdgpu-overclock.conf
install -Dm644 /ctx/system_files/lib/modprobe.d/kvm-nested.conf /usr/lib/modprobe.d/kvm-nested.conf
install -Dm644 /ctx/system_files/lib/modules-load.d/boppos-modules.conf /usr/lib/modules-load.d/boppos-modules.conf
install -Dm644 /ctx/system_files/lib/systemd/ksmd.service /usr/lib/systemd/system/ksmd.service
install -Dm644 /ctx/system_files/etc/mpv.conf /etc/mpv/mpv.conf

# Unmask hooks
rm -f /etc/kernel/install.d/05-rpmostree.install
rm -f /etc/kernel/install.d/50-dracut.install
rm -f /etc/kernel/install.d/90-loaderentry.install

# Manually trigger kernel setup
KERNEL_VERSION=$(ls /usr/lib/modules | grep cachyos | sort -V | tail -n 1)
if [[ -n "$KERNEL_VERSION" ]]; then
    echo "Configuring kernel $KERNEL_VERSION"
    depmod -a "$KERNEL_VERSION"
    # Generate initramfs directly using dracut to avoid kernel-install issues in container
    # and ensure it includes the ostree module.
    TMPDIR=/var/tmp dracut --no-hostonly --kver "$KERNEL_VERSION" --reproducible -v --add ostree -f "/usr/lib/modules/$KERNEL_VERSION/initramfs.img"
    chmod 0600 "/usr/lib/modules/$KERNEL_VERSION/initramfs.img"
fi

# Services
systemctl enable ksmd.service libvirtd.service scx_loader.service inputplumber.service openrgb.service
systemctl disable lactd.service coolercontrold.service mullvad-daemon.service tailscaled.service

# Cleanup /var/tmp used by kernel-install workaround
rm -rf /var/tmp/*
