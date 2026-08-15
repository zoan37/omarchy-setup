# Hyprland + shell tweaks (XPS 13)

Small customizations that weren't written up anywhere. All live in user config
(`~/.config/`), so `omarchy update` leaves them alone — but `omarchy refresh
hyprland` / `omarchy refresh shell` resets them (with a `.bak` backup).

## `~/.config/hypr/input.lua`

- **Swap left Super/Alt** (macOS-style Cmd position):
  `kb_options = "compose:caps,shift:both_capslock_cancel,altwin:swap_lalt_lwin"`
  — the first two options are Omarchy's defaults, repeated because `kb_options`
  replaces the whole string.
- **Natural scroll**: `touchpad.natural_scroll = true`.
- **Three-finger horizontal workspace swipe**, tuned hair-trigger over three
  iterations (macOS-loose is the preference — don't re-tune conservative):
  ```lua
  hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
  -- gestures section:
  workspace_swipe_distance = 150
  workspace_swipe_cancel_ratio = 0.1
  workspace_swipe_min_speed_to_force = 2
  ```
- Leftover TODO comment about kinetic-scroll `interval_ms=8`: not settable
  under the Lua config parser — see
  [touchpad-kinetic-scroll.md](touchpad-kinetic-scroll.md). Runs at defaults.

## `~/.config/hypr/looknfeel.lua`

Resize windows by grabbing borders (with a generous grab area):

```lua
general.resize_on_border = true
general.extend_border_grab_area = 15
general.hover_icon_on_border = true
```

## `~/.config/hypr/bindings.lua`

Reorder tabs within a Hyprland group (browser-tab style, pairs with the
hypr-tab-drag plugin — groups are a core part of the workflow):

```lua
SUPER+CTRL+SHIFT+LEFT  -> hl.dsp.group.move_window({ forward = false })
SUPER+CTRL+SHIFT+RIGHT -> hl.dsp.group.move_window({ forward = true })
```

**SUPER+A = select all**, to complete Omarchy's macOS-ish `SUPER+C/V/X`
clipboard set (which stock leaves without a select-all). Copy the
`send_shortcut_once` helper verbatim from
`/usr/share/omarchy/default/hypr/bindings/clipboard.lua` — the explicit-mods
send with no window target is what reaches layer-shell surfaces (Omarchy
panels) too, and the down/up split works around Hyprland leaving the synthetic
key stuck ([hyprwm/Hyprland#14099](https://github.com/hyprwm/Hyprland/discussions/14099)).
A virtual keyboard (`wtype`) does **not** work here: the physically held SUPER
merges into the injected chord at the seat.

```lua
local function send_shortcut_once(mods, key)
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))

    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  end
end

o.bind("SUPER + A", "Universal select all", send_shortcut_once("CTRL", "A"))
```

SUPER+A is unbound in stock Omarchy, so no `hl.unbind` is needed. Deliberately
**not** terminal-special-cased the way copy/paste is (stock swaps to
`CTRL+Insert` / `SHIFT+Insert` there): terminals have no universal select-all,
so in a terminal SUPER+A just sends CTRL+A = beginning-of-line. Fine as-is;
revisit only if a tmux prefix ever lands on CTRL+A.

Verify: `hyprctl reload && hyprctl configerrors`, then
`omarchy menu keybindings --print | grep -i "select all"`.

## `~/.config/hypr/monitors.lua`

- `omarchy_monitor_scale = 1.6` (stock "auto" picked 2 — too zoomed on the
  2560x1600 panel).
- `omarchy_gdk_scale` is **2 and should stay 2** — it's an intentional Omarchy
  default (keeps XWayland GTK apps from rendering microscopic). It was once set
  to 1 and omarchy tooling put it back; that's fine, leave it.

## Omarchy shell (`~/.config/omarchy/`)

- `shell.json`: clock format `"ddd d MMM HH:mm"` (stock is `"dddd HH:mm"`);
  tray has `"pinned": ["Slack_status_icon_1"]` so Slack's status icon stays
  visible.
- `shell.toml` (user-added file): `[font] base-size = 12` — the global text
  size. Pairs with the ghostty decouple in
  [ghostty-font-size.md](ghostty-font-size.md); other terminals follow the
  global knob at 9pt **on purpose** (only ghostty is pinned to 10).

## Default apps

`~/.config/mimeapps.list`: default browser switched to Google Chrome
(`google-chrome.desktop` for http/https/html), `mailto` → HEY.

## Services & packages beyond stock

- `syncthing` (pacman) + `systemctl --user enable --now syncthing.service` —
  syncs `~/Sync`.
- `lsp-plugins-lv2` — required by the speaker tuning
  ([xps13-speaker-pops-and-eq.md](xps13-speaker-pops-and-eq.md)).
- AUR/foreign: `google-chrome`, `slack-desktop`.
- mise tools (`~/.config/mise/config.toml`): claude, codex, gh, node 26.7.0.
  Claude Code is upgraded **manually** when its banner appears:
  `MISE_MINIMUM_RELEASE_AGE=0 mise install claude@$(npm view @anthropic-ai/claude-code version)`
  — the mise-backend/PATH workarounds were tried and deliberately reverted;
  `~/.bashrc` stays stock Omarchy.
