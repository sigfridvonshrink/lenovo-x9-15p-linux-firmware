#!/usr/bin/env bash
#
# install.sh — install ThinkPad X9-15 (and siblings) speaker + sensor-hub firmware
# on Debian from the official Lenovo Windows driver package, and make it survive
# kernel upgrades. Ships NO firmware itself: it extracts from YOUR download.
#
# Usage:   sudo ./install.sh /path/to/extracted/DRIVERS
#
# It auto-detects the exact firmware filenames your kernel is asking for (from
# dmesg), finds the matching blobs in the extracted Lenovo driver tree, installs
# them under the names the kernel wants, mirrors an authoritative copy to a vault,
# installs an initramfs hook, and rebuilds the initramfs.
#
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo " [*] $*"; }
warn(){ echo " [!] $*" >&2; }

[ "${1:-}" ] || die "usage: sudo $0 /path/to/extracted/DRIVERS"
DRIVERS="$1"
[ -d "$DRIVERS" ] || die "not a directory: $DRIVERS"
[ "$(id -u)" = 0 ] || die "run as root: sudo $0 $DRIVERS"

FWDIR=/lib/firmware
VAULT=/usr/local/lib/x9-15-firmware
HOOK=/etc/initramfs-tools/hooks/x9-15-firmware
SELF="$(cd "$(dirname "$0")" && pwd)"

# --- 1. What is the kernel actually asking for? ------------------------------
# Collect firmware paths that failed to load this boot (ENOENT).
mapfile -t WANT < <(dmesg 2>/dev/null \
    | grep -oE 'firmware: failed to load [^ ]+' \
    | awk '{print $NF}' | sort -u)

[ "${#WANT[@]}" -gt 0 ] || warn "No 'failed to load' firmware lines in dmesg — nothing missing, or already installed. Continuing to (re)assert known files."

install_file(){ # <src> <relpath-under-/lib/firmware>
    local src="$1" rel="$2"
    install -Dm644 "$src" "$FWDIR/$rel"
    install -Dm644 "$src" "$VAULT/$rel"
    info "installed  $rel  <-  ${src#"$DRIVERS"/}"
}

# --- 2. Cirrus CS35L5x speaker tuning coefficients (.bin) ---------------------
# Kernel wants e.g. cirrus/cs35l57-b2-dsp1-misc-17aaXXXX-spkidN-lLuU.bin
# Windows source: .../CS/XU_Ext/lenovo/tn/35L57/<MODEL>/dflt/b2_dflt_SSN_<MODEL>_{LW,RW}_lLuU.bin
# where <MODEL> = last 4 hex of the 17aaXXXX subsystem id, and SSN == spkidN.
for w in "${WANT[@]:-}"; do
    case "$w" in
      cirrus/cs35l5*-*spkid*-l*u*.bin)
        base="${w##*/}"
        spk="$(grep -oE 'spkid[0-9]+' <<<"$base" | grep -oE '[0-9]+')"
        lu="$(grep -oE 'l[0-9]+u[0-9]+' <<<"$base")"
        model="$(grep -oE '17aa[0-9a-fA-F]{4}' <<<"$base" | sed 's/^17aa//')"
        src="$(find "$DRIVERS" -type f -iname "b2_dflt_SS${spk}_${model}_*_${lu}.bin" 2>/dev/null | head -1 || true)"
        if [ -n "$src" ]; then install_file "$src" "$w"; else warn "no Windows match for $w (SS${spk}/${model}/${lu})"; fi
        ;;
    esac
done

# --- 3. Cirrus DSP firmware (.wmfw) — only if missing from linux-firmware -----
# Single Windows image b2_dflt_35l56_*.wmfw maps to cs35l57-b2-dsp1-misc.wmfw,
# with the per-amp names as symlinks to it.
wmfw_src="$(find "$DRIVERS" -type f -iname 'b2_dflt_35l5*_*.wmfw' 2>/dev/null | sort -V | tail -1 || true)"
for w in "${WANT[@]:-}"; do
    case "$w" in
      cirrus/cs35l5*-*.wmfw)
        [ -n "$wmfw_src" ] || { warn "no .wmfw in drivers for $w"; continue; }
        base_rel="cirrus/$(grep -oE 'cs35l5[0-9]-b[0-9]-dsp1-misc' <<<"$w").wmfw"
        [ -e "$FWDIR/$base_rel" ] || install_file "$wmfw_src" "$base_rel"
        if [ "$w" != "$base_rel" ]; then
            ln -sf "$(basename "$base_rel")" "$FWDIR/$w"
            info "symlink    $w -> $(basename "$base_rel")"
        fi
        ;;
    esac
done

# --- 4. Intel ISH sensor-hub firmware ----------------------------------------
# Kernel probes a cascade of hashed names ish_ptl_<hash...>.bin, most-specific
# first. Install the Lenovo-signed image under the most-specific requested name.
# Windows source: .../Sensor/.../Lenovo/FwImage/<NN>/ishS_SI_<ver>.bin
# (NOT the IntelDriver/ generic build — the ISH bootloader rejects that.)
ish_target="$(printf '%s\n' "${WANT[@]:-}" | grep -E '^intel/ish/ish_ptl_.*\.bin$' \
    | awk '{print length, $0}' | sort -rn | head -1 | cut -d' ' -f2- || true)"
if [ -n "$ish_target" ]; then
    ish_src="$(find "$DRIVERS" -ipath '*[Ll]enovo*[Ff]w[Ii]mage*' -iname 'ishS_SI_*.bin' 2>/dev/null | sort -V | tail -1 || true)"
    if [ -n "$ish_src" ]; then
        install_file "$ish_src" "$ish_target"
    else
        warn "no Lenovo ISH image (ishS_SI_*.bin under a Lenovo/FwImage dir) found in $DRIVERS"
    fi
else
    info "ISH: kernel not requesting a hashed ish_ptl firmware (already satisfied or n/a)"
fi

# --- 5. initramfs hook (auto-runs on every kernel install) --------------------
install -Dm755 "$SELF/initramfs/x9-15-firmware" "$HOOK"
info "initramfs hook -> $HOOK"

# --- 6. Rebuild initramfs -----------------------------------------------------
info "rebuilding initramfs ..."
update-initramfs -u

echo
info "Done. Reboot to load the firmware."
info "Verify after reboot:"
echo "     sudo dmesg | grep -iE 'cs35l5|ish_ipc' | grep -ivE 'failed'"
