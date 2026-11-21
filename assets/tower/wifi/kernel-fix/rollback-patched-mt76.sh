#!/bin/bash
set -euo pipefail
K=$(uname -r); sudo rm -rf /lib/modules/$K/updates/mt76-usb-txleak-fix; sudo depmod -a $K
modinfo -F filename mt76; echo "Stock mt76 restored for next boot."
