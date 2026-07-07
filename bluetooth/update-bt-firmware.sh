#!/usr/bin/env bash
#
# update-bt-firmware.sh — refresh the Intel Bluetooth firmware on the X9-15p Gen 1
# (Panther Lake CNVi, driver `btintel_pcie`) from UPSTREAM linux-firmware.
#
# Unlike the speaker/sensor blobs, the Bluetooth firmware does NOT come from the
# Lenovo Windows driver: Intel ships the Linux `.sfi` (signed Secure Firmware
# Image) only via linux-firmware.git. The blob inside Windows' `ibtpci.sys` is a
# different, unsigned-for-Linux container and will NOT load. So the only real fix
# for an unstable BT stack here is a NEWER upstream `.sfi` (or a newer kernel).
#
# This script auto-detects the exact ibt-*-pci.sfi your controller asks for,
# downloads that file from upstream, and installs it only if it's actually newer.
# Idempotent. Ships no firmware itself. Run as root.
#
#   Usage:  sudo ./update-bt-firmware.sh
#
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo " [*] $*"; }
warn(){ echo " [!] $*" >&2; }

[ "$(id -u)" = 0 ] || die "run as root: sudo $0"
command -v curl >/dev/null || die "curl not found"

FWDIR=/lib/firmware
RAW=https://gitlab.com/kernel-firmware/linux-firmware/-/raw/main

# --- 1. Which .sfi does this controller request? -----------------------------
# btintel logs e.g.: "Found device firmware: intel/ibt-00a0-01a1-pci.sfi"
SFI=$(dmesg 2>/dev/null \
    | grep -oE 'intel/ibt-[0-9a-f]{4}-[0-9a-f]{4}-pci\.sfi' \
    | tail -1)
[ -n "$SFI" ] || die "no 'Found device firmware: intel/ibt-*-pci.sfi' in dmesg — is btintel_pcie loaded?"
info "Controller firmware: $SFI"

# --- 2. Fetch upstream copy to a temp file -----------------------------------
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
info "Downloading upstream $SFI ..."
curl -fsSL "$RAW/$SFI" -o "$TMP" || die "download failed: $RAW/$SFI"
[ -s "$TMP" ] || die "downloaded file is empty"

# --- 3. Compare with what's installed ----------------------------------------
CUR="$FWDIR/$SFI"
if [ -f "$CUR" ] && cmp -s "$CUR" "$TMP"; then
    info "Already up to date ($(sha256sum "$CUR" | cut -c1-12)…) — nothing to do."
    exit 0
fi

if [ -f "$CUR" ]; then
    BAK="$CUR.bak-$(sha256sum "$CUR" | cut -c1-8)"
    cp -a "$CUR" "$BAK"
    info "Backed up current firmware -> $BAK"
    info "  old: $(stat -c%s "$CUR") bytes  $(sha256sum "$CUR" | cut -c1-12)…"
fi
install -Dm644 "$TMP" "$CUR"
info "  new: $(stat -c%s "$CUR") bytes  $(sha256sum "$CUR" | cut -c1-12)…"
info "Installed upstream firmware -> $CUR"

# --- 4. Reload the driver so the new image takes effect ----------------------
if modprobe -r btintel_pcie 2>/dev/null && modprobe btintel_pcie 2>/dev/null; then
    info "Reloaded btintel_pcie."
else
    warn "Could not hot-reload btintel_pcie (BT in use?). Reboot to load the new firmware."
fi

echo
info "Verify the new build loaded:"
echo "    sudo dmesg | grep -iE 'hci0: Firmware (timestamp|SHA)'"
info "Then USE Bluetooth a while and check the drop bug is gone:"
echo "    sudo dmesg | grep -iE 'boot_stage|-112|unknown connection|scanning failed'"
