#!/bin/bash
# Install (or reinstall) the XPS 16 local speaker tuning directory.
#
#   sudo bash ~/.local/share/omarchy-xps16-tuning/restore.sh
#   xps16-tuning              # confirm which variant came back
#
# Creates a tuning directory that SHADOWS the packaged dell-xps-2026 one:
# omarchy-audio-tuning returns the first tunings/*/ dir whose match_* passes,
# in glob order, and `dell-xps-16-custom` sorts before `dell-xps-2026`. The
# packaged files are never modified, so `xps16-tuning stock` is a real A/B
# against upstream rather than a reconstruction of it.
#
# Root is needed only because /usr/share/omarchy is root-owned. The directory
# is chowned to the invoking user afterwards so xps16-tuning can swap variants
# without sudo -- same arrangement as the XPS 13 kit.
#
# Run this again after any omarchy update that wipes the directory.
set -euo pipefail

here="$(dirname "$(readlink -f "$0")")"
dst=/usr/share/omarchy/default/audio/tunings/dell-xps-16-custom
packaged=/usr/share/omarchy/default/audio/tunings/dell-xps-2026
owner="${SUDO_USER:-$USER}"

[[ $EUID -eq 0 ]] || {
  echo "Needs root (writes under /usr/share/omarchy). Re-run with sudo." >&2
  exit 1
}

# The variants embed the packaged chain verbatim, so a release that changes it
# leaves them stale without any visible error. Say so rather than silently
# installing a curve built against an older upstream.
if [[ -r $packaged/filter-chain.conf ]]; then
  if ! cmp -s "$here/variants/stock.conf" "$packaged/filter-chain.conf"; then
    echo "WARNING: packaged dell-xps-2026 chain differs from variants/stock.conf." >&2
    echo "         Upstream changed. Rebuild before trusting these variants:" >&2
    echo "           python3 $here/build-variants.py" >&2
    echo "         Continuing with the variants as they are." >&2
  fi
else
  echo "WARNING: packaged dell-xps-2026 tuning not found at $packaged" >&2
  echo "         The variants were built from it; they may not match this release." >&2
fi

variant="$(cat "$here/default-variant" 2>/dev/null || echo soft)"
src="$here/variants/$variant.conf"
[[ -r $src ]] || {
  echo "No such variant: $variant (looked for $src)" >&2
  exit 1
}

install -d "$dst"
install -m644 "$here/tuning.conf" "$dst/tuning.conf"
install -m644 "$src"              "$dst/filter-chain.conf"
sed -i "s|^description=.*|description=\"Dell XPS 16 (2026) speakers [$variant, experimental]\"|" \
  "$dst/tuning.conf"
chown -R "$owner:$owner" "$dst"

echo "Installed: $dst (variant: $variant)"
echo
echo "Now, as your user:"
echo "  omarchy audio tuning on --force"
echo "  xps16-tuning                     # list variants, show what is active"
