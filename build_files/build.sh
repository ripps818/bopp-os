#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# 1. Repositories

# --- CachyOS ---
dnf5 -y copr enable bieszczaders/kernel-cachyos
dnf5 -y copr enable bieszczaders/kernel-cachyos-addons

# --- Tools ---
dnf5 -y copr enable jackgreiner/lsfg-vk-git
dnf5 -y copr enable codifryed/CoolerControl
dnf5 -y copr enable ilyaz/LACT

# --- Mullvad ---
curl -fsSL https://repository.mullvad.net/rpm/stable/mullvad.repo -o /etc/yum.repos.d/mullvad.repo

# 2. Removals
# Removing stock kernel and drivers to replace with CachyOS
dnf5 remove -y \
    kernel \
    kernel-core \
    kernel-modules \
    kernel-modules-core \
    kernel-modules-extra \
    mesa-va-drivers

# 3. Installation

# --- Release RPMs ---
# Note: Bazzite usually has these, but ensuring they are present as per recipe.
dnf5 install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm || true

# --- Packages ---
dnf5 install -y \
    kernel-cachyos \
    kernel-cachyos-devel-matched \
    cachyos-settings \
    cachyos-ksm-settings \
    scx-scheds \
    scx-tools \
    scxctl \
    mesa-va-drivers-freeworld \
    mesa-vdpau-drivers-freeworld \
    libavcodec-freeworld \
    mpv \
    yt-dlp \
    libva-utils \
    lsfg-vk \
    goverlay \
    gpu-screen-recorder \
    openrgb \
    coolercontrol \
    lact \
    tailscale \
    mullvad-vpn \
    virt-manager \
    qemu-kvm \
    libvirt \
    edk2-ovmf \
    starship \
    zoxide \
    eza \
    bat \
    fzf \
    ripgrep \
    fd-find \
    tealdeer \
    fastfetch \
    atuin \
    byobu

# 4. Services
systemctl enable ksmd.service scx.service libvirtd.service
systemctl disable lactd.service coolercontrold.service mullvad-daemon.service tailscaled.service

# 5. Config Files

# AMD GPU Overclocking Unlock
mkdir -p /usr/lib/modprobe.d
echo "options amdgpu ppfeaturemask=0xffffffff" > /usr/lib/modprobe.d/amdgpu-overclock.conf

# AMD Nested Virtualization Unlock
mkdir -p /etc/modprobe.d
echo "options kvm_amd nested=1" > /etc/modprobe.d/kvm-nested.conf

# Optimized MPV Config
mkdir -p /etc/mpv
cat <<EOF > /etc/mpv/mpv.conf
vo=gpu-next
gpu-api=vulkan
hwdec=auto-safe
profile=gpu-hq
scale=ewa_lanczossharp
cscale=ewa_lanczossharp
EOF
