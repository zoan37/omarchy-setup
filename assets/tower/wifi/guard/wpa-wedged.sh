#!/bin/bash
# Exit 0 (= wedged) if wpa_supplicant is stuck in sendto() on a full AF_PACKET socket.
p=$(pgrep -xo wpa_supplicant) || exit 1
grep -q sock_alloc_send_pskb /proc/$p/stack 2>/dev/null && exit 0
read -r t tb pct < <(/usr/local/bin/eapol-wmem.sh) && [ -n "$pct" ] && [ "$pct" -ge 95 ] && exit 0
exit 1
