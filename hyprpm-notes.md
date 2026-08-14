# hyprpm: install gotchas (Hyprland 0.56+)

## Plugins installed on my machines

- [hypr-kinetic-scroll](https://github.com/savonovv/hypr-kinetic-scroll) — see [touchpad-kinetic-scroll.md](touchpad-kinetic-scroll.md)
- [hypr-tab-drag](https://github.com/zoan37/hypr-tab-drag) — my plugin; drag groupbar tabs to reorder, like browser tabs

Install pattern:

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
