#!/bin/bash
# Builds the MT7921U module chain from stable v7.2.15 + the two upstream mt76 fixes
# (7.3.y ad626a35bd78 "fix memory leak in USB TX path" and its prerequisite ec6d03d8b21c).
# Output: ./mt76-patched/*.ko next to this script. Loads nothing, installs nothing.
# Runs at nice 19 / idle I/O so it can share the box with a training job.
set -euo pipefail
K=${KVER:-$(uname -r)}; [ "$K" = 7.2.15-1-omarchy ] || { echo "patches are for 7.2.15; running $K. Kernel >= 7.3.4 already has the fix."; exit 1; }
H=$(dirname "$(readlink -f "$0")"); W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
git clone -q --depth 1 --no-checkout --branch v7.2.15 \
  https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git "$W/linux"
git -C "$W/linux" sparse-checkout set drivers/net/wireless/mediatek/mt76
git -C "$W/linux" checkout -q
git -C "$W/linux" apply "$H"/0001-*.patch "$H"/0002-*.patch
rm -rf "$H/mt76-patched"; cp -r "$W/linux/drivers/net/wireless/mediatek/mt76" "$H/mt76-patched"
off=""; for c in MT76_SDIO MT76x02_LIB MT76x02_USB MT7601U MT76x0_COMMON MT76x0U MT76x0E MT76x2_COMMON \
  MT76x2E MT76x2U MT7603E MT7615_COMMON MT7615E MT7663_USB_SDIO_COMMON MT7663U MT7663S MT7915E MT7921E \
  MT7921S MT7996E MT7925_COMMON MT7925E MT7925U; do off+=" CONFIG_$c="; done
nice -n 19 ionice -c3 make -j4 -C /lib/modules/$K/build M="$H/mt76-patched" $off modules
find "$H/mt76-patched" -name '*.ko' | sort
modinfo -F vermagic "$H/mt76-patched/mt76.ko"
