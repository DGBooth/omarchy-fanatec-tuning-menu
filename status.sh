#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 DGBooth
# Emit key=value lines describing the first hid-fanatecff device, or nothing.
for d in /sys/bus/hid/drivers/fanatec/*/; do
  [ -e "$d/range" ] || continue
  rd() { cat "$d/$1" 2>/dev/null | head -n1; }
  echo "connected=1"
  echo "name=$(sed -n 's/^HID_NAME=//p' "$d/uevent")"
  echo "hid_id=$(sed -n 's/^HID_ID=//p' "$d/uevent")"
  echo "range=$(rd range)"
  echo "wheel_id=$(rd wheel_id)"
  echo "fw=$(rd fw_version)"
  t=$(ls -d /sys/class/ftec_tuning/*/ 2>/dev/null | head -n1)
  if [ -n "$t" ]; then
    [ -w "${t}SLOT" ] && echo "tun_writable=1" || echo "tun_writable=0"
    for a in SLOT SEN FF FEI FOR SPR DPR ACP BLI SHO DRI NDP NFR NIN INT FFS FUL brF advanced_mode; do
      [ -r "$t$a" ] && echo "tun_$a=$(head -n1 "$t$a" 2>/dev/null)"
    done
  fi
  exit 0
done
echo "connected=0"
