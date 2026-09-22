# SER8: Logi Bolt pairing and excessively fast mouse scrolling

Applied **2026-09-21** on the Beelink SER8 with a Logitech MX Anywhere 3S
mouse, MX Keys Mini keyboard, and Logi Bolt USB-A receiver (`046d:c548`) in
a rear USB port. Solaar package: `1.1.20-2`.

The receiver was detected immediately, but both peripherals initially
remained on Bluetooth. Pairing through Solaar connected them to Bolt.
Scrolling then became excessively fast; disabling the mouse's
high-resolution wheel mode restored normal scrolling, confirmed by the user.
Ghostty still felt slow afterward; restoring its default mouse-wheel
multiplier separately improved scrolling in the Codex terminal window.

## Install and pair

Run in a terminal so sudo can prompt for a password:

```sh
omarchy pkg add solaar
solaar
```

In Solaar, select **Bolt Receiver → Pair new device**, then put the desired
mouse or keyboard Easy-Switch channel into pairing mode by holding its
button for about three seconds, until the light blinks rapidly. Follow the
authentication prompts and repeat for the other device. Choose an unused
channel if available to preserve existing connections; re-pairing an occupied
channel replaces that channel's pairing.

The mouse's requested click sequence is a pairing passkey, like the code
entered on a keyboard. It authenticates the connection during setup and
helps protect against nearby attackers interfering with pairing. See
[Logitech's Bolt security white paper](https://www.logitech.com/content/dam/logitech/en/business/pdf/logi-bolt-white-paper.pdf).

No additional kernel driver or reboot was needed for pairing. Inspect the
receiver and connected devices with:

```sh
solaar show
hyprctl devices
```

`solaar show` includes hardware identifiers; omit serial numbers when sharing
its output. Receiver input devices may appear as generic **Logitech USB
Receiver** names in Hyprland instead of the mouse/keyboard model names.

## Scroll-speed fix that worked

After the switch to Bolt, the live `hires-smooth-resolution` setting was
`True`. The receiver's mouse interface was bound to `hid-generic`, and
Hyprland's global mouse scroll factor was the default `1.0`. A mismatch
between high-resolution wheel output and the receiver/driver's interpretation
was the likely cause; raw wheel events were not captured to prove the
mechanism.

Back up Solaar's config, inspect the setting, and disable it:

```sh
cp -a ~/.config/solaar/config.yaml ~/.config/solaar/config.yaml.bak.$(date +%s)
solaar config 'MX Anywhere' hires-smooth-resolution
solaar config 'MX Anywhere' hires-smooth-resolution false
solaar config 'MX Anywhere' hires-smooth-resolution
```

The final query returned **`hires-smooth-resolution = False`**, and the user
confirmed scrolling was back to normal. No Hyprland scroll-speed adjustment
was made. The mouse must be awake and connected for these commands to work.

The resulting mouse entry in `~/.config/solaar/config.yaml` included:

```yaml
hires-smooth-resolution: false
_sensitive:
  hires-scroll-mode: ignore
  hires-smooth-invert: ignore
  hires-smooth-resolution: ignore
```

This is a relevant excerpt, **not a replacement config**. `ignore` means
Solaar should leave the setting alone rather than reapply a saved value.
The saved `false` value therefore does not establish that Solaar will force
it off at every reconnect. Reboot, mouse power-cycle, and switching back to
Bluetooth were not tested during this session.

[Solaar's known-issues documentation](https://pwr-solaar.github.io/Solaar/issues/)
explains that the Linux HID++ driver also controls wheel resolution; competing
changes can produce very fast or very slow scrolling. Its general remedy is
to set **Scroll Wheel Resolution → Ignore this setting** using the icon at
the right of the setting, then turn the mouse off and on. The command above
was the immediate fix verified on this receiver; do not assume forcing it
off is correct for every Bluetooth or HID++ driver configuration.

## Ghostty follow-up: normal wheel speed, not touchpad momentum

After the device-level fix, scrolling in the Codex session inside Ghostty
still felt slow. `~/.config/ghostty/config` contained
`mouse-scroll-multiplier = 0.95`, applying that multiplier to both precision
devices and discrete mouse wheels. Ghostty's default discrete-wheel
multiplier is `3`, so the existing setting moved about one-third as far per
notch. See [Ghostty's configuration reference](https://ghostty.org/docs/config/reference#mouse-scroll-multiplier).

Back up `~/.config/ghostty/local.conf`, then add this override there:

```ini
# Use Ghostty's default wheel speed for the Logitech mouse over Bolt.
# Preserve the existing multiplier for precision scrolling devices.
mouse-scroll-multiplier = precision:0.95,discrete:3
```

The main `config` already includes `local.conf` as its last line, so this
overrides the earlier `0.95` without changing the packaged-style defaults.
Preserve the existing font and keybinding overrides in `local.conf`.
Validate and reload the running terminals:

```sh
ghostty +validate-config
ghostty +show-config | rg '^mouse-scroll-multiplier'
omarchy restart terminal
```

Validation passed and the effective configuration reported
`precision:0.95,discrete:3`. The user confirmed scrolling felt better after
the reload. The mouse's `hires-smooth-resolution` remained `False`; no
Hyprland scroll factor was changed. This restores Ghostty's standard wheel
speed, not a measured reproduction of the previous Bluetooth behavior.

The [momentum plugin](touchpad-momentum-scroll.md) is a separate laptop
touchpad feature. On this SER8, `hyprpm list` and `hyprctl plugin list`
showed only `tab-drag`, and
[hypr-momentum explicitly handles touchpads only](https://github.com/zoan37/hypr-momentum#notes).
Installing it would not add inertia to this mouse. Changing Ghostty's
multiplier changes scroll distance, not momentum.

To undo only this terminal adjustment, remove the new multiplier line from
`local.conf`, validate, and run `omarchy restart terminal` again. The earlier
`0.95` in the main config will apply. Keep the separate Bolt resolution fix
unless its symptoms also warrant reassessment.

## Recheck after updates or reconnects

Test a few wheel notches in a familiar app. If the problem returns, inspect
the live resolution setting and driver before changing desktop scroll speed:

```sh
solaar config 'MX Anywhere' hires-smooth-resolution
hyprctl getoption input:scroll_factor
readlink /sys/bus/hid/devices/0003:046D:C548.*/driver
```

If the same fast-scroll symptom returns on the recorded configuration,
repeat the verified `false` command. If a different driver or connection
instead produces very slow scrolling, use the upstream ignore-and-power-cycle
procedure and reassess.

To undo the live change and restore the observed pre-fix value:

```sh
solaar config 'MX Anywhere' hires-smooth-resolution true
```

That can reproduce the excessive speed on this setup. For a full config
rollback, quit Solaar, restore the chosen `config.yaml.bak.*` backup, and
reopen it; restoring a file alone does not necessarily reset the live device.

## Receiver placement

An external receiver can improve reception compared with an antenna inside
a metal chassis, but no Bluetooth-versus-Bolt signal or reliability comparison
was measured here. A rear port can still leave the chassis between the mouse
and receiver. If movement stutters, try a front port or short USB extension
to bring the receiver closer and away from USB 3 interference, following
[Logitech's placement guidance](https://support.logi.com/hc/en-ch/articles/360023414273-Wireless-product-not-working-properly-when-also-using-a-USB-3-0-device).
Placement was not changed as part of the scroll fix.
