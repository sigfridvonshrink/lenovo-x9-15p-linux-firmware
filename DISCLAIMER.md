# Disclaimer & firmware licensing

## No firmware is distributed by this project

This repository contains **only** scripts and documentation. It ships **no** firmware
binaries. The speaker tuning, DSP `.wmfw`, and Intel ISH sensor-hub images are
proprietary and remain the property of their respective owners (Lenovo, Intel, Cirrus
Logic, STMicroelectronics).

You obtain those binaries yourself by downloading the **official Lenovo Windows driver
package for your own machine** from Lenovo Support, and these scripts extract and
install them locally on that same machine. This is the same firmware Lenovo already
licensed to you with your laptop; it is never redistributed here.

**Do not** commit extracted `.bin` / `.wmfw` firmware to this or any public repository.
The included `.gitignore` blocks the common firmware extensions as a safety net.

## No warranty

Provided "as is", without warranty of any kind. Loading firmware is inherently
low-level. In particular, installing the wrong Intel ISH image can wedge the sensor hub
until a clean reboot (`cmd 2 failed 10` / `hw start failed`) — see the README
troubleshooting. You run this at your own risk. The authors are not liable for any
damage or data loss.

## Scope

Intended for the Lenovo ThinkPad X9-15p Gen 1 (2026, Panther Lake) and close siblings
on Linux, as a stopgap until this firmware is shipped by `linux-firmware`. When that
happens, uninstall this and use the distribution packages. (The 2025 X9-15 Gen 1 /
Lunar Lake is a different machine and already supported upstream.)
