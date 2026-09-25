#!/bin/bash
# Install board-2.bin on an omarchy-snapdragon install. The driver reads the per-kernel firmware
# dir /usr/lib/firmware/<release>/, a read-only bind mount of the oma-snap "set" directory, so the
# file must go into the set. Then reboot (modprobe -r ath12k hangs). usage: sudo ./install-wifi-board.sh board-2.bin
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
src=${1:-board-2.bin}
for d in /usr/lib/oma-snap/sets/*/firmware/$(uname -r)/ath12k/QCC2072/hw1.0; do
  [ -e "$d/board-2.bin" ] && [ ! -e "$d/board-2.bin.orig" ] && cp -a "$d/board-2.bin" "$d/board-2.bin.orig"
  install -m 644 "$src" "$d/board-2.bin" && echo "installed into $d"
done
install -Dm644 "$src" /usr/lib/firmware/ath12k/QCC2072/hw1.0/board-2.bin  # fallback for non-set kernels
echo "reboot now; then: nmcli device"
