#!/bin/bash
# Build an ath12k board-2.bin that includes the ASUS Zenbook A16 (UX3607OA) QCC2072 board data.
# Needs: curl, bsdtar, python3, git. Output: ./out/board-2.bin
set -euo pipefail
W=${W:-$PWD/a16-board2-work}; mkdir -p "$W" "$PWD/out"; cd "$W"
# 1. Official ASUS "Qualcomm Board Support Package" for UX3607OA (7z SFX). URL from the ASUS support API:
#    https://www.asus.com/support/api/product.asmx/GetPDDrivers?website=us&model=UX3607OA&cpu=&osid=52
PKG_URL=${PKG_URL:-"https://dlcdnets.asus.com/pub/ASUS/nb/Image/Driver/DriverPackage/50616/SOCPackage_forWebSite_Qualcomm_Z_V1.312.4500.0_50616.exe?model=UX3607OA"}
[ -f soc.exe ] || curl -sSL -A Mozilla/5.0 -o soc.exe "$PKG_URL"
off=$(python3 -c "d=open('soc.exe','rb').read(); print(d.find(b'\x37\x7a\xbc\xaf\x27\x1c'))")
tail -c +$((off+1)) soc.exe > soc.7z
bsdtar -xf soc.7z QualcommBSP/WIFI_BT/qcwlancol8480/bdwlan_qcc2072_1p0_ncm820A.elf
cp QualcommBSP/WIFI_BT/qcwlancol8480/bdwlan_qcc2072_1p0_ncm820A.elf a16.bin
# 2. Upstream container + encoder
curl -sSL -o board-2.bin https://gitlab.com/kernel-firmware/linux-firmware/-/raw/main/ath12k/QCC2072/hw1.0/board-2.bin
[ -d qca ] || git clone -q --depth 1 https://github.com/qca/qca-swiss-army-knife qca
BD=qca/tools/scripts/ath12k/ath12k-bdencoder
python3 $BD -e board-2.bin >/dev/null
python3 - <<'PY'
import json
js=json.load(open('board-2.json'))
A="bus=pci,vendor=17cb,device=1112,subsystem-vendor=105b,subsystem-device=e14f,qmi-chip-id=33,qmi-board-id=255"
js[0]["board"]=[b for b in js[0]["board"] if not any("e14f" in n for n in b["names"])]
js[0]["board"].append({"names":[A+",variant=UX3407Q",A],"data":"a16.bin"})
json.dump(js,open('board-2.json','w'),indent=4)
PY
rm -f board-2.bin; python3 $BD -c board-2.json >/dev/null
python3 $BD -i board-2.bin | grep -q e14f && cp board-2.bin "$OLDPWD/out/board-2.bin" && echo "ok: $OLDPWD/out/board-2.bin $(sha256sum "$OLDPWD/out/board-2.bin" | cut -c1-16)…"
