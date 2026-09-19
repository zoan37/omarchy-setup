# omarchy-setup

Nuanced fixes and hard-won config for my Omarchy machines, so a fresh install
doesn't mean re-deriving everything. Written for myself — and maybe useful to
other Dell XPS 13 / XPS 16 owners running Omarchy. Steps carry exact commands,
verification, and revert paths, so the checklists also work handed to a coding
agent ("set up this machine"; identify the machine via
`cat /sys/class/dmi/id/product_name`).

## Machines

| Machine | GPU | Notes |
|---|---|---|
| Dell XPS 13 (DX13260) | Intel Wildcat Lake | 2560x1600@120Hz eDP, fractional scale 1.6 |
| Dell XPS 16 (DA16260) | Intel Panther Lake (Arc B390) | SKU `0DBA`. **Being returned (2026-09-19): the zero-lattice keyboard never felt right; see [keyboard notes](xps16-keyboard-dropped-keys.md).** 3200x2000@120Hz LG **OLED** eDP, fractional scale 1.6 (stock `auto` resolved correctly). Fresh Quattro 4.0.4 install. Assess display issues separately from the XPS 13; live Panel Replay checks in [xps16-notes.md](xps16-notes.md). |
| Beelink SER8 | AMD Hawk Point iGPU (Radeon 780M) | 32GB RAM, mini-PC. 3440x1440 ultrawide over HDMI, scale 1 (stock `auto` resolves correctly). Wi-Fi, which is what exposes the weather boot race. Logitech keyboard + mouse, **no touchpad** — so the touchpad/gesture/kinetic-scroll fixes below don't apply here. Upgraded from Omarchy 3; the XPS 13 was a fresh Quattro install. |

## Checklists

- [**Post-update checklist**](post-update-checklist.md) — run after every `omarchy update`: what breaks (speaker tuning, hyprpm plugins), what to spot-check, what survives.
- [New machine checklist](new-machine-checklist.md) — condensed order of operations for a fresh Omarchy install.
- [**Dell XPS 16 notes**](xps16-notes.md) — what ported over from the XPS 13 and what didn't. Includes the September 18 Panel Replay checks (the severe failure in PR #11076 was not observed) and the September 19 flickering-line fix: PSR2 selective fetch disabled with `xe.enable_psr2_sel_fetch=0`, pending verification.

## Themes

Daily default is stock **Tokyo Night**; Cyberspace is the custom theme I
switch back to once in a while.

- [**Cyberspace**](cyberspace-theme.md) — custom space/cyberpunk theme: neon
  cyan/magenta on near-black, 27 NASA/ESA/ESO wallpapers (credits + source
  links in the doc), a generated synthwave wallpaper, and a muted
  `hyprland_active_border` override. Full theme + images in
  `assets/cyberspace-theme/`.

## Fixes

- [**XPS 16: built-in keyboard drops keystrokes**](xps16-keyboard-dropped-keys.md) — Dell's known issue 000435203 still reproduces on BIOS 1.11.0: the keyboard controller stalls, then sends only its current state, losing keys in between (visible in `libinput debug-events` as a long apparent hold, then a release and a press in the same millisecond). A Q-to-P swipe test to check yours, the external-keyboard and XPS 13 comparisons, and the later night of A/B tests (CPU sleep states, charger, suspend, restart vs power-off, Dell quiet mode) that found no trigger. Ends with why the laptop went back: the zero-lattice keyboard itself.
- [XPS 16: custom fan-control investigation](xps16-custom-fan-control.md) — paused after no noticeable noise on September 18; BIOS/client findings, offline checks, and a read-only recorder for revisiting it. Manual control remains unverified; F12 diagnostics deferred.
- [**XPS 16: turbo-off trial for less fan noise**](xps16-turbo-off-trial.md) — started 2026-09-17; turbo disabled now and at boot, with a deliberate tradeoff in development performance. Evaluation ongoing, not a confirmed fan fix. Includes verified speed ceilings, existing power limits, reboot checks, and rollback.
- [**Quattro (4.0): the `.conf` → `.lua` migration drops your tweaks**](quattro-lua-migration.md) — a major upgrade orphans `~/.config/hypr/*.conf` without warning or backup. What was lost, how to tell, and the Lua equivalents. Also covers the two quieter halves of the same upgrade: keys silently reclaimed by new stock bindings (screenshot → Google Maps), and the default terminal switching to foot, whose lack of tabs reads as Ghostty breaking.
- [Chrome: Vulkan + white-video fix](chrome-vulkan-white-video.md) — enable Vulkan without x.com/YouTube videos rendering as white rectangles, plus the flags-file gotcha that makes it look like nothing works.
- [Chrome: unlock the administrator-managed theme](chrome-managed-theme.md) — Omarchy's local color policy locks theme selection; back up its policy directory to choose Chrome themes independently, with verification and undo steps.
- [**XPS 13: fan spins up on YouTube / x.com video**](xps13-fan-spins-up-on-video.md) — Omarchy's Intel detection regex doesn't match `Wildcat Lake`, so it silently installs no VA-API driver and Chrome decodes every video in software. One `pacman -S` fixes it; upstream issue #11958. Also covers the 35 W RAPL limit as the second quiet-mode knob.
- [**XPS 16: fan spins up on video — it was a web page, not the hardware**](xps16-fan-spins-up-on-video.md) — same symptom as the XPS 13, entirely different cause, and that machine's fix is a no-op here (VA-API is installed and working). A local page rebuilt a DOM layer every frame at 120 Hz, holding ~54% of a core and raising the idle floor 33 °C → 45 °C until anything tipped the fan over. Chrome's Task Manager named it in seconds; four OS-side thermal levers before that moved nothing. Keeps the dead ends (EPP, turbo cap, halved RAPL, BIOS `Quiet`), the sensor trap that hid it for hours (`dell_ddv` reads ~20 °C below `x86_pkg_temp`), the inverse fan/temperature correlation, and the BIOS `ThermalManagement` attribute Linux can set without rebooting.
- [Bar weather icon missing after boot](weather-widget-boot-race.md) — the shell starts before Wi-Fi associates and the widget hides itself with no error; why a working `omarchy weather status` doesn't rule it out.
- [XPS 13: choppy scrolling = Panel Replay](xps13-panel-replay-scroll-judder.md) — the eDP panel's Panel Replay Selective Update stalls frames during scrolling; fixed with `xe.enable_psr=0 xe.enable_panel_replay=0`. Includes the dead ends (Hyprland VFR, Chrome resampling flags) so they don't get re-chased.
- [XPS 13: second speaker amp dead → fixed by upstream PR #7032](xps13-sidecar-amps.md) — `dell-xps13-sidecar-amps` package forces the `SOC_SDW_SIDECAR_AMPS` quirk on kernel 7.1; makes the custom EQ below obsolete.
- [XPS 13: speaker pops + piercing speech](xps13-speaker-pops-and-eq.md) *(obsolete, see above)* — EQ revision on the packaged soft tuning, WirePlumber no-suspend for the start pop, and `node.always-process` on the tuning chain for the stop snap. Includes the CS35L56 runtime-PM red herring.
- [11pt terminal with 12px global text size](terminal-font-size.md) — decouple terminal font size from Omarchy's global text-size knob, for ghostty and kitty. Kitty needs an extra step or the fix silently dies.
- [XPS 16: Ghostty default-terminal trial](xps16-ghostty-trial.md) — switched from Kitty on September 18, retaining 11pt text; verification, keyboard-test limits, and how to switch back.
- [**Ghostty: every window dies when herdr attaches**](ghostty-io-thread-segfault.md) *(unresolved)* — a ~12% null-deref race in Ghostty's `io` thread at `+0x151c90d`. How to identify it from a coredump in one command, and the dead ends (`async-backend = epoll`, memory pressure, scrollback) so they don't get re-chased. Not an Omarchy bug, and already reported upstream eight times over — likeliest fix is a Ghostty newer than Arch's five-month-stale `tip` build.
- [hyprpm: install gotchas](hyprpm-notes.md) — plugins in use (my hypr-momentum and hypr-tab-drag), and why hyprpm dies with "failed to create cache dir" outside a terminal.
- [**Browser games: camera dies after the first WASD key**](browser-game-pointer-lock.md) — reads exactly like Chrome's pointer lock breaking, on both laptops but not macOS. It isn't: libinput's touchpad disable-while-typing mutes the pad while you hold a movement key. Includes the four dead ends (cursor `hide_on_key_press`, software cursors, fcitx5, XWayland) and the `hyprctl cursorpos` trick that proves the lock was held all along.
- [Touchpad: momentum scrolling + cursor feel](touchpad-momentum-scroll.md) — macOS-style momentum via my hypr-momentum plugin, and why the XPS 13 pad itself is fine.
- [**XPS 16: taming the packaged tuning's sharpness**](xps16-speaker-tuning.md) — the shipped `dell-xps-2026` curve was fitted on the XPS 14 and fatigues the ear on the 16. A generated corrective stage on top of it, plus an `xps16-tuning` switcher. Includes the measured-by-computation finding that the curve is *not* bright — the real culprit is a +5.96 dB local peak at 1322 Hz — and the wrong rationale that got there first.
- [**Syncthing + the ufw wall**](syncthing-and-ufw.md) — Omarchy enables `ufw` by default and ships no helper, so nothing on a fresh machine is reachable: two laptops ping each other fine while every TCP port times out, and each concludes the *other* isn't running syncthing. Also v2's moved config path, the vanished default `~/Sync`, and the folder-ID direction trap.
- [Claude Code: local session retention](claude-code-notes.md) — sessions expire after 30 days by default; there is no "never" value and `0` is invalid, so it takes a large number. Also what the sweep deletes beyond transcripts.
- [Hyprland + shell tweaks](hyprland-shell-tweaks.md) — the small stuff: Alt/Super swap, natural scroll, hair-trigger 3-finger swipe, border-resize, group tab-reorder + SUPER+A select-all binds, monitor scale, clock/tray, syncthing, mise tools.

`assets/xps13-speaker-tuning/` holds the actual speaker-tuning files (restore
kit mirror), since the live profile sits in a package-owned path that omarchy
updates wipe. `assets/xps16-speaker-tuning/` is the same idea for the XPS 16,
plus the generator that builds its curves —
[xps16-speaker-tuning.md](xps16-speaker-tuning.md).
