# omarchy-fixes

Nuanced fixes and hard-won config for my Omarchy machines, so a fresh install
doesn't mean re-deriving everything.

## Machines

| Machine | GPU | Notes |
|---|---|---|
| Dell XPS 13 (DX13260) | Intel Wildcat Lake | 2560x1600@120Hz eDP, fractional scale 1.6 |
| Other box | AMD HawkPoint1 iGPU | |

## Fixes

- [Chrome: Vulkan + white-video fix](chrome-vulkan-white-video.md) — enable Vulkan without x.com/YouTube videos rendering as white rectangles, plus the flags-file gotcha that makes it look like nothing works.
- [XPS 13: choppy scrolling = Panel Replay](xps13-panel-replay-scroll-judder.md) — the eDP panel's Panel Replay Selective Update stalls frames during scrolling; fixed with `xe.enable_psr=0 xe.enable_panel_replay=0`. Includes the dead ends (Hyprland VFR, Chrome resampling flags) so they don't get re-chased.
- [Ghostty: 10pt terminal with 12px global text size](ghostty-font-size.md) — decouple terminal font size from Omarchy's global text-size knob.
- [hyprpm: install gotchas](hyprpm-notes.md) — plugins in use (kinetic-scroll, my hypr-tab-drag), and why hyprpm dies with "failed to create cache dir" outside a terminal.
- [Touchpad: momentum scrolling + cursor feel](touchpad-kinetic-scroll.md) — compositor-level kinetic scroll via hyprpm plugin, and why the XPS 13 pad itself is fine.
- [New machine checklist](new-machine-checklist.md) — condensed order of operations for a fresh Omarchy install.
