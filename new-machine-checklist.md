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

## Terminal font (ghostty only)

- `~/.config/ghostty/local.conf` → `font-size = 10`
- append to `~/.config/ghostty/config`:
  `config-file = ?"~/.config/ghostty/local.conf"`
- Set global: `omarchy display text size 12`

## Touchpad / scrolling

- Install `hypr-kinetic-scroll` via hyprpm.
- Add `o.exec_on_start("hyprpm reload -n")` to `~/.config/hypr/autostart.lua`.
- Before any `omarchy update` that bumps Hyprland, remember the plugin's ABI
  check is disabled — see [touchpad-kinetic-scroll.md](touchpad-kinetic-scroll.md) for the escape hatch.

## Hyprland config tweaks

Apply the input/looknfeel/bindings/monitors edits from
[hyprland-shell-tweaks.md](hyprland-shell-tweaks.md) (Alt/Super swap, natural
scroll, 3-finger swipe tuning, border resize, group tab-reorder binds).

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
