# Chrome: Vulkan enabled + fix for white/blank video

**Current SER8 configuration, 2026-09-22 at 11:56 EDT:** the main browser now
uses the [experimental OpenGL + WebGPU interop flags](assets/chrome-ser8-gl-webgpu-experimental.conf),
following renewed tab-strip/toolbar flicker under the full Vulkan settings
below. Chrome was fully restarted and its running flags verified. See the
[trial notes](chrome-ser8-flicker-trial.md) for activation, backup, and evidence.
URL Flicker Tamer v1.4.0 is also installed locally and was submitted to the Web
Store for review. The owner later reported a quiet interval without flicker,
following earlier recurrences and a transient scrolling artifact; this is not
yet a confirmed fix. The full Vulkan setup below remains the previous
video-compatible configuration and rollback option.

**SER8 update, 2026-09-22:** the
[OpenGL ANGLE + Vulkan trial](chrome-ser8-flicker-trial.md) produced white
video on x.com after activation. Restored the configuration below and fully
restarted the daily browser with session restoration; its command line confirms
the restored flags. A separate Chrome profile passed an H.264 playback check
using `VaapiVideoDecoder` with visible colored frames and no media errors.
The specific X post still needs a playback check in the daily profile. Toolbar
flicker remains unresolved.

**Symptom:** after enabling Vulkan in Chrome, videos on x.com / YouTube play
audio but render as a solid white rectangle.

**Cause:** enabling Vulkan alone leaves ANGLE (Chrome's GL layer) running on
OpenGL. Decoded video frames then can't be imported into the Vulkan compositing
path, so the `<video>` element paints white. The fix is to run ANGLE on Vulkan
too, so both sides agree on the frame format.

## The fix

Put this in `~/.config/chrome-flags.conf` (works on both Intel/ANV and
AMD/RADV):

```
# Vulkan for WebGL/WebGPU games, with VA-API video decode kept working.
# DefaultANGLEVulkan + VulkanFromANGLE run ANGLE on Vulkan so decoded video
# frames import cleanly (plain #enable-vulkan alone causes white video).
--enable-features=Vulkan,DefaultANGLEVulkan,VulkanFromANGLE,VaapiVideoDecoder,VaapiIgnoreDriverChecks
```

Leave `chrome://flags` alone (everything on Default) — the conf file is the
single source of truth. Vulkan enabled in both places is harmless but confusing
to debug.

## The gotcha that made it look broken

**Chrome's in-app Relaunch button (and `chrome://restart`) re-execs Chrome with
its old command line.** It never re-runs the `/usr/bin/google-chrome-stable`
wrapper, which is the only thing that reads `chrome-flags.conf`. So after
editing the conf file, relaunching from inside Chrome tests *nothing* — the
browser keeps running flag-less, and every experiment (toggling hardware
decode, etc.) appears to have no effect.

After any conf change: **full quit (Ctrl+Q / close all windows), then launch
from the app launcher or `google-chrome-stable` in a terminal.**

Verify the flags actually landed:

```
pgrep -a -f '^/opt/google/chrome/chrome ' | head -1
```

The main process must show `--enable-features=Vulkan,...`. Then `chrome://gpu`
should report *Vulkan: Enabled* and the ANGLE/GL_RENDERER line should mention
Vulkan rather than OpenGL ES.

## Per-machine notes

- **File name matters:** Google Chrome reads `~/.config/chrome-flags.conf`;
  Chromium reads `~/.config/chromium-flags.conf`. They do not inherit from each
  other.
- **Intel (Wildcat Lake XPS 13):** Mesa ships no Intel VA-API driver, so the
  `VaapiVideoDecoder` half is a no-op until `intel-media-driver` (iHD) is
  installed — and Omarchy's installer **skips it on this hardware**, which is
  why the fan spins up on video. Full write-up and the correct package set in
  [xps13-fan-spins-up-on-video.md](xps13-fan-spins-up-on-video.md). Vulkan
  itself works out of the box via `vulkan-intel` (ANV).
- **AMD (HawkPoint1):** `radeonsi_drv_video.so` comes with Mesa, so VA-API
  decode works with no extra packages. `VaapiIgnoreDriverChecks` is needed
  because Chrome's allowlist doesn't recognize the Mesa stack.
