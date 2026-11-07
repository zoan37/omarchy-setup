# MacBook Pro 16-inch M1 Pro (MacBookPro18,1): new-machine setup

Set up **2026-11-07** on Omarchy 4.5.0-3 for Apple Silicon (arm64, `omarchy-mac`
0.2.3, kernel `7.2.11-14-1-ARCH`, Hyprland 0.56.2). 3456x2234@120Hz eDP on a
346x223 mm panel, run at scale 2. Identify it with
`cat /sys/class/dmi/id/product_name`.

This follows the [MacBook Neo setup](macbook-neo-setup.md). Same result, except:

- **Scale 2, the stock value.** It gives 1728x1117. The Neo's 1.725 scale,
  `disable_scale_checks` and cloned Display menu aren't needed.
- **No Wi-Fi driver patch.** That patch is for the Neo's MediaTek chip.
- **hypr-tab-drag not installed.** It didn't load on the Neo.
- **Chrome uses Vulkan.** See [below](#chrome-vulkan).
- **Ghostty is 10pt**, like the Neo. At scale 2 that's about 2.7 mm, in line with
  the [Neo's table](macbook-neo-setup.md#terminal-font-10pt-not-11pt).

## Applied

User config (each changed file has a `.bak.<timestamp>` next to it):

| What | Where |
|---|---|
| Natural scroll, 3-finger swipe with the hair-trigger tuning | `~/.config/hypr/input.lua` |
| `extend_border_grab_area = 15` | `~/.config/hypr/looknfeel.lua` |
| Group tab reorder, SUPER+SHIFT+S screenshot | `~/.config/hypr/bindings.lua` |
| `o.exec_on_start("hyprpm reload -n")`, hypr-dwt-timeout load | `~/.config/hypr/autostart.lua` |
| Clock format `ddd d MMM HH:mm` | `~/.config/omarchy/shell.json` |
| Ghostty as default terminal, 10pt, `ctrl+enter=unbind` | `~/.config/xdg-terminals.list`, `~/.config/ghostty/local.conf` + trailing include |
| Vulkan features | `~/.config/chrome-flags.conf` |
| `cleanupPeriodDays: 10950` | `~/.claude/settings.json` |

Root:

```sh
sudo pacman -S --needed ghostty cmake hyprpm libinput-tools
sudo install -Dm755 assets/clock-refresh-on-resume/omarchy-clock-refresh \
  /usr/lib/systemd/system-sleep/omarchy-clock-refresh
```

`libinput-tools` is only for `libinput quirks list` and `libinput record`. Chrome's
theme policy was removed with the
[symlink variant](chrome-managed-theme.md#if-other-policies-are-present-keep-them-with-a-symlink).

hypr-momentum loads on this machine. hyprpm needs a real terminal for its sudo prompt.

## Chrome: Vulkan

Added to the existing `--enable-features=` line in `~/.config/chrome-flags.conf`:

```
Vulkan,DefaultANGLEVulkan,VulkanFromANGLE
```

The VA-API flags from the other machines are left out, because the stock
`--disable-features=AcceleratedVideoDecoder` keeps video decoding in software.

Compared in throwaway profiles, using the same flags otherwise:

| | Stock | Vulkan |
|---|---|---|
| Display type | `ANGLE_OPENGL` | `ANGLE_VULKAN` |
| Skia backend | `GaneshGL` | `GaneshVulkan` |
| WebGPU | No adapter | Works, render read back correctly |
| Heavy WebGL shader | 118 fps | 117 fps (both at the 120 Hz vsync cap) |
| H.264 test video | Plays | Plays, not white |

The main gain is WebGPU. The WebGL number says nothing about which is faster,
because both hit the cap. It has felt fine in light daily use. Battery use, long
sessions, and sleep and wake are not measured.

To undo it, restore `chrome-flags.conf.bak.<timestamp>`, then fully quit and reopen
Chrome.

## Palm touches while typing

`disable_while_typing` and tap-to-click are both left on. Palms can still make the
hidden pointer reappear while typing, so the pause after typing is now tunable
([below](#pause-after-typing-500-ms)).

libinput does match this pad. `libinput quirks list` shows the `Apple Laptop
Touchpad (SPI)` entry, and the keyboard is tagged internal, so the two are paired:

```
ModelAppleTouchpad=1
AttrSizeHint=104x75
AttrPalmSizeThreshold=1600
AttrTouchSizeRange=150:130
```

The pad reports touch major and minor, width major and minor, orientation and
pressure. A short `libinput record` while typing (34 touches) and resting a palm
(8 touches) showed why a size threshold isn't the fix:

| Touch | Peak size | Result |
|---|---|---|
| Side-of-hand grazes, right side of the pad | major 98-206, minor 58-112 | Already ignored: below `AttrTouchSizeRange` |
| Touches at the far left edge | major up to about 700 | Should fall in libinput's edge palm zone, not confirmed |
| Touches that moved 8-28 mm during typing | major 440-670 | Passes everything |
| Full resting palm | major 2460-2998 | Caught by the 1600 threshold |

The third row is the problem. Those touches are far below 1600, but may be close to
a normal fingertip. The recording has no finger step, and it was taken while trying
to trigger the problem, so some may be real swipes. Lowering the threshold without
that data risks dropping real fingers.

### Pause after typing: 500 ms

libinput's `libinput_device_config_dwt_set_timeout` can change the pause, but
Hyprland 0.56.2 doesn't call it or expose an option. A small plugin sets it:
[assets/macbook-pro-m1/hypr-dwt-timeout](assets/macbook-pro-m1/hypr-dwt-timeout).
800 ms was tried first and felt too long, so it's back at 500 ms, which is the
default libinput reports for this pad. At that value the plugin may change nothing,
so it's only there to make the pause easy to tune.

```sh
cp -r assets/macbook-pro-m1/hypr-dwt-timeout ~/Projects/
cd ~/Projects/hypr-dwt-timeout && make
hyprctl plugin load "$PWD/dwt-timeout.so"
```

Then in `~/.config/hypr/autostart.lua`:

```lua
o.exec_on_start("hyprctl plugin load $HOME/Projects/hypr-dwt-timeout/dwt-timeout.so")
```

It isn't managed by hyprpm, so `hyprpm update` won't rebuild it. After a Hyprland
update it refuses to load and the pad falls back to the default pause. To rebuild:

```sh
hyprctl plugin unload ~/Projects/hypr-dwt-timeout/dwt-timeout.so
make -C ~/Projects/hypr-dwt-timeout clean all
hyprctl plugin load ~/Projects/hypr-dwt-timeout/dwt-timeout.so
```

Set `HYPR_DWT_TIMEOUT_MS` in the compositor's environment for a different value.
`cat $XDG_RUNTIME_DIR/hypr-dwt-timeout` shows what was applied. To undo it, remove
the autostart line and unload the plugin.

### Todo: macOS-style palm detection

Build a filter that judges a touch on more than its size, since palms and fingers
overlap in size here. macOS's method is private, but the pad gives enough to try:

- shape and angle (touch major, minor and orientation)
- where the touch lands, and how far it is from the keyboard
- how it arrives: a palm rolls on and spreads, a finger lands and moves
- whether keys were pressed just before

Start by recording deliberate finger use, which is the missing half of the data above.
Compare it with palm touches for a signal that separates them, then look at whether
libinput or a Hyprland plugin is the right place for the filter.

## Verify

```sh
hyprctl getoption input:touchpad:natural_scroll          # true
hyprctl getoption input:touchpad:disable_while_typing    # true
hyprctl getoption input:touchpad:tap-to-click            # true
hyprctl getoption gestures:workspace_swipe_distance      # 150
hyprctl -j monitors | jq '.[0].scale'                    # 2
hyprctl plugin list | grep '^Plugin'                     # hypr-momentum, hypr-dwt-timeout
omarchy-default-terminal                                 # ghostty
ghostty +show-config | grep font-size                    # 10
libinput quirks list /dev/input/event1                   # the block above
```

Check that `event1` is the trackpad first: `cat /sys/class/input/event1/device/name`.

## Open / not done

- **Clock hook:** installed, not confirmed on a real lid close.
- **Chrome theme policy symlink:** not confirmed through a live theme change.
- **SSH and syncthing:** not set up. Both need firewall changes
  ([syncthing-and-ufw.md](syncthing-and-ufw.md)).
