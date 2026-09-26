# Post-`omarchy update` checklist

Run through this after every `omarchy update` (or any `omarchy refresh ...`).
Ordered by likelihood of breakage. Compiled 2026-08-14 from a full audit of
session history + live system state, with subsequent additions. Follow the
machine labels: the speaker, display, and SER8 fan checks are hardware-specific.

## 0. Major-version upgrades: check the config provider first

**A major upgrade can migrate the config format and orphan every file your
tweaks live in.** Quattro (4.0) rewrites `~/.config/hypr/*.conf` as stock
`*.lua`, leaves the `.conf` files on disk unread, and warns about nothing —
so the rest of this checklist's "survives updates" assumption does not hold
across that boundary.

```sh
hyprctl systeminfo | grep configProvider
```

If that changed, stop and work through
[quattro-lua-migration.md](quattro-lua-migration.md) before anything else.
Confirmed lost on the SER8, which upgraded from Omarchy 3: border-resize, the
group tab-reorder binds, the hyprpm plugin, and — found four days later — the
`SUPER + SHIFT + S` screenshot bind and the `SUPER + SHIFT + W` editor bind.
The XPS 13 was a fresh Quattro install and never migrated, so this cost nothing
there. Verify against live state (`hyprctl getoption` / `hyprctl binds` /
`hyprctl plugin list`), not against the files — a stock config and a dropped
setting read identically.

**A missing bind is the easy case.** A major upgrade ships *more* defaults than
the last one, so keys you had customized can be quietly reclaimed by a new stock
binding — they still fire, just wrong, and no presence check catches it. Read
the whole keymap by description rather than grepping for what you remember:

```sh
omarchy menu keybindings --print
```

**Also check the default terminal**, which the same upgrade can change without
touching any config file you own:

```sh
omarchy default terminal    # Expected: ghostty on the XPS 16 trial and XPS 13
```

The XPS 16 switched from Kitty to a Ghostty trial on 2026-09-18; see
[trial and rollback notes](xps16-ghostty-trial.md).

## 1. Speaker tuning — RETIRED 2026-08-26 (XPS 13 only; N/A on XPS 16)

**Skip the restore steps below.** The second CS35L56 amp is now enabled by the
`dell-xps13-sidecar-amps` package ([xps13-sidecar-amps.md](xps13-sidecar-amps.md));
the custom EQ was tuning around that and must stay off. After an update just
check `pacman -Q dell-xps13-sidecar-amps` and that
`/sys/module/snd_soc_sof_sdw/parameters/quirk` is `65536`. Historical text follows.

The tuning profile is our own directory inside package-owned
`/usr/share/omarchy/default/audio/tunings/`, so it is always the most exposed
thing here. **Observed 2026-08-14 on `4.0.0rc4-1 → 4.0.0-1`: it survived
untouched** — pacman only removes files the package owns, and this update ran
no rsync that pruned foreign directories. Treat it as "verify", not "will
break", but keep verifying: an install script that syncs with `--delete` would
still take it out.

```sh
omarchy audio tuning status
```

- "Matches: nothing ships for this laptop" → restore it:
  ```sh
  sudo bash ~/.local/share/omarchy-xps13-tuning/restore.sh
  omarchy audio tuning on --force
  ```
- Also verify the fragment kept the pop fix:
  `grep always-process ~/.config/pipewire/omarchy-speaker-tuning.conf.d/90-tuning.conf`
  (restore kit has it baked in as of 2026-08-14; older kit copies don't).
- Sanity check by ear with the test clip in
  [xps13-speaker-pops-and-eq.md](xps13-speaker-pops-and-eq.md).
- `~/.config/wireplumber/wireplumber.conf.d/90-speaker-no-suspend.conf`
  survives updates on its own.

**New neighbour as of 4.0.0:** upstream now ships
`tunings/dell-xps-2026/`, matched on `match_sku=("0DB9" "0DBA")` — the XPS 14
and XPS 16. This laptop is SKU **0E53**, so it does not match and there is no
conflict; `omarchy audio tuning status` still resolves to our
`dell-xps-13-2026-deharsh`. Two things follow: upstream is clearly willing to
carry per-SKU XPS tunings, so our XPS 13 profile is a plausible upstream
contribution; and if a future release adds `0E53` to a shipped profile, ours
should be retired rather than left to shadow it.

**Follow-up 2026-09-17:** the XPS 16 (`0DBA`) landed and *does* match
`dell-xps-2026`, which arrives on and needs no setup at all. Note upstream's
own comment says `0DBA` was "included on report that this profile suits it, not
measured" — the curve was measured on the XPS 14. Worth an A/B
(`omarchy audio tuning off`) before trusting it, and a measured XPS 16
correction would be a real upstream contribution.

## 1b. XPS 16 speaker tuning — our directory, so an update can wipe it

`/usr/share/omarchy/default/audio/tunings/dell-xps-16-custom/` is ours and sits
inside a package-owned parent, exactly like the XPS 13 profile did. pacman only
removes files it owns, so it should survive — verify rather than assume:

```sh
xps16-tuning                  # lists variants, marks active, prints live status
omarchy audio tuning status   # must say: Dell XPS 16 (2026) speakers [soft, experimental]
```

If it says `dell-xps-2026` instead, our directory is gone and upstream's curve
took over (audible: the sharpness returns). Reinstall:

```sh
sudo bash ~/.local/share/omarchy-xps16-tuning/restore.sh   # reinstates default-variant
omarchy audio tuning on --force
```

`restore.sh` also warns if the packaged chain changed, which means the variants
were built against an older upstream and
`python3 ~/.local/share/omarchy-xps16-tuning/build-variants.py` should be re-run.
Details: [xps16-speaker-tuning.md](xps16-speaker-tuning.md).

## 1c. Zenbook A16 speaker filter — lives in `~/.config`, so updates leave it alone

All of it is user config (`~/.config/pipewire/omarchy-speaker-tuning.conf*`,
`~/.config/systemd/user/omarchy-speaker-tuning.service`), and `omarchy audio
tuning on` finds no shipped match for this laptop, so it does nothing. Two things
could still change that: a future Omarchy release that ships a tuning matching
the A16 (then `on`, run by a migration, would overwrite our `90-tuning.conf`), or
`lsp-plugins-lv2` going missing.

```sh
omarchy audio tuning status   # Tuning sink: present; Matches: nothing ships for this laptop
grep -c tw_l_trim ~/.config/pipewire/omarchy-speaker-tuning.conf.d/90-tuning.conf   # 3 = ours
```

To reinstall: `bash assets/zenbook-a16/speaker-boost/install-speaker-boost.sh`. Details:
[Zenbook notes, section 14](zenbook-a16-omarchy-snapdragon.md#14-speakers-tweeters-were-silent-plus-a-limited-6-db-boost-2026-09-26).

## 2. Hyprland plugins — WILL break if the update bumps Hyprland

Both plugins check the ABI and refuse to load on a mismatched Hyprland, so a
bump means no momentum/tab-drag until rebuilt — annoying, not fatal.

```sh
hyprpm update   # rebuild both plugins against the new headers (needs a real terminal)
```

If the compositor still won't start / crashes on login: from a TTY,
`hyprpm disable momentum` (and `tab-drag` if needed), log in, then rebuild.
Plugins installed: `momentum` ([hypr-momentum](https://github.com/zoan37/hypr-momentum),
zoan37), `tab-drag` (zoan37). The `o.exec_on_start("hyprpm reload -n")` line
in `autostart.lua` is what loads them at all — see
[hyprpm-notes.md](hyprpm-notes.md).

## 3. Panel Replay / PSR boot fix — XPS 13; assess XPS 16 separately

**XPS 16 correction (2026-09-18):** kernel 7.2.5 does not by itself establish
that Panel Replay is disabled or fixed. Live checks reported Panel Replay mode,
but only 334–348 Xe interrupts/second and 62.6% GPU C6 residency in a 10-second
sample, unlike the severe pattern in
[PR #11076](https://github.com/omacom/omarchy/pull/11076). Battery impact remains
unverified. No display workaround was applied; if symptoms appear, use the
measurements and checks in [xps16-notes.md](xps16-notes.md). The boot workaround
below remains specific to the XPS 13.

`/etc/limine-entry-tool.d/dell-xps13-wildcat-display.conf` is ours and
persists. After a **kernel** update, check whether the upstream quirk landed
(drm/xe#8930); until then, if scrolling turns choppy verify the cmdline took:

```sh
cat /proc/cmdline | grep -o "xe.enable_psr=0 xe.enable_panel_replay=0"
```

A miss here does **not** mean the drop-in was clobbered — `/proc/cmdline` only
reflects the args as of the last boot. Compare `uptime -s` against the
drop-in's mtime first; if the boot is older, the fix is merely staged and a
reboot is all that's owed. Confirm the regeneration actually ran with
`journalctl | grep limine-mkinitcpio` rather than re-running it blind.

**Two independent paths disable PSR, and they mask each other.** On the boot
where this was first set up, the debugfs toggle was already applied by hand, so
scrolling was smooth *despite* the cmdline args being absent — the symptom and
the mechanism had come apart. Read the actual state before concluding anything:

```sh
sudo cat /sys/kernel/debug/dri/0000:00:02.0/eDP-1/i915_psr_status   # want: PSR disabled
journalctl | grep i915_edp_psr_debug                                # was the toggle run this boot?
```

The toggle dies at reboot and the cmdline takes over, so coverage is continuous
across a restart — but that handoff is the moment to re-check. Smooth scrolling
before a reboot proves only that *one* of the two paths works.

Retirement steps in [xps13-panel-replay-scroll-judder.md](xps13-panel-replay-scroll-judder.md).

## 4. Terminal font — breaks only on `omarchy refresh`, not update

The include that decouples the terminal font size is the **last line** of the
file `omarchy refresh terminal` regenerates, so that one command drops it.
The text-size slider rewriting the size to 9 in the regenerated file is
harmless — `local.conf` wins. See
[terminal-font-size.md](terminal-font-size.md).

- **ghostty:** `ghostty +show-config | grep font-size` → must say 11. If 9,
  re-append `config-file = ?"~/.config/ghostty/local.conf"`.
- **kitty:** check **both** that `include local.conf` is the last line of
  `kitty.conf` *and* that an active `font_size` line still exists above it. If
  the active line is gone, Omarchy's next text-size write appends its stomp
  after the include and quietly wins:
  ```sh
  tail -1 ~/.config/kitty/kitty.conf              # -> include local.conf
  grep -cE '^[[:space:]]*font_size[[:space:]]+' ~/.config/kitty/kitty.conf   # -> 1
  ```

## 5. Claude Code wrapper — cosmetic

Updates may regenerate `~/.local/bin/claude` via `omarchy-mise-install`.
Doesn't matter: upgrades are done manually anyway —
`MISE_MINIMUM_RELEASE_AGE=0 mise install claude@$(npm view @anthropic-ai/claude-code version)`.
Do NOT re-add PATH workarounds to `~/.bashrc`; it stays stock.

## SER8: Logitech mouse scrolling after updates or reconnects

Check that a few wheel notches scroll normally through the Bolt receiver.
If scrolling suddenly becomes very fast or slow, inspect Solaar's live
wheel-resolution setting before adjusting Hyprland's scroll factor. The
[Bolt setup and scroll-fix notes](ser8-logi-bolt.md) record the verified
command, the saved ignore policy, and the untested reboot/power-cycle behavior.

## 6. Things that survive updates (only `omarchy refresh <x>` resets them)

Spot-check only if something feels off. All have `.bak.*` neighbors from past
edits, and everything is documented here:

| File | Custom content | Doc |
|---|---|---|
| `~/.config/hypr/input.lua` | Alt/Super swap, natural scroll, 3-finger swipe tuning | [hyprland-shell-tweaks.md](hyprland-shell-tweaks.md) |
| `~/.config/hypr/looknfeel.lua` | resize-on-border trio | same |
| `~/.config/hypr/bindings.lua` | group tab-reorder binds, SUPER+A select-all, SUPER+SHIFT+S screenshot (needs `hl.unbind` first) | same |
| `~/.config/hypr/monitors.lua` | monitor scale 1.6 | same |
| `~/.config/hypr/autostart.lua` | `hyprpm reload -n` | [hyprpm-notes.md](hyprpm-notes.md) |
| `~/.config/omarchy/shell.json` | clock format, Slack tray pin (`Slack_status_icon_1`) | [hyprland-shell-tweaks.md](hyprland-shell-tweaks.md) |
| `~/.config/omarchy/shell.toml` | base-size 12 | same |
| `~/.claude/settings.json` | `cleanupPeriodDays` (session retention) | [claude-code-notes.md](claude-code-notes.md) |
| `~/.config/ghostty/local.conf` | `ctrl+enter=unbind` lets Claude Code receive Ctrl+Enter (SER8); requires the trailing include in `ghostty/config` | [ghostty-ctrl-enter.md](ghostty-ctrl-enter.md) |
| `~/.config/xdg-terminals.list` | default terminal (Ghostty trial on the XPS 16; Ghostty on the XPS 13) | [xps16-ghostty-trial.md](xps16-ghostty-trial.md) |
| `~/.config/kitty/{kitty,local}.conf` | `font_size 11.0` + the seeded line and trailing include | [terminal-font-size.md](terminal-font-size.md) |
| `~/.config/chrome-flags.conf` | Machine-specific Vulkan/VA-API flags; SER8 is trying OpenGL ANGLE with Vulkan retained | [white-video setup](chrome-vulkan-white-video.md), [SER8 flicker trial and rollback](chrome-ser8-flicker-trial.md) |
| `~/.config/mimeapps.list` | Chrome default browser, HEY mailto | — |
| `~/.config/mise/config.toml` | claude/codex/gh/node | — |
| syncthing user service | enabled (starts at login, not boot) | [syncthing-and-ufw.md](syncthing-and-ufw.md) |
| ufw rules | `allow syncthing`, LAN-scoped ssh | same |

## 7. Bar weather icon missing after a reboot

Cosmetic, and not caused by the update itself — the shell can start before
Wi-Fi associates, and the weather widget hides itself when it has no data.
`omarchy restart shell` fixes it.
[weather-widget-boot-race.md](weather-widget-boot-race.md)

## 8. Chrome theme selection — check if the administrator restriction returns

If Chrome was opted out of Omarchy's forced theme, its
`/etc/opt/chrome/policies/managed` directory should remain absent. The installed
theme script skips missing directories, but browser reinstallation or a future
migration can recreate it. If Chrome's theme becomes administrator-managed
again, inspect `managed/color.json` and check `chrome://policy` before making
changes. Backup, repair, and undo steps:
[chrome-managed-theme.md](chrome-managed-theme.md).

## 9. SER8 quiet fan — check the DKMS build after kernel updates

The helper and systemd units live outside Omarchy's package-owned tree, but
the IT8613E driver must build for the new kernel. After rebooting into it:

```sh
uname -r
dkms status
modinfo -n it87
systemctl status ser8-quiet-fan.service
ser8-quiet-fan status
powerprofilesctl get
```

Expect `it87/bc06d34.20260913` installed for the running kernel, a module path
under `updates/dkms`, automatic mode `2`, start `40`, slope `20`, and the
40°C/90°C ramp/full-speed thresholds. Power profile should be `power-saver`.
Idle RPM depends on temperature; about 755 RPM was observed near 39°C.

A failed DKMS build or changed BIOS needs investigation, not forced device IDs
or bypassed guards. Check matching kernel headers and
`journalctl -b -u ser8-quiet-fan.service`. Re-check the curve after a real
suspend/resume too; the initial setup only exercised the resume handler
directly. Restore and rollback: [ser8-quiet-fan.md](ser8-quiet-fan.md).

## 10. SER8 desktop power selector

The local `zoan.power` widget should remain at the far top right. Click its
icon and verify the mode picker opens; Power Saver uses a leaf icon. Check the
live and saved choices:

```sh
powerprofilesctl get
cat "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/powerprofiles/ac"
```

Both should say `power-saver` unless another mode was deliberately selected.
Use `omarchy powerprofiles set ac power-saver` to restore it persistently;
`powerprofilesctl set` alone does not update Omarchy's startup preference.
The clone survives in user config but depends on the installed shell's UI
components. Restoration, shell-restart workaround, and rollback:
[ser8-power-selector.md](ser8-power-selector.md).

## 11. Zephyrus M16 — boost, profile, and GPU mode

Nothing here is package-owned, but a new power-profiles-daemon or asusd can
change who writes EPP. After updating and **rebooting**:

```sh
asusctl profile get                   # AC + Battery: Quiet
powerprofilesctl list | head -4       # no CpuDriver line (drop-in active)
cat /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference | sort | uniq -c   # 20 balance_performance
timeout 4 sh -c 'while :; do :; done' & sleep 3; grep MHz /proc/cpuinfo | sort -k4 -n | tail -1   # up to ~3800 with the clock cap
supergfxctl -g                        # Integrated
asusctl battery info                  # 80%
cat /sys/devices/system/cpu/cpu0/cpuidle/state{3,4}/{name,disable}   # C8 1, C10 1 (coil-whine fix)
cat /sys/class/firmware-attributes/*/attributes/ppt_pl{1_spl,2_sppt}/current_value   # 30 35
systemctl is-active zephyrus-fan-curve-guard.timer   # active
cat /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq | sort -u   # 3800000
hyprctl monitors | grep vrr           # vrr: true
cat /sys/bus/pci/devices/0000:2c:00.0/power/{control,runtime_status}   # auto / suspended after ~15 s without Ethernet
```

Fan curve: check the hardware, not `asusctl`. After the BIOS 311 flash, asusctl said
"enabled" while the controller ran the firmware curve. `pwm1_enable` in the
`asus_custom_fan_curve` hwmon must be `1`, and the auto points must read `30 40 50 60 66 70 80 90` with both fans at PWM `0 0 0 0 0 26 77 115` (fans off through the 66°C point). The guard timer
should repair a reset within 30 s. The fix is in the Zephyrus doc's BIOS section.

If EPP reads `power` again, the desktop will stutter at 165 Hz. Check that
`/etc/systemd/system/power-profiles-daemon.service.d/no-cpu-epp.conf` still
exists and that PPD still accepts `--block-driver` (`/usr/lib/power-profiles-daemon --help-all`).
Ethernet runtime PM is scoped to the onboard ASUS RTL8125 by
`/etc/udev/rules.d/80-zephyrus-ethernet-pm.rules`. With a cable/link, active is normal;
a cable reconnect still needs a practical check. For comparable package-power samples, use
`pkexec python3 assets/zephyrus-m16/zephyrus-power-sample --seconds 45`.

Details: [zephyrus-m16-quiet-power.md](zephyrus-m16-quiet-power.md).

## Known open gap (XPS 13 / SER8)

`chrome-flags.conf` enables `VaapiVideoDecoder`, but `intel-media-driver`
(iHD) is **not installed** on the XPS 13, so hardware video decode is silently
off. `sudo pacman -S intel-media-driver`, then verify at `chrome://gpu`.
Not a gap on the XPS 16 — Quattro installed it there already.
