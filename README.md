# Lenovo ThinkPad Debian Optimizer (`thinkpad-debian-optimizer`)

An automated, idempotent system optimization and health check-up script for **Debian (Bookworm / Trixie / Forky / Sid)** on **Lenovo ThinkPad** laptops (specifically tuned for the **ThinkPad 13 2nd Gen — Intel Core i5-7200U, Intel HD Graphics 620, Intel 600p NVMe SSD, and Intel Dual Band Wireless-AC 8265**).

---

## ✨ What This Script Optimizes

### 1. System Check-Up, Hardware Video Acceleration & Essential Tools
- Installs `thermald`, `zram-tools`, `nvme-cli`, `smartmontools`, `plymouth`, `plymouth-themes`, `vainfo`, and `intel-media-va-driver-non-free` (enabling `contrib` and `non-free` repositories automatically if needed).
- Enables full **Intel iHD VA-API (`iHD_drv_video.so`)** hardware video decoding and encoding on Intel HD Graphics 620 (H.264, HEVC 8/10-bit, VP8, VP9, MPEG2, JPEG).
- Audits NVMe SMART health (`nvme smart-log`), active swap/ZRAM devices, THP state, and kernel parameters.

### 2. Performance, Memory/ZRAM & Battery Life
- **ZRAM Compressed Memory Swap & Zswap Conflict Prevention (`/etc/default/zramswap`):** Configures `zstd`-compressed RAM swap (`25%` of RAM at priority `100`) and disables kernel `zswap` (`zswap.enabled=0`) so pages are compressed directly into fast ZRAM without double-compression overhead.
- **Transparent Hugepages (`/etc/tmpfiles.d/thp-madvise.conf`):** Sets THP `enabled` to `madvise` and `defrag` to `defer+madvise` to avoid memory bloat and compaction latency stalls.
- **Intel GPU & Audio Power Saving (`/etc/modprobe.d/99-thinkpad-power.conf`):**
  - Enables Framebuffer Compression (`enable_fbc=1`) and flicker-free `fastboot=1` on Intel HD Graphics 620 (`i915`).
  - Enables 1-second idle power-save on Intel Sunrise Point-LP HD Audio (`snd_hda_intel power_save=1`).
- **Thermal & Power Profiles:** Enables `thermald.service` (Intel Dynamic Platform and Thermal Framework) and `power-profiles-daemon.service`.
- **CPU & VM Tuning (`/etc/sysctl.d/99-thinkpad-performance-nvme-net.conf`):**
  - Disables NMI watchdog interrupts (`kernel.nmi_watchdog = 0`).
  - Tunes `vm.swappiness = 100`, `vm.watermark_boost_factor = 0`, `vm.watermark_scale_factor = 125`, `vm.page-cluster = 0`, and `vm.vfs_cache_pressure = 50` specifically for 16 GB RAM + Zstd ZRAM laptops.
- **ThinkPad Battery Charge Thresholds (`thinkpad-battery-threshold.service`):** Sets battery charge thresholds (`75%`–`90%`, lowering `start` before raising `end` to satisfy ThinkPad EC ordering constraints) to prevent high-voltage Li-ion wear.
- **Suspend-then-Hibernate & Intelligent Lid Handling (`/etc/systemd/sleep.conf.d/` & `/etc/systemd/logind.conf.d/`):**
  - Configures `suspend-then-hibernate` with a 120-minute delay (`HibernateDelaySec=120min`).
  - On battery: closing the lid suspends immediately and automatically hibernates to disk after 2 hours (or on low battery) to prevent dead-battery surprises.
  - On AC power: closing the lid performs instantaneous standard suspend.

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

### 5. Plymouth Boot Splash, Fast Boot & 1080p Flicker-Free GRUB
- Disables `NetworkManager-wait-online.service` to eliminate ~5.5 seconds of userspace boot stall.
- Configures `/etc/default/grub` with:
  - `GRUB_TIMEOUT=2`
  - `GRUB_GFXMODE=1920x1080x32,1920x1080,auto` and `GRUB_GFXPAYLOAD_LINUX=keep` for native 1080p flicker-free handoff.
  - `GRUB_CMDLINE_LINUX_DEFAULT="quiet splash i915.enable_fbc=1 i915.fastboot=1 nmi_watchdog=0 nvme_core.default_ps_max_latency_us=5500 zswap.enabled=0 resume=UUID=<swap-uuid>"`
  - Automatically detects the swap partition UUID via `blkid` and configures both `/etc/initramfs-tools/conf.d/resume` and GRUB for seamless hibernation resume.
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

---

## 🎙️ Microphone & Bluetooth Audio Fix (`optimize_audio.sh`)

Fixes on the ThinkPad 13 (Realtek ALC298 + PipeWire/WirePlumber + EasyEffects):
- **Internal mic clipping:** the stock gain was +60 dB (`Internal Mic Boost` 3 + `Capture` 100%), making ~16% of samples clip. The script sets the boost to 0, `Capture` to 65%, and the source volume to 0.60, which brings clipping down to about 0.2%.
- **Default input** set to the built-in mic instead of the unstable Bluetooth HFP transport.
- **Bluetooth headset** switched back to A2DP **SBC-XQ** (stops it getting stuck on 8 kHz CVSD).
- Installs a systemd **user** service (`thinkpad-audio-optimize.service`) that re-applies these settings at login.

```bash
./optimize_audio.sh   # run as your normal user, NOT with sudo
```

EasyEffects input filters (Noise Reduction, Gate, Compressor) also work on Bluetooth headset mics. For the headset mic, use the mSBC profile (`headset-head-unit`) instead of CVSD.
