#!/bin/bash
# Save a devcoredump + kernel log after a GPU hang (for the drm/amd report). Run before rebooting.
d=~/egpu-tests/hang-$(date +%Y%m%d-%H%M%S); mkdir -p $d
for c in /sys/class/drm/card*/device/devcoredump/data; do [ -e "$c" ] && sudo -n cat "$c" > $d/devcoredump-$(basename $(dirname $(dirname $(dirname $c)))).txt; done
sudo -n dmesg > $d/dmesg.txt; cp ~/egpu-tests/*.log $d/ 2>/dev/null; cat /proc/cmdline > $d/cmdline.txt
ls -la $d
