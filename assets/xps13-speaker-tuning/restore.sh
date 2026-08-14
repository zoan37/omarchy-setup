#!/bin/bash
# Reinstall the XPS 13 speaker tuning after an Omarchy update has wiped it from
# the package-owned tunings directory.
#
#   sudo bash ~/.local/share/omarchy-xps13-tuning/restore.sh
#   xps13-tuning            # confirm which variant came back
#
# Reinstates the variant recorded in default-variant, so the curve you settled
# on is the one that returns.
set -euo pipefail

here="$(dirname "$(readlink -f "$0")")"
dst=/usr/share/omarchy/default/audio/tunings/dell-xps-13-2026-deharsh
owner="${SUDO_USER:-$USER}"

variant="$(cat "$here/default-variant" 2>/dev/null || echo soft)"
src="$here/variants/$variant.conf"
[[ -r $src ]] || {
  echo "No such variant: $variant (looked for $src)" >&2
  exit 1
}

install -d "$dst"
install -m644 "$here/tuning.conf" "$dst/tuning.conf"
install -m644 "$src"              "$dst/filter-chain.conf"
sed -i "s|^description=.*|description=\"Dell XPS 13 (2026) speakers [$variant, experimental]\"|" \
  "$dst/tuning.conf"
chown -R "$owner:$owner" "$dst"

echo "Restored: $dst (variant: $variant)"
echo "Now run as your user:  omarchy audio tuning on --force"
