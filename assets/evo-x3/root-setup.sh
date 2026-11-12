#!/bin/bash
# EVO X3 root setup (from the omarchy-setup new-machine checklist). Copy assets/clock-refresh-on-resume/omarchy-clock-refresh to ~ first, then: sudo bash root-setup.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
U=${SUDO_USER:?run via sudo}

echo "== packages"
pacman -Sy --noconfirm
pacman -S --needed --noconfirm ghostty syncthing cmake hyprpm

echo "== sshd + firewall"
systemctl enable --now sshd
ufw allow from 192.168.0.0/24 to any port 22 proto tcp
ufw allow in on eno1 from 10.77.0.0/30 to any port 22 proto tcp
ufw allow syncthing

echo "== key-only SSH"
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' > /etc/ssh/sshd_config.d/10-keys-only.conf
sshd -t && systemctl reload sshd

echo "== Avahi: don't advertise docker0"
grep -q '^deny-interfaces=docker0' /etc/avahi/avahi-daemon.conf || sed -i '/^\[server\]$/a deny-interfaces=docker0' /etc/avahi/avahi-daemon.conf
systemctl restart avahi-daemon

echo "== bar clock refresh on resume"
install -Dm755 /home/$U/omarchy-clock-refresh /usr/lib/systemd/system-sleep/omarchy-clock-refresh

echo "== direct cable to the DGX Spark: static 10.77.0.2/30 (Spark is 10.77.0.1)"
if nmcli -t -f NAME c | grep -qx 'Wired connection 1'; then
  nmcli c modify 'Wired connection 1' connection.id spark-direct
fi
nmcli c modify spark-direct ipv4.method manual ipv4.addresses 10.77.0.2/30 ipv4.never-default yes \
  ipv6.method link-local connection.autoconnect yes
nmcli c up spark-direct

echo "== done"; ufw status | grep -E '22|syncthing'; ip -br addr show eno1
