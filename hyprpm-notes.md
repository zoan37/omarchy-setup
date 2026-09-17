# hyprpm: install gotchas (Hyprland 0.56+)

## Plugins installed on my machines

- [hypr-momentum](https://github.com/zoan37/hypr-momentum) — my plugin; macOS-style momentum scrolling — see [touchpad-momentum-scroll.md](touchpad-momentum-scroll.md)
- [hypr-tab-drag](https://github.com/zoan37/hypr-tab-drag) — my plugin; drag groupbar tabs to reorder, like browser tabs

(hypr-kinetic-scroll, savonovv — replaced by hypr-momentum Aug 2026; disable
it with `hyprpm disable hypr-kinetic-scroll` if it's still enabled.)

Install pattern (on a fresh machine, `hyprpm update` first — see the cmake
gotcha below):

```sh
hyprpm add https://github.com/zoan37/hypr-tab-drag
hyprpm enable tab-drag
hyprpm reload
```

Plus (once per machine) in `~/.config/hypr/autostart.lua`, or plugins vanish
after reboot:

```lua
o.exec_on_start("hyprpm reload -n")
```

## Gotcha: a fresh Omarchy install is missing `cmake`, and the error names the wrong step

On a fresh Quattro install (observed on the XPS 16, 2026-09-17), the very first
`hyprpm add` fails with something that looks like a version problem:

```
$ hyprpm add https://github.com/zoan37/hypr-momentum
✖ Headers outdated, please run hyprpm update.

$ hyprpm update
✖ Missing dependency: cmake
✖ Could not update. Dependencies not satisfied. Hyprpm requires: cmake, cpio, pkg-config, git, g++, gcc
```

Nothing is outdated — hyprpm has **no** Hyprland headers yet and has to build
them, which it can't do. Of the six dependencies only `cmake` is actually
absent; `base-devel` ships the rest:

```sh
for p in cmake cpio pkg-config git g++ gcc; do
  printf '%-12s ' "$p"; command -v $p >/dev/null && echo present || echo MISSING
done
sudo pacman -S cmake
```

Then `hyprpm update` **before** `hyprpm add` — the header fetch is a
prerequisite for compiling any plugin, not a repair step.

## Gotcha: hyprpm must run in an interactive terminal

Since ~0.56, hyprpm keeps its state in **root-owned** `/var/cache/hyprpm/<user>`
and elevates itself by shelling out to `sudo` for every write. Run it from
anything without a terminal for the password prompt (a script, an agent, a
keybind) and it dies mid-install with the misleading error:

```
[ERR] addNewPluginRepo: failed to create cache dir
```

The build actually succeeds — only the final root-elevated copy fails. Fix:
just run `hyprpm add/enable/update` in a normal terminal.

**Do not** "fix" it by chowning `/var/cache/hyprpm/<user>` to yourself — root
ownership is intentional (the dirs are written via `sudo install`). If you did:

```sh
sudo chown -R root:root /var/cache/hyprpm/$USER
```

## Gotcha: never have two copies of one plugin loaded — unloading one aborts the compositor

Learned the hard way migrating hypr-momentum from a manually loaded `.so`
(`hyprctl plugin load ~/hypr-momentum/momentum.so`, used during development)
to the hyprpm-managed copy (Aug 15 2026). With both copies loaded, running

```sh
hyprctl plugin unload ~/hypr-momentum/momentum.so
```

killed Hyprland with SIGABRT. Symbolized core dump shows the mechanism, and
it's the **surviving** copy that dies, not the one being unloaded:

- Both copies register the same `plugin:momentum:*` config keys.
- Unloading either copy makes Hyprland remove those keys.
- The survivor's next tick constructs `CConfigValue("plugin:momentum:enabled")`,
  whose `bind()` asserts because the key is gone (`ConfigValue.hpp:47`) → abort.

This is generic to any Hyprland plugin that reads its config values by name at
runtime (most do), so treat it as a hard rule: **one loaded copy per plugin,
ever.** Safe migration from a dev copy to hyprpm:

1. `hyprctl plugin unload <dev .so>` **first**, while it's the only copy.
2. Then `hyprpm add` / `hyprpm enable` / `hyprpm reload`.

Or skip the ordering problem entirely: enable in hyprpm, then log out/in —
only the hyprpm copy comes back (autostart runs `hyprpm reload -n`).
