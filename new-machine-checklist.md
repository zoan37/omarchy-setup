# New machine checklist (fresh Omarchy install)

Condensed order of operations. Details in the per-topic files.

Machine-specific pages: [Dell XPS 16](xps16-notes.md). Identify the machine with
`cat /sys/class/dmi/id/product_name` and its speaker/display variant with
`cat /sys/class/dmi/id/product_sku`.

## First: sync the pacman databases

A fresh install has **no** package databases, so `pacman -Si <pkg>` reports
"package not found" for packages that exist — easy to misread as a missing
package. Sync before installing anything:

```sh
sudo pacman -Sy
```

## GitHub / git

```sh
gh auth login -h github.com -p https -w
gh auth setup-git
git config --global user.name "zoan37"
git config --global user.email "104385984+zoan37@users.noreply.github.com"
```

## Chrome

1. Install Chrome (Quattro may already ship it), then edit
   `~/.config/chrome-flags.conf`. A fresh install already has an
   `--enable-features=` line, so **merge** rather than adding a second one:
   ```
   --enable-features=TouchpadOverscrollHistoryNavigation,Vulkan,DefaultANGLEVulkan,VulkanFromANGLE,VaapiVideoDecoder,VaapiIgnoreDriverChecks
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

- `sudo pacman -S cmake` and then `hyprpm update` **first** — a fresh install
  has no Hyprland headers and no cmake, and the failure misreports itself as
  "Headers outdated" ([hyprpm-notes.md](hyprpm-notes.md)).
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

## Speakers

**XPS 14/16 (SKU `0DB9`/`0DBA`): nothing to do** — Omarchy's shipped
`dell-xps-2026` tuning auto-matches and is already on. Confirm with
`omarchy audio tuning status`, then skip to the next section.

### XPS 13 only (SKU `0E53`)

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

- `sudo pacman -S syncthing && systemctl --user enable --now syncthing` (not
  installed by default; starts at login, not boot)
- **Open the firewall, or nothing is reachable.** `ufw` is active out of the box
  and there is no `omarchy firewall` helper, so a fresh machine drops all
  inbound — syncthing and sshd included:
  ```sh
  sudo ufw allow syncthing
  sudo systemctl enable --now sshd                                # off by default
  sudo ufw allow from 192.168.0.0/24 to any port 22 proto tcp     # LAN-scoped
  ```
  Full writeup, including why two machines each report the other as having no
  services: [syncthing-and-ufw.md](syncthing-and-ufw.md).

## Useful references

- Omarchy Quattro plugin directory: <https://omarchyplugins.com>
