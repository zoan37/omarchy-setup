#!/bin/bash
# run with sudo from the omarchy-setup checkout
D=$(cd "$(dirname "$0")" && pwd)
install -m 755 "$D/ser8-whine-tweaks" /usr/local/bin/ser8-whine-tweaks
install -m 644 "$D/ser8-whine-tweaks.service" /etc/systemd/system/ser8-whine-tweaks.service
systemctl daemon-reload && systemctl enable --now ser8-whine-tweaks.service
systemctl --no-pager status ser8-whine-tweaks | tail -4
