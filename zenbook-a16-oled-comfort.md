# Zenbook A16: OLED flicker-free dimming (a16-dim)

**Status: applied 2026-09-28; the owner finds the display more comfortable.** It started from headaches after long
sessions on the Zenbook A16 (Samsung Display `ATNA60HR07-0`, 2880x1800 OLED, 120 Hz), without eye strain.
Before the change the panel sat at **15 % hardware brightness** (307/2047 on `dp_aux_backlight`), which is where
OLED PWM is deepest.

## Why

- **The panel flickers (PWM) at about 1 kHz at every brightness level**
  ([UltrabookReview](https://www.ultrabookreview.com/75005-asus-zenbook-a16-review/)). OLED PWM switches the
  pixels off for part of each cycle, and the lower the hardware brightness, the longer the off part.
- **MyASUS "OLED Flicker-Free Dimming"** keeps the hardware brightness high and darkens the image in software;
  G-Helper's maintainers found it's software only, a pre-dimmed ICC profile / gamma
  ([g-helper #2056](https://github.com/seerge/g-helper/discussions/2056)). Same perceived brightness, shallower
  flicker. On this panel it reduces the flicker; it can't remove it. Linux has no MyASUS, so the Omarchy
  brightness keys dimmed the panel itself.
- **A Galaxy S26 (480 Hz PWM, no flicker-free mode) is fine for the owner**
  ([Android Authority](https://www.androidauthority.com/samsung-galaxy-s26-pwm-dimming-3643875/)), but that
  doesn't rule flicker out: flicker is easier to perceive when it fills more of the visual field and when it's
  brighter, and the phone is a small screen at arm's length.

## What a16-dim does

[`a16-dim`](assets/zenbook-a16/a16-dim) is the MyASUS model, nothing more: the panel stays fixed at **80 %**, and
the brightness keys only change hyprsunset's gamma (a color transform: no tint, no day/night schedule, standard
colors). The level is saved in `~/.local/state/a16-dim/level` and shown on Omarchy's brightness OSD.

```
a16-dim            # print the level
a16-dim +5 | -5    # step it (the keys)
a16-dim 45         # set it
a16-dim restore    # login: panel to 80 %, start hyprsunset -i, reapply the saved level
```

`PANEL=80` and `MIN=10` sit at the top of the script. Level 45 at panel 80 % looks about like the old panel 15 %
(the transform works on encoded values, so luminance falls roughly as level^2.2).

## Install

```
install -m755 assets/zenbook-a16/a16-dim ~/.local/bin/
```

`~/.config/hypr/autostart.lua`:
```lua
-- Zenbook A16 flicker-free dimming: panel to 80 %, hyprsunset, saved gamma level.
o.launch_on_start(os.getenv("HOME") .. "/.local/bin/a16-dim restore")
```

`~/.config/hypr/bindings.lua` (replaces the six defaults from `default/hypr/bindings/media.lua`):
```lua
local a16_dim = os.getenv("HOME") .. "/.local/bin/a16-dim"
for _, key in ipairs({ "XF86MonBrightnessUp", "XF86MonBrightnessDown",
                       "SHIFT + XF86MonBrightnessUp", "SHIFT + XF86MonBrightnessDown",
                       "ALT + XF86MonBrightnessUp", "ALT + XF86MonBrightnessDown" }) do
  hl.unbind(key)
end
o.bind("XF86MonBrightnessUp", "Brightness up", a16_dim .. " +5", { locked = true, repeating = true })
o.bind("XF86MonBrightnessDown", "Brightness down", a16_dim .. " -5", { locked = true, repeating = true })
o.bind("SHIFT + XF86MonBrightnessUp", "Brightness maximum", a16_dim .. " 100", { locked = true })
o.bind("SHIFT + XF86MonBrightnessDown", "Brightness minimum", a16_dim .. " 10", { locked = true })
o.bind("ALT + XF86MonBrightnessUp", "Brightness up precise", a16_dim .. " +1", { locked = true, repeating = true })
o.bind("ALT + XF86MonBrightnessDown", "Brightness down precise", a16_dim .. " -1", { locked = true, repeating = true })
```

`~/.config/hypr/hyprsunset.conf`: comment out Omarchy's `07:00 identity` profile. A scheduled profile re-applies
at its time and would reset the gamma to 100 every morning; `a16-dim` starts hyprsunset with `-i` instead, so
there's no tint without it. (`omarchy-refresh-hyprsunset` puts the profile back.)

Then `hyprctl reload` and `a16-dim restore` from a terminal in the session.

## Gotchas found while building it

- **hyprsunset gamma works on this msm driver**: Hyprland logs `drm: connector eDP-1 crtc supports CTM`, and
  `hyprctl hyprsunset gamma 50` visibly dims.
- **`brightnessctl` over SSH fails** with `Operation not permitted`: it goes through logind, and an SSH session
  isn't the active seat. The keys and autostart run in the desktop session and are fine; from SSH use
  `systemd-run --user --wait -E WAYLAND_DISPLAY=wayland-1 -E HYPRLAND_INSTANCE_SIGNATURE=… ~/.local/bin/a16-dim restore`.
- **The gamma readback is a float for some levels** (`15` reads back as `15.000001`). An exact string compare
  never matched, and each key press spun the 10-try resend loop for ~2 s. Compare rounded.
- **Omarchy's OSD helper outlives the script and inherits its `flock` fd**, so the next key press within that
  window was dropped. Release the lock before calling `omarchy-osd`, and start hyprsunset before taking it.
  A key press now takes ~13 ms.

## Side effects

- For a few seconds at boot, before autostart runs, the panel is at 80 % without the dimming.
- Anything that reads the hardware brightness (`omarchy-brightness-display`, the bar) shows 80 %.
- Very dark grays can band at low levels; dim less or raise `PANEL` if that shows.

## Revert

Restore the three `~/.config/hypr/*.bak-20260928` files (bindings, autostart, hyprsunset.conf),
`hyprctl reload`, `pkill hyprsunset`, then set the panel with the brightness keys again.

## Still open

- **Phone-camera check of the flicker depth**, not done (the difference was visible by eye). S26 Pro mode,
  shutter 1/2000 s or faster, at a white screen: compare panel 15 % against panel 80 % + gamma. Fainter stripes
  = shallower flicker.
- **What MyASUS does on this machine.** Whether it's on by default isn't documented. Boot Windows and look in
  MyASUS's display settings, or from Linux mount the Windows partition (p14, `ntfs3`, read-only) and search the
  registry hives and `ProgramData` for the setting, plus `Windows/System32/spool/drivers/color` for ASUS's
  pre-dimmed ICC profiles (they'd show how far it dims at each step, and whether ASUS's panel level is 80 %).
- **Other factors** worth keeping in mind: session length and breaks, the constant fan (~700 rpm idle floor,
  [section 11](zenbook-a16-omarchy-snapdragon.md); `IDLE_PWM=0` stops it at idle), and screen height.
