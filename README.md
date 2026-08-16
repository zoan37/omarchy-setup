# omarchy-setup

Nuanced fixes and hard-won config for my Omarchy machines, so a fresh install
doesn't mean re-deriving everything. Written for myself — and maybe useful to
other Dell XPS 13 owners running Omarchy. Steps carry exact commands,
verification, and revert paths, so the checklists also work handed to a coding
agent ("set up this machine"; identify the machine via
`cat /sys/class/dmi/id/product_name`).

## Machines

| Machine | GPU | Notes |
|---|---|---|
| Dell XPS 13 (DX13260) | Intel Wildcat Lake | 2560x1600@120Hz eDP, fractional scale 1.6 |
| Beelink SER8 | AMD Hawk Point iGPU (Radeon 780M) | 32GB RAM, mini-PC. 3440x1440 ultrawide over HDMI, scale 1 (stock `auto` resolves correctly). Wi-Fi, which is what exposes the weather boot race. Logitech keyboard + mouse, **no touchpad** — so the touchpad/gesture/kinetic-scroll fixes below don't apply here. Upgraded from Omarchy 3; the XPS 13 was a fresh Quattro install. |

## Checklists

- [**Post-update checklist**](post-update-checklist.md) — run after every `omarchy update`: what breaks (speaker tuning, hyprpm plugins), what to spot-check, what survives.
- [New machine checklist](new-machine-checklist.md) — condensed order of operations for a fresh Omarchy install.

## Fixes

- [**Quattro (4.0): the `.conf` → `.lua` migration drops your tweaks**](quattro-lua-migration.md) — a major upgrade orphans `~/.config/hypr/*.conf` without warning or backup. What was lost, how to tell, and the Lua equivalents.
- [Chrome: Vulkan + white-video fix](chrome-vulkan-white-video.md) — enable Vulkan without x.com/YouTube videos rendering as white rectangles, plus the flags-file gotcha that makes it look like nothing works.
- [Bar weather icon missing after boot](weather-widget-boot-race.md) — the shell starts before Wi-Fi associates and the widget hides itself with no error; why a working `omarchy weather status` doesn't rule it out.
- [XPS 13: choppy scrolling = Panel Replay](xps13-panel-replay-scroll-judder.md) — the eDP panel's Panel Replay Selective Update stalls frames during scrolling; fixed with `xe.enable_psr=0 xe.enable_panel_replay=0`. Includes the dead ends (Hyprland VFR, Chrome resampling flags) so they don't get re-chased.
- [XPS 13: speaker pops + piercing speech](xps13-speaker-pops-and-eq.md) — EQ revision on the packaged soft tuning, WirePlumber no-suspend for the start pop, and `node.always-process` on the tuning chain for the stop snap. Includes the CS35L56 runtime-PM red herring.
- [Ghostty: 10pt terminal with 12px global text size](ghostty-font-size.md) — decouple terminal font size from Omarchy's global text-size knob.
- [hyprpm: install gotchas](hyprpm-notes.md) — plugins in use (my hypr-momentum and hypr-tab-drag), and why hyprpm dies with "failed to create cache dir" outside a terminal.
- [Touchpad: momentum scrolling + cursor feel](touchpad-momentum-scroll.md) — macOS-style momentum via my hypr-momentum plugin, and why the XPS 13 pad itself is fine.
- [Hyprland + shell tweaks](hyprland-shell-tweaks.md) — the small stuff: Alt/Super swap, natural scroll, hair-trigger 3-finger swipe, border-resize, group tab-reorder + SUPER+A select-all binds, monitor scale, clock/tray, syncthing, mise tools.

`assets/xps13-speaker-tuning/` holds the actual speaker-tuning files (restore
kit mirror), since the live profile sits in a package-owned path that omarchy
updates wipe.
