# SER8 Chrome toolbar flicker: graphics and extension trials

**Latest observation, 2026-09-22 evening:** the URL flicker returned after the
quiet interval. While scrolling `x.com/home`, without clicking a post, the
owner saw Home alternate with a longer, unreadable URL for a couple of seconds.
Historically it also happened after clicking into a post. **Not resolved.**

A no-reload v1.4.0 snapshot at 19:48:39 EDT showed Home, no held URL, and 156 of
400 ring entries. The newest decision was about 120 seconds old; the ring had
not filled. A follow-up confirmed the History and title filters were attached.
Exact symptom timing is unknown, so absence of matching decisions does not
establish a GPU cause or rule out an unobserved navigation mechanism. Raw logs
are private under `~/.local/state/x-url-flicker-tamer/`, not in this repository.

At the owner's request, v1.5.0 adds a persistent extension-local recorder:
browser URL/title notifications, page navigation, observed titles, filter
decisions, scroll timing and heartbeat. The popup offers **Flicker just
happened**, **Export log**, **Clear log** and pause/resume. It keeps up to 2,000
events, bounded by serialized size; events older than seven days are pruned on
later activity. Logs contain URLs/titles, remain local, and survive restarts.
The in-page buffer is still temporary; a crash can lose the latest unsaved
one-second batch. No automatic uploads or Chrome Sync. The temporary DevTools
watcher was superseded by this recorder, not left running.

Version 1.5.0 was reloaded and verified enabled in the main profile at about
20:01 EDT. The affected Home tab was reloaded to start the new recorder; new
X tabs and restarted sessions load it automatically. Other previously open X
tabs need one reload for page-level recording (browser-level logging is already
active). The diagnostics icon is pinned in the toolbar. Its popup was verified to show
recording enabled and 25 saved events after installation.

Validation: 19 replay, 13 native Chrome DOM/history, 7 storage/message-boundary,
and 4 complete-extension integration checks passed. The integration test used
an isolated headless Chromium profile and verified a full browser restart plus
JSON export. The v1.5.0 changes are local; the earlier v1.4.0 store submission
is separate. Filtering timings and graphics flags remain unchanged. An
OpenGL-only comparison was discussed but **not applied**.

**Configuration activated, 2026-09-22 at 11:56 EDT:** the saved
[OpenGL + WebGPU interop configuration](assets/chrome-ser8-gl-webgpu-experimental.conf)
is now **active in the main browser**. Chrome was fully stopped and started
through `google-chrome-stable --restore-last-session`; all five experimental
graphics switches were verified in the running main process. The previous
configuration is backed up at
`~/.config/chrome-flags.conf.before-gl-webgpu-interop-20260922-115622.bak`.
The owner subsequently reported continued URL/tab-title and extension-toolbar
flicker, plus a transient split-looking page while scrolling that returned to
normal. The graphics change alone was therefore not a confirmed fix. The scrolling
artifact suggests a rendering issue, but no recording or controlled reproduction
establishes its cause. Kernel checks found no new GPU reset/hang; the display
timeout was from boot, and Chrome's Wayland/Vulkan warning alone is inconclusive.

The local [URL Flicker Tamer](https://github.com/zoan37/x-url-flicker-tamer)
was updated from v1.3.0 to v1.4.0 and verified enabled in the main profile's
extension manager after a full restart on September 22. It now handles direct
title-element edits, cancels obsolete queued writes on Back/Forward, and guards
duplicate injection. Validation: 19 replay checks and 13 native Chrome checks.
These fix demonstrated extension gaps, not a confirmed cause of the visual
artifact. Graphics flags remain unchanged; an OpenGL-only comparison was
proposed, with loss of WebGPU support established by the earlier adapter test.

## Extension installation and Web Store release

- Local repo: `~/Projects/x-url-flicker-tamer`, upstream
  [zoan37/x-url-flicker-tamer](https://github.com/zoan37/x-url-flicker-tamer).
- The main Chrome profile uses the unpacked extension from that directory.
  Version **1.4.0** was initially verified after a full restart; **1.5.0**
  is now verified enabled after reloading its extension card. This local installation does not depend on store approval.
- The v1.4.0 ZIP was uploaded to the existing
  [Chrome Web Store item](https://chromewebstore.google.com/detail/url-flicker-tamer-for-x/dfemkbbkdllddebdecaagfhdcmagiifp)
  on September 22 at approximately 14:00 EDT. The dashboard confirmed
  **Pending review**, with automatic publication after approval enabled.
  That was the last verified store status, not a claim that v1.4.0 is live.
- No new permissions or site access were added. The package checksum and
  submission details are saved in the extension repo's
  `store-assets/release-1.4.0.md`; the ZIP is
  `dist/url-flicker-tamer-1.4.0.zip` there.

If the symptom returns, capture evidence before reloading the affected X tab:

```js
__uft.version   // confirms which content script is running
__uft.state()   // displayed URL/title and whether a URL change is queued
__uft.dump()    // last ~400 interception/commit records, kept only in this tab
```

These records can help distinguish actual URL/title writes from a visual
repaint with stable values. They do not diagnose GPU/compositor faults by
themselves. Record whether the address text, tab title, extension icons, or page
content changed, and whether scrolling or navigation triggered it. A short
recording would be more useful than assuming every similar flicker has one cause.

## Browser automation on the shared Omarchy desktop

The store upload used direct Wayland desktop input and screenshots, rather than
the OpenAI Chrome extension. That method shares the user's pointer and keyboard
focus, so even a different Chrome profile/window can interrupt other work.
The owner allowed it for this upload but asked to consider a less disruptive
approach for future tasks. Prefer an isolated browser session controlled through
browser automation when available; a separate profile alone does not isolate
desktop input. No background-browser setup was installed during this session.

## Earlier mixed-backend video regression

**Outcome, 2026-09-22:** the owner reported white video on x.com after activating
the original mixed OpenGL ANGLE + Vulkan compositing trial
(example: https://x.com/Mayz1169/status/2102392486241190253).
The running browser was confirmed to have the mixed OpenGL/Vulkan flags below.
Restored the pre-trial `chrome-flags.conf`, enabling `DefaultANGLEVulkan` and
`VulkanFromANGLE` again and removing the forced OpenGL switches. The daily
browser was fully stopped and started through `google-chrome-stable
--restore-last-session`; its running command line confirms the restored flags.
The trial was backed up as
`~/.config/chrome-flags.conf.before-white-video-rollback-20260922-101129.bak`.
Toolbar flicker remains unresolved; do not reapply this mixed configuration
without verifying video playback.

Rollback verification in a separate temporary native Wayland Chrome profile:
an H.264 test video played with `VaapiVideoDecoder`, advanced normally, and
rendered colored frames in both a screenshot and pixel readback, with no media
errors. This verifies the restored video path, not the specific X post in the
daily authenticated profile; that still needs a user playback check.

## Follow-up: flicker returned after rollback

Later on September 22, the owner reported that the flicker returned after the
full Vulkan configuration was restored. It now visibly involves the top tab
strip, address bar, and extension icons. Page-content flicker is possible but
unconfirmed. This timing implicates the rendering configuration but does not
establish a Chrome, Mesa, or Hyprland root cause, or a controlled clean-profile
reproduction.

A second candidate was tested in an isolated native Wayland profile:

Saved graphics fragment: [chrome-ser8-gl-webgpu-experimental.conf](assets/chrome-ser8-gl-webgpu-experimental.conf).
The fragment is saved for reuse and was applied to the main SER8 browser at
11:56 EDT on September 22; it is not automatically installed on other machines.

```text
--enable-features=VaapiVideoDecoder,VaapiIgnoreDriverChecks,ForceEnableWebGpuInterop
--disable-features=Vulkan,DefaultANGLEVulkan,VulkanFromANGLE
--use-gl=angle
--use-angle=gl
--use-vulkan=native
```

Unlike the failed mixed trial, this disables Vulkan compositing/rasterization.
The `--use-vulkan` switch initializes Vulkan for other uses such as WebGPU;
see Chromium's [GPU fallback documentation](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/content/browser/gpu/fallback.md).

- H.264 playback used `VaapiVideoDecoder`, advanced normally, and displayed
  colored frames in a screenshot and pixel readback without media errors.
- WebGL 2 selected ANGLE OpenGL ES on Radeon 780M.
- WebGPU obtained a non-fallback AMD RDNA 3 adapter, created a device, submitted
  a canvas render, and displayed the intended green rectangle without a
  validation error.
- The otherwise identical candidate without `ForceEnableWebGpuInterop` played
  video but returned `null` from `navigator.gpu.requestAdapter()`.
- MechaBlade's rendered menu was visible in a screenshot under the interop
  candidate. This check did not exercise gameplay or establish game stability.

**Experimental:** Chromium's [software rendering list, entry 186](https://github.com/chromium/chromium/blob/main/gpu/config/software_rendering_list.json)
currently disables this WebGPU interop path by default outside listed Intel
and NVIDIA exceptions. `ForceEnableWebGpuInterop` overrides that interop
decision, as implemented in [gpu_util.cc](https://github.com/chromium/chromium/blob/main/gpu/config/gpu_util.cc).
The checks above do not establish long-term stability or flicker improvement.
The candidate was subsequently activated in the main browser at 11:56 EDT.
Immediately before activation, the owner saw URL flicker again on X; a process
check confirmed that occurrence was still under the previous full Vulkan
configuration. It is not evidence that the new interop trial has failed.
The new main process command line was verified after a full restart with
session restoration. Subsequent daily-profile observations, including the
latest recurrence and persistent diagnostics, are recorded at the top of this document.

### Applying the saved experimental candidate

Back up `~/.config/chrome-flags.conf` first. Replace its existing graphics
switches with the five switches from the saved fragment; keep extension and
password-store settings. If unrelated enabled/disabled features are present,
merge their names into the corresponding feature lists instead of duplicating
`--enable-features` or `--disable-features` switches. Keep Chrome's graphics
acceleration setting enabled.

Fully quit Chrome and start it through `google-chrome-stable` or the app
launcher. `chrome://restart` reuses the old command line and will not apply a
flags-file edit. Verify the new process command line, then check X video,
normal browsing, and WebGPU games. Record flicker results separately from
video/game compatibility. To roll back, restore the flags-file backup and
fully quit/reopen again.

Originally configured **2026-09-21** on the Beelink SER8. The sections below
record the unsuccessful trial, not the current settings or a confirmed flicker fix.

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
