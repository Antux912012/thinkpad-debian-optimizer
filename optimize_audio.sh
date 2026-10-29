#!/usr/bin/env bash
# ==============================================================================
# Lenovo ThinkPad 13 2nd Gen - Microphone & Bluetooth Headset Audio Optimizer
# Target: Realtek ALC298 (HDA Intel PCH) + PipeWire / WirePlumber + EasyEffects
#
# Fixes:
#   - Internal mic clipping/distortion caused by +60 dB total gain
#     (Internal Mic Boost +30 dB + Capture +30 dB)
#   - Bluetooth headset stuck in low-quality HSP/HFP CVSD (8 kHz) mode
#   - Default input pointing at an unstable Bluetooth mic transport
#
# Run as your NORMAL USER (not root): PipeWire runs in the user session.
#   ./optimize_audio.sh            apply settings now + install login service
#   ./optimize_audio.sh --apply    apply settings only (used by the service)
# ==============================================================================
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo "[!] Run this script as your normal user, not root (PipeWire is per-user)." >&2
    exit 1
fi

CARD_NAME="PCH"                                      # HDA Intel PCH (ALC298)
INTERNAL_MIC_NODE="alsa_input.pci-0000_00_1f.3.analog-stereo"
MIC_BOOST=0          # 0..3 (x10 dB). 0 = no analog boost -> no clipping
CAPTURE_LEVEL="65%"  # ALSA 'Capture' hardware gain
SOURCE_VOLUME="0.60" # PipeWire software volume for the internal mic

apply_settings() {
    echo "=== [1/3] Calibrating internal microphone gain (ALC298) ==="
    amixer -q -c "$CARD_NAME" set 'Internal Mic Boost' "$MIC_BOOST" || true
    amixer -q -c "$CARD_NAME" set 'Capture' "$CAPTURE_LEVEL" cap || true

    echo "=== [2/3] Setting internal mic as default input ==="
    local src_id
    src_id=$(pw-dump 2>/dev/null | python3 -c "
import json, sys
for o in json.load(sys.stdin):
    p = o.get('info', {}).get('props', {}) or {}
    if p.get('node.name') == '$INTERNAL_MIC_NODE':
        print(o['id']); break
" || true)
    if [[ -n "${src_id:-}" ]]; then
        wpctl set-default "$src_id"
        wpctl set-volume "$src_id" "$SOURCE_VOLUME"
    else
        echo "[!] Internal mic node not found, skipping."
    fi

    # Re-apply analog gain last: PipeWire's ACP mixer may remap boost on volume change
    amixer -q -c "$CARD_NAME" set 'Internal Mic Boost' "$MIC_BOOST" || true

    echo "=== [3/3] Switching Bluetooth headsets to A2DP high-fidelity playback ==="
    pw-dump 2>/dev/null | python3 -c "
import json, sys, subprocess
for o in json.load(sys.stdin):
    info = o.get('info') or {}
    props = info.get('props') or {}
    if props.get('device.api') != 'bluez5':
        continue
    profiles = (info.get('params') or {}).get('EnumProfile', [])
    names = {p.get('name'): p.get('index') for p in profiles}
    for pref in ('a2dp-sink-sbc_xq', 'a2dp-sink'):
        if pref in names:
            subprocess.run(['wpctl', 'set-profile', str(o['id']), str(names[pref])])
            print(f\"  {props.get('device.description')}: {pref}\")
            break
" || true
}

install_service() {
    local dest="$HOME/.local/bin/thinkpad-audio-optimize"
    mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
    install -m 755 "$0" "$dest"
    cat > "$HOME/.config/systemd/user/thinkpad-audio-optimize.service" << EOF
[Unit]
Description=ThinkPad 13 microphone gain & Bluetooth audio profile fix
After=pipewire.service wireplumber.service
Wants=wireplumber.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=$dest --apply

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable thinkpad-audio-optimize.service
    echo "[+] Login service installed: thinkpad-audio-optimize.service"
}

apply_settings
if [[ "${1:-}" != "--apply" ]]; then
    install_service
    echo
    echo "Tip: EasyEffects input filters (Noise Reduction, Gate, Compressor) apply to"
    echo "whichever mic is selected, including Bluetooth headsets in HSP/HFP mode."
    echo "Prefer the mSBC codec (profile 'headset-head-unit') over CVSD for headset mics."
fi
echo "Done."
