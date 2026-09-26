#!/bin/bash
# apply-a16-fixes.sh: apply all Zenbook A16 fixes to a fresh omarchy-snapdragon v0.2.2-1 install.
# Run on the laptop as root from the directory containing the bundle files:
#   sudo bash apply-a16-fixes.sh
# Idempotent. Reboot afterwards and pick the default GRUB entry.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd); R=$(uname -r)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
echo "== 1/6 Wi-Fi board file into the kernel set (+ plain firmware dir fallback)"
for d in /usr/lib/oma-snap/sets/*/firmware/$R/ath12k/QCC2072/hw1.0; do
  [ -e "$d/board-2.bin" ] && [ ! -e "$d/board-2.bin.orig" ] && cp -a "$d/board-2.bin" "$d/board-2.bin.orig"
  install -m 644 "$D/board-2.bin" "$d/board-2.bin"; echo "   -> $d"
done
install -Dm644 "$D/board-2.bin" /usr/lib/firmware/ath12k/QCC2072/hw1.0/board-2.bin
echo "== 2/6 audio UCM name"
U=/usr/share/alsa/ucm2/conf.d/glymur; ln -sf GLYMUR-ASUS-Zenbook-A16-UX3607OA.conf "$U/ASUSTeKCOMPUTERINC.-ZenbookA16UX3607OA-1.0-UX3607OA.conf"
echo "== 3/6 cpufreq: patched kernel image + GRUB entries"
SET=$(ls -d /usr/lib/oma-snap/sets/* | head -1)
python3 "$D/patch-vmlinuz-dtb.py" "$SET/vmlinuz.efi" /tmp/vmlinuz-scmipoll.efi
mkdir -p /boot/oma-snap/custom && install -m 700 /tmp/vmlinuz-scmipoll.efi /boot/oma-snap/custom/vmlinuz-scmipoll.efi
echo scmi-cpufreq > /etc/modules-load.d/scmi-cpufreq.conf
G=/boot/oma-snap/grub/grub.cfg; cp -n "$G" "$G.orig-$(date +%Y%m%d)"
ENTRY=$(ls /boot/oma-snap/entries | head -1)
CMD=$(grep -m1 -o 'cryptdevice=[^ ]* root=[^ ]* [^"]*rootfstype=btrfs' "$G")
ESP=$(grep -m1 -o 'fs-uuid --set=root [0-9A-F-]*' "$G" | awk '{print $3}')
grep -q oma-snap-custom-noignore "$G" || cat >> "$G" <<EOG
menuentry 'Omarchy Snapdragon (SCMI polling, no clk/pd_ignore_unused)' --id 'oma-snap-custom-noignore' {
  search --no-floppy --fs-uuid --set=root $ESP
  linux /oma-snap/custom/vmlinuz-scmipoll.efi $CMD arm64.nopauth quiet splash
  initrd /oma-snap/entries/$ENTRY/initramfs.img
}
menuentry 'Omarchy Snapdragon (SCMI polling, stock flags)' --id 'oma-snap-custom-scmipoll' {
  search --no-floppy --fs-uuid --set=root $ESP
  linux /oma-snap/custom/vmlinuz-scmipoll.efi $CMD clk_ignore_unused pd_ignore_unused arm64.nopauth quiet splash
  initrd /oma-snap/entries/$ENTRY/initramfs.img
}
EOG
sed -i 's/^set default=.*/set default=oma-snap-custom-noignore/' "$G"
echo "== 4/6 Windows Boot Manager GRUB entry (if a Windows ESP exists)"
WESP=$(blkid -t TYPE=vfat -o device | while read p; do m=$(mktemp -d); mount -o ro "$p" "$m" 2>/dev/null && { [ -d "$m/EFI/Microsoft" ] && echo "$p"; umount "$m"; }; rmdir "$m"; done | head -1)
if [ -n "$WESP" ]; then WU=$(blkid -s UUID -o value "$WESP"); grep -q win-ssd "$G" || cat >> "$G" <<EOG
menuentry 'Windows Boot Manager' --id 'win-ssd' {
  insmod part_gpt
  insmod fat
  insmod chain
  search --no-floppy --fs-uuid --set=root $WU
  chainloader /EFI/Microsoft/Boot/bootmgfw.efi
}
EOG
echo "   -> Windows ESP $WESP ($WU)"; fi
echo "== 5/6 quiet thermal service, fan control script + daemon, EC scripts"
install -m 755 "$D/a16-fan.sh" /usr/local/bin/a16-fan.sh
install -m 755 "$D/a16-fan-daemon" /usr/local/bin/a16-fan-daemon
install -m 644 "$D/a16-fan-daemon.service" /etc/systemd/system/a16-fan-daemon.service
[ -e /etc/default/a16-fan ] || install -m 644 "$D/a16-fan.conf" /etc/default/a16-fan
install -m 755 "$D/a16-quiet-thermal" /usr/local/bin/a16-quiet-thermal
install -m 644 "$D/a16-quiet-thermal.service" /etc/systemd/system/a16-quiet-thermal.service
install -m 755 "$D/glymur-ec-read.sh" "$D/glymur-ec-block.sh" /usr/local/bin/
install -m 644 "$D/a16-cpuidle-nosleep.service" /etc/systemd/system/a16-cpuidle-nosleep.service   # not enabled: no measurable effect
install -m 755 "$D/a16-nvme-aspm" /usr/local/bin/a16-nvme-aspm
install -m 644 "$D/a16-nvme-aspm.service" /etc/systemd/system/a16-nvme-aspm.service
systemctl daemon-reload; systemctl enable a16-quiet-thermal.service a16-fan-daemon.service a16-nvme-aspm.service >/dev/null 2>&1 || true
echo "== 5b/6 suspend is broken on this kernel (never resumes, resets instead): mask the sleep targets"
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target >/dev/null 2>&1 || true
echo "== 6/6 Wi-Fi power save (applies to any saved wireless connection)"
for c in $(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="802-11-wireless"{print $1}'); do nmcli connection modify "$c" 802-11-wireless.powersave 3 || true; done
sync; echo "DONE. Reboot; GRUB default is the patched entry. Then: nmcli device; wpctl status; ls /sys/devices/system/cpu/cpufreq/"
