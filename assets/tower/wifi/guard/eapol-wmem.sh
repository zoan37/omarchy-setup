#!/bin/bash
# Prints "<wmem_alloc> <sndbuf> <pct>" for wpa_supplicant's EAPOL (0x888e) packet socket,
# or nothing if not found. A healthy socket sits near 0. Unpatched mt76 USB leaks each
# zero-length WNM keep-alive (960 B; one per BSS Max Idle Period, ~491 s on this AP) until
# wmem >= sndbuf (212992, 222 keep-alives, ~30 h) and wpa_supplicant blocks in sendto().
ss -f link -a -p -e -m 2>/dev/null | awk '
  /\[34958\]/ && /wpa_supplicant/ { want=1; next }
  want && /skmem:/ { match($0,/,t[0-9]+,tb[0-9]+/); s=substr($0,RSTART+2,RLENGTH-2);
                     split(s,a,",tb"); printf "%d %d %d\n", a[1], a[2], (a[2]? a[1]*100/a[2] : 0); exit }
  { want=0 }'
