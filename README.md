# omarchy-setup

Nuanced fixes and hard-won config for my Omarchy machines, so a fresh install
doesn't mean re-deriving everything. Written for myself — and maybe useful to
other Dell XPS 13 / XPS 16 / Beelink SER8 / ASUS Zephyrus M16 owners running Omarchy. Steps carry
exact commands, verification, and revert paths, so the checklists also work handed to a coding
agent ("set up this machine"; identify the machine via
`cat /sys/class/dmi/id/product_name`).

## Machines

| Machine | GPU | Notes |
|---|---|---|
| Dell XPS 13 (DX13260) | Intel Wildcat Lake | 2560x1600@120Hz eDP, fractional scale 1.6 |
| Dell XPS 16 (DA16260) | Intel Panther Lake (Arc B390) | SKU `0DBA`. **Being returned (2026-09-19): the zero-lattice keyboard never felt right (see [keyboard notes](xps16-keyboard-dropped-keys.md)), and the short fan bursts at idle were part of it too; the bursts were later traced to a browser page holding a core, not the hardware (see [fan notes](xps16-fan-spins-up-on-video.md)).** 3200x2000@120Hz LG **OLED** eDP, fractional scale 1.6 (stock `auto` resolved correctly). Fresh Quattro 4.0.4 install. Assess display issues separately from the XPS 13; live Panel Replay checks in [xps16-notes.md](xps16-notes.md). |
| Beelink SER8 | AMD Hawk Point iGPU (Radeon 780M) | 32GB RAM, mini-PC. 3440x1440 ultrawide over HDMI, scale 1 (stock `auto` resolves correctly). Wi-Fi, which is what exposes the weather boot race. Logitech keyboard + mouse, **no touchpad** — so the touchpad/gesture/kinetic-scroll fixes below don't apply here. Upgraded from Omarchy 3; the XPS 13 was a fresh Quattro install. |
| ASUS ROG Zephyrus M16 (GU603ZW) | Intel Iris Xe + RTX 3070 Ti (run **Integrated-only**) | i9-12900H. 2560x1600@165Hz eDP, scale 1.6 (stock `auto`). Fresh Quattro 4.0.4 install, 2026-09-20. Hardware via `asusctl`/`supergfxctl`. Quiet/power-saver everywhere, silent fan curve, dGPU off, 80% charge limit: [zephyrus-m16-quiet-power.md](zephyrus-m16-quiet-power.md). |
| ASUS Zenbook A16 (UX3607OA) | Qualcomm Snapdragon X2 Elite Extreme (Adreno) | Community [Omarchy Snapdragon](https://github.com/bprendie/omarchy-snapdragon) v0.2.2-1, arm64, dual boot with factory Windows 11. 2880x1800@120Hz OLED eDP, 48GB RAM. Wi-Fi, audio and CPU frequency scaling each needed a fix, and the tweeters needed routing; the fan is driven from Linux through the reverse-engineered EC mailbox (Mac-style ~700 rpm whisper floor, bursts never spin it up); see [Zenbook A16 notes](zenbook-a16-omarchy-snapdragon.md). |

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

- [**Zenbook A16: Omarchy Snapdragon install and fixes**](zenbook-a16-omarchy-snapdragon.md) — installer clock bug (set the date before `pacman -Syy`), QCC2072 Wi-Fi board file rebuilt from the ASUS driver package, UCM file-name symlink that brings up speakers and mic, a device-tree patch inside `vmlinuz.efi` that enables CPU frequency scaling, custom GRUB entries, a userspace quiet thermal profile, the embedded-controller reverse engineering (Linux I2C + Windows WMI) that ended in manual fan control, a Mac-style "whisper" fan daemon (0 rpm idle), the Windows 11 dual boot via ASUS Cloud Recovery, BIOS updates on a Snapdragon model, a coil whine traced with a webcam mic and a pure-Python FFT to the SSD's PCIe link power state (fixed with one sysfs bit), silent tweeters (stock PipeWire leaves the 4-channel sink's rear pair, the tweeters, unfed; mic-mapped, sides crossed) fixed with a filter-chain crossover plus a limited +6 dB boost, and the things that did not work. Scripts, Windows PowerShell helpers and EC dumps in `assets/zenbook-a16/`.
- [**Zephyrus M16: quiet fans, low power, no desktop lag**](zephyrus-m16-quiet-power.md) — Quiet profile on AC and battery, Integrated-only GPU, a 30/35 W power cap and 3.8 GHz clock cap, while keeping 165 Hz. The EPP fix prevents power-saver from slowing the CPU to ~1.7 GHz; C8/C10 remain disabled for coil whine. The current fan curve allows silence through 66°C, with occasional ramps under heavier activity (both fans off in 87% of a five-minute trial). Includes the previous steady-fan alternative, the fan-curve guard, unused Ethernet autosuspend, repeatable scroll/power tools, and clock/VRR trials that showed no useful watt saving. Exact measurements, verification, and revert steps.
- [**SER8: Logi Bolt pairing and fast-scroll fix**](ser8-logi-bolt.md) — pair the MX Anywhere 3S and MX Keys Mini through Solaar; disabling high-resolution wheel output restored normal scrolling after switching from Bluetooth. Includes the separate Ghostty wheel-speed adjustment, why the touchpad momentum plugin does not apply, verification, reconnect checks, and undo steps.
- [**SER8: turn off the blinking USB Wi-Fi LED**](ser8-usb-wifi-led.md) — the TP-Link adapter's Linux driver exposes an LED control; a small udev rule disables the green activity light while keeping Wi-Fi enabled. Includes the exact rule, verification, and undo steps.
- [**SER8: faint coil whine**](ser8-coil-whine.md) — the same three levers as the Zenbook A16 (NVMe and Wi-Fi links out of ASPM L1, C3 idle off) as a boot service; ear-judged A/B, not the fan or the USB Wi-Fi dongle.
- [**SER8: desktop power-mode selector**](ser8-power-selector.md) — adds the missing top-right Power Saver / Balanced / Performance control on a machine without a battery. Includes the widget files, restoration steps, and the Omarchy-specific setting needed to retain the chosen mode at startup.
- [**SER8: quieter automatic fan curve**](ser8-quiet-fan.md) — power-saver disables CPU boost; an IT8613E driver exposes the hardware fan curve directly in Linux. Lowered idle speed from about 1,076 to 755 RPM, with a 2°C increase in the short CPU load test. Includes the exact driver pin, startup/wake services, restore assets, rollback, and the wattage-control investigation that remains unimplemented.
- [**XPS 16: built-in keyboard drops keystrokes**](xps16-keyboard-dropped-keys.md) — Dell's known issue 000435203 still reproduces on BIOS 1.11.0: the keyboard controller stalls, then sends only its current state, losing keys in between (visible in `libinput debug-events` as a long apparent hold, then a release and a press in the same millisecond). A Q-to-P swipe test to check yours, the external-keyboard and XPS 13 comparisons, and the later night of A/B tests (CPU sleep states, charger, suspend, restart vs power-off, Dell quiet mode) that found no trigger. Ends with why the laptop went back: the zero-lattice keyboard itself.
- [XPS 16: custom fan-control investigation](xps16-custom-fan-control.md) — paused after no noticeable noise on September 18; BIOS/client findings, offline checks, and a read-only recorder for revisiting it. Manual control remains unverified; F12 diagnostics deferred.
- [**XPS 16: turbo-off trial for less fan noise**](xps16-turbo-off-trial.md) — started 2026-09-17; turbo disabled now and at boot, with a deliberate tradeoff in development performance. Evaluation ongoing, not a confirmed fan fix. Includes verified speed ceilings, existing power limits, reboot checks, and rollback.
- [**Quattro (4.0): the `.conf` → `.lua` migration drops your tweaks**](quattro-lua-migration.md) — a major upgrade orphans `~/.config/hypr/*.conf` without warning or backup. What was lost, how to tell, and the Lua equivalents. Also covers the two quieter halves of the same upgrade: keys silently reclaimed by new stock bindings (screenshot → Google Maps), and the default terminal switching to foot, whose lack of tabs reads as Ghostty breaking.
- [Chrome: Vulkan + white-video fix](chrome-vulkan-white-video.md) — enable Vulkan without x.com/YouTube videos rendering as white rectangles, plus the flags-file gotcha that makes it look like nothing works.
- [**SER8 Chrome toolbar flicker trials**](chrome-ser8-flicker-trial.md) — the [experimental OpenGL + WebGPU interop config](assets/chrome-ser8-gl-webgpu-experimental.conf) is active. Home URL flicker recurred while scrolling without a click. URL Flicker Tamer v1.5.0 is installed locally with persistent diagnostics; v1.4.0 was submitted for store review earlier. Includes evidence, local log controls, trial history, backup/rollback, and shared-desktop browser-control notes.
- [Chrome: unlock the administrator-managed theme](chrome-managed-theme.md) — Omarchy's local color policy locks theme selection; back up its policy directory to choose Chrome themes independently, with verification and undo steps.
- [**XPS 13: fan spins up on YouTube / x.com video**](xps13-fan-spins-up-on-video.md) — Omarchy's Intel detection regex doesn't match `Wildcat Lake`, so it silently installs no VA-API driver and Chrome decodes every video in software. One `pacman -S` fixes it; upstream issue #11958. Also covers the 35 W RAPL limit as the second quiet-mode knob.
- [**XPS 16: fan spins up on video — it was a web page, not the hardware**](xps16-fan-spins-up-on-video.md) — same symptom as the XPS 13, entirely different cause, and that machine's fix is a no-op here (VA-API is installed and working). A local page rebuilt a DOM layer every frame at 120 Hz, holding ~54% of a core and raising the idle floor 33 °C → 45 °C until anything tipped the fan over. Chrome's Task Manager named it in seconds; four OS-side thermal levers before that moved nothing. Keeps the dead ends (EPP, turbo cap, halved RAPL, BIOS `Quiet`), the sensor trap that hid it for hours (`dell_ddv` reads ~20 °C below `x86_pkg_temp`), the inverse fan/temperature correlation, and the BIOS `ThermalManagement` attribute Linux can set without rebooting.
- [Bar weather icon missing after boot](weather-widget-boot-race.md) — the shell starts before Wi-Fi associates and the widget hides itself with no error; why a working `omarchy weather status` doesn't rule it out.
- [XPS 13: choppy scrolling = Panel Replay](xps13-panel-replay-scroll-judder.md) — the eDP panel's Panel Replay Selective Update stalls frames during scrolling; fixed with `xe.enable_psr=0 xe.enable_panel_replay=0`. Includes the dead ends (Hyprland VFR, Chrome resampling flags) so they don't get re-chased.
- [XPS 13: second speaker amp dead → fixed by upstream PR #7032](xps13-sidecar-amps.md) — `dell-xps13-sidecar-amps` package forces the `SOC_SDW_SIDECAR_AMPS` quirk on kernel 7.1; makes the custom EQ below obsolete.
- [XPS 13: speaker pops + piercing speech](xps13-speaker-pops-and-eq.md) *(obsolete, see above)* — EQ revision on the packaged soft tuning, WirePlumber no-suspend for the start pop, and `node.always-process` on the tuning chain for the stop snap. Includes the CS35L56 runtime-PM red herring.
- [11pt terminal with 12px global text size](terminal-font-size.md) — decouple terminal font size from Omarchy's global text-size knob, for ghostty and kitty. Kitty needs an extra step or the fix silently dies.
- [Ghostty: Ctrl+Enter for Claude Code](ghostty-ctrl-enter.md) — disable the terminal's fullscreen shortcut so Claude receives the keystroke; applied on the SER8.
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

`assets/ser8-quiet-fan/` mirrors the installed fan helper, systemd units, DKMS
configuration, and original controller settings; reproduction steps are in
[ser8-quiet-fan.md](ser8-quiet-fan.md).

`assets/zephyrus-m16/` mirrors the Zephyrus asusd, fan-curve, supergfxd, and
power-profiles-daemon drop-in files; see
[zephyrus-m16-quiet-power.md](zephyrus-m16-quiet-power.md).
