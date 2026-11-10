# Browser games: camera dies after the first WASD key (both laptops)

**Symptom.** Load a WebGL/three.js game in Chrome, click to lock the pointer.
Mouse-look works for a second or two. The moment you press a movement key the
camera stops responding to the trackpad — it reads exactly like pointer lock
breaking. Identical on the XPS 13 and XPS 16; fine on macOS.

**It is not pointer lock.** libinput's *disable-while-typing* mutes the
touchpad for a short window after every keystroke, to reject palms. In a WASD
game you're holding keys constantly, so the pad stays muted. The lock is held
the entire time; the touchpad just isn't sending events.

Hyprland/libinput default this **on**. Omarchy even ships the knob commented
out in the stock `~/.config/hypr/input.lua` template:

```lua
--       -- Enable the touchpad while typing.
--       disable_while_typing = false,
```

## Fix

In `~/.config/hypr/input.lua`, inside the existing `input.touchpad` block:

```lua
touchpad = {
  natural_scroll = true,
  disable_while_typing = false,
},
```

Apply and verify:

```sh
hyprctl reload
hyprctl configerrors                                   # must be empty
hyprctl getoption input:touchpad:disable_while_typing  # -> bool: false
```

Applied to both laptops 2026-09-17. **Not applicable to the Beelink** — no
touchpad. **Left on the default on the [MacBook Neo](macbook-neo-setup.md#palm-touches-while-typing)**,
where turning it off let palms move the pointer during normal typing.

**Tradeoff:** palm rejection while typing is now off, so you may occasionally
jog the cursor with a palm mid-typing. There's no per-application libinput
switch, so scoping it to games only would mean a keybound toggle script. Not
worth it unless the palm contact actually bothers you.

**Revert:** delete the line (the default is `true`), or restore the
`input.lua.bak.<epoch>` written next to it.

## Update 2026-11-09: the fix was gone, now a bar toggle (XPS 13)

The `disable_while_typing = false` line had disappeared from `input.lua`,
probably in the [`.conf` → `.lua` migration](quattro-lua-migration.md), so the
camera died again in a three.js shooter. Instead of turning palm rejection off
for good, there's now a **game-mode button in the bar** (right section, before
the keyboard layout): an outlined gamepad (`󱔓`) means off, normal palm rejection;
a filled one (`󰊗`) means on, touchpad live while keys are held. Click to switch.
It also shows a 2 s notification.

It's a `command` bar module, two scripts in
[`assets/game-mode/`](assets/game-mode/) copied to `~/.config/omarchy/bar/scripts/`,
plus this entry in `bar.layout.right` of `~/.config/omarchy/shell.json`:

```json
{ "id": "game-mode", "type": "command",
  "exec": "~/.config/omarchy/bar/scripts/game-mode-status", "interval": 2,
  "tooltip": "Game mode", "onClick": "~/.config/omarchy/bar/scripts/game-mode-toggle" }
```

Under the Lua config `hyprctl keyword` is refused ("keyword can't work with
non-legacy parsers. Use eval."), so the toggle uses

```sh
hyprctl eval 'hl.config({ input = { touchpad = { disable_while_typing = false } } })'
```

The change is runtime only: a config reload or re-login goes back to the default
(palm rejection on), which is the safe side. Undo: delete the entry from
`shell.json` (backup `shell.json.bak.<epoch>` next to it) and the two scripts.

## Dead ends — don't re-chase these

All four were tried and *all four failed*, in this order. The whole detour came
from believing the symptom's framing ("pointer lock breaks") instead of
questioning it.

- **`cursor:hide_on_key_press = false`.** Hyprland hides the cursor on key
  press, which looks like an obvious way to drop a pointer constraint, and the
  symptom is keypress-triggered. Wrong layer — it never touches libinput.
- **`cursor:no_hardware_cursors = 1`** (force software cursors). The commonly
  cited Hyprland fix for cursors "refusing to lock" in games. Unrelated here.
- **Stopping `omarchy-fcitx5.service`.** fcitx5 is a stock enabled Omarchy
  service and *does* register `hl-virtual-keyboard-fcitx5` with Hyprland,
  firing `activelayout` events — visible in the `.socket2.sock` event stream.
  Looks damning next to a keypress-triggered bug. Not the cause.
- **Running Chrome under XWayland** (`--ozone-platform=x11`, throwaway
  profile). Also broke. This was the real tell and it got misread: X11 grabs
  and `zwp_pointer_constraints_v1` are *different* code paths, so both failing
  doesn't mean "must be the compositor" — it means the cause sits **below**
  both, in libinput. Chrome and Hyprland were both innocent.

Also ruled out: bare `W/A/S/D` are not bound in Hyprland (all 16 WASD binds
require SUPER, `modmask >= 64`; no submaps), so nothing was intercepting the
movement keys.

## The diagnostic that actually settled it

`hyprctl cursorpos` is an objective lock indicator — while the pointer is
locked the real cursor cannot move. Sampling it every 250 ms during a "broken"
session:

```
16:03:25.33  pos=787,483  win=google-chrome
16:03:25.64  pos=786,482
16:03:26.26  pos=787,483
...  frozen at 787,483 for 7+ seconds
```

Frozen solid while it *felt* broken. That proves the lock was held and moves
the search off the compositor entirely. Worth reaching for early next time
instead of toggling compositor options.

Useful companion: the Hyprland event stream, which shows focus changes, layout
changes and virtual keyboards in real time.

```sh
socat -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock
```

(Note `hyprctl` over SSH needs `XDG_RUNTIME_DIR=/run/user/$(id -u)` and
`HYPRLAND_INSTANCE_SIGNATURE=$(ls $XDG_RUNTIME_DIR/hypr/ | head -1)`, or it
errors with "is hyprland running?".)

## Related

- [touchpad-momentum-scroll.md](touchpad-momentum-scroll.md) — the other
  touchpad-feel work; note that pad measured clean, so input weirdness is
  always downstream of the hardware.
- [hyprland-shell-tweaks.md](hyprland-shell-tweaks.md) — where the rest of the
  `input.lua` tweaks (Alt/Super swap, natural scroll, swipe) live.
