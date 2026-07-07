# Bluetooth (Intel Panther Lake CNVi) — unstable? update the upstream firmware

The X9-15p Gen 1's Bluetooth is an **Intel CNVi radio** (PCI `8086:E476`, kernel
driver **`btintel_pcie`** — not USB). On brand-new Panther Lake silicon the
in-tree firmware that ships with your distro can lag Intel's fixes, and the stack
drops connections / fails to scan. Typical symptoms in `dmesg`:

```
Bluetooth: hci0: Opcode 0x2042 failed: -112
Bluetooth: hci0: Unable to disable scanning: -112
Bluetooth: hci0: Controller device warning (boot_stage: 0xa0db1047)
Bluetooth: hci0: ACL packet for unknown connection handle 2048
```

## The Windows firmware does NOT help here

Unlike the speaker (Cirrus) and sensor-hub (ISH) blobs — which are OS-agnostic and
*are* extracted from Lenovo's Windows driver by this repo — the Bluetooth firmware
is different:

- Linux `btintel_pcie` loads a **signed `.sfi` (Secure Firmware Image)** that Intel
  ships **only** through `linux-firmware.git`.
- Windows' `ibtpci.sys` embeds firmware in a **different, proprietary container**
  (no `.sfi`, no matching filenames). Copying blobs out of it into `/lib/firmware`
  will **not** load — signature/format mismatch, controller won't boot.

So there's nothing to extract from Windows for Bluetooth. The real fix is a
**newer upstream `.sfi`**, or failing that a **newer kernel** (the `btintel_pcie`
driver itself is still maturing for 2026 silicon).

## Fix: pull the newest upstream firmware

```bash
sudo ./update-bt-firmware.sh
```

It auto-detects the exact `ibt-*-pci.sfi` your controller requests, downloads that
one file from upstream linux-firmware, installs it **only if it's newer**, backs up
the old one, and reloads the driver.

### Verify

```bash
sudo dmesg | grep -iE 'hci0: Firmware (timestamp|SHA)'
```

Note the `timestamp`/`build`. If it changed, the update took. Then **use Bluetooth
for a while** (pair a device, let it idle) and confirm the drop bug is gone:

```bash
sudo dmesg | grep -iE 'boot_stage|-112|unknown connection|scanning failed'
```

Empty after real use = fixed. If those lines still appear under the new build, the
firmware booted fine but the bug is in `btintel_pcie`/the kernel → upgrade the
kernel next.

### Rollback

The script leaves a `*.bak-<sha>` next to the installed file. Copy it back over
`intel/ibt-*-pci.sfi` and reload `btintel_pcie` (or reboot).

---

*Verified on X9-15p Gen 1 (Debian sid, kernel 7.1.3): the Jun-2026 build
`timestamp 2026.13 / build 85926` (SHA1 `0xde043160`) dropped connections; upstream
`timestamp 2026.18 / build 88847` (SHA1 `0x38841b2b`) booted clean.*
