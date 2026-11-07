#!/bin/bash
# Install a patched mt7932-fullmac.ko for the running kernel and rebuild the
# normal boot image. Keeps the previous unpatched image as a boot menu fallback.
#   sudo ./mt7932-tkip-install.sh /path/to/mt7932-fullmac.ko
# Any failed check restores the previous image and menu.
set -uo pipefail
KO=${1:?usage: mt7932-tkip-install.sh /path/to/mt7932-fullmac.ko}
[ "$(id -u)" = 0 ] || { echo 'run as root'; exit 1; }
[ -f "$KO" ] || { echo "no such file: $KO"; exit 1; }
KVER=$(uname -r); ESP=/boot/efi; CONF=$ESP/limine.conf; LIN=$ESP/EFI/Linux
UKI=$LIN/omarchy_linux-aurora.efi; STOCK=$LIN/omarchy_stock-fallback.efi
PREV=$ESP/omarchy-prev.efi; BAK=$CONF.pre-tkip-install
UP=/lib/modules/$KVER/updates; NAME='Stock Wi-Fi driver (fallback)'
[ "$(modinfo -F vermagic "$KO" | cut -d' ' -f1)" = "$KVER" ] || { echo "module is not built for $KVER"; exit 1; }

die() {
  echo "FAILED: $1 -- restoring"
  [ -f "$PREV" ] && mv "$PREV" "$UKI"
  [ -f "$BAK" ] && cp "$BAK" "$CONF"
  rm -f "$UP/mt7932-fullmac.ko"; rmdir "$UP" 2>/dev/null; depmod "$KVER"; sync
  exit 1
}

echo '--- backups'
WANT=$(grep -oE 'omarchy_linux-aurora\.efi#[0-9a-f]+' "$CONF" | cut -d'#' -f2)
[ "$(b2sum "$UKI" | cut -d' ' -f1)" = "$WANT" ] || { echo 'normal image does not match its hash, nothing changed'; exit 1; }
cp "$UKI" "$PREV" && cp "$CONF" "$BAK" || { echo 'backup failed, nothing changed'; exit 1; }
# Only an unpatched image may become the fallback.
if ! lsinitcpio "$UKI" | grep -q 'updates/mt7932-fullmac.ko'; then
  cp "$UKI" "$STOCK" || die 'cannot copy fallback image'
fi
sync

echo '--- module'
mkdir -p "$UP" && install -m644 -o root -g root "$KO" "$UP/mt7932-fullmac.ko" && depmod "$KVER" || die depmod

echo '--- rebuild'
limine-mkinitcpio 2>&1 | tail -6; [ "${PIPESTATUS[0]}" = 0 ] || die limine-mkinitcpio

echo '--- verify'
L=$(lsinitcpio "$UKI") || die 'cannot read the new image'
grep -q 'updates/mt7932-fullmac.ko' <<<"$L" || die 'patched module not in image'
grep -q 'kernel/drivers/net/wireless/mediatek/mt7932/mt7932-fullmac.ko' <<<"$L" && die 'stock module still in image'
for f in aurora-peripheral-firmware.service cfg80211.ko; do grep -q "$f" <<<"$L" || die "missing $f"; done
H=$(grep -oE 'omarchy_linux-aurora\.efi#[0-9a-f]+' "$CONF" | cut -d'#' -f2)
[ "$(b2sum "$UKI" | cut -d' ' -f1)" = "$H" ] || die 'hash mismatch in limine.conf'
grep -q 'rd.luks.name=' "$CONF" || die 'disk unlock option missing'

echo '--- menu'
if ! grep -qF "//$NAME" "$CONF"; then
  CMD=$(grep -m1 -E '^[[:space:]]*cmdline:' "$CONF" | sed -E 's/^[[:space:]]*cmdline:[[:space:]]*//')
  printf '\n  //%s\n  comment: original unpatched boot image\n  protocol: efi\n  path: boot():/EFI/Linux/omarchy_stock-fallback.efi\n  cmdline: %s\n' "$NAME" "$CMD" >> "$CONF" || die 'menu edit failed'
fi
sed -i -E 's/^timeout: 1$/timeout: 3/' "$CONF" || die 'menu edit failed'
rm -f "$PREV"; sync
grep -nE '^timeout|^default_entry|^ *//|path:' "$CONF" | sed -E 's/#[0-9a-f]{32,}/#<hash>/'
echo 'Done. Reboot, then run mt7932-tkip-check.sh.'
