# Post-`omarchy update` checklist (XPS 13)

Run through this after every `omarchy update` (or any `omarchy refresh ...`).
Ordered by likelihood of breakage. Compiled 2026-08-14 from a full audit of
session history + live system state.

## 1. Speaker tuning — WILL break on update

The tuning profile is our own file inside package-owned
`/usr/share/omarchy/default/audio/tunings/`; updates delete it.

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

## 2. Hyprland plugins — WILL break if the update bumps Hyprland

kinetic-scroll's ABI check is disabled; a Hyprland bump can crash the
compositor at plugin load instead of refusing.

```sh
hyprpm update   # rebuild both plugins against the new headers (needs a real terminal)
```

If the compositor won't start / crashes on login: from a TTY,
`hyprpm disable hypr-kinetic-scroll` (and `tab-drag` if needed), log in, then
rebuild. Plugins installed: `hypr-kinetic-scroll` (savonovv), `tab-drag`
(zoan37). The `o.exec_on_start("hyprpm reload -n")` line in `autostart.lua` is
what loads them at all — see [hyprpm-notes.md](hyprpm-notes.md).

## 3. Panel Replay / PSR boot fix — survives updates, retire when kernel fixed

`/etc/limine-entry-tool.d/dell-xps13-wildcat-display.conf` is ours and
persists. After a **kernel** update, check whether the upstream quirk landed
(drm/xe#8930); until then, if scrolling turns choppy verify the cmdline took:

```sh
cat /proc/cmdline | grep -o "xe.enable_psr=0 xe.enable_panel_replay=0"
```

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
| `~/.config/hypr/bindings.lua` | group tab-reorder binds | same |
| `~/.config/hypr/monitors.lua` | monitor scale 1.6 | same |
| `~/.config/hypr/autostart.lua` | `hyprpm reload -n` | [hyprpm-notes.md](hyprpm-notes.md) |
| `~/.config/omarchy/shell.json` | clock format, Slack tray pin | [hyprland-shell-tweaks.md](hyprland-shell-tweaks.md) |
| `~/.config/omarchy/shell.toml` | base-size 12 | same |
| `~/.config/chrome-flags.conf` | Vulkan/VA-API flags | [chrome-vulkan-white-video.md](chrome-vulkan-white-video.md) |
| `~/.config/mimeapps.list` | Chrome default browser, HEY mailto | — |
| `~/.config/mise/config.toml` | claude/codex/gh/node | — |
| syncthing user service | enabled | — |

## Known open gap

`chrome-flags.conf` enables `VaapiVideoDecoder`, but `intel-media-driver`
(iHD) is **not installed** on this box, so hardware video decode is silently
off. `sudo pacman -S intel-media-driver`, then verify at `chrome://gpu`.
