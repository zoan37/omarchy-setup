#!/bin/bash
# Count how often correctable AER errors recur on a PCIe port: clear the sticky status, re-read every 0.5 s.
# Usage: link-errors.sh 0000:67:00.0 [0000:00:04.1 ...]
for d in "$@"; do hits=0; last=0
  for i in $(seq 1 20); do sudo setpci -s $d ECAP_AER+10.l=ffffffff; sleep 0.5; v=$(sudo setpci -s $d ECAP_AER+10.l); [ "$v" != "00000000" ] && hits=$((hits+1)) && last=$v; done
  echo "$d: errors in $hits/20 windows (last CESta=0x$last)"; done
