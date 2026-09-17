# XPS 13: fan spins up on YouTube / x.com video

**Symptom:** the machine is silent at idle, but playing video in Chrome —
YouTube, x.com — ramps the fan within a minute or two. Nothing else
(editing, browsing, builds of moderate size) does it as reliably.

**Cause:** Chrome has **no VA-API driver at all**, so every video is decoded in
software across all 6 cores. On a fan-curve that's tuned for a ~35 W sustained
package, 1080p60 AV1/VP9 software decode is more than enough to cross the ramp
threshold.

The reason there's no driver is an Omarchy hardware-detection bug, not anything
you did: `/usr/share/omarchy/install/hardware/intel/video-acceleration.sh`
gates the VA-API install on

```
if [[ ${INTEL_GPU,,} =~ (hd\ graphics|uhd\ graphics|xe|iris|arc|panther\ lake) ]]; then
  omarchy-pkg-add intel-media-driver libvpl vpl-gpu-rt
```

This machine's iGPU reports as **`Intel Corporation Wildcat Lake [Intel
Graphics]`**, which matches none of those substrings. The `elif` only catches
`gma`, so the whole block falls through and **installs nothing, silently.** A
fresh install looks completely healthy.

Filed upstream as [omacom/omarchy#11958][issue] (open, no maintainer response
or PR as of 2026-09-17). The proposed one-word fix is adding `|wildcat\ lake`
to the regex.

[issue]: https://github.com/omacom/omarchy/issues/11958

## This is XPS 13-only — it does *not* explain the XPS 16

Per [xps16-notes.md](xps16-notes.md), the XPS 16 (DA16260) is **Panther Lake
with an Arc B390 iGPU** (`8086:b080`). The detection regex contains both
`panther\ lake` *and* `arc`, so it matches on that machine and
`intel-media-driver libvpl vpl-gpu-rt` are installed normally. Hardware decode
is not the XPS 16's problem, and the fix below is a no-op there.

If the XPS 16 ramps its fan on video, it needs to be measured on that machine —
start with `vainfo`, `chrome://gpu`, and the RAPL limits below, but expect a
different root cause. Same warning as the rest of this repo: the two laptops
share almost no silicon below the CPU vendor; don't reason from one to the
other.

## Confirming it's this and not something else

Three checks, all read-only:

```bash
# 1. Does the GPU name miss the regex?
lspci -nn | grep -Ei 'vga|3d|display'
#    -> Intel Corporation Wildcat Lake [Intel Graphics] [8086:fd80]

# 2. Is there an Intel VA-API driver on disk? (iHD_drv_video.so is the one)
ls /usr/lib/dri/*_drv_video.so
#    -> only d3d12 / nouveau / r600 / radeonsi / virtio_gpu. No iHD.

# 3. Are the packages actually absent?
pacman -Q intel-media-driver libvpl vpl-gpu-rt libva-utils
#    -> "package 'intel-media-driver' was not found", etc.
```

Note the trap: `~/.config/chrome-flags.conf` already carries
`VaapiVideoDecoder,VaapiIgnoreDriverChecks` (see
[chrome-vulkan-white-video.md](chrome-vulkan-white-video.md)), and
`chrome://flags` looks correct. **Those flags are inert without a driver** —
the config being right is not evidence the decode path works.

## The fix

```bash
sudo pacman -S intel-media-driver libvpl vpl-gpu-rt libva-utils
```

`libva-utils` is only for `vainfo` (verification), but it's worth having.
Then **fully quit Chrome** — not `chrome://restart`, which re-execs with the
old command line and reads no config; see the gotcha section of
[chrome-vulkan-white-video.md](chrome-vulkan-white-video.md) — and relaunch.

## Verify

```bash
vainfo 2>&1 | head -30
```

Expect `vainfo: Driver version: Intel iHD driver` and a profile list including
`VAProfileAV1Profile0`, `VAProfileVP9Profile0`, `VAProfileH264High`. Xe3's
media engine covers AV1 / VP9 / HEVC / H.264, so both YouTube (AV1/VP9) and
x.com (mostly H.264) are handled.

Then in Chrome:

- `chrome://gpu` → **Video Decode: Hardware accelerated**
- On a YouTube video, right-click → *Stats for nerds*. Dropped frames should
  stay at 0 while package temperature and CPU stay near idle.
- `sensors | grep -A2 dell_smm` during playback — `fan1` should hold at 0 RPM.

## Revert

```bash
sudo pacman -Rns intel-media-driver libvpl vpl-gpu-rt libva-utils
```

Nothing else changes; the Chrome flags simply go inert again.

## Survives `omarchy update`?

Yes — these are normal packages, not a patched file in a package-owned path.
The detection script never re-runs on an existing install, so the bug can't
un-install them. Once upstream merges the regex fix, a fresh install on this
hardware will do this automatically and this doc becomes obsolete.

## Secondary lever: the power limits are high

Independent of decode, RAPL on this machine is configured at:

```bash
cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw   # 35000000 = 35 W long_term
cat /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw   # 35000000 = 35 W short_term
cat /sys/class/powercap/intel-rapl:0/constraint_2_power_limit_uw   # 93000000 = 93 W peak
```

35 W *sustained* in this chassis will spin the fan for any long workload, video
or not. If near-silence matters more than burst throughput, capping PL1 to
15–20 W is the single biggest knob:

```bash
# Not persistent — resets on reboot. Test before committing to it.
echo 18000000 | sudo tee /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw
```

Invisible for video and browsing; costs sustained compile/export performance.
Make it persistent with a systemd unit or udev rule only after living with it.

## Dead ends — already checked, don't re-chase

- **`platform_profile`** is already `low-power`, `energy_performance_preference`
  is `power`, governor is `powersave`. Nothing to gain; they were never the
  problem.
- **`thermald`** is inactive (`power-profiles-daemon` is the active one).
  Running it would smooth the ramp curve but treats the symptom, not the 6-core
  software decode causing it.
- **Manual fan control** is technically available — `dell_smm_hwmon` exposes
  `/sys/class/hwmon/hwmon4/pwm1` and `pwm1_enable` (currently `2`, EC
  automatic). Setting `1` for manual is a last resort: Dell's EC generally
  reclaims control anyway, and you'd be overriding thermal protection to
  silence a fan that has a real reason to spin.
- **Thermal baseline is fine.** Idle sits at ~38 °C package with `fan1` at
  0 RPM, so this was never a paste/airflow/hardware fault.
- **h264ify-style extensions** (forcing H.264 to dodge AV1) are unnecessary —
  the hardware decodes AV1 natively once iHD is installed.
