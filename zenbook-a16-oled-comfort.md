# Zenbook A16: OLED comfort plan (headaches)

**Status: plan, not tried yet (written 2026-09-27).** Symptom: headache after long sessions on the Zenbook A16
(2880x1800 OLED, 120 Hz), without eye strain. The screen is not confirmed as the cause. Those sessions were also
long, including nights, with hours spent listening closely to 6.8 / 8.9 kHz coil-whine tones
([zenbook-a16-omarchy-snapdragon.md](zenbook-a16-omarchy-snapdragon.md) section 8).

## What we know

- **The panel flickers (PWM) at about 1 kHz at every brightness level**
  ([UltrabookReview](https://www.ultrabookreview.com/75005-asus-zenbook-a16-review/)). On Windows, MyASUS has
  an "OLED Flicker-Free Dimming" option: the panel's hardware brightness stays high and the image is dimmed in
  software. Linux has no MyASUS, so the Omarchy brightness keys dim the panel itself (`brightnessctl`).
- **How the MyASUS trick works:** OLED PWM switches the pixels off for part of each cycle, and the lower the
  hardware brightness, the longer the off part (deeper flicker). Flicker-free dimming keeps the hardware
  brightness high and darkens the image in software; G-Helper's maintainers found it's software only, a
  pre-dimmed ICC profile / gamma ([g-helper #2056](https://github.com/seerge/g-helper/discussions/2056)). Same
  perceived brightness, shallower flicker; the darkest shades lose some steps. On this panel it can only
  reduce the flicker, since it's there at every level.
- **The owner uses a Galaxy S26 all day without problems.** The S26 flickers at about 480 Hz (240 Hz in one
  lab), slower than the Zenbook, and has no flicker-free or DC-like dimming option
  ([Android Authority](https://www.androidauthority.com/samsung-galaxy-s26-pwm-dimming-3643875/)).
  **That does not rule flicker out.** Flicker is easier to perceive when it fills more of the visual field
  (the periphery is more flicker-sensitive than the center) and when it's brighter. The phone is a small
  screen at arm's length; the Zenbook is 16" at ~50 cm, run bright ("brighter helps" the soft text).
- **So two explanations fit:** too much light (the "OLED feels like a flashlight" complaint) or flicker from a
  large, bright panel. Lowering the brightness with software dimming addresses both at once, so the plan
  starts there instead of saving it as a fallback. Warm-color schedules and auto-brightness are deliberately
  left out (owner's choice, 2026-09-27).

## Plan

**0. Baseline (on the Zenbook).** Write down the current brightness before changing anything:
```
brightnessctl -d "$(omarchy-hw-display)" -m           # current %, raw value
```

**1. Lower the brightness with flicker-free dimming (the MyASUS approach).** Keep the panel at 80–100 % and
dim the image with hyprsunset's gamma (100 = normal; no color change):
```
pgrep -x hyprsunset || setsid uwsm-app -- hyprsunset &   # if it isn't running
brightnessctl -d "$(omarchy-hw-display)" set 90%
hyprctl hyprsunset gamma 50
```
Aim for a white page that looks like a sheet of paper in the room, not a lamp; adjust the gamma from there,
lower in the evening. If text looks too soft, go up 0.5 pt in kitty's `local.conf` instead of raising it.
On OLED, gamma dimming saves about the same power as dimming the panel. If it sticks, remap the brightness
keys in `bindings.lua` to step the gamma (with an OSD) instead of calling `omarchy-brightness-display`.

Two things to check first on this machine:
- **The dimming works on the msm driver.** hyprsunset's gamma is a color transform; if the screen doesn't
  darken after `hyprctl hyprsunset gamma 50`, it isn't supported here and step 1 falls back to plain
  brightness keys (30–40 % daytime, lower in the evening).
- **High panel brightness really gives shallower flicker on this panel.** S26 camera in Pro mode, shutter
  1/2000 s or faster, pointed at a white screen: PWM shows as dark stripes. Compare panel 20 % against panel
  100 % + gamma at the same apparent brightness. Fainter stripes the second way = the trick works here.

**2. Things other than the screen.** Session length (a break every hour), the constant fan (~700 rpm idle
floor, section 11; `IDLE_PWM=0` stops it at idle), no more whine listening sessions, and screen height: a 16"
laptop on a desk means looking down, which can cause tension headaches on its own. A stand is worth a try.

## How to judge

Keep a one-line daily log for a week: machine, hours, headache yes/no. Include a few days on the XPS 13
(IPS LCD) for comparison. Steps 1 and 2 together; if the headaches ease, it doesn't matter which theory was
right.

## Revert

`hyprctl hyprsunset gamma 100`, then the brightness keys as before.

## Later: what MyASUS actually does on this machine

Not checked yet. Whether it's on by default isn't documented. The quick way: boot Windows and look in MyASUS's
display settings. The deeper way, from Linux: mount the Windows partition (p14, `ntfs3`, read-only) and search
the registry hives and `ProgramData` for the MyASUS flicker-free setting, plus
`Windows/System32/spool/drivers/color` for ASUS's pre-dimmed ICC profiles. G-Helper says the feature is software
only (a dimmed ICC profile / gamma), so those profiles would show exactly how far it dims at each step.
