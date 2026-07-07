# ToF human-presence sensor — protocol & meaning

The X9-15p Gen 1 (2026) presence sensor is an **ST VL53L5CX** multizone Time-of-Flight, hosted on
the Intel ISH and exposed via `hid-sensor-hub` as the IIO device named **`prox`**. The
presence/head-orientation AI runs inside the ISH firmware.

## Enumeration

IIO indices are **not stable** (the machine has two `als` devices too) — match by name:

```sh
D=$(for x in /sys/bus/iio/devices/iio:device*; do
      [ "$(cat "$x/name")" = prox ] && echo "$x" && break; done)
```

## Channels

| channel              | index | buffer type    | meaning                                   |
|----------------------|-------|----------------|-------------------------------------------|
| `in_proximity0_raw`  | 0     | `le:s8/32>>0`  | **presence**: `1` = person in FoV, `0` = gone |
| `in_proximity1_raw`  | 1     | `le:s16/32>>0` | **distance** to user, **millimetres**     |
| `in_attention_input` | 2     | `le:s8/32>>0`  | **attention**: `100` present / `0` absent |

`sampling_frequency = 10` Hz. Each channel occupies 32 bits (4 bytes) in the buffer.

## Activation (critical)

`_raw`/`_input` sysfs reads return a **frozen standby value** — the ToF only ranges
while a consumer has the IIO **buffer** enabled, and live data comes over the **device
node**, not sysfs.

```sh
for c in "$D"/scan_elements/*_en; do echo 1 | sudo tee "$c" >/dev/null; done
[ -z "$(cat "$D/trigger/current_trigger")" ] && \
  echo prox-dev1 | sudo tee "$D/trigger/current_trigger" >/dev/null
echo 1 | sudo tee "$D/buffer0/enable" >/dev/null   # some kernels: buffer/enable
```

(`enable-tof-buffer.sh` does exactly this.) Not persistent across reboot; the node is
root-only by default (add a udev rule for user access).

## Reading

12-byte records, `struct <iii` = `[presence, distance_mm, attention]`, ~10/s:

```python
import struct
with open("/dev/iio:device1", "rb") as f:
    while chunk := f.read(12):
        presence, distance_mm, attention = struct.unpack("<iii", chunk)
```

On leave, all three go to 0 in the same record.

## Semantics & limits (measured)

- **presence** — reliable enter/leave, flips `1→0` single-sample the instant you leave FoV.
- **distance** — live, granular mm (≈50 mm at the sensor to several hundred mm seated).
- **attention** — **NOT gaze.** It's ToF head-orientation, and the firmware force-pins it
  to `100` whenever you're present (turning your head does nothing). Effectively a copy of
  `presence`. Real look-away detection would need the IR camera + vision model
  (Windows-only) — not available with this ToF on Linux.

**Usable:** presence (lock/dim on leave, wake on return), distance (thresholds).
**Not usable:** "dim while I look away but stay seated."

## Notes

- Continuous ranging costs power/minor heat — only enable if you use it; consider
  disabling on battery. Firmware self-throttles frame rate by attention.
- Debounce presence (ignore single-sample `0` blips) before acting.
- Never auto-*unlock* on approach — approach may at most wake the display.
