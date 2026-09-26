#!/bin/bash
# run with sudo from the omarchy-setup checkout
D=$(cd "$(dirname "$0")" && pwd)
install -m 755 "$D/ser8-whine-tweaks" /usr/local/bin/ser8-whine-tweaks
install -m 644 "$D/ser8-whine-tweaks.service" /etc/systemd/system/ser8-whine-tweaks.service
[ -e /etc/default/ser8-whine ] || printf "# C3_OFF=1 also disables the C3 idle state (quieter buzz, +6 C idle, fan ~1000 rpm)\nC3_OFF=0\n" > /etc/default/ser8-whine
systemctl daemon-reload && systemctl enable ser8-whine-tweaks.service; systemctl restart ser8-whine-tweaks.service
systemctl --no-pager status ser8-whine-tweaks | tail -4
