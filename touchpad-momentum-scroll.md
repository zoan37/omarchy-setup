# Touchpad: momentum scrolling + cursor feel (XPS 13)

**Current fix: [hypr-momentum](https://github.com/zoan37/hypr-momentum)** — my
own plugin, written Aug 2026 from first principles. It replaced savonovv's
hypr-kinetic-scroll (history below).

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

## Fix: compositor-level momentum via hypr-momentum

[hypr-momentum](https://github.com/zoan37/hypr-momentum) (mine, MIT) emits
synthetic decaying scroll events at the compositor, so every app gets the same
inertia. See its README for install and the full option table. The design
notes that matter here:

- **macOS decay curve, time-based**: `v(t) = v0 · 0.998^t_ms` (Apple's
  `UIScrollViewDecelerationRateNormal`) computed from measured dt — feel is
  independent of the pad's 143 Hz report rate and of timer cadence.
- **Emits at panel refresh**: 8 ms ticks on this 120 Hz panel. This fixes the
  old 62.5 Hz-glide-on-a-120 Hz-panel problem for good.
- **Launches on libinput's scroll-end event** (FINGER source, delta 0), not
  timer heuristics; resting fingers before lifting doesn't fling.
- **ABI check is ON**: after an `omarchy update` bumps Hyprland it refuses to
  load with a clear message instead of crashing the compositor. Fix is just
  `hyprpm update` in a terminal.
- **Everything tunable at runtime** — this was impossible with the old plugin
  under Omarchy's Lua config (plugins load after config parse, so
  `hl.config` can't see plugin keys):
  ```sh
  hyprctl eval "hl.plugin.momentum.set('decay', 0.9985)"   # floatier
  hyprctl eval "hl.plugin.momentum.disable('mpv')"         # per-app off
  ```
- `disable_in_browser` defaults on, so Chrome keeps its native fling and
  doesn't double-dip.
- **`o.exec_on_start("hyprpm reload -n")` in `~/.config/hypr/autostart.lua` is
  still required** — without it all hyprpm plugins silently vanish after
  reboot ([hyprpm-notes.md](hyprpm-notes.md)).

### Migration crash (Aug 15 2026, diagnosed from core dump)

Switching from the manually loaded dev copy to the hyprpm copy with **both
loaded at once**, then unloading the dev copy, SIGABRT'd the compositor: the
two copies share the `plugin:momentum:*` config keys, unloading one deletes
the keys, and the survivor's next glide tick asserts looking them up. Not a
bug in the plugin's physics or teardown — a Hyprland plugin-system hazard.
Rule and safe migration order in
[hyprpm-notes.md](hyprpm-notes.md#gotcha-never-have-two-copies-of-one-plugin-loaded--unloading-one-aborts-the-compositor).

## History: hypr-kinetic-scroll (replaced Aug 2026)

First fix was [hypr-kinetic-scroll](https://github.com/savonovv/hypr-kinetic-scroll)
(savonovv). It worked, but: per-tick decay on a fixed 16 ms timer (62.5 Hz
glide on the 120 Hz panel, and the `interval_ms` option couldn't be set under
Omarchy's Lua config), velocity in per-event units patched by a
`delta_multiplier` fudge, ABI version check commented out (compositor-crash
risk on every Hyprland bump), and no license. Replaced by writing
hypr-momentum from first principles rather than forking, partly because of
that missing license.

## Related defaults that look wrong but aren't

- `GDK_SCALE=2` in `~/.config/hypr/monitors.lua` is an intentional Omarchy
  default (keeps XWayland GTK apps from rendering microscopic). Leave it.
- Omarchy ships `input:touchpad:scroll_factor = 0.4`. Raising it changes
  scroll *distance*, not smoothness.
