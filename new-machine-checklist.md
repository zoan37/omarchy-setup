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

## Useful references

- Omarchy Quattro plugin directory: <https://omarchyplugins.com>
