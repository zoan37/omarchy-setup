# Touchpad: momentum scrolling + cursor feel (XPS 13)

## The hardware is fine — don't chase it

Measured the Goodix pad (`GXTP7863:00 27C6:0D4B`, I2C-HID) by reading raw
evdev (Aug 2026):

- Report rate **143 Hz**, rock solid (median 6.98 ms, p99 7.92 ms).
- 31 units/mm (~787 dpi), 117.3 x 66.5 mm, fuzz=0, clean stream, no i2c_hid
  errors, no libinput "touch jump" warnings.
- Reports **no pressure and no contact size** (all those axes max=0), so
  libinput can't do pressure/size-based palm rejection on this pad.
- Absent from libinput's quirks DB even though sibling Dell Goodix pads
  (0F60/0F61/0F62) get `AttrInputProp=+INPUT_PROP_PRESSUREPAD`.

Any cursor weirdness is downstream (libinput accel / Hyprland / 143 Hz input
vs 120 Hz scanout beat), not the hardware.

## Why scrolling doesn't feel like macOS

**Momentum scrolling on Linux is per-application.** libinput deliberately
doesn't generate it — each app is expected to compute its own fling. Chrome
has momentum (Blink's fling controller); foot/ghostty/kitty have none. On
macOS, WindowServer emits momentum-phase events so every app gets identical
inertia — that *uniformity* is what's missing. Terminals are extra-handicapped:
foot scrolls in whole text lines (dnkl/foot#300; alacritty#2053 same).

## Fix: compositor-level kinetic scroll

Installed [hypr-kinetic-scroll](https://github.com/savonovv/hypr-kinetic-scroll)
via `hyprpm` — momentum for every app at the compositor level. Works well.

Hard-won details:

- **`o.exec_on_start("hyprpm reload -n")` in `~/.config/hypr/autostart.lua` is
  required** — without it the plugin silently vanishes after reboot.
- **Plugin's numeric options can't be set under Omarchy's Lua config.**
  `hl.config` rejects plugin keys, `hl.keyword` doesn't exist, `hyprctl
  keyword` and `hyprctl eval` with `hl.config` are refused under the Lua
  parser. So it runs at defaults (`interval_ms=16`, a 62.5 Hz decay tick on a
  120 Hz panel).
- What *does* work — per-app disable at runtime:
  `hyprctl eval 'hl.plugin.kinetic_scroll.disable("com.mitchellh.ghostty")'`
- `disable_in_browser` defaults to 1, so Chrome keeps its native fling and
  doesn't double-dip.
- **Risk:** the plugin's ABI version check is commented out (`main.cpp:191`).
  After `omarchy update` bumps Hyprland it may crash the compositor instead of
  refusing to load. Escape hatch from a TTY:
  `hyprpm disable hypr-kinetic-scroll`, then `hyprpm update`.

## Related defaults that look wrong but aren't

- `GDK_SCALE=2` in `~/.config/hypr/monitors.lua` is an intentional Omarchy
  default (keeps XWayland GTK apps from rendering microscopic). Leave it.
- Omarchy ships `input:touchpad:scroll_factor = 0.4`. Raising it changes
  scroll *distance*, not smoothness.
