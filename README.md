# Lenovo ThinkPad Debian Optimizer (`thinkpad-debian-optimizer`)

An automated, idempotent system optimization and health check-up script for **Debian (Bookworm / Trixie / Forky / Sid)** on **Lenovo ThinkPad** laptops (specifically tuned for the **ThinkPad 13 2nd Gen — Intel Core i5-7200U, Intel HD Graphics 620, Intel 600p NVMe SSD, and Intel Dual Band Wireless-AC 8265**).

---

## ✨ What This Script Optimizes

### 1. System Check-Up & Essential Hardware Tools
- Installs `thermald`, `zram-tools`, `nvme-cli`, `smartmontools`, `plymouth`, and `plymouth-themes`.
- Audits NVMe SMART health (`nvme smart-log`), active swap/ZRAM devices, and kernel parameters.

### 2. Performance & Battery Life
- **ZRAM Compressed Memory Swap (`/etc/default/zramswap`):** Configures `zstd`-compressed RAM swap (`25%` of RAM at priority `100`) so memory pressure is handled in fast RAM before touching the NVMe swap partition.
- **Intel GPU & Audio Power Saving (`/etc/modprobe.d/99-thinkpad-power.conf`):**
  - Enables Framebuffer Compression (`enable_fbc=1`) and flicker-free `fastboot=1` on Intel HD Graphics 620 (`i915`).
  - Enables 1-second idle power-save on Intel Sunrise Point-LP HD Audio (`snd_hda_intel power_save=1`).
- **Thermal & Power Profiles:** Enables `thermald.service` (Intel Dynamic Platform and Thermal Framework) and `power-profiles-daemon.service`.
- **CPU & VM Tuning (`/etc/sysctl.d/99-thinkpad-performance-nvme-net.conf`):**
  - Disables NMI watchdog interrupts (`kernel.nmi_watchdog = 0`).
  - Tunes `vm.swappiness = 10` and `vm.vfs_cache_pressure = 50` for 16 GB RAM laptops.
- **ThinkPad Battery Charge Thresholds (`thinkpad-battery-threshold.service`):** Sets battery charge thresholds (`75%`–`90%`) to prevent high-voltage Li-ion wear.

### 3. NVMe / SSD Lifespan Protection
- **`/etc/fstab` Mount Tuning:** Automatically adds `noatime,commit=60` to the root `ext4` filesystem and remounts `/` live, eliminating read-access timestamp writes and batching journal commits to 60s intervals.
- **Dirty Page Writeback Consolidation:** Sets `vm.dirty_writeback_centisecs = 1500` (15s), `vm.dirty_background_ratio = 5`, and `vm.dirty_ratio = 15`.
- **Systemd Journal Write Cap (`/etc/systemd/journald.conf.d/99-ssd-lifespan.conf`):** Caps persistent logs (`SystemMaxUse=200M`, `SyncIntervalSec=5m`) to prevent log churn on NAND flash.
- **NVMe I/O Scheduler & Weekly TRIM (`/etc/udev/rules.d/60-nvme-ssd-optimize.rules`):** Enforces `scheduler=none`, `rq_affinity=2`, PCI runtime PM `auto`, and enables `fstrim.timer`.

### 4. Intel Dual Band Wireless-AC 8265 & Network Speed
- **Intel `iwlwifi` / `iwlmvm` Tuning (`/etc/modprobe.d/99-iwlwifi-8265.conf`):**
  - `options iwlwifi 11n_disable=8 power_save=0 uapsd_disable=3 bt_coex_active=1 swcrypto=0` (enables aggressive TX AMPDU frame aggregation via `11n_disable=8` and prevents link power-save drops).
  - `options iwlmvm power_scheme=1` (switches `iwlmvm` from Balanced/Power-save `2` to Continuously Active Mode `1` to eliminate ping spikes).
- **NetworkManager Wi-Fi Power-Save Override (`/etc/NetworkManager/conf.d/99-wifi-powersave-off.conf`):** Sets `wifi.powersave = 2` (disabled).
- **TCP BBR Congestion Control & Fair Queueing:** Enables `tcp_bbr` (`net.ipv4.tcp_congestion_control = bbr`, `net.core.default_qdisc = fq`), `tcp_fastopen = 3`, `tcp_mtu_probing = 1`, and 16 MB socket buffers.

### 5. Plymouth Boot Splash & 1080p Flicker-Free GRUB
- Configures `/etc/default/grub` with:
  - `GRUB_TIMEOUT=2`
  - `GRUB_GFXMODE=1920x1080x32,1920x1080,auto` and `GRUB_GFXPAYLOAD_LINUX=keep` for native 1080p flicker-free handoff.
  - `GRUB_CMDLINE_LINUX_DEFAULT="quiet splash i915.enable_fbc=1 i915.fastboot=1 nmi_watchdog=0 nvme_core.default_ps_max_latency_us=5500"`
- Configures Plymouth boot splash theme (`bgrt` / `ceratopsian`) and updates initramfs (`update-initramfs -u -k all`) and GRUB (`update-grub`).

---

## 🚀 Usage

```bash
git clone https://github.com/Antux912012/thinkpad-debian-optimizer.git
cd thinkpad-debian-optimizer
chmod +x optimize_thinkpad.sh
sudo ./optimize_thinkpad.sh
```

*(If run without `sudo`, the script automatically prompts for elevation via `sudo` or `pkexec`).*
