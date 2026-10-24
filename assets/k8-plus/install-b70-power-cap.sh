#!/bin/sh
# Install the B70 power cap (default 225 W) as a boot service. Run from the repo root with sudo.
set -e
install -Dm755 assets/k8-plus/b70-power-cap /usr/local/bin/b70-power-cap
install -Dm644 assets/k8-plus/b70-power-cap.service /etc/systemd/system/b70-power-cap.service
systemctl daemon-reload
systemctl enable --now b70-power-cap.service
