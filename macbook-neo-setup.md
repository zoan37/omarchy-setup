# MacBook Neo (Mac17,5): new-machine setup

Set up **2026-11-06** on Omarchy 4.5.0-3 for Apple Silicon (arm64, `omarchy-mac`
0.2.3, kernel `7.2.11-14-1-ARCH`, Hyprland 0.56.2). 2408x1506@60Hz eDP on a
279x175 mm panel (about 219 ppi), scale 2. Identify it with
`cat /sys/class/dmi/id/product_name`.

The [new machine checklist](new-machine-checklist.md) was followed, keeping only
what applies to an arm64 Mac. Three things differ from the other laptops:

- **No Alt/Super swap.** Command is already Super, in the macOS position:
  `hid_apple` has `swap_opt_cmd=0` and nothing remaps it. Adding
  `altwin:swap_lalt_lwin` here would move Super to Option.
- **`disable_while_typing` stays on.** The other laptops turn it off for WASD
  games. See [below](#palm-touches-while-typing).
- **Ghostty is 9pt, not 11pt.** See [below](#terminal-font-9pt-not-11pt).

## Applied

User config (each file has a `.bak.<timestamp>` next to it):

| What | Where | Doc |
|---|---|---|
| Natural scroll, 3-finger swipe with the hair-trigger tuning | `~/.config/hypr/input.lua` | [hyprland-shell-tweaks.md](hyprland-shell-tweaks.md) |
| `extend_border_grab_area = 15` (`resize_on_border` and `hover_icon_on_border` are stock now) | `~/.config/hypr/looknfeel.lua` | same |
| Group tab reorder, SUPER+SHIFT+S screenshot (the keyboard has no Print Screen) | `~/.config/hypr/bindings.lua` | same |
| Clock format `ddd d MMM HH:mm` | `~/.config/omarchy/shell.json` | same |
| Ghostty as default terminal, 9pt, `ctrl+enter=unbind` | `~/.config/xdg-terminals.list`, `~/.config/ghostty/local.conf` + trailing include | [terminal-font-size.md](terminal-font-size.md), [ghostty-ctrl-enter.md](ghostty-ctrl-enter.md) |
| `cleanupPeriodDays: 10950` | `~/.claude/settings.json` | [claude-code-notes.md](claude-code-notes.md) |
| git identity | `~/.gitconfig` | [new-machine-checklist.md](new-machine-checklist.md) |
| `o.exec_on_start("hyprpm reload -n")` | `~/.config/hypr/autostart.lua` | [hyprpm-notes.md](hyprpm-notes.md) |

Root:

```sh
sudo pacman -S --needed ghostty cmake hyprpm
sudo install -Dm755 assets/clock-refresh-on-resume/omarchy-clock-refresh \
  /usr/lib/systemd/system-sleep/omarchy-clock-refresh
```

SUPER+A is not added: Omarchy 4.5 ships its own "Select all".

## Palm touches while typing

With `disable_while_typing = false` copied from the other laptops, palms and
fingers landing on the trackpad moved the pointer during normal typing. The fix
was to delete the line, which restores the default of `true`.

The trackpad is the wide Apple kind and sits right under the hands, so the
tradeoff goes the other way here: the
[WASD browser-game problem](browser-game-pointer-lock.md) comes back, and the
pad may stop responding while movement keys are held. A keybound toggle is the
way to get both, if it starts to matter. Not built yet.

libinput's Apple MTP quirks (`/usr/share/libinput/50-system-apple.quirks`) match
this pad by name and vendor (`05ac`), including `AttrPalmSizeThreshold=1600`, so
palm size detection needs no local quirk.

If stray clicks continue, the next thing to try is `tap_to_click = false` in the
`touchpad` block. Omarchy leaves tap-to-click on.

The pointer also vanishing while typing is Omarchy's `hide_on_key_press`, not a
fault.

## Terminal font: 9pt, not 11pt

11pt looked large. Ghostty sizes text from the Hyprland scale, and this machine
runs at 2 where the XPS 13 runs at 1.6, on a panel of similar density. So the
same point size draws larger:

| | Scale | Em size at 11pt | Em size at 9pt |
|---|---|---|---|
| MacBook Neo (219 ppi) | 2 | 29 px, 3.4 mm | 24 px, 2.8 mm |
| XPS 13 (roughly 225 ppi) | 1.6 | 23 px, 2.6 mm | |

So 9pt here is close to the physical size of 11pt on the XPS 13. The size lives in
`~/.config/ghostty/local.conf`, which is per machine, so nothing else changes:

```
font-size = 9
```

Apply with `omarchy restart terminal`, which reloads windows in place.

## Wi-Fi: routers in WPA/WPA2 mixed mode

Home Wi-Fi failed instantly here while macOS joined it fine, because the Linux
driver accepts only AES and the router's group key is TKIP. It's fixed with a driver
patch that **has to be rebuilt after each kernel update**:
[macbook-neo-wifi-tkip.md](macbook-neo-wifi-tkip.md).

## Open / not done

- **hypr-momentum and hypr-tab-drag: not installed yet.** `cmake` and `hyprpm` are
  in, but hyprpm needs an interactive terminal
  ([hyprpm-notes.md](hyprpm-notes.md)), and neither plugin has been tried on
  arm64. If login crashes afterwards: `hyprpm disable momentum` from a TTY.
- **SSH and syncthing: not set up.** Both need firewall changes
  ([syncthing-and-ufw.md](syncthing-and-ufw.md)).
- **Chrome flags: skipped.** Chrome isn't installed, and the flags are for x86
  GPUs. Chromium stays on its stock flags.
- **Tray half-pixel patch: skipped.** It edits a package-owned file, and every update
  reverts it ([tray-icon-half-pixel.md](tray-icon-half-pixel.md)).
- **Clock hook:** the dry run passed. Not yet confirmed on a real lid close.

## Verify

```sh
hyprctl getoption input:touchpad:natural_scroll          # true
hyprctl getoption input:touchpad:disable_while_typing    # true
hyprctl getoption input:kb_options                       # no altwin:swap_lalt_lwin
hyprctl getoption gestures:workspace_swipe_distance      # 150
omarchy menu keybindings --print | grep -E 'Screenshot|Move tab'
omarchy-default-terminal                                 # ghostty
ghostty +show-config | grep font-size                    # 9
```

## Undo

```sh
# config: restore the .bak.<timestamp> files in ~/.config/hypr and ~/.config/omarchy
rm ~/.config/ghostty/local.conf
omarchy-default-terminal foot
sudo rm /usr/lib/systemd/system-sleep/omarchy-clock-refresh
```
