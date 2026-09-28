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

[`a16-dim`](assets/zenbook-a16/a16-dim) is the MyASUS model, nothing more: the panel stays fixed at **100 %** (80 % at first), and
the brightness keys only change hyprsunset's gamma (a color transform: no tint, no day/night schedule, standard
colors). The level is saved in `~/.local/state/a16-dim/level` and shown on Omarchy's brightness OSD.

```
a16-dim            # print the level
a16-dim +5 | -5    # step it (the keys)
a16-dim 45         # set it
a16-dim restore    # login: panel to 100 %, start hyprsunset -i, reapply the saved level
```

`PANEL=100` and `MIN=5` sit at the top of the script. Level ~40 at panel 100 % (45 at 80 %) looks about like the old panel 15 %
(the transform works on encoded values, so luminance falls roughly as level^2.2).

**What ASUS itself asks for** (found 2026-09-28 in the factory Windows install, mounted read-only with `ntfs3`:
MyASUS 4.4.10.0, `ModuleDll/HWSettings/AsusCustomization.dll`, a .NET assembly): *"please make sure your Windows
system brightness is set above 60% … then adjust the OLED Flicker-Free Dimming slider on the right-hand side to a
level that suits your needs."* So there's no fixed ASUS level: panel above 60 %, dimming in software. The same DLL
calls `SetSplendidDimming` / `-SetDimming`, i.e. ASUS's Splendid color service does the dimming, consistent with
G-Helper's finding. Both 80 % and the current 100 % sit above ASUS's 60 %; 100 % is shallower still at the cost
of a few more gamma steps.

### How it works (physics)

Each pixel is red, green and blue organic LED subpixels (Samsung's PenTile-style layout, extra green) that emit
light themselves; there's no backlight. A subpixel's light follows its current. Two separate controls set it:

- **Panel brightness** (`dp_aux_backlight`, 15 % before, 100 % now) sets **how long** each subpixel is lit in every
  ~1 ms PWM cycle. A timer, not the current.
- **The pixel value** (what hyprsunset's gamma scales) sets **how much current** flows while it's lit.

Perceived brightness is current × time lit. For a white pixel at the same apparent brightness:

| | Current while lit | Lit per cycle (simple model) | Result |
|---|---|---|---|
| Before: panel 15 %, no dimming | Full | ~15 % | Short full-strength bursts, long dark gaps |
| Panel 80 %, gamma ~45 | About a fifth | ~80 % | A dim, nearly continuous glow |
| Now: panel 100 %, gamma ~40 | About a sixth | Most of it (PWM remains at 100 %) | Dimmer still per pulse, shortest gaps |

Same average light, much lower peak current, much shorter dark gaps: "DC-like dimming", done through the image
instead of the panel. The PWM frequency (~1 kHz) doesn't change. Pixel values are gamma-encoded, so light falls
roughly as level^2.2; level 14 at panel 80 % is about 1 % of the panel's full output.

The "lit per cycle" figures assume the panel dims purely by duty cycle. It may also lower the current over part of
its range, and it PWMs even at 100 %, so none of this is measured. The S26 camera test below or a flicker meter
(e.g. Opple Light Master) would settle it.

### Why dark shades suffer at low levels

- **Near-black unevenness (mura):** each subpixel's drive transistor differs slightly from its neighbors. At
  normal currents the panel's compensation hides that; at very low currents the same differences are a large
  share of the total, so dark grays can look blotchy, grainy or tinted green/magenta. This is also why panels
  PWM at low brightness instead of lowering the current.
- **Banding:** 256 input levels get squeezed into a smaller output range. At level 14 that's ~36 distinct steps
  if the link to the panel is 8-bit, ~143 if it's 10-bit (not checked), so smooth dark gradients can step.

Both get worse as the pixel values go lower, which is the cost of a higher `PANEL`.

### 60 vs 80 vs 100 %

Model estimates at the same apparent brightness (level 14 at 80 %):

| Panel | Equivalent level | Dark per cycle (model) | Steps left (8-bit) | Undimmed flash at boot |
|---|---|---|---|---|
| 60 % (ASUS's advice) | ~16 | ~40 % | ~41 | 60 % |
| 80 % (first setting) | 14 | ~20 % | ~36 | 80 % |
| **100 % (current)** | ~13 | Least possible; guessed 5–15 %, not 0 (PWM at every level) | ~32 | 100 % |
| *15 %, the old way* | *100 (no dimming)* | *~85 %* | *256* | *15 %* |

- **80 %:** a few more shades for dark content, a gentler boot flash, and if hyprsunset ever dies the screen jumps
  to 80 %, not full. Slightly more flicker than 100 %.
- **100 %:** the shallowest flicker this panel can do, but ~10 % fewer shades, a full-brightness flash at boot,
  and a small gain over 80 % (most of the benefit came from leaving 15 %).

**Switched to 100 % on 2026-09-28** (the level scaled by 0.8^(1/2.2) ≈ 0.9 to keep the same apparent brightness,
e.g. 29 → 26; `MIN` lowered from 10 to 5 so the floor stays about as dim). Go back to `PANEL=80` if dark video
bands or dark grays turn blotchy. Power and burn-in are about the same at every setting, since on
OLED both follow the light actually emitted.

### Compared with MyASUS

Same principle (panel high, where each PWM off-period is short; image dimmed in software), so the flicker benefit
is the same. The differences are in the details:

| | MyASUS (Windows) | a16-dim (Omarchy) |
|---|---|---|
| Panel level | Up to the user: ASUS asks for Windows brightness above 60 % | Fixed at `PANEL=100` |
| Controls | Two: Windows brightness (the panel) + the MyASUS slider (the dimming) | One: the brightness keys drive only the dimming |
| Brightness keys (F5/F6) | Still change the panel, so one tap can drop it below 60 % and back into deep PWM (why reviewers say to use the slider, not the keys) | Can't lower the panel |
| Dimming method | ASUS's Splendid color service (per G-Helper, a pre-dimmed ICC profile); ASUS could shape the curve to protect shadows | Hyprland CTM via hyprsunset: every encoded value scaled by the same factor |
| Where it applies | Windows desktop and apps; can clash with HDR / color management | Whole output, lock screen included |
| Lowest level | Not known | `MIN=5` |

MyASUS might keep dark shades slightly cleaner at very low levels (its curve isn't decompiled, so unconfirmed);
a16-dim can't be undone by an accidental key press. For reading text, a16-dim is the better fit.

**Why 60 %?** ASUS doesn't say. Likely its compromise between shallow flicker and keeping more shades for the
software dimming (older ASUS OLEDs reportedly switched from PWM to DC dimming around 50 %; this panel PWMs at
every level, so here 60 % is a trade-off, not a threshold). `PANEL` is the equivalent knob: 60 gives cleaner
shadows at low levels and deeper flicker than 100 (the current setting).

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
- Very dark grays can band at low levels; dim less or raise `PANEL` if that shows.

## Revert

Restore the three `~/.config/hypr/*.bak-20260928` files (bindings, autostart, hyprsunset.conf),
`hyprctl reload`, `pkill hyprsunset`, then set the panel with the brightness keys again.

## Still open

- **Measuring the flicker**, not done (the difference was visible by eye). Free and rough: S26 Pro mode, shutter
  1/4000 s, at a white page. The rolling shutter turns time into image rows, so dark-stripe width ÷ stripe
  period ≈ fraction of each cycle spent dark, and fainter stripes = shallower dips; compare panel 15 % against
  100 % + gamma. Exact: an Opple Light Master (frequency, percent flicker, flicker index, IEEE 1789 rating).
  DIY: a photodiode or small solar cell into a mic jack recorded at 48–192 kHz shows the waveform and duty cycle
  (mic inputs are AC-coupled, so not the absolute depth).
- **Other factors** worth keeping in mind: session length and breaks, the constant fan (~700 rpm idle floor,
  [section 11](zenbook-a16-omarchy-snapdragon.md); `IDLE_PWM=0` stops it at idle), and screen height.
