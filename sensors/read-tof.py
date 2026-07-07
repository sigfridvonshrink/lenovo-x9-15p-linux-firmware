#!/usr/bin/env python3
"""Read the X9-15 ToF human-presence sensor stream.

Prereq: the sensor's IIO buffer must be enabled (run enable-tof-buffer.sh first).
Prints presence / distance / attention on change. Requires root to open the node.

  sudo ./sensors/enable-tof-buffer.sh
  sudo ./sensors/read-tof.py
"""
import glob
import os
import struct
import sys
import time


def find_prox_node():
    for d in glob.glob("/sys/bus/iio/devices/iio:device*"):
        try:
            if open(os.path.join(d, "name")).read().strip() == "prox":
                return "/dev/" + os.path.basename(d)
        except OSError:
            pass
    sys.exit("no 'prox' IIO device — ISH firmware loaded and buffer enabled?")


def main():
    node = find_prox_node()
    last = None
    with open(node, "rb") as f:
        while True:
            rec = f.read(12)  # <iii : presence(0/1), distance_mm, attention(0/100)
            if len(rec) < 12:
                break
            presence, distance_mm, attention = struct.unpack("<iii", rec)
            cur = (presence, attention)
            if cur != last:
                state = "PRESENT" if presence else "AWAY"
                print(f"{time.strftime('%H:%M:%S')}  {state:7}  "
                      f"distance={distance_mm:>4} mm  attention={attention}", flush=True)
                last = cur


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
