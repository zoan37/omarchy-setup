# Omarchy Quattro (4.0): the `.conf` → `.lua` migration silently drops your tweaks

**Observed 2026-08-15 on the Beelink SER8**, upgrading to Omarchy Quattro
(`4.0.0-1`, version file says `4.0.0.alpha`).

The upgrade writes a new set of **stock** `~/.config/hypr/*.lua` files and
switches Hyprland's config provider to Lua. Your old `~/.config/hypr/*.conf`
files are **left on disk but never read again**. Nothing warns you, nothing is
backed up under a `.bak` name, and every customization that lived in the
`.conf` files stops applying at the next reload.

This is the one case that breaks the "user config in `~/.config/` survives
`omarchy update`" assumption in
[post-update-checklist.md](post-update-checklist.md). It is a **one-time**
migration, but it hits every machine you upgrade.

## Confirm which provider is live

```sh
hyprctl systeminfo | grep configProvider    # -> configProvider: lua
```

`lua` means the `.conf` files are dead weight. Both file sets carry the same
mtime (the upgrade regenerates `hyprland.conf` too), so timestamps tell you
nothing — do not use them to guess.

## What was actually lost on the SER8

Read the old `.conf`, diff it against the new stock `.lua` by hand — the
migration copies nothing across.

| Setting | Old `.conf` | After upgrade |
|---|---|---|
| `resize_on_border` + `extend_border_grab_area = 15` | set | `false` / unset |
| Group tab-reorder `SUPER CTRL SHIFT ←/→` | 2 binds | 0 binds |
| hypr-tab-drag plugin | enabled | `no plugins loaded` |

Verify live rather than trusting the file, since a stock `.lua` and a missing
setting look identical:

```sh
hyprctl getoption general:resize_on_border
hyprctl binds | grep -c movegroupwindow
hyprctl plugin list
omarchy menu keybindings --print | grep -i "select all\|in group"
```

Most of the old `bindings.conf` was stock Omarchy 3.x app bindings that Quattro
now ships as defaults — those are not a loss. Only the genuinely custom lines
need porting.

## Porting the tweaks

The Lua API is not a transliteration of the `.conf` syntax. Equivalents:

```lua
-- looknfeel.lua
hl.config({
  general = {
    resize_on_border = true,
    extend_border_grab_area = 15,
    hover_icon_on_border = true,
  },
})

-- bindings.lua  (was: bindd = ..., movegroupwindow, b|f)
o.bind("SUPER + CTRL + SHIFT + LEFT",  "Move window left in group",  hl.dsp.group.move_window({ forward = false }))
o.bind("SUPER + CTRL + SHIFT + RIGHT", "Move window right in group", hl.dsp.group.move_window({ forward = true }))

-- autostart.lua  (was: exec-once)
o.exec_on_start("hyprpm reload -n")
```

`o.exec_on_start` is the raw exec; `o.launch_on_start` wraps the command in a
uwsm app scope, which is wrong for `hyprpm`.

**The dispatcher namespace is discoverable** — don't guess at names. Stubs
live at `/usr/share/hypr/stubs/hl.meta.lua` (e.g. `move_window` is listed
under `HL.DspGroupNamespace`), and `/usr/share/omarchy/default/hypr/bindings/`
holds working examples of nearly every call.

Apply with `hyprctl reload && hyprctl configerrors` — configerrors prints
nothing on success, and a Lua syntax error will otherwise leave the whole file
silently unapplied.

## Cleaning up

Once the live checks above pass, the orphaned `.conf` files are safe to delete
— but keep them until then, since they are the only record of what was set.
The `.conf.bak.*` files from earlier hand-edits are older still and can go with
them.

## Also check

- **hyprpm plugins need rebuilding**, since Quattro bumps Hyprland. See
  [hyprpm-notes.md](hyprpm-notes.md); `hyprpm update` must run in a real
  terminal.
- Monitor scale: Quattro's stock `monitors.lua` uses `scale = "auto"`. On the
  SER8's 3440x1440 ultrawide that resolves to `1`, matching the old explicit
  value, so no action was needed. Confirm per machine with
  `hyprctl monitors | grep scale` rather than assuming.
- `~/.config/omarchy/shell.json` is untouched by the migration.
