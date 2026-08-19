# Post-`omarchy update` checklist

Run through this after every `omarchy update` (or any `omarchy refresh ...`).
Ordered by likelihood of breakage. Compiled 2026-08-14 from a full audit of
session history + live system state. Sections 1 and 3 are XPS 13-only; the
rest applies to any machine.

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
omarchy-default-terminal    # Quattro switched this to foot, which has no tabs
```

## 1. Speaker tuning — check every time, but it survived 4.0.0

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

## 3. Panel Replay / PSR boot fix — survives updates, retire when kernel fixed

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

## 4. Ghostty font — breaks only on `omarchy refresh`, not update

The `config-file = ?"~/.config/ghostty/local.conf"` include is the **last line
of `~/.config/ghostty/config`**, which `omarchy refresh terminal` regenerates
without it. Check: `ghostty +show-config | grep font-size` → must say 10. If
9, re-append the include line ([ghostty-font-size.md](ghostty-font-size.md)).
The text-size slider rewriting font-size to 9 inside `config` is harmless —
`local.conf` wins.

## 5. Claude Code wrapper — cosmetic

Updates may regenerate `~/.local/bin/claude` via `omarchy-mise-install`.
Doesn't matter: upgrades are done manually anyway —
`MISE_MINIMUM_RELEASE_AGE=0 mise install claude@$(npm view @anthropic-ai/claude-code version)`.
Do NOT re-add PATH workarounds to `~/.bashrc`; it stays stock.

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
| `~/.config/omarchy/shell.json` | clock format, Slack tray pin | [hyprland-shell-tweaks.md](hyprland-shell-tweaks.md) |
| `~/.config/omarchy/shell.toml` | base-size 12 | same |
| `~/.config/xdg-terminals.list` | ghostty as default terminal | [quattro-lua-migration.md](quattro-lua-migration.md) |
| `~/.config/chrome-flags.conf` | Vulkan/VA-API flags | [chrome-vulkan-white-video.md](chrome-vulkan-white-video.md) |
| `~/.config/mimeapps.list` | Chrome default browser, HEY mailto | — |
| `~/.config/mise/config.toml` | claude/codex/gh/node | — |
| syncthing user service | enabled | — |

## 7. Bar weather icon missing after a reboot

Cosmetic, and not caused by the update itself — the shell can start before
Wi-Fi associates, and the weather widget hides itself when it has no data.
`omarchy restart shell` fixes it.
[weather-widget-boot-race.md](weather-widget-boot-race.md)

## Known open gap

`chrome-flags.conf` enables `VaapiVideoDecoder`, but `intel-media-driver`
(iHD) is **not installed** on this box, so hardware video decode is silently
off. `sudo pacman -S intel-media-driver`, then verify at `chrome://gpu`.
