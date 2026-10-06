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

## Retest on Omarchy 4.0.4 / `linux-omarchy` 7.2.5-4 (2026-09-27): still needed

Spencer Bull said on the PR that Wildcat Lake XPS machines don't show this on
4.0.4. On this machine they still do. I moved the drop-in to
`~/dell-xps13-wildcat-display.conf.bak`, ran `limine-update`, rebooted, and
confirmed `/proc/cmdline` had no `xe.` params. Scrolling in Chrome was juddery
again and the cursor was laggy. With PSR on, the status showed:

```
Sink support: PSR = yes [0x04] (Early Transport), Panel Replay = yes, Panel Replay Selective Update = yes
PSR mode: Panel Replay Selective Update enabled (Early Transport)
```

Restored the drop-in (`pkexec` does the `mv` and `limine-update` without a
terminal password prompt) and wrote `1` to `i915_edp_psr_debug` so it was
smooth again without another reboot.

The source explains why. `linux-omarchy`'s patch
`0401-drm-i915-psr-exit-panel-replay-for-alpm-lag.patch` (in
`omacom-io/omarchy-pkgs`) turns the upstream "disable Panel Replay" quirk into
a Panel Replay ALPM cursor-lag workaround. Its table lists only Dell `0db9` (XPS 14) and
`0dba` (XPS 16) with sink OUI `00:22:b9`. This machine has the same sink OUI,
but its subsystem `0e53` isn't in the list, so nothing in the kernel applies
here. Kernel releases 7.2.5-5 and 7.2.5-6 changed nothing in the display code.
The likely fix is adding `0e53` to that table, which would keep the power
savings. Reported on the PR:
https://github.com/omacom/omarchy/pull/6849#issuecomment-5862460895

Side note: the panel's EDID says manufacturer `SHP`, product `LQ134Z1`
(Sharp). The sink OUI `00:22:b9` was never LG's. It's Analogix's, the
controller maker. See the next section.

## Panel identity: Sharp glass, Analogix "Bamboo" controller (2026-10-05)

Spencer Bull found a second Wildcat Lake DX13260 with the same subsystem
(`1028:0e53`) and the same sink OUI that **doesn't** judder on `linux-omarchy`
7.2.5 with Panel Replay on. The difference is the panel:

| | This machine | Spencer's |
|---|---|---|
| Panel (EDID) | **Sharp LQ134Z1** (`SHP`, product 5597 / `0x15dd`, Dell P/N 933KG, made week 4 of 2026) | LG LP134WQ |
| DPCD device ID (`0x403`) | `Bamboo` | `Balsa2` |
| Controller firmware (`0x40A–0x40B`) | 0.0 (not populated) | 2.17 |
| Sink OUI | `00:22:b9` | `00:22:b9` |
| Judder | yes | no |

**`00:22:b9` is Analogix** (`/usr/share/hwdata/oui.txt`), not LG Display. It
names the controller vendor, so it matches across both panels and can't tell
them apart. Earlier notes, the PR and the upstream issue called it "LGD", which
was wrong. These are two different panels from two different makers, not one
panel on two firmware versions, so a panel firmware update won't fix it.

The Panther Lake DX13260 (`0e54`) also ships the Sharp LQ134Z1 and needs its
own workaround (omarchy #12297). If it reports `Bamboo` too, the bug follows the
panel across both platforms. That isn't confirmed yet.

Reading the DPCD ID. `drm_dp_aux_dev` is built into `linux-omarchy`, so skip
`modprobe`. `xxd` isn't installed, so use `od`. `aux0` is `AUX A`, the eDP link:

```
pkexec sh -c 'dd if=/dev/drm_dp_aux0 bs=1 skip=$((0x400)) count=12 2>/dev/null | od -A x -t x1z'
# 000000 00 22 b9 42 61 6d 62 6f 6f 00 00 00  >.".Bamboo...<
```

**Other `0e53` owners upstream** (Fedora 44, kernel 7.1.8, KDE; panels not yet
identified) report the same bug, plus `Selective fetch area calculation failed
in pipe A` in dmesg:

- joel1: `xe.enable_panel_replay=0` alone fixes the judder but adds **flicker**
  from the PSR2 fallback. That confirms a quirk that only turns Panel Replay
  off isn't enough for this panel.
- Both run **PSR1** without problems: `xe.enable_psr=1 xe.enable_panel_replay=0`
  (karz adds `xe.enable_psr2_sel_fetch=0` and turns VRR off). joel1 measured
  ~77% package C10 at idle versus 0% with PSR fully off, about **2.4W saved**.
  **Not tried on this machine yet** (`linux-omarchy` + Hyprland). This is the
  thing to test if battery matters more than certainty.

Posted upstream with a request for their DPCD IDs:
https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/8930#note_3696599
(PR reply: https://github.com/omacom/omarchy/pull/6849#issuecomment-6008169611)

State on 2026-10-05: the drop-in (`xe.enable_psr=0 xe.enable_panel_replay=0`) is
in `/etc/limine-entry-tool.d/`, and both UKIs (`linux` and `linux-omarchy`) and
`limine.conf` have it. The boot from 2026-09-27 doesn't have it, so PSR is off
through `i915_edp_psr_debug=1` until the next reboot.

## Upstream trail (for retiring this workaround later)

- Kernel report: https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/8930
- Omarchy issue/PR: basecamp/omarchy#6853 / basecamp/omarchy#6849
- Key identifiers: GPU subsystem `1028:0e53`, DPCD sink OUI `00:22:b9`
  (Analogix), device ID `Bamboo`, EDID Sharp LQ134Z1. The XPS 14 DA14260
  (`45c77d4bf8d4`, v7.1) and XPS 16 DA16260 (`cb8d155b0806`, 7.2-rc1) quirks
  use the same OUI. `intel_dpcd_quirks[]` matches only on subsystem + OUI, which
  would also catch the working `Balsa2` panel. A quirk matching `Bamboo` is
  narrower.
- Omarchy's planned fix (spencerbull, PR #6849): add `0e53` + Bamboo to
  `QUIRK_PANEL_REPLAY_ALPM_CURSOR_LAG` in `linux-omarchy`. Offered to test it.
- When a kernel ships a quirk: delete
  `/etc/limine-entry-tool.d/dell-xps13-wildcat-display.conf`, run
  `sudo limine-mkinitcpio`, reboot, confirm `/proc/cmdline` has no `xe.`
  params, and check that scrolling and the cursor stay smooth. If the quirk
  only disables Panel Replay, PSR2 comes back. Watch for **flicker** as well
  as judder, and for `Selective fetch area calculation failed` in
  `journalctl -k -b`.
