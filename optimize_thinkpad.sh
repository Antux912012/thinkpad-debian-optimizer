#!/usr/bin/env bash
# ==============================================================================
# Lenovo ThinkPad (Debian / Ubuntu) System, NVMe, Intel Wi-Fi & GRUB Optimizer
# Target Hardware Profile:
#   - Lenovo ThinkPad 13 2nd Gen (i5-7200U / Intel HD Graphics 620 / 1920x1080)
#   - Intel NVMe SSD (e.g., Intel SSD 600p Series)
#   - Intel Dual Band Wireless-AC (iwlwifi / iwlmvm, e.g., 8265 / 8275)
# ==============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "[*] Root privileges required. Elevating..."
    if command -v sudo >/dev/null 2>&1; then
        exec sudo bash "$0" "$@"
    elif command -v pkexec >/dev/null 2>&1; then
        exec pkexec bash "$0" "$@"
    else
        echo "[!] Error: Please run this script as root." >&2
        exit 1
    fi
fi

echo "=================================================================="
echo " Lenovo ThinkPad Debian System Optimization Suite"
echo "=================================================================="

export DEBIAN_FRONTEND=noninteractive

echo "=== [1/6] Installing System Optimization, NVMe, Thermal & Plymouth Packages ==="
apt-get update -qq
apt-get install -y -qq thermald zram-tools nvme-cli smartmontools plymouth plymouth-themes

echo "=== [2/6] Optimizing NVMe SSD Lifespan (/etc/fstab, Journald, Udev, Fstrim) ==="
cp -a /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
# Dynamically add noatime,commit=60 to the root (/) ext4 entry in /etc/fstab if not present
awk '
$2 == "/" && $3 == "ext4" && $4 !~ /noatime/ {
    $4 = "noatime,commit=60," $4
}
{ print }
' /etc/fstab > /etc/fstab.tmp && mv /etc/fstab.tmp /etc/fstab

systemctl daemon-reload
mount -o remount,noatime,commit=60 / || true

# Configure systemd-journald write caps to protect SSD from excessive log wear
mkdir -p /etc/systemd/journald.conf.d
cat << 'EOF' > /etc/systemd/journald.conf.d/99-ssd-lifespan.conf
[Journal]
SystemMaxUse=200M
SystemMaxFileSize=50M
RuntimeMaxUse=64M
SyncIntervalSec=5m
EOF
systemctl restart systemd-journald || true

# Ensure NVMe udev rule for none scheduler, rq_affinity=2, and PCI runtime PM
cat << 'EOF' > /etc/udev/rules.d/60-nvme-ssd-optimize.rules
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none", ATTR{queue/rq_affinity}="2"
ACTION=="add", SUBSYSTEM=="pci", ATTR{class}=="0x010802", ATTR{power/control}="auto"
EOF
udevadm control --reload-rules && udevadm trigger --subsystem-match=block || true

# Ensure weekly TRIM timer is enabled and active
systemctl enable --now fstrim.timer

echo "=== [3/6] Optimizing Performance, RAM/ZRAM & Battery Life ==="
# Configure zram-tools for fast zstd compressed RAM swap (reduces NVMe swap wear)
if [ -f /etc/default/zramswap ]; then
    cp -a /etc/default/zramswap /etc/default/zramswap.bak || true
fi
cat << 'EOF' > /etc/default/zramswap
ALGO=zstd
PERCENT=25
PRIORITY=100
EOF
systemctl enable zramswap.service || true
systemctl restart zramswap.service || true

# Configure Intel HD Graphics 620 (i915) & Sunrise Point-LP HD Audio power saving
cat << 'EOF' > /etc/modprobe.d/99-thinkpad-power.conf
# Intel HD Graphics (Kaby Lake / Skylake+): enable framebuffer compression & fastboot
options i915 enable_fbc=1 fastboot=1

# Intel HDA Audio: enter power-save after 1s idle
options snd_hda_intel power_save=1 power_save_controller=Y
EOF

# Apply audio power save live
echo 1 > /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null || true
echo Y > /sys/module/snd_hda_intel/parameters/power_save_controller 2>/dev/null || true

# Enable Intel thermald and power-profiles-daemon
systemctl enable --now thermald.service || true
systemctl enable --now power-profiles-daemon.service || true

# Configure ThinkPad battery charge thresholds (75% start / 90% end) to protect Li-ion longevity
for bat in /sys/class/power_supply/BAT*; do
    if [ -f "$bat/charge_control_end_threshold" ]; then
        echo 90 > "$bat/charge_control_end_threshold" 2>/dev/null || true
        if [ -f "$bat/charge_control_start_threshold" ]; then
            echo 75 > "$bat/charge_control_start_threshold" 2>/dev/null || true
        fi
    fi
done

cat << 'EOF' > /etc/systemd/system/thinkpad-battery-threshold.service
[Unit]
Description=Set Lenovo ThinkPad Battery Charge Thresholds (75%-90%)
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for bat in /sys/class/power_supply/BAT*; do [ -w "$bat/charge_control_end_threshold" ] && echo 90 > "$bat/charge_control_end_threshold" || true; [ -w "$bat/charge_control_start_threshold" ] && echo 75 > "$bat/charge_control_start_threshold" || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable thinkpad-battery-threshold.service || true

echo "=== [4/6] Optimizing Intel Dual Band Wireless-AC & Network Stack ==="
# Load TCP BBR congestion control module
modprobe tcp_bbr || true
mkdir -p /etc/modules-load.d
echo "tcp_bbr" > /etc/modules-load.d/bbr.conf

# Configure iwlwifi & iwlmvm parameters for Intel Wireless-AC (8265/8275+)
cat << 'EOF' > /etc/modprobe.d/99-iwlwifi-8265.conf
# Intel Dual Band Wireless-AC optimizations:
# - 11n_disable=8: Enables aggressive TX AMPDU frame aggregation for higher throughput
# - power_save=0: Disables link-layer power save to prevent latency spikes and drops
# - uapsd_disable=3: Disables U-APSD power save on BSS & P2P to improve AP compatibility & speed
# - bt_coex_active=1: Maintains Bluetooth/Wi-Fi coexistence
options iwlwifi 11n_disable=8 power_save=0 uapsd_disable=3 bt_coex_active=1 swcrypto=0

# Set iwlmvm power_scheme=1 (Continuously Active / CAM) instead of 2 (Balanced) to eliminate ping spikes
options iwlmvm power_scheme=1
EOF

# Disable NetworkManager Wi-Fi power saving (2 = disable)
mkdir -p /etc/NetworkManager/conf.d
cat << 'EOF' > /etc/NetworkManager/conf.d/99-wifi-powersave-off.conf
[connection]
wifi.powersave = 2
EOF
nmcli general reload 2>/dev/null || systemctl reload NetworkManager 2>/dev/null || true
for iface in /sys/class/net/wl*; do
    if [ -e "$iface" ]; then
        iw dev "$(basename "$iface")" set power_save off 2>/dev/null || true
    fi
done

# Configure Sysctl for VM, NVMe Writeback, Power, and TCP BBR + FQ Network Stack
cat << 'EOF' > /etc/sysctl.d/99-thinkpad-performance-nvme-net.conf
# --- CPU & Power Saving ---
kernel.nmi_watchdog = 0

# --- Memory & NVMe SSD Lifespan (16GB RAM + ZRAM) ---
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_background_ratio = 5
vm.dirty_ratio = 15
vm.dirty_writeback_centisecs = 1500
vm.page-cluster = 0

# --- Network & Intel Wi-Fi Throughput (TCP BBR + Fair Queueing) ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 131072 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.netdev_max_backlog = 16384
EOF
sysctl --system >/dev/null

echo "=== [5/6] Configuring Plymouth & Optimizing GRUB (1920x1080 Flicker-Free Boot) ==="
if /usr/sbin/plymouth-set-default-theme -l | grep -qx "bgrt"; then
    /usr/sbin/plymouth-set-default-theme bgrt || true
else
    /usr/sbin/plymouth-set-default-theme ceratopsian || true
fi

cp -a /etc/default/grub "/etc/default/grub.bak.$(date +%Y%m%d%H%M%S)"
cat << 'EOF' > /etc/default/grub
# GRUB configuration optimized for Lenovo ThinkPad 13 2nd Gen (i5-7200U / HD 620 1920x1080 / Intel NVMe)
GRUB_DEFAULT=0
GRUB_TIMEOUT=2
GRUB_TIMEOUT_STYLE=menu
GRUB_DISTRIBUTOR=`( . /etc/os-release && echo ${NAME} )`
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash i915.enable_fbc=1 i915.fastboot=1 nmi_watchdog=0 nvme_core.default_ps_max_latency_us=5500"
GRUB_CMDLINE_LINUX=""
GRUB_GFXMODE=1920x1080x32,1920x1080,auto
GRUB_GFXPAYLOAD_LINUX=keep
EOF

update-initramfs -u -k all
update-grub

echo "=== [6/6] Post-Optimization System & NVMe Health Verification ==="
echo "--- NVMe SMART Health Summary ---"
nvme smart-log /dev/nvme0n1 | head -n 15 2>/dev/null || true
echo "--- Active Swap & ZRAM ---"
swapon --show || true
echo "--- Active Sysctl Values ---"
sysctl kernel.nmi_watchdog vm.swappiness vm.vfs_cache_pressure vm.dirty_writeback_centisecs net.ipv4.tcp_congestion_control net.core.default_qdisc net.ipv4.tcp_fastopen
echo "--- Plymouth Default Theme ---"
/usr/sbin/plymouth-set-default-theme || true
echo "=================================================================="
echo " All System Check-Up & Optimization Tasks Completed Successfully!"
echo "=================================================================="
