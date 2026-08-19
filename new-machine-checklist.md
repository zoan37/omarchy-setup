# New machine checklist (fresh Omarchy install)

Condensed order of operations. Details in the per-topic files.

## GitHub / git

```sh
gh auth login -h github.com -p https -w
gh auth setup-git
git config --global user.name "zoan37"
git config --global user.email "104385984+zoan37@users.noreply.github.com"
```

## Chrome

1. Install Chrome, then write `~/.config/chrome-flags.conf`:
   ```
   --enable-features=Vulkan,DefaultANGLEVulkan,VulkanFromANGLE,VaapiVideoDecoder,VaapiIgnoreDriverChecks
   ```
2. On Intel machines: `sudo pacman -S intel-media-driver` (VA-API decode).
   AMD needs nothing extra.
3. Launch via `google-chrome-stable` (never trust the in-app Relaunch button
   to pick up conf changes — see [chrome-vulkan-white-video.md](chrome-vulkan-white-video.md)).
4. Verify: `chrome://gpu` → Vulkan Enabled, ANGLE on Vulkan.

## Terminal

Quattro installs foot and makes it the default, so set this *before* touching
any terminal config — otherwise you tune a terminal you are not running, and
foot's lack of tabs gets mistaken for a broken Ghostty
([quattro-lua-migration.md](quattro-lua-migration.md)).

```sh
omarchy-default-terminal            # what is actually launching
omarchy-default-terminal ghostty    # writes ~/.config/xdg-terminals.list
```

Existing windows keep their old terminal; open a new one to verify.

Font (ghostty only):

- `~/.config/ghostty/local.conf` → `font-size = 11` (both machines)
- append to `~/.config/ghostty/config`:
  `config-file = ?"~/.config/ghostty/local.conf"`
- Set global: `omarchy display text size 12`

## Touchpad / scrolling

- Install [hypr-momentum](https://github.com/zoan37/hypr-momentum) via hyprpm
  (`hyprpm add https://github.com/zoan37/hypr-momentum && hyprpm enable momentum`).
- Add `o.exec_on_start("hyprpm reload -n")` to `~/.config/hypr/autostart.lua`.
- After any `omarchy update` that bumps Hyprland: `hyprpm update` to rebuild —
  see [touchpad-momentum-scroll.md](touchpad-momentum-scroll.md).

## Hyprland config tweaks

Apply the input/looknfeel/bindings/monitors edits from
[hyprland-shell-tweaks.md](hyprland-shell-tweaks.md) (Alt/Super swap, natural
scroll, 3-finger swipe tuning, border resize, group tab-reorder binds).

Any binding that collides with an Omarchy default needs `hl.unbind` before the
`o.bind`, or the default wins. `SUPER + SHIFT + S` (screenshot vs. the stock
Google Maps webapp) is the one that bites — verify with
`omarchy menu keybindings --print`.

## Speakers (XPS 13 only)

1. `sudo pacman -S lsp-plugins-lv2`
2. Copy `assets/xps13-speaker-tuning/` from this repo to
   `~/.local/share/omarchy-xps13-tuning/`, then
   `sudo bash ~/.local/share/omarchy-xps13-tuning/restore.sh` and
   `omarchy audio tuning on`.
3. Copy `assets/xps13-speaker-tuning/90-speaker-no-suspend.conf` to
   `~/.config/wireplumber/wireplumber.conf.d/` and
   `systemctl --user restart wireplumber`.
   Details: [xps13-speaker-pops-and-eq.md](xps13-speaker-pops-and-eq.md).

## XPS 13 display (Wildcat Lake only)

Panel Replay/PSR boot workaround — see
[xps13-panel-replay-scroll-judder.md](xps13-panel-replay-scroll-judder.md)
(check first whether the kernel quirk for DX13260 has landed; then it's
unnecessary).

## Services

- `sudo pacman -S syncthing && systemctl --user enable --now syncthing`

## Useful references

- Omarchy Quattro plugin directory: <https://omarchyplugins.com>
