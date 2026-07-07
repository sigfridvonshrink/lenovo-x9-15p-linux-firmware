#!/usr/bin/env bash
# uninstall.sh — remove everything install.sh added. Run as root.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root: sudo $0" >&2; exit 1; }

VAULT=/usr/local/lib/x9-15-firmware
HOOK=/etc/initramfs-tools/hooks/x9-15-firmware

if [ -d "$VAULT" ]; then
    # Remove the installed /lib/firmware copies that mirror the vault.
    find "$VAULT" -type f | while read -r vf; do
        rel="${vf#"$VAULT"/}"
        rm -f "/lib/firmware/$rel" && echo " [*] removed /lib/firmware/$rel"
    done
    rm -rf "$VAULT" && echo " [*] removed vault $VAULT"
fi
rm -f "$HOOK" && echo " [*] removed hook $HOOK"

# Optional ToF scaffolding, if it was installed.
if [ -e /etc/systemd/system/x9-15-tof.service ]; then
    systemctl disable --now x9-15-tof.service 2>/dev/null || true
    rm -f /etc/systemd/system/x9-15-tof.service /usr/local/sbin/x9-15-enable-tof-buffer
    systemctl daemon-reload 2>/dev/null || true
    echo " [*] removed ToF service"
fi

echo " [*] rebuilding initramfs ..."
update-initramfs -u
echo " [*] Done. Reboot. (Symlinked .wmfw names, if any, were left in place — harmless.)"
