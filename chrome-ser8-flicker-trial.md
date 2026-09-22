# SER8 Chrome toolbar flicker: OpenGL ANGLE + Vulkan trial

Configured **2026-09-21** on the Beelink SER8. **Evaluation pending:** this
is a rendering-backend trial, not a confirmed flicker fix. The existing daily
Chrome process keeps its old settings until a full quit and fresh launch.

## Symptom and machine

Chrome intermittently alternates URLs in the address bar, particularly on
x.com, and extension icons sometimes appear to disappear and reappear.
The owner has not noticed this on the Dell XPS 13; its current graphics
configuration was not compared. X's own URL changes and extensions remain
possible contributors, so similar-looking artifacts do not establish a
graphics-driver fault.

- Beelink SER8 / AZW SER8, Ryzen 7 8745HS, Radeon 780M (`1002:1900`, `amdgpu`).
- Omarchy 4.0.4, kernel `7.2.5-3-omarchy`, Hyprland `0.56.2-2`.
- Google Chrome `153.0.8010.52-1`; Mesa / vulkan-radeon `26.2.2-1`.
- Native Wayland. During these checks: Dell S2721QS, 3840×2160 at 60 Hz
  over HDMI, scale 1.6, VRR disabled.

[Comment on Hyprland #5333](https://github.com/hyprwm/Hyprland/issues/5333#issuecomment-5769337998).
That issue is closed and much older; this report does not establish the same
cause or a regression of its fix.

## Trial configuration

In `~/.config/chrome-flags.conf`, replace the previous graphics feature line
with these four lines. Preserve the extension-loading and password-store
lines, and merge unrelated enabled/disabled features if present rather than
creating duplicate feature-list switches.

```text
--enable-features=Vulkan,VaapiVideoDecoder,VaapiIgnoreDriverChecks
--disable-features=DefaultANGLEVulkan,VulkanFromANGLE
--use-gl=angle
--use-angle=gl
```

Keep Chrome's **Use graphics acceleration when available** setting enabled.
Leave `chrome://flags` at Default for these features. Chromium has a separate
`chromium-flags.conf`; this trial changes Google Chrome only.

This forces ANGLE (Chrome's graphics translation layer used for WebGL) onto
OpenGL while leaving Chrome's Vulkan feature enabled. In the tests below,
WebGPU could still obtain the AMD GPU and render. It does **not** establish
that every part of Chrome's interface/compositor now uses OpenGL, or remove
Vulkan from the system. Both paths remain hardware accelerated.

## What was tested

Separate temporary Chrome profiles were used; the daily profile and its
extensions were not part of the compatibility tests.

| Configuration | WebGL 2 | Actual WebGPU adapter/render test |
|---|---|---|
| Previous Vulkan ANGLE flags | Works | AMD adapter; basic canvas submission succeeds |
| OpenGL ANGLE with Vulkan disabled | Works | `requestAdapter()` returns `null` |
| OpenGL ANGLE with Vulkan retained | Works | AMD adapter; basic canvas submission succeeds |

The OpenGL-only configuration still reported WebGPU as enabled in the GPU
feature summary. **That summary is insufficient:** an actual adapter/device
request and rendering test are needed.

[MechaBlade](https://www.spawn.co/@ress/mechablade/play) was then tested under
both the old configuration and this trial. Both rendered the animated menu
and tutorial, and accepted keyboard input to advance dialogue and exercise
controls. The trial's game log reported an AMD RDNA 3 GPU device. No GPU-process
crashes or WebGPU validation/device-lost errors were observed during these
short checks. This was not a full playthrough, frame-rate benchmark, video
decode test, or long-term stability test.

Both Vulkan-enabled configurations logged the Wayland/Vulkan incompatibility
warning from `wayland_surface_factory.cc` while still rendering successfully.
The warning alone neither proves the flicker's cause nor establishes that
Vulkan is entirely unusable. The running daily Chrome GPU process loaded
`libvulkan_radeon.so`. This boot's kernel log showed no GPU resets/hangs; the
display timeout found occurred during startup.

## Activate and evaluate

1. Save any in-progress browser work, fully quit Chrome, then reopen from the
   app launcher or `google-chrome-stable`. **Do not use `chrome://restart` or
   Chrome's in-app Relaunch button** to pick up edits to this file: they reuse
   the old command line instead of running the wrapper that reads the file.
2. Check `chrome://version` for the four switches above. In `chrome://gpu`,
   ANGLE should identify OpenGL / Mesa / Radeon 780M, with GPU compositing
   enabled and Vulkan still enabled.
3. Recheck MechaBlade and normal browsing with the usual extensions. Record
   whether URL/icon flicker changes, and whether it also occurs outside x.com.
4. Check x.com and YouTube video playback. The older
   [white-video notes](chrome-vulkan-white-video.md) document problems mixing
   OpenGL ANGLE with Vulkan compositing. Those tests motivated the previous
   flags; the game checks here do not establish video compatibility.

If video turns white/blank, gameplay regresses, or the trial offers no benefit,
restore the previous configuration. Do not promote this trial to a general
recommendation for the Dell laptops without testing them separately.

## Roll back

The exact pre-trial file was saved on this SER8 as:

```text
~/.config/chrome-flags.conf.before-angle-opengl-20260921-203444.bak
```

To restore that snapshot (it also restores the extension/password-store lines
as they were at backup time):

```sh
cp ~/.config/chrome-flags.conf.before-angle-opengl-20260921-203444.bak \
  ~/.config/chrome-flags.conf
```

If later unrelated changes must be retained, instead remove the trial's
`--use-gl` / `--use-angle` switches and its two disabled-feature entries, then
restore the original graphics feature list:

```text
--enable-features=Vulkan,DefaultANGLEVulkan,VulkanFromANGLE,VaapiVideoDecoder,VaapiIgnoreDriverChecks
```

Fully quit and reopen Chrome again after rollback.
