#!/bin/bash
# One compact line of Wi-Fi link health every 30s (journal tag wifi-stats), for history before a drop.
IF=wlp244s0f4u2i3
[ -e /sys/class/net/$IF ] || { logger -t wifi-stats "adapter missing"; exit 0; }
l=$(timeout 5 iw dev $IF link 2>&1 | tr -s " \t\n" " ")
s=$(timeout 5 iw dev $IF station dump 2>&1 | grep -E "signal:|tx retries|tx failed|beacon loss|rx drop misc|inactive time|tx bitrate|rx bitrate|connected time" | tr -s " \t\n" " ")
logger -t wifi-stats "$l | $s"
