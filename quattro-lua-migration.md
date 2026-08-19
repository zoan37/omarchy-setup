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
[post-update-checklist.md](post-update-checklist.md).

The same upgrade also replaces the default terminal, which is a separate
mechanism with no connection to Hyprland config — covered at the bottom,
since it gets diagnosed as the same kind of "my tweak vanished" symptom.

**Scope: upgrade-path machines only.** It is a one-time migration on the way
from Omarchy 3 to 4, so it hits exactly the machines that carried `.conf`
files across. The XPS 13 was a fresh Quattro install and was never affected —
its tweaks were authored in Lua from the start, which is why
[hyprland-shell-tweaks.md](hyprland-shell-tweaks.md) is already in Lua syntax
while the SER8's were still `.conf`. With both machines now on Quattro this
should not recur, but the section-0 `configProvider` check is cheap insurance
for the next major version.

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
| `SUPER + SHIFT + S` screenshot | bound | **silently reassigned** to the Google Maps webapp |
| `SUPER + SHIFT + W` editor | Typora | Omawrite (Quattro default; Typora still installed, now unbound) |

The last two were found on 2026-08-19, four days after the migration was
thought closed out — see the failure mode below for why they outlasted the
first audit.

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

### Two failure modes, and the second one hides

A dropped binding does nothing, which is easy to notice and easy to grep for.
But Quattro's defaults are *larger* than Omarchy 3's, so some keys you had
customized are now claimed by a stock binding. Those keys still do something —
just the wrong thing — and they never show up as missing:

```sh
hyprctl binds | grep -c movegroupwindow   # dropped bind: count is 0, obvious
```

`SUPER + SHIFT + S` was screenshot for years and silently became Google Maps.
Nothing is absent, so every "is it still bound?" check passes. The tell is that
the key does something unexpected, which reads as a broken app rather than a
broken binding — you go looking at the screenshot tool, not at the keymap.

Check by intent, not by presence. Dump every bind with its description and
read it, rather than grepping for the ones you remember:

```sh
omarchy menu keybindings --print
```

Or resolve a single combo — modmask is a bitmask, `SUPER=64 SHIFT=1 CTRL=4 ALT=8`,
so `SUPER + SHIFT` is `65`:

```sh
hyprctl binds -j | python3 -c "
import json,sys
for b in json.load(sys.stdin):
    if b.get('key','').upper()=='S' and b.get('modmask')==65:
        print(b['modmask'], b['key'], '->', b.get('description'))
"
```

Porting a reclaimed key needs `hl.unbind` first — a bare `o.bind` on a key the
defaults already took does not reliably win, since user files load after the
defaults but both end up in the same bind table:

```lua
-- bindings.lua
hl.unbind("SUPER + SHIFT + S")
o.bind("SUPER + SHIFT + S", "Screenshot", "omarchy-capture-screenshot")
```

Verify with the modmask snippet above: `65 S -> Screenshot`.

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

## Not a config problem: Quattro also swaps the default terminal to foot

Same upgrade, different mechanism, and it presents as an application bug rather
than a system change. Quattro installs **foot** and points
`xdg-terminal-exec` at it, so `SUPER + RETURN` stops launching whatever you had
before. Both landed in the same pacman batch as the Lua rewrite:

```sh
expac --timefmt='%Y-%m-%d %H:%M' '%l %n' foot ghostty omawrite
# 2026-08-15 13:59 foot        <- installed by the upgrade
# 2026-08-15 13:59 omawrite    <- same batch, see the SUPER+SHIFT+W row above
# 2026-08-12 15:26 ghostty     <- pre-existing, untouched, still installed
```

**foot has no tabs at all** — that is an upstream design decision, not a
missing config — so `CTRL + SHIFT + T` silently does nothing. Since the window
still looks like a terminal and your `~/.config/ghostty/config` is untouched
and correct, this reads as "Ghostty lost its tabs". It hadn't; Ghostty simply
was not the thing running. `ghostty +list-keybinds | grep new_tab` happily
confirms the binding is live in a program you never launched, which is exactly
the wrong reassurance.

Check what is actually running before debugging any terminal behaviour:

```sh
omarchy-default-terminal         # -> foot
pgrep -a -f "ghostty|alacritty|kitty|foot"
```

Restore:

```sh
omarchy-default-terminal ghostty   # writes ~/.config/xdg-terminals.list
```

Only new windows pick this up — terminals already open stay on foot until
closed, so a first check right after the switch can look like it failed.
Revert with `omarchy-default-terminal foot`. Note that
`~/.config/xdg-terminals.list` does not exist at all until you set this once;
with no list, `xdg-terminal-exec` resolves via desktop entries and the answer
is whatever the upgrade last installed.

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
