# SER8: turn off the blinking USB Wi-Fi LED

Applied **2026-09-21** on the Beelink SER8, kernel `7.2.5-3-omarchy`.
The USB Wi-Fi adapter's green activity light was distracting. Its Linux
driver exposes an LED control, so a small udev rule turns it off without
disabling Wi-Fi. No tape required.

## Hardware and discovery

| Item | Observed value |
|---|---|
| USB vendor/product | `2357:0120` (TP-Link) |
| USB product string | `802.11ac WLAN Adapter` |
| Driver | `rtw88_8821au` |
| Network interface on this boot | `wlp101s0f3u2` |
| LED on this USB port | `/sys/class/leds/rtw88-1-2:1.0` |
| Original trigger | `phy1tpt` (Wi-Fi throughput/activity) |
| Original / maximum brightness | `1` / `1` |

The useful discovery was that the adapter appears under `/sys/class/leds/`.
The driver exposes both `trigger` and `brightness`; setting the trigger to
`none` and brightness to `0` disables the activity light. This uses the
[Linux LED class interface](https://docs.kernel.org/leds/leds-class.html).
Availability depends on the driver, so this is not a universal recipe for
every USB Wi-Fi adapter.

Inspect the LED and its USB parent:

```sh
ls -l /sys/class/leds/
cat /sys/class/leds/rtw88-1-2:1.0/trigger
cat /sys/class/leds/rtw88-1-2:1.0/brightness
udevadm info --attribute-walk --path=/sys/class/leds/rtw88-1-2:1.0
```

The bracketed entry in `trigger` is the active one. USB port names and
`phy` numbers can change; inspect them again if using a different port.

## Persistent rule

The exact installed rule is archived in
[assets/ser8-usb-wifi-led/99-usb-wifi-led-off.rules](assets/ser8-usb-wifi-led/99-usb-wifi-led-off.rules).
It matches the adapter's USB vendor/product IDs and an `rtw88-*` LED name,
so it is not tied to the current USB port or network interface name:

```udev
ACTION=="add", SUBSYSTEM=="leds", KERNEL=="rtw88-*", ATTRS{idVendor}=="2357", ATTRS{idProduct}=="0120", ATTR{trigger}="none", ATTR{brightness}="0"
```

From this repository's root, install and apply it:

```sh
sudo install -m 0644 assets/ser8-usb-wifi-led/99-usb-wifi-led-off.rules /etc/udev/rules.d/99-usb-wifi-led-off.rules
udevadm verify /etc/udev/rules.d/99-usb-wifi-led-off.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --action=add /sys/class/leds/rtw88-1-2:1.0
sudo udevadm settle --timeout=10
```

Use the current LED path if the adapter moved ports. The targeted trigger
applies the rule immediately; no network restart is needed. The same rule
is intended to apply whenever the LED device is added at boot or reconnect.
It lives in `/etc/udev/rules.d/`, outside Omarchy's package-owned files.

## Verification

```sh
cat /sys/class/leds/rtw88-1-2:1.0/brightness
cat /sys/class/leds/rtw88-1-2:1.0/trigger
```

Expect brightness **`0`** and **`[none]`** in the trigger list. Both were
verified after applying the rule, and `udevadm verify` reported success.
Actual reboot and unplug/reconnect checks were not performed in this session.
If the light returns after a kernel update, check that the driver still
exposes the same LED controls and that the rule still matches.

## Undo

Remove the persistent rule and reload udev:

```sh
sudo rm /etc/udev/rules.d/99-usb-wifi-led-off.rules
sudo udevadm control --reload-rules
```

Restore blinking immediately using the original activity trigger on this
boot:

```sh
printf '%s\n' phy1tpt | sudo tee /sys/class/leds/rtw88-1-2:1.0/trigger
```

If the adapter's `phy` number changed, use its current throughput trigger
from the trigger list instead. Alternatively, unplug and reconnect the
adapter after removing the rule to restore the driver's default behavior.
