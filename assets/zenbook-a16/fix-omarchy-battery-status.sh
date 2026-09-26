#!/bin/bash
# Make omarchy-battery-status find Qualcomm batteries (qcom-battmgr-bat, UPower path
# .../battery_qcom_battmgr_bat). Stock script only matches "BAT" (BAT0 on x86), so the power
# panel shows no percentage/size/cycles/time on Snapdragon. qcom-battmgr also reports power_now
# negative while discharging, so take its absolute value. Idempotent; re-run by the
# pacman hook zz-omarchy-battery-status.hook after omarchy upgrades.
f=/usr/bin/omarchy-battery-status
[[ -f $f ]] || exit 0
sed -i \
  -e "s/grep BAT | head -n 1/grep -E 'BAT|_bat\$' | head -n 1/" \
  -e 's|"\$power_supply_path"/BAT\*/|"$battery_path"/|g' \
  -e 's|BEGIN { print microwatts / 1000000 }|BEGIN { w = microwatts / 1000000; print (w < 0 ? -w : w) }|' \
  "$f"
