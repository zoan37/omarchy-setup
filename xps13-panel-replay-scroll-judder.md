# XPS 13 (Wildcat Lake): choppy scrolling caused by Panel Replay

**Symptom:** scrolling in Chrome (x.com etc.) has inertia but looks like it's
running at a low framerate — discrete/steppy motion instead of the fluid glide
macOS delivers on the same sites. Rendering benchmarks confuse the issue:
TestUFO bounces anywhere from 70 to 120 fps on the 120Hz panel.

**Cause:** the eDP panel self-refresh stack. This panel negotiates the newest
variant — **Panel Replay Selective Update with Early Transport** — and its
sleep/wake path stalls frame updates: the panel drops into `SLEEP` between
updates and wakes late, so frames get skipped in bursts during scrolling.
Confirmed state before the fix (`sudo cat
/sys/kernel/debug/dri/0000:00:02.0/eDP-1/i915_psr_status`):

```
PSR mode: Panel Replay Selective Update enabled (Early Transport)
Source PSR/PanelReplay status: SLEEP [0x30200001]
PSR2 selective fetch: enabled
```

This is the same Xe3 pathology Omarchy already patches for *Panther Lake* XPS
models (`fix-xps-ptl-display.sh`, basecamp/omarchy PR #5315: "Xe PSR causes
freezes and display glitches on both OLED and IPS panels") — but the hardware
gate there doesn't match this Wildcat Lake machine (Core 5 320), so the fix
never applied.

## Confirming it live (no reboot)

```
echo 1 | sudo tee /sys/kernel/debug/dri/0000:00:02.0/i915_edp_psr_debug
```

Scrolling became smooth immediately. (`echo 0` restores; state resets on
reboot either way.)

## The fix

Drop-in for the kernel command line, using the same mechanism as Omarchy's own
hardware fixes — `/etc/limine-entry-tool.d/dell-xps13-wildcat-display.conf`:

```
# Dell XPS 13 (Wildcat Lake / Xe3 iGPU) display workaround.
# Panel Replay Selective Update (Early Transport) stalls frame updates
# during scrolling (panel sleeps between updates, wakes late).
KERNEL_CMDLINE[default]+=" xe.enable_psr=0 xe.enable_panel_replay=0"
```

Then rebuild the boot image and reboot:

```
sudo limine-mkinitcpio
```

**Both parameters are required.** Omarchy's ASUS B9406 fix documents that
`xe.enable_psr=0` does not cover Panel Replay; and disabling only Panel Replay
(`xe.enable_panel_replay=0` alone) makes the driver fall back to PSR2
selective fetch, which judders the same way. The sink supports the whole
alphabet (PSR1/PSR2/Panel Replay), so close every door.

## Dead ends investigated (don't re-chase these)

- **Hyprland VFR** (`debug.vfr`, this fork's name for `misc:vfr`): turning it
  off *measurably* improved rAF pacing in Chrome (TestUFO ~70 → ~110 fps,
  median frame locked at 8.33ms) but was **not perceptible** during real
  scrolling, so it stays at its default (on). Upstream context if it ever
  resurfaces: hyprwm/Hyprland#10979 (open — "new render scheduling causes
  lags and stutters", worst on Intel iGPUs), PR #14849 (merged May 2026,
  fixed frame-callback starvation of continuously-rendering clients),
  PR #14021 (vfr demoted to debug-only).
- **Chrome scroll-resampling flags**: `ResamplingScrollEvents` is hard-gated
  to touchscreen input in `scroll_predictor.cc` — inert for touchpads on
  every platform. No Chrome flag smooths touchpad scroll input.
- **The Vulkan/ANGLE chrome-flags** (see `chrome-vulkan-white-video.md`): a
  clean flag-less profile juddered identically. Innocent.
- **GPU clocks**: steady 1000MHz (max 2500) throughout — not clock starvation.

## The residual gap vs macOS (unfixable today)

The touchpad reports at 143Hz, the panel at 120Hz, and Chromium *coalesces*
scroll events one-per-frame without resampling (`ResamplingScrollEvents` is
touchscreen-only; coalescing in `compositor_thread_event_queue.cc` is
source-independent). Result: every ~6th frame the page steps double distance —
a ~23Hz judder component baked in at the input layer. macOS resamples input to
display cadence system-wide, which is the remaining reason a Mac feels
slightly more fluid. Firefox on Wayland has the same class of complaint
(mozilla bugs 1545927, 1554408). A Chromium feature request to extend
resampling to wheel-source input would be legitimate — none exists yet.

## Upstream trail (for retiring this workaround later)

- Kernel report: https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/8930
- Omarchy issue/PR: basecamp/omarchy#6853 / basecamp/omarchy#6849
- Key identifiers: GPU subsystem `1028:0e53`, DPCD sink OUI `00:22:b9` (LGD,
  device string "Bamboo") — same sink family as the upstream quirks for
  XPS 14 DA14260 (`45c77d4bf8d4`, v7.1) and XPS 16 DA16260 (`cb8d155b0806`,
  7.2-rc1). Expected fix: matching `intel_dpcd_quirks[]` entry for DX13260.
- When a kernel ships that quirk: delete
  `/etc/limine-entry-tool.d/dell-xps13-wildcat-display.conf`, run
  `sudo limine-mkinitcpio`, reboot, and verify scrolling stays smooth
  (the quirk only disables Panel Replay, so PSR2 comes back — if it judders,
  the sink OUI read was `sudo dd if=/dev/drm_dp_aux0 bs=1 skip=1024 count=16`).
