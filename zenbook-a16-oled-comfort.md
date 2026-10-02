# Zenbook A16: MyASUS-style OLED dimming (a16-dim), and what it does to the PWM (measured)

**Status: applied 2026-09-28; the owner finds the display more comfortable.** It started from headaches after long
sessions on the Zenbook A16 (Samsung Display `ATNA60HR07-0`, 2880x1800 OLED, 120 Hz), without eye strain.
Before the change the panel sat at **15 % hardware brightness** (307/2047 on `dp_aux_backlight`).

**Measured result (section "Measured"):** this panel keeps a near-full-depth dark gap of **~35–45 % of every PWM
cycle at every brightness**. Software dimming shortened it only from **~43 % to ~36 %**. The panel dims mainly by
current, not by duty cycle, so the MyASUS trick helps a little here, not a lot. The comfort gain most likely comes
from running the screen dimmer overall, which the keys now make easy.

## Why it was tried

- **The panel flickers (PWM) at about 1 kHz at every brightness level** (Notebookcheck: 960 Hz, 56 % amplitude)
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

## Published measurements and the Windows panel config (research, 2026-10-02)

**Lab numbers agree on the frequency and are gentler on the depth.**
- Notebookcheck measured this laptop at **960 Hz with 56 % amplitude, at 100 % brightness and every level below**
  ([review](https://www.notebookcheck.net/Asus-Zenbook-A16-Laptop-Review-X2-Elite-Extreme-48-GB-RAM-for-1599.1261795.0.html)).
  960 Hz is 8 pulses per 120 Hz frame. The review text also mentions "DC dimming at lower brightness", which
  contradicts its own table.
- The AMD Zenbook S16 UM5606 uses the **same panel** and measured the same 960 Hz / 56 %, although AMD drives
  brightness through its nits interface. So the PWM is the panel's own and doesn't depend on how the host sets
  brightness.
- 56 % is within IEEE 1789's low-risk limit at 960 Hz (0.08 × f = 76.8 %), but well above its no-effect level
  (~32 %).
- Our camera estimate of a near-full-depth gap, judged from 8-bit stripe brightness at ISO 3200, is cruder than
  a photodiode. Treat 56 % as the better depth figure. The dark-share numbers above still describe how the
  waveform changes with the settings.

**Sibling panels:**

| Laptop | Panel | PWM |
|---|---|---|
| Zenbook S16, older | ATNA60CL10 | 480 Hz, 30 % |
| Zenbook A14 | ATNA40CT06 | 480 Hz, 22 %, and **none above 86 % brightness** (the only DC-above-threshold case found on these Samsung panels) |
| Galaxy Book6 Pro | ATNA60HR05 | 240 Hz, 100 % at every level |

**Windows does nothing special to this panel.** aarch64-laptops published this laptop's DSDT
([build/misc/asus-zenbook-a16-ux3607oa](https://github.com/aarch64-laptops/build/tree/master/misc/asus-zenbook-a16-ux3607oa)).
Its panel XML for ATNA60HR07-0 has `BacklightType 8`, a 5–500-nit brightness range, PSR2 and SSC, and **no
`BrightnessInitSequence` or custom AUX writes**. So no hidden DPCD setup exists that Linux is missing. G-Helper's
source shows MyASUS's flicker-free slider is ASUS Splendid command 19, a software dim with a 40 % floor, the same
idea as `a16-dim`. No ASUS model was found with true DC dimming on this panel.

**No host control for the PWM is known.** Neither the standard eDP registers nor the AMD (0x317–0x37E) or Intel
(0x340–0x359) vendor nit interfaces control emission duty or frequency, and this panel reports no PWM-frequency
capability. The only vendor write found on any Samsung laptop OLED is Lenovo's `0x332/0x333` "A-ELP" setting,
which is undocumented and most likely about power. Don't write undocumented 0x3xx registers blind: TCONs can
expose test or firmware modes over AUX.

**Still worth one camera test each:**
- **60 Hz** (`hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "2880x1800@60", … })'`). The 60 Hz mode is
  stretched vblank at the same line rate, so the panel either keeps ~960 Hz or drops to ~480 Hz.
- **eDP 1.5 luminance mode.** Set `0x721` bit 7 and a millinit target in `0x734–0x736`. It's documented and
  resets at panel power-off, but expect no change: the AMD laptop's nits path measured the same.

## Panel vendor registers, reverse engineered (2026-10-02)

The hunt for a hidden flicker or DC-dimming control. Short answer: none found. Here is what the panel exposes.

**Read-only map.** [dpcdscan.py](assets/zenbook-a16/dpcdscan.py) `/dev/drm_dp_aux2 0x0 0x100000 out.json` reads
the whole 20-bit DPCD space in 16-byte chunks with `pread`, about 30 s, and never writes. Only these areas are
non-zero: the standard blocks (0x000–0x0BF, 0x100, 0x200, 0x600, 0x700–0x72F, 0x2000, 0x2200, 0x2260,
0x4020), plus the vendor area 0x310–0x37F:

| Register | Value | Meaning |
|---|---|---|
| 0x314 | 0x1e | unknown |
| 0x317 | 0x97 | AMD `DP_SOURCE_SINK_CAP`: SDR + HDR AUX backlight, OLED, **emission_output** |
| 0x330–0x331 | 01 01 | 0x331 = **A-ELP supported** (ASUS reads 3 bytes at 0x331 and checks byte 0 = 1) |
| 0x332–0x333 | 00 00 | **A-ELP mode / level** (see below) |
| 0x340–0x344 | 01 77 01 00 10 | Intel HDR TCON interface: PQ decode, BT.2020, tone mapping, brightness in nits, optimization, SDP colorimetry; 0x344 bit 4 (AUX brightness) set |
| 0x371–0x372 | changes every read | live 16-bit value in AMD's Panel Replay/vtotal area; doesn't follow brightness or refresh rate |
| 0x379–0x37A | 09 18 | AMD Panel Replay pixel deviation / deviation lines |
| **0x37E–0x37F** | **c0 03 = 960** | AMD `DP_SINK_EMISSION_RATE`: the panel reports its own 960 Hz PWM. amdgpu only reads it |
| 0x400–0x40B | `00 12 fb` `60HR07` … | sink OUI 00-12-FB, device ID, HW/FW revision |

Snapshots at panel brightness 2047/1024/205/10 differ only in 0x722–0x723 (the brightness itself) and the
live 0x371 value. So **no readable register tracks emission duty**. Like Notebookcheck's identical result on
the AMD S16, this points to a PWM fixed in the panel firmware. A Samsung sibling (ATNA60HR05 in the Galaxy
Book6 Pro) runs 240 Hz, so the rate is set per customer, not at runtime.

**A-ELP = Samsung Display's Edge Luminance Profile, not a flicker control.** Samsung presented it at Computex
2025 as power saving that dims the screen's periphery. MyASUS calls it "Adaptive Edge Brightness" (Snapdragon
models, off by default). Decoded from ASUS's Windows service (`AsusHotkey.exe -AdvancedELPSet <mode> <level>`,
which uses Qualcomm `qdcmlib.dll` `DPControlLibrary2` AuxRead/AuxWrite):
- it reads 2 bytes at 0x332 and, if they differ, writes `[mode, level]`;
- `AsusOptimization.exe` maps its four slider steps to `01 01`, `01 03`, `01 05` and `01 07`, and off to `00 00`;
- it takes the default level (0–3) from the BIOS through ASUS WMI device `0x00050044`.

Lenovo's Yoga Slim 7x panel XML writes `01 03` ("A-ELP setting for 9%"). Tested here at `01 07` (the panel
accepted it and read back `01 01 01 07`): no visible dimming on the owner's dark-theme desktop, so it went back to
`00 00`. To toggle:
`sudo python3 -c "import os;os.pwrite(os.open('/dev/drm_dp_aux2',os.O_RDWR),bytes([1,7]),0x332)"`
(use `[0,0]` for off). ASUS re-sends it at every boot, so it is probably volatile.

**All panel traffic ASUS's software sends.** A search of the Windows install for users of Qualcomm's AUX library
found AsusHotkey (A-ELP only: 0x331/0x332), AsusSplendid (QDCM gamma, no AUX), and AsusSmartBrightnessControl
/ AsusOneG (ScreenXpert/ScreenPad brightness, keyed on the sink OUI at 0x400). The Qualcomm display driver's
panel keys include `EDPCustomAuxCmd` and `EDPCustomScenarioCmd`, but this laptop's ACPI panel XML uses
neither. Windows sends this panel nothing beyond A-ELP that Linux can't.

**Don't:**
- **Don't switch refresh rate for experiments.** A 120 → 60 Hz switch made msm retrain the link, it failed
  twice (`link training on sink failed. ret=-110`) and the screen went black until a reboot. This is the same
  intermittent eDP training failure as the black screen after LUKS unlock.
- **Don't write blind** to undocumented 0x3xx, 0x4xx or 0x5xx registers, 0x600 (power state) or ≥ 0xF0000
  (LTTPR). TCONs can expose firmware-update or test modes over AUX.

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
