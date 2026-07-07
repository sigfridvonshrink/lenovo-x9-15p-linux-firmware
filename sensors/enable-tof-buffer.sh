#!/bin/sh
# Enable the ToF human-presence sensor's IIO buffer so it streams live data.
# ALS and accelerometer do NOT need this — only the presence/ToF stream does.
# Idempotent. Run as root.
set -e

D=""
for x in /sys/bus/iio/devices/iio:device*; do
    [ "$(cat "$x/name" 2>/dev/null)" = prox ] && D="$x" && break
done
[ -n "$D" ] || { echo "no 'prox' IIO device — is the ISH firmware loaded?" >&2; exit 1; }

# Enable all scan elements (presence, distance, attention).
for c in "$D"/scan_elements/*_en; do echo 1 > "$c"; done

# Attach the sensor's own trigger if none is set (prox-devN for iio:deviceN).
if [ -z "$(cat "$D/trigger/current_trigger" 2>/dev/null)" ]; then
    trg="$(basename "$D" | sed 's/iio:device/prox-dev/')"
    echo "$trg" > "$D/trigger/current_trigger" 2>/dev/null || true
fi

# Enable the buffer (kernels differ on buffer0/ vs buffer/).
if [ -e "$D/buffer0/enable" ]; then echo 1 > "$D/buffer0/enable"
else echo 1 > "$D/buffer/enable"; fi

echo "ToF streaming on $D — read /dev/$(basename "$D") (12-byte records: presence,distance_mm,attention)"
