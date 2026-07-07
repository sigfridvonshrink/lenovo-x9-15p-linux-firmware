# Lenovo ThinkPad X9-15p Gen 1 (2026) — speaker & sensor firmware for Linux

Brings up the hardware that Linux can't drive out of the box on the **ThinkPad
X9-15p Gen 1 (2026, Panther Lake — project "Poseidon")** because the firmware isn't in
`linux-firmware` yet — by extracting it from Lenovo's official Windows driver package.

> **Model matters.** This is for the **2026 X9-15p Gen 1** (Panther Lake). It is **not**
> the **2025 X9-15 Gen 1** (Lunar Lake) — that older machine's sensor firmware *is*
> already in `linux-firmware` (`ish_lnlm_lenovo_x9-15_2025…`) and does not need this.

Once installed you get:

| Component | What starts working | Kernel driver |
|---|---|---|
| **Speakers** | 4× Cirrus CS35L57 amps (proper tuning/volume, no more silent/quiet output) | `snd_soc_cs35l56` |
| **Sensor hub (ISH)** | The Intel Sensor Hub actually boots instead of `hw start failed` | `intel_ish_ipc` |
| **Ambient light** | Auto-brightness (`iio` illuminance) | `hid-sensor-als` |
| **Accelerometer** | Screen auto-rotate / tablet orientation | `hid-sensor-accel-3d` |
| **ToF human presence** | Presence + distance (optional, for lock/dim-on-leave) — see [Sensors](#5-sensors) | `hid-sensor-prox` |

> **This repo contains no firmware.** The blobs are proprietary (Lenovo / Intel /
> Cirrus / ST). You download Lenovo's driver package for **your own machine** and
> these scripts extract and install from it. Nothing here is redistributed.

---

## 0. Does this apply to me?

Made for the **X9-15p Gen 1 (2026, Panther Lake)**. It also adapts to close siblings
(X9-14 Gen 1 2026, some X1 2026) because the installer keys off the exact firmware names
*your* kernel requests, not hardcoded ones. If you're on the **2025 X9-15 Gen 1 (Lunar
Lake)**, you don't need this — update `linux-firmware` instead.

Check you actually have the gap:

```bash
sudo dmesg | grep -iE 'firmware: failed to load .*(cs35l5|ish_ptl)'
```

If you see lines like:

```
cs35l56 ...: firmware: failed to load cirrus/cs35l57-b2-dsp1-misc-17aa2355-spkid1-l1u0.bin (-2)
intel_ish_ipc ...: firmware: failed to load intel/ish/ish_ptl_53c4ffad_6a9af742_....bin (-2)
```

…you're in the right place. (Your `17aaXXXX` / hash values may differ — that's fine.)

Requirements: Debian **trixie/sid** (or any recent distro with the `cs35l56` and
`intel-ish` drivers — kernel ≥ 6.11ish), `initramfs-tools`, and one of `7z` /
`p7zip-full` or `innoextract` to unpack the Windows driver.

---

## 1. Get the Lenovo driver package

From Lenovo Support → your X9-15 → **Drivers & Software**, download **both**:

- **Audio driver** (Realtek/Cirrus SmartAmp package) — contains the CS35L57 speaker
  tuning + the `.wmfw`.
- **Camera/Sensor / Integrated Sensor Solution** package — contains the ISH sensor-hub
  firmware (`ishS_SI_*.bin`) and the ToF/ALS/accel definitions.

They're `.exe` installers. You don't run them — you just unpack them.

## 2. Unpack it on Linux

```bash
mkdir -p ~/x9drivers && cd ~/x9drivers
7z x /path/to/<audio-driver>.exe   -o audio
7z x /path/to/<sensor-driver>.exe  -o sensor
# or, if 7z can't: innoextract /path/to/<driver>.exe
```

You want the tree that contains a top-level `DRIVERS/` (or the `CS/` and `Sensor/`
folders). Point the installer at whatever directory holds them — it searches
recursively, so the common parent of both extracted packages is fine:

```
~/x9drivers/            <-- pass this
├── audio/…/CS/XU_Ext/lenovo/tn/35L57/2355/dflt/b2_dflt_SS1_2355_*_l1u0.bin  (speaker tuning)
├── audio/…/…/fw/35L56/…/b2_dflt_35l56_*.wmfw                                (speaker DSP fw)
└── sensor/…/Lenovo/FwImage/0004/ishS_SI_5.8.1.7779.bin                      (ISH firmware)
```

## 3. Install

```bash
git clone https://github.com/sigfridvonshrink/lenovo-x9-15p-linux-firmware.git
cd lenovo-x9-15p-linux-firmware
sudo ./install.sh ~/x9drivers
sudo reboot
```

What it does:

1. Reads `dmesg` for the firmware names your kernel is failing to load.
2. Finds the matching blobs in your extracted driver tree and installs them under
   those exact names in `/lib/firmware/`.
3. Mirrors an authoritative copy to `/usr/local/lib/x9-15-firmware/` (the *vault*).
4. Installs an initramfs hook and rebuilds the initramfs.

## 4. Verify (after reboot)

```bash
# Speakers: tuning loaded, "Calibration applied", no -2 errors
sudo dmesg | grep -i cs35l56 | grep -iE 'bin|Calibration|failed'

# ISH: booted clean (NO 'cmd 2 failed' / 'hw start failed')
sudo dmesg | grep -i ish_ipc

# Sensors present
for d in /sys/bus/iio/devices/iio:device*; do echo "$d = $(cat $d/name)"; done
# expect: als, accel_3d, prox, …
cat /sys/bus/iio/devices/iio:device*/in_illuminance_raw 2>/dev/null   # light level moves
```

Play audio — both speakers should sound full. Auto-brightness and auto-rotate should
work (GNOME picks up the `iio` sensors automatically).

---

## 5. Sensors

**Ambient-light and accelerometer need nothing extra** — once the ISH firmware boots
and the `hid-sensor-*` modules load, GNOME/`iio-sensor-proxy` consume them directly
(auto-brightness, auto-rotate).

### ToF human-presence (optional, advanced)

The X9-15 has an **ST VL53L5CX Time-of-Flight** sensor exposed as the `prox` iio
device. Unlike ALS/accel it stays in standby until a consumer enables its buffer, and
its live data comes over the device node, not `_raw`. Enable + read:

```bash
sudo ./sensors/enable-tof-buffer.sh          # powers the ToF, starts streaming
sudo hexdump -C /dev/iio:device1             # 12-byte records; bytes change as you move
```

Record format: `struct <iii` = **presence(0/1), distance_mm, attention(0/100)** @ ~10 Hz.
See [`sensors/TOF.md`](sensors/TOF.md) for the full protocol, meaning, limits, and a
Python reader.

To keep it enabled at every boot (only if you plan to *use* it — it draws power to
range continuously):

```bash
sudo install -Dm755 sensors/enable-tof-buffer.sh /usr/local/sbin/x9-15-enable-tof-buffer
sudo install -Dm644 sensors/x9-15-tof.service   /etc/systemd/system/x9-15-tof.service
sudo systemctl enable --now x9-15-tof.service
```

> Note: `attention` here is ToF head-orientation, not gaze — it tracks presence, not
> where you're looking. Presence + distance are the reliable signals. Details in TOF.md.

---

## How it survives kernel upgrades

- Firmware in `/lib/firmware` is **not kernel-versioned**, so a new kernel reuses it.
- The initramfs hook (`/etc/initramfs-tools/hooks/x9-15-firmware`) runs automatically
  on **every** kernel install: it re-bundles the ISH firmware into the new initramfs
  and **self-heals** the `/lib/firmware` copies from the vault if anything removed them.
- If a package upgrade ever clobbers a file, re-run `sudo ./install.sh ~/x9drivers`,
  or just rebuild the initramfs (`sudo update-initramfs -u`) to trigger the self-heal.

When `linux-firmware` eventually ships these files officially, the packaged versions
win on upgrade — you can then `./uninstall.sh` and delete this. That's the goal.

## Uninstall

```bash
sudo ./uninstall.sh
```

Removes the vault, the initramfs hook, and the files this tool installed (it keeps a
manifest), then rebuilds the initramfs.

---

## Troubleshooting

**`ISH loader: cmd 2 failed 10` / `hw start failed`** — you installed the wrong ISH
image. The Intel-generic build under `IntelDriver/IshHeci/.../FWImage/` is **rejected**
by the bootloader; only the **Lenovo** one under `.../Lenovo/FwImage/<NN>/ishS_SI_*.bin`
works. The installer picks the Lenovo one automatically — make sure the *sensor* driver
package is included in the directory you passed. A wedged ISH also needs one clean
reboot to recover.

**No `failed to load` lines in dmesg** — either it's already working, or your ring
buffer rolled. Reboot and re-check immediately, or `journalctl -k -b | grep -i 'failed to load'`.

**Speaker `.wmfw` also missing** — the installer handles it (installs the base
`cs35l57-b2-dsp1-misc.wmfw` from `b2_dflt_35l56_*.wmfw` and symlinks the per-amp names).

**IIO device index moves** (there are two `als` devices) — always match by `name`,
never hardcode `iio:deviceN`.

## Manual mapping (reference)

If you'd rather do it by hand, or adapt for another SKU — the name translation:

- **Speakers:** `cirrus/cs35l57-b2-dsp1-misc-17aa<MODEL>-spkid<N>-l<L>u<U>.bin`
  ⇐ `.../tn/35L57/<MODEL>/dflt/b2_dflt_SS<N>_<MODEL>_{LW,RW}_l<L>u<U>.bin`
  (`SS<N>` == `spkid<N>`; `<MODEL>` = last 4 hex of the subsystem id; `l<L>u<U>` =
  the SoundWire link/unit, matches the `sdw:0:L:...:U` in dmesg 1:1).
- **ISH:** the longest `intel/ish/ish_ptl_<hash…>.bin` the kernel probes
  ⇐ `.../Sensor/.../Lenovo/FwImage/<NN>/ishS_SI_<ver>.bin` (Lenovo build only).

## Status / upstreaming

This is a stopgap. The right long-term fix is these blobs landing in
[`linux-firmware`](https://gitlab.com/kernel-firmware/linux-firmware). If you can help
push that (or have contacts at Lenovo/Intel to get them submitted), please do.

## Credits & license

Scripts/docs: MIT (see `LICENSE`). Firmware blobs are **not** included and remain
property of their vendors — see [`DISCLAIMER.md`](DISCLAIMER.md). Use on your own
hardware only.
