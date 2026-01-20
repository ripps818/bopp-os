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
dnf5 -y copr enable brycensranch/gpu-screen-recorder-git

# --- Mullvad ---
curl -fsSL https://repository.mullvad.net/rpm/stable/mullvad.repo -o /etc/yum.repos.d/mullvad.repo

# 2. Removals
# Removing stock kernel and drivers to replace with CachyOS
dnf5 remove -y \
    kernel \
    kernel-core \
    kernel-modules \
    kernel-modules-core \
    kernel-modules-extra 

# 3. Installation
# --- Packages ---
dnf5 install -y --allowerasing --skip-unavailable \
    kernel-cachyos \
    kernel-cachyos-devel-matched \
    cachyos-settings \
    cachyos-ksm-settings \
    scxctl \
    mpv \
    yt-dlp \
    lsfg-vk \
    goverlay \
    gpu-screen-recorder-ui \
    openrgb \
    coolercontrol \
    lact \
    mullvad-vpn \
    virt-manager \
    zoxide \
    bat \
    ripgrep \
    ugrep \
    fd-find \
    tealdeer \
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
