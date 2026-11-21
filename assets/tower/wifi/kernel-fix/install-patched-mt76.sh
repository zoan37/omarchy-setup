#!/bin/bash
# Installs the patched mt76 set into updates/, which depmod prefers over the stock kernel/ copies.
# Takes effect at the next boot; nothing is loaded or unloaded now. Stock modules are not touched.
# Rollback: ./rollback-patched-mt76.sh, then reboot.
set -euo pipefail
K=$(uname -r); [ "$K" = 7.2.15-1-omarchy ] || { echo "built for 7.2.15-1-omarchy, running $K - rebuild first"; exit 1; }
SRC=${MT76_BUILD:-$(dirname "$(readlink -f "$0")")/mt76-patched}
D=/lib/modules/$K/updates/mt76-usb-txleak-fix
sudo install -d $D/mt7921
for m in mt76 mt76-usb mt76-connac-lib mt792x-lib mt792x-usb; do sudo install -m644 $SRC/$m.ko $D/; done
for m in mt7921-common mt7921u; do sudo install -m644 $SRC/mt7921/$m.ko $D/mt7921/; done
sudo depmod -a $K
modinfo -F filename mt76 mt7921u
echo "Installed. Reboot to use it. Check after boot: modinfo -F filename mt76 (should be updates/...)"
