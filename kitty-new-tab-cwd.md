# Kitty: new tabs open in `~` instead of the current directory

**Symptom:** `cd` somewhere in kitty, press **Ctrl+Shift+T**, and the new tab
starts in `~`. Ghostty opens new tabs in the directory you were in, so after
switching terminals this reads as kitty being broken.

**Cause:** it's kitty's default, not an Omarchy bug. `kitty_mod+t` is bound to
`new_tab`, which starts the shell in kitty's *own* working directory (where the
kitty process was launched, usually `~`). Kitty has a separate action,
`new_tab_with_cwd`, that uses the current window's directory. Ghostty inherits
by default (`window-inherit-working-directory = true`). Neither Omarchy's
`~/.config/kitty/kitty.conf` nor `/etc/xdg/kitty/kitty.conf` remaps it.

## Fix

Append to `~/.config/kitty/local.conf` (the file `kitty.conf` includes on its
last line, see [terminal-font-size.md](terminal-font-size.md)):

```
# New tabs/splits open in the current tab's directory (kitty's plain new_tab
# uses the dir kitty was launched from; ghostty inherits cwd by default).
map kitty_mod+t     new_tab_with_cwd
map kitty_mod+enter new_window_with_cwd
```

The second line does the same for **Ctrl+Shift+Enter** (a new split inside
the tab), which has the same default.

It goes in `local.conf` and not `kitty.conf` because `omarchy refresh terminal`
regenerates `kitty.conf`. The include line is the one thing to re-check after
a refresh (see the post-update checklist).

Apply with `omarchy restart terminal` (SIGUSR1, reloads running kitty windows
in place).

## Verify

The parsed config keeps every definition for a key, and the last one is the
active one:

```sh
kitty +runpy 'import os; from kitty.config import load_config
o = load_config(os.path.expanduser("~/.config/kitty/kitty.conf"))
for k, v in o.keyboard_modes[""].keymap.items():
    if any(d.definition.startswith(("new_tab", "new_window")) for d in v):
        print(k, [d.definition for d in v])'
# SingleKey(mods=5, key=57345) ['new_window', 'new_window_with_cwd']
# SingleKey(mods=5, key=116)   ['new_tab', 'new_tab_with_cwd']
```

Pass the config path explicitly. A bare `load_config()` loads only the
built-in defaults and shows the plain `new_tab`, which looks like the fix
didn't take.

Then by hand: `cd /tmp`, Ctrl+Shift+T, `pwd` → `/tmp`.

## How kitty finds the directory

Kitty reads the cwd of the window's foreground process from `/proc`, or uses
what the shell reports through shell integration (Omarchy ships
`shell_integration no-cursor`, which leaves cwd reporting on). Either way no
shell changes are needed.

## Undo

Delete the two `map` lines from `local.conf` and run `omarchy restart terminal`.
