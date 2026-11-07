# MacBook Neo (Mac17,5): new-machine setup

Set up **2026-11-06** on Omarchy 4.5.0-3 for Apple Silicon (arm64, `omarchy-mac`
0.2.3, kernel `7.2.11-14-1-ARCH`, Hyprland 0.56.2). 2408x1506@60Hz eDP on a
279x175 mm panel (about 219 ppi), run at scale 1.725. Identify it with
`cat /sys/class/dmi/id/product_name`.

The [new machine checklist](new-machine-checklist.md) was followed, keeping only
what applies to an arm64 Mac. Four things differ from the other laptops:

- **No Alt/Super swap.** Command is already Super, in the macOS position:
  `hid_apple` has `swap_opt_cmd=0` and nothing remaps it. Adding
  `altwin:swap_lalt_lwin` here would move Super to Option.
- **`disable_while_typing` stays on.** The other laptops turn it off for WASD
  games. See [below](#palm-touches-while-typing).
- **Scale 1.725, which Hyprland refuses by default.** See
  [below](#scale-1725-the-macos-default-size).
- **Ghostty is 10pt, not 11pt.** See [below](#terminal-font-10pt-not-11pt).

## Applied

User config (each file has a `.bak.<timestamp>` next to it):

| What | Where | Doc |
|---|---|---|
| Natural scroll, 3-finger swipe with the hair-trigger tuning | `~/.config/hypr/input.lua` | [hyprland-shell-tweaks.md](hyprland-shell-tweaks.md) |
| `extend_border_grab_area = 15` (`resize_on_border` and `hover_icon_on_border` are stock now) | `~/.config/hypr/looknfeel.lua` | same |
| Scale 1.725 and `debug.disable_scale_checks` | `~/.config/hypr/monitors.lua`, `looknfeel.lua` | [below](#scale-1725-the-macos-default-size) |
| Display menu with a 1.725x button | `~/.config/omarchy/plugins/<user>.monitor/` | [below](#a-1725x-button-in-the-display-menu) |
| Group tab reorder, SUPER+SHIFT+S screenshot (the keyboard has no Print Screen), SUPER+CTRL+D to the cloned Display menu | `~/.config/hypr/bindings.lua` | [hyprland-shell-tweaks.md](hyprland-shell-tweaks.md) |
| Clock format `ddd d MMM HH:mm` | `~/.config/omarchy/shell.json` | same |
| Ghostty as default terminal, 10pt, `ctrl+enter=unbind` | `~/.config/xdg-terminals.list`, `~/.config/ghostty/local.conf` + trailing include | [terminal-font-size.md](terminal-font-size.md), [ghostty-ctrl-enter.md](ghostty-ctrl-enter.md) |
| hypr-momentum, plus `o.exec_on_start("hyprpm reload -n")` | hyprpm, `~/.config/hypr/autostart.lua` | [hyprpm-notes.md](hyprpm-notes.md) |
| `cleanupPeriodDays: 10950` | `~/.claude/settings.json` | [claude-code-notes.md](claude-code-notes.md) |
| git identity | `~/.gitconfig` | [new-machine-checklist.md](new-machine-checklist.md) |

Root:

```sh
sudo pacman -S --needed ghostty cmake hyprpm
sudo install -Dm755 assets/clock-refresh-on-resume/omarchy-clock-refresh \
  /usr/lib/systemd/system-sleep/omarchy-clock-refresh
```

Chrome's forced theme policy was also removed, in a variant that keeps
`omarchy.json`: [chrome-managed-theme.md](chrome-managed-theme.md#if-other-policies-are-present-keep-them-with-a-symlink).

SUPER+A is not added: Omarchy 4.5 ships its own "Select all".

## Scale 1.725: the macOS default size

At scale 2 the desktop is only 1204x753, and Chrome looked zoomed in. macOS isn't
at 2x by default on this machine. It reportedly defaults to "looks like" 1408x881
and offers 1204x753 as the step before that
([MacMost](https://macmost.com/15-tips-for-new-macbook-neo-users.html),
[MacRumors](https://forums.macrumors.com/threads/neo-display-thoughts.2481697/)).
macOS draws at 2x onto a hidden 2816x1762 canvas, then shrinks it to the panel,
which comes to about 1.71x.

**No scale between 1 and 2 divides this panel evenly.** `gcd(2408, 1506) = 2`, so
only 1 and 2 give whole logical pixels. The closest misses in Hyprland's 1/120
steps:

| Scale | Logical size | Max error |
|---|---|---|
| 1.725 (207/120) | 1395.94 x 873.04 | 0.06 px |
| 1.54167 (185/120) | 1561.95 x 976.87 | 0.14 px |
| 1.36667 (164/120) | 1761.95 x 1101.95 | 0.05 px |

1.725 gives 1396x873 and looks great in daily use. Fractional-aware apps draw at
1.725x directly. Older Wayland apps draw at 2x and Hyprland shrinks them, which is
the macOS trick per window.

**Hyprland rejects 1.725 and silently stays at 2**, with no config error. Getting
it to apply takes both of these:

```lua
-- looknfeel.lua
hl.config({ debug = { disable_scale_checks = true } })
-- monitors.lua
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.725 })
```

To apply it live without a reload, `hyprctl eval` needs an explicit mode. With
`mode = "preferred"` it answered `ok` and changed nothing:

```sh
hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "2408x1506@59.98200", position = "auto", scale = 1.725 })'
```

`disable_scale_checks` is a debug option, so suspect it first if rendering glitches
appear. It also means Hyprland won't catch a bad scale on this machine.

### A 1.725x button in the Display menu

Stock Omarchy rounds every scale up to a clean value, so on this panel the menu
offers only 1x and 2x, and `omarchy-hyprland-monitor-scaling 1.725` lands on 2.
The clone adds 1.725 for the 2408x1506 mode only, and applies it through a small
helper, so external monitors keep their normal list:

```sh
omarchy plugin clone omarchy.monitor      # switches the bar to <user>.monitor
D=~/.config/omarchy/plugins/$USER.monitor
patch -d "$D" -p1 < assets/macbook-neo/display-scale-widget.patch
install -m755 assets/macbook-neo/set-exact-scale "$D/"
omarchy restart shell
```

Then rebind the shortcut, which still opens the stock menu by name, in
`~/.config/hypr/bindings.lua` (put your real login in the plugin id):

```lua
o.rebind("SUPER + CTRL + D", "Display", { panel = "<user>.monitor" })
```

`omarchy restart shell` is required. Plugin hot-reload picked up `Panel.qml` but
kept the old `Model.js`, so the button didn't appear until the restart.

The patch was made against Omarchy 4.5.0-3. The clone won't receive later changes
to the stock widget. `SUPER+/` still uses Omarchy's rounding, so it snaps to 2.

## Palm touches while typing

With `disable_while_typing = false` copied from the other laptops, palms and
fingers landing on the trackpad moved the pointer during normal typing. The fix
was to delete the line, which restores the default of `true`.

The trackpad sits right under the hands, so the tradeoff goes the other way here:
the [WASD browser-game problem](browser-game-pointer-lock.md) comes back, and the
pad may stop responding while movement keys are held. A keybound toggle is the way
to get both, if it starts to matter. Not built yet.

libinput's Apple MTP quirks (`/usr/share/libinput/50-system-apple.quirks`) match
this pad by name and vendor (`05ac`), including `AttrPalmSizeThreshold=1600`, so
palm size detection needs no local quirk.

If stray clicks continue, the next thing to try is `tap_to_click = false` in the
`touchpad` block. Omarchy leaves tap-to-click on.

The pointer also vanishing while typing is Omarchy's `hide_on_key_press`, not a
fault.

## Terminal font: 10pt, not 11pt

Ghostty sizes text from the Hyprland scale, so the same point size draws larger
here than on the XPS 13, which runs at 1.6 on a panel of similar density:

| | Scale | Point size | Em size |
|---|---|---|---|
| XPS 13 (roughly 225 ppi) | 1.6 | 11pt | 23 px, 2.6 mm |
| MacBook Neo (219 ppi) | 1.725 | 10pt | 23 px, 2.7 mm |
| MacBook Neo at 11pt | 1.725 | 11pt | 25 px, 2.9 mm |

The size lives in `~/.config/ghostty/local.conf`, which is per machine:

```
font-size = 10
```

Apply with `omarchy restart terminal`, which reloads windows in place.

## Chrome

Google Chrome has an aarch64 package here (157.0.8103.38). It runs natively on
Wayland. The only flag change is Vulkan, [below](#vulkan-in-chrome).

`--force-device-scale-factor` **multiplies** with the Hyprland scale on Wayland
instead of replacing it. Measured at scale 2 in a throwaway profile, 1.0 gave
`devicePixelRatio` 2, 0.8 gave 1.6, and 1.6 made everything larger. Below 1 it does
shrink the tabs and toolbar, unlike Page zoom, which only affects page content. It
wasn't needed once the screen moved to 1.725, but it's the Chrome-only option if
the screen goes back to 2. `0.85` should be close to the macOS size. Only `0.8`,
`1.0` and `1.6` were tested.

### Vulkan in Chrome

Set up 2026-11-07. Stock Chrome runs WebGL on OpenGL and has no WebGPU adapter. The
Vulkan driver was already there: `vulkan-aurora`, a Honeykrisp-derived driver named
Borealis, reports `Apple A18 Pro (G17P B1)`, Vulkan 1.4.363, conformant
(`vulkaninfo --summary`, from `vulkan-tools`).

In `~/.config/chrome-flags.conf`, add the three features to the existing
`--enable-features` line. Only the last `--enable-features` counts, so a second line
would drop Omarchy's own features:

```
--enable-features=TouchpadOverscrollHistoryNavigation,OverlayScrollbar,Vulkan,VulkanFromANGLE,DefaultANGLEVulkan
```

No `--use-angle=vulkan` or `--ignore-gpu-blocklist` is needed. They changed nothing
here. Quit Chrome completely to apply it: the Relaunch button keeps the old flags
([gotcha](chrome-vulkan-white-video.md#the-gotcha-that-made-it-look-broken)).

Tested with real Wayland windows in throwaway profiles:

| Flags | WebGL | WebGPU | H.264 test video |
|---|---|---|---|
| Stock | OpenGL (`AGX G13/G14`) | no adapter | plays |
| `--use-angle=vulkan` only | Vulkan, A18 Pro | no adapter | not tested |
| The three features above | **Vulkan, A18 Pro** | **works** | **plays, correct color, no dropped frames** |
| `--use-angle=gl` with Vulkan and `--use-webgpu-adapter=vulkan` | OpenGL | works | **white rectangle** |

The last row is the [white-video bug](chrome-vulkan-white-video.md), so WebGPU on an
OpenGL ANGLE is not an option here.

Two misleading results while testing:

- **Don't test in headless mode.** `--headless=new` falls back to SwiftShader
  software rendering, and with `--use-angle=vulkan` its GPU process segfaults.
  Neither happens in a real window. Check `chrome://gpu`, or a page reading
  `WEBGL_debug_renderer_info`.
- **Chrome logs `'--ozone-platform=wayland' is not compatible with Vulkan`.** WebGL
  and WebGPU use Vulkan anyway, as above. Whether Chrome's own page compositing does
  wasn't established.

The daily browser has run these flags since 2026-11-07 with no crashes so far, which
is a short time. **Not tested:** real sites and games, any performance gain over OpenGL, or tab and
toolbar flicker over a long session, which the SER8 had with Vulkan flags. Video is
still decoded on the CPU, because Omarchy's flags set
`--disable-features=AcceleratedVideoDecoder`. Chromium is unchanged.

Undo: remove the three features from that line and fully restart Chrome.

## Wi-Fi: routers in WPA/WPA2 mixed mode

Home Wi-Fi failed instantly here while macOS joined it fine, because the Linux
driver accepts only AES and the router's group key is TKIP. It's fixed with a driver
patch that **has to be rebuilt after each kernel update**:
[macbook-neo-wifi-tkip.md](macbook-neo-wifi-tkip.md).

## Open / not done

- **hypr-tab-drag: built and enabled, but not loading.** hyprpm reported it loaded,
  yet `hyprctl plugin list` shows only hypr-momentum. Left as is on purpose. It has
  been a problem on other machines too.
- **hypr-momentum feel not confirmed.** It loads on arm64. It still needs a real
  test in a non-browser app. If login crashes: `hyprpm disable momentum` from a TTY.
- **SSH: inbound only, from another laptop on the LAN.** Keys only
  (`/etc/ssh/sshd_config.d/10-keys-only.conf`), with a `ufw` rule for `192.168.0.0/24`.
  This install had no SSH host keys, so `sshd` refuses to start until
  `sudo ssh-keygen -A` has run.
- **Syncthing: not set up.** It needs firewall changes
  ([syncthing-and-ufw.md](syncthing-and-ufw.md)).
- **Tray half-pixel patch: skipped.** It edits a package-owned file, and every update
  reverts it ([tray-icon-half-pixel.md](tray-icon-half-pixel.md)).
- **Clock hook:** the dry run passed. Not yet confirmed on a real lid close.
- **Chrome Vulkan: try it here.** Not done on the Neo yet. On a 16-inch M1 Pro
  (same Omarchy, kernel and Chrome setup), adding
  `Vulkan,DefaultANGLEVulkan,VulkanFromANGLE` to the `--enable-features=` line in
  `~/.config/chrome-flags.conf` took WebGPU from "no adapter" to working, with
  video still playing and no crashes. It has held up in light daily use there. The
  main gain is WebGPU, so don't expect browsing to change. The Neo has a different
  GPU, so check that it has a Vulkan driver first (`ls /usr/share/vulkan/icd.d`).
  Fully quit and reopen Chrome, then confirm in `chrome://gpu`. Watch for the toolbar
  flicker seen on the [SER8](chrome-ser8-flicker-trial.md) and for
  [white video](chrome-vulkan-white-video.md).

## Verify

```sh
hyprctl getoption input:touchpad:natural_scroll          # true
hyprctl getoption input:touchpad:disable_while_typing    # true
hyprctl getoption input:kb_options                       # no altwin:swap_lalt_lwin
hyprctl getoption gestures:workspace_swipe_distance      # 150
hyprctl getoption debug:disable_scale_checks             # true
hyprctl -j monitors | jq '.[0].scale'                    # 1.725
hyprctl plugin list | grep '^Plugin'                     # hypr-momentum
omarchy menu keybindings --print | grep -E 'Screenshot|Move tab'
omarchy-default-terminal                                 # ghostty
ghostty +show-config | grep font-size                    # 10
```

## Undo

```sh
# config: restore the .bak.<timestamp> files in ~/.config/hypr and ~/.config/omarchy
# scale: set scale = 2 in monitors.lua and remove disable_scale_checks from looknfeel.lua
# Display menu: put omarchy.monitor back in shell.json, drop the SUPER+CTRL+D rebind,
#   and delete ~/.config/omarchy/plugins/$USER.monitor
rm ~/.config/ghostty/local.conf
omarchy-default-terminal foot
sudo rm /usr/lib/systemd/system-sleep/omarchy-clock-refresh
```
