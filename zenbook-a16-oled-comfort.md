# Zenbook A16: MyASUS-style OLED dimming (a16-dim), and what it does to the PWM (measured)

**Status: applied 2026-09-28; the owner finds the display more comfortable.** It started from headaches after long
sessions on the Zenbook A16 (Samsung Display `ATNA60HR07-0`, 2880x1800 OLED, 120 Hz), without eye strain.
Before the change the panel sat at **15 % hardware brightness** (307/2047 on `dp_aux_backlight`).

**Measured result (section "Measured"):** this panel keeps a near-full-depth dark gap of **~35–45 % of every PWM
cycle at every brightness**. Software dimming shortened it only from **~43 % to ~36 %**. The panel dims mainly by
current, not by duty cycle, so the MyASUS trick helps a little here, not a lot. The comfort gain most likely comes
from running the screen dimmer overall, which the keys now make easy.

## Why it was tried

- **The panel flickers (PWM) at about 1 kHz at every brightness level**
  ([UltrabookReview](https://www.ultrabookreview.com/75005-asus-zenbook-a16-review/)).
- **MyASUS "OLED Flicker-Free Dimming"** keeps the hardware brightness high and darkens the image in software;
  G-Helper's maintainers found it's software only, a pre-dimmed ICC profile / gamma
  ([g-helper #2056](https://github.com/seerge/g-helper/discussions/2056)). On panels that dim by shortening the
  lit time, that shortens the dark gaps. Linux has no MyASUS, so the Omarchy brightness keys dimmed the panel
  itself.
- **A Galaxy S26 (480 Hz PWM, no flicker-free mode) is fine for the owner**
  ([Android Authority](https://www.androidauthority.com/samsung-galaxy-s26-pwm-dimming-3643875/)), but that
  doesn't rule flicker out: flicker is easier to perceive when it fills more of the visual field and when it's
  brighter, and the phone is a small screen at arm's length.

## What a16-dim does

[`a16-dim`](assets/zenbook-a16/a16-dim) is the MyASUS model, nothing more: the panel stays fixed at **100 %** (80 % at
first), and the brightness keys only change hyprsunset's gamma (a color transform: no tint, no day/night schedule,
standard colors). The level is saved in `~/.local/state/a16-dim/level` and shown on Omarchy's brightness OSD.

```
a16-dim            # print the level
a16-dim +5 | -5    # step it (the keys)
a16-dim 45         # set it
a16-dim restore    # login: panel to 100 %, start hyprsunset -i, reapply the saved level
```

`PANEL=100` and `MIN=5` sit at the top of the script. Pixel values are gamma-encoded, so light falls roughly as
level^2.2: level ~40 at panel 100 % looks about like the old panel 15 %, and level 31 is ~7–8 % of full output.

**What ASUS itself asks for** (found 2026-09-28 in the factory Windows install, mounted read-only with `ntfs3`:
MyASUS 4.4.10.0, `ModuleDll/HWSettings/AsusCustomization.dll`, a .NET assembly): *"please make sure your Windows
system brightness is set above 60% … then adjust the OLED Flicker-Free Dimming slider on the right-hand side to a
level that suits your needs."* So there's no fixed ASUS level: panel above 60 %, dimming in software. The same DLL
calls `SetSplendidDimming` / `-SetDimming`, i.e. ASUS's Splendid color service does the dimming, consistent with
G-Helper's finding.

## Measured (2026-09-28)

Galaxy S26 camera, Pro mode, **1/12000 s** (83 µs, ~8 % of a PWM cycle), ISO 3200, at a white browser page. The
rolling shutter turns the ~1 ms PWM cycle into stripes; they're diagonal because the panel also emits line by line,
so the stripe spacing can't give the frequency, but the dark share of each stripe period is the dark share of each
cycle. [`pwm-stripes.py`](assets/zenbook-a16/pwm-stripes.py) finds the stripe direction with a 2-D FFT, folds the
image onto one period and thresholds half-way between lit and dark:

| Setup | Photos | Dark share of each cycle | Dark stripe vs black background (8-bit) |
|---|---|---|---|
| Old way: panel 5 %, no gamma | 3 | **42–45 %** | 7 vs 5: near full off |
| a16-dim: panel 100 %, gamma 26 | 3 | **35–38 %** | 7 vs 4–5: near full off |

Photos within a set agree within ~3 points. The panel's eDP DPCD (read-only, `/dev/drm_dp_aux2`) offers no PWM
frequency control: `0x702` = `0x86` (brightness over AUX, 16-bit; `FREQ_AUX_SET_CAP` and PWM pass-through not
set), `0x721` = `0x02` (AUX brightness mode), `0x728` (frequency) = 0. Undocumented vendor registers weren't
touched.

**Windows has no hidden PWM control either** (factory install searched read-only, 2026-09-28). The Qualcomm display
driver (`qcdx8480`, `qcdxkm8480.sys`) knows `BacklightPmicPWMFrequency`, `BacklightPmicWledDimmingMethod` and
related keys, but those drive a PMIC WLED, the LED backlight of an LCD; this OLED's brightness goes over AUX
(`BacklightAuxPWMSizeinBits` = the 11-bit field above). Its other backlight keys (`CABL*`, `BacklightReduction*`)
are content-adaptive power saving. The CRD extension (`qcdxkmext8480_CRD.bin`) only names power/brightness
controls, the registry has no display PWM or dimming values, and ASUS's `asusoledcare.inf` is the OLED Care
screensaver. What Windows does run that Linux doesn't is PSR and dynamic refresh (power, see the main notes'
section 16), not flicker. The per-laptop panel config lives in ACPI, which a device-tree boot can't read, so
that one spot is unchecked; the panel's own DPCD caps bound what any driver can set.

**What that means:** the dark gap barely depends on the brightness setting, and each dip goes almost fully dark.
The original model here (panel brightness = lit time, so 15 % ≈ 85 % dark and 100 % ≈ 5–15 % dark) was wrong for
this panel; it lowers the current and keeps most of the gap. a16-dim still helps somewhat: ~15 % less dark time,
and dimmer light overall, which also makes flicker less perceptible (flicker sensitivity falls with luminance).

### How it works (physics)

Each pixel is red, green and blue organic LED subpixels (Samsung's PenTile-style layout, extra green) that emit
light themselves; there's no backlight. A subpixel's light follows its current, and perceived brightness is
current × time lit. Two controls exist:

- **Panel brightness** (`dp_aux_backlight`): on this panel it mostly scales the **current**; the lit share of
  each ~1 ms cycle only moves from ~57 % (at 5 %) to ~64 % (at 100 %).
- **The pixel value** (what hyprsunset's gamma scales): also sets the **current** while lit.

So both controls mostly do the same thing here, and the PWM gap is built into the panel's emission timing.

### Why dark shades suffer at low levels

- **Near-black unevenness (mura):** each subpixel's drive transistor differs slightly from its neighbors. At
  normal currents the panel's compensation hides that; at very low currents the same differences are a large
  share of the total, so dark grays can look blotchy, grainy or tinted green/magenta.
- **Banding:** 256 input levels get squeezed into a smaller output range. At level 31 that's ~80 distinct steps
  if the link to the panel is 8-bit, more if it's 10-bit (not checked), so smooth dark gradients can step.

Both get worse as the pixel values go lower, which is the cost of dimming in software. Given the measurement, the
choice of `PANEL` (60, 80 or 100) matters little for flicker; 100 gives the shortest measured gap, 80 or 60 keep a
few more shades. Power and burn-in are about the same either way, since on OLED both follow the light emitted.

### Compared with MyASUS

Same principle, so on this panel the same small flicker gain. The differences are in the details:

| | MyASUS (Windows) | a16-dim (Omarchy) |
|---|---|---|
| Panel level | Up to the user: ASUS asks for Windows brightness above 60 % | Fixed at `PANEL=100` |
| Controls | Two: Windows brightness (the panel) + the MyASUS slider (the dimming) | One: the brightness keys drive only the dimming |
| Brightness keys (F5/F6) | Still change the panel (why reviewers say to use the slider, not the keys) | Can't lower the panel |
| Dimming method | ASUS's Splendid color service (per G-Helper, a pre-dimmed ICC profile); ASUS could shape the curve to protect shadows | Hyprland CTM via hyprsunset: every encoded value scaled by the same factor |
| Where it applies | Windows desktop and apps; can clash with HDR / color management | Whole output, lock screen included |
| Lowest level | Not known | `MIN=5` |

**Why 60 %?** ASUS doesn't say. Older ASUS OLEDs reportedly switched from PWM to DC dimming around 50 %, where the
trick removes the flicker outright; this panel PWMs at every level, so here it's a trade-off, not a threshold.

## Install

```
install -m755 assets/zenbook-a16/a16-dim ~/.local/bin/
```

`~/.config/hypr/autostart.lua`:
```lua
-- Zenbook A16 flicker-free dimming: panel to 100 %, hyprsunset, saved gamma level.
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
o.bind("SHIFT + XF86MonBrightnessDown", "Brightness minimum", a16_dim .. " 5", { locked = true })
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

- For a few seconds at boot, before autostart runs, the panel is at 100 % without the dimming (bright in a dark room).
- Anything that reads the hardware brightness (`omarchy-brightness-display`, the bar) shows 100 %.
- Very dark grays can band at low levels; dim less or lower `PANEL` if that shows.

## Revert

Restore the three `~/.config/hypr/*.bak-20260928` files (bindings, autostart, hyprsunset.conf),
`hyprctl reload`, `pkill hyprsunset`, then set the panel with the brightness keys again.

## Other ways to reduce flicker exposure on this panel

The gap is in the panel's timing and there's no documented control for it, so the remaining levers reduce how much
flickering light reaches the eye, or how noticeable it is:

- **Run dimmer, with a dark theme.** Less modulated light, and flicker perception falls with luminance.
- **More room light.** Lower contrast between screen and surroundings and a smaller pupil make flicker less
  noticeable than in a dark room.
- **Stay at 120 Hz.** Whether the PWM rate follows the refresh rate isn't tested; 60 Hz could halve it.
- **A flicker-free external monitor or an LCD laptop for long sessions.** The only way to remove it entirely;
  check any screen with the same camera test first (no stripes at 1/12000 s = no PWM).
- **Other factors** worth keeping in mind: session length and breaks, the constant fan (~700 rpm idle floor,
  [section 11](zenbook-a16-omarchy-snapdragon.md); `IDLE_PWM=0` stops it at idle), and screen height.

For exact numbers (frequency, percent flicker, flicker index, IEEE 1789 rating), an Opple Light Master. A
photodiode or small solar cell into a mic jack recorded at 48–192 kHz shows the waveform and duty cycle (mic
inputs are AC-coupled, so not the absolute depth).
