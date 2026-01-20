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
dnf5 -y copr enable ilyaz/LACT
dnf5 -y copr enable jackgreiner/lsfg-vk-git
dnf5 -y copr enable codifryed/CoolerControl
dnf5 -y copr enable brycensranch/gpu-screen-recorder-git
dnf5 -y copr enable che/nerd-fonts

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
    zram-generator-defaults

# 3. Installation

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
    mpv \
    yt-dlp \
    lsfg-vk \
    goverlay \
    gpu-screen-recorder-ui \
    gpu-screen-recorder-gtk \
    openrgb \
    coolercontrol \
    lact \
    mullvad-vpn \
    virt-manager \
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

## Enable KSMD
tee "/usr/lib/systemd/system/ksmd.service" > /dev/null <<EOF
[Unit]
Description=Activates Kernel Samepage Merging
ConditionPathExists=/sys/kernel/mm/ksm

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/ksmctl -e
ExecStop=/usr/bin/ksmctl -d

[Install]
WantedBy=multi-user.target
EOF

# 4. Services
systemctl enable ksmd.service libvirtd.service
systemctl disable lactd.service coolercontrold.service mullvad-daemon.service tailscaled.service

# 5. Config Files
# AMD GPU Overclocking Unlock
mkdir -p /usr/lib/modprobe.d
echo "options amdgpu ppfeaturemask=0xffffffff" > /usr/lib/modprobe.d/amdgpu-overclock.conf

# AMD Nested Virtualization Unlock
echo "options kvm_amd nested=1" > /usr/lib/modprobe.d/kvm-nested.conf

# Optimized MPV Config
# Note: mpv does not support reading config from /usr/lib or /usr/share,
# so we must place this in /etc/mpv.
mkdir -p /etc/mpv
cat <<EOF > /etc/mpv/mpv.conf
vo=gpu-next
gpu-api=vulkan
hwdec=auto-safe
profile=gpu-hq
scale=ewa_lanczossharp
cscale=ewa_lanczossharp
EOF

# Cleanup /var/tmp used by kernel-install workaround
rm -rf /var/tmp/*
