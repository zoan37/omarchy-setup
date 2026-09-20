# Ghostty: let Claude Code receive Ctrl+Enter

**Applied 2026-09-19 on the SER8.** Ghostty's default
`ctrl+enter=toggle_fullscreen` intercepted Ctrl+Enter before Claude Code could
use it to send a message.

Add this to `~/.config/ghostty/local.conf`:

```ini
# Let Claude Code receive Ctrl+Enter instead of toggling terminal fullscreen.
keybind = ctrl+enter=unbind
```

The last line of `~/.config/ghostty/config` must include the local overrides:

```ini
config-file = ?"~/.config/ghostty/local.conf"
```

This machine already has that include for the
[terminal font-size override](terminal-font-size.md). Keep it last so personal
settings are applied after the main config. `unbind` removes the terminal
shortcut; `ignore` would consume the keystroke instead.

Validate and reload existing terminal windows:

```sh
ghostty +validate-config
omarchy restart terminal
```

Despite its name, `omarchy restart terminal` reloads Ghostty's config with
SIGUSR2; it does not close terminal sessions.

Verify the effective config:

```sh
ghostty +show-config | rg '^keybind = ctrl\+enter='
```

Expected: no matching binding. Then try Ctrl+Enter in Claude Code: Ghostty
should no longer enter fullscreen. Omarchy's **Super+F** still toggles window
fullscreen.

This is a per-machine Ghostty setting. To undo it, remove the `unbind` line
and reload. If an Omarchy refresh replaces the main config, check that the
trailing `local.conf` include is still present.
