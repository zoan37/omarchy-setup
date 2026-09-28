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
- **The owner uses a Galaxy S26 all day without problems.** The S26 flickers at about 480 Hz (240 Hz in one
  lab), slower than the Zenbook, and has no flicker-free or DC-like dimming option
  ([Android Authority](https://www.androidauthority.com/samsung-galaxy-s26-pwm-dimming-3643875/)).
  It dims the panel in hardware with PWM, the same way the Zenbook does on Linux now. **So flicker is
  unlikely to be the cause.** The more likely screen factor is how much light it puts out. The "OLED feels
  like a flashlight" complaint is about that.

## What the phone does differently

The S26 doesn't do the MyASUS trick either: it dims the panel itself, with PWM, at every level. What differs is
**how much light reaches you**. The phone is a small screen at arm's length. The Zenbook is 16" at ~50 cm, run
bright ("brighter helps" the soft text), so a much larger part of what you see is lit. The plan goes after
that. Warm-color schedules and auto-brightness are deliberately left out (owner's choice, 2026-09-27).

## Plan

**0. Baseline (on the Zenbook).** Write down the current brightness before changing anything:
```
brightnessctl -d "$(omarchy-hw-display)" -m           # current %, raw value
```

**1. Match brightness to the room, by hand.** A white page should look like a sheet of paper in the room, not
like a lamp. Start at **30–40 % in daytime indoors, lower in the evening**, and adjust from there with the
brightness keys. If text looks too soft at the lower level, go up 0.5 pt in kitty's `local.conf` instead of
raising the brightness. (The backlight boots at 5 %, which looks black; see the notes' status table.)

**2. Things other than the screen.** Session length (a break every hour), the constant fan (~700 rpm idle
floor, section 11; `IDLE_PWM=0` stops it at idle), no more whine listening sessions, and screen height: a 16"
laptop on a desk means looking down, which can cause tension headaches on its own. A stand is worth a try.

**3. Only if 1–2 don't help: flicker-free dimming (the MyASUS approach).** Keep the backlight at 80–100 % and
dim with `hyprctl hyprsunset gamma 50` (100 = normal; no color change; start it with
`pgrep -x hyprsunset || setsid uwsm-app -- hyprsunset &` if it isn't running). On OLED this saves about the same power
as dimming the backlight. If it helps, remap the brightness keys in `bindings.lua` to step the gamma instead of
calling `omarchy-brightness-display`. It isn't measured whether this panel's flicker actually gets shallower at
high backlight; the MyASUS feature suggests it does. It's last because the S26 result points away from flicker.

## How to judge

Keep a one-line daily log for a week: machine, hours, headache yes/no. Include a few days on the XPS 13
(IPS LCD) for comparison. Change one thing at a time: steps 1 and 2 first, 3 only if needed.

## Revert

Brightness keys for step 1. `hyprctl hyprsunset gamma 100` undoes step 3 immediately.

## Later: what MyASUS actually does on this machine

Not checked yet. Whether it's on by default isn't documented. The quick way: boot Windows and look in MyASUS's
display settings. The deeper way, from Linux: mount the Windows partition (p14, `ntfs3`, read-only) and search
the registry hives and `ProgramData` for the MyASUS flicker-free setting, plus
`Windows/System32/spool/drivers/color` for ASUS's pre-dimmed ICC profiles. G-Helper says the feature is software
only (a dimmed ICC profile / gamma), so those profiles would show exactly how far it dims at each step.
