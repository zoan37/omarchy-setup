#!/bin/bash
# Check the patched driver is running, then try each saved network by name.
#   ./mt7932-tkip-check.sh "Network 1" "Network 2"
# Leaves you on the last network that worked. Needs no root.
if iw phy phy0 info | grep -q 'TKIP'; then echo 'patched driver running'
else echo 'stock driver running'; exit 1; fi
ok=
for n in "$@"; do
  echo "#### $n"
  if nmcli -w 40 con up "$n" >/dev/null; then
    gw=$(ip -4 route show default | awk '{print $3; exit}')
    iw dev wlan0 link | grep -E 'freq|rx bitrate'
    if ping -c3 -W2 "$gw" >/dev/null && ping -c3 -W3 1.1.1.1 >/dev/null; then echo 'internet: ok'; ok=$n; else echo 'joined, but no traffic'; fi
  else echo 'could not join'; fi
done
[ -n "$ok" ] && nmcli -w 30 con up "$ok" >/dev/null
journalctl -k -b --no-pager | grep -E 'mt7932' | grep -iE 'fail|error|timeout|mismatch|recover' | tail -10
