# Dell XPS 16 (DA16260): what carried over from the XPS 13, and what didn't

**Set up 2026-09-17** on a fresh Omarchy `4.0.4-1` install, kernel
`7.2.5-3-omarchy`. The XPS 13 hardware workarounds were not carried over;
the software tweaks ported across unchanged. **Correction 2026-09-18:** kernel
version alone does not establish that Panel Replay is disabled or fixed here.
Live checks did not show the severe interrupt/awake pattern reported in
Omarchy PR #11076, but battery impact remains unverified. See the measurements
below before applying a display workaround.

## Identifiers

| | Value |
|---|---|
| `product_name` | `XPS 16 DA16260` |
| `product_sku` | `0DBA` (XPS 13 is `0E53`, XPS 14 is `0DB9`) |
| `board_name` | `0W09YJ` |
| CPU | Intel Core Ultra X9 388H (**Panther Lake**) |
| GPU | `8086:b080` — Arc B390 iGPU (Xe3) |
| Panel | LG **OLED**, 3200x2000@120Hz eDP, scale 1.6 |
| Audio | `sof-soundwire`, SoundWire speakers |
| Touchpad | `VEN_2C2F:00 2C2F:0033`, non-haptic |

The XPS 13 is Wildcat Lake with a 2560x1600 IPS panel and a Goodix touchpad, so
**the two machines share almost no silicon below the CPU vendor.** Don't reason
from one to the other.

## XPS 13 hardware fixes: assess this machine separately

### Panel Replay / PSR — severe failure not observed; no workaround applied

The earlier version of this note inferred from an upstream quirk and kernel
7.2.5 that Panel Replay was disabled. **That conclusion was not verified and
does not match the live mode report.** Do not use the kernel version or smooth
scrolling alone as evidence that this feature is off or free of power issues.

[Omarchy PR #11076](https://github.com/omacom/omarchy/pull/11076) reports a
Panel Replay failure on an XPS 14 with Panther Lake: roughly 6,000 GPU
interrupts/second at 120 Hz, the render tile awake 95% of the time, and high
battery draw. Its proposed workaround disables only Panel Replay and keeps
PSR2 available. Those are the reporter's observations, not measurements from
this XPS 16.

Read-only checks on **2026-09-18**, running `7.2.5-3-omarchy`, found:

| Check | XPS 16 result |
|---|---|
| Boot log | `Applying Panel Replay ALPM cursor lag workaround`; also `Selective fetch area calculation failed in pipe A` |
| Module parameters | `enable_panel_replay = -1`, `enable_psr = -1`; no explicit disable flags in `/proc/cmdline` |
| Reported PSR mode | `Panel Replay Selective Update enabled (Early Transport)` |
| Source control/status snapshot | `disabled [0x00000000]` / `IDLE [0x04002400]` |
| Performance counter / selective fetch | `0` / `enabled` |
| Xe interrupt rate | 347.7/s over 5 seconds; 333.8/s in a later 10-second sample |
| GPU C6 residency | 62.6% during that 10-second sample; a separate snapshot reported `gt-c6` and actual frequency 0 |
| Battery | `Full`, not discharging; battery-drain impact was not measured |

**Interpretation:** the boot warning overlaps with the PR, but these short
samples do not show its severe interrupt storm or nearly always-awake GPU.
The mode line does not prove Panel Replay was actively updating the panel at
that instant: the source control/status snapshot also reported disabled/IDLE.
Neither that snapshot nor the zero performance counter establishes the PR's
failure by itself. This was ordinary desktop activity, not a controlled idle
or battery A/B test, and it cannot rule out intermittent or smaller effects.

No display settings were changed. Do not copy the XPS 13's combined PSR and
Panel Replay disable flags based on this evidence. If lag or unexplained
battery drain appears, repeat the live checks and compare matched workloads
before deciding whether the narrower workaround in PR #11076 helps.

Useful read-only checks:

```sh
journalctl -k -b --no-pager | rg -i 'selective fetch|panel replay|psr'
sudo cat /sys/kernel/debug/dri/0000:00:02.0/eDP-1/i915_psr_status
sudo cat /sys/module/xe/parameters/enable_panel_replay /sys/module/xe/parameters/enable_psr
cat /proc/cmdline
cat /sys/class/drm/card0/device/tile0/gt0/gtidle/idle_status
cat /sys/class/drm/card0/device/tile0/gt0/gtidle/idle_residency_ms
rg '\bxe$' /proc/interrupts
```

Interrupt totals and idle residency are cumulative: take two readings and
divide their differences by elapsed time. C6 percentage is the residency
difference in milliseconds divided by elapsed milliseconds, multiplied by 100.

Omarchy also applied `fred=on` on this machine. That is a separate setting and
does not verify Panel Replay's state:

```sh
cat /etc/limine-entry-tool.d/intel-panther-lake-fred.conf   # -> KERNEL_CMDLINE[default]+=" fred=on"
cat /proc/cmdline | grep -o 'fred=on'
```

Note the **panel is OLED here**, which the XPS 13's is not. Omarchy ships a
matcher for exactly this combination, and it fires:

```sh
/usr/share/omarchy/bin/omarchy-hw-dell-xps-oled && echo match   # EDID bytes 8-9 == 30e4
```

### Speakers — upstream profile auto-matched, nothing to install

The whole [xps13-speaker-pops-and-eq.md](xps13-speaker-pops-and-eq.md) /
[xps13-sidecar-amps.md](xps13-sidecar-amps.md) saga is inapplicable: no
`dell-xps13-sidecar-amps` package, no restore kit, no
`90-speaker-no-suspend.conf`, no `lsp-plugins-lv2` to install by hand (the
tuning pulls it in). On a fresh install this was already live:

```
$ omarchy audio tuning status
Installed:    yes (~/.config/pipewire/omarchy-speaker-tuning.conf.d/90-tuning.conf)
Host service: active (enabled)
Matches:      Dell XPS 14/16 (2026) speakers (dell-xps-2026)
```

This is the `tunings/dell-xps-2026/` profile that
[post-update-checklist.md](post-update-checklist.md) §1 flagged as a "new
neighbour" which the XPS 13 (SKU `0E53`) deliberately does *not* match. This
machine is `0DBA`, which **does**.

**Caveat worth knowing, from upstream's own comments** in
`/usr/share/omarchy/default/audio/tunings/dell-xps-2026/tuning.conf`:

```
##   0DB9  XPS 14 -- measured here, see below
##   0DBA  XPS 16 -- included on report that this profile suits it, not measured
```

So the curve applied to this laptop was **measured on the XPS 14 and extended to
the XPS 16 on a report, not a measurement**. It sounds good, but if it ever
seems off, that is the reason — and a measured XPS 16 correction would be a
legitimate upstream contribution. Toggle with `omarchy audio tuning off` to
A/B against the raw Cirrus voicing before concluding anything.

**Follow-up, same day: it does fatigue the ear.** Corrected with a local
corrective stage and a variant switcher rather than by editing the packaged
files — [xps16-speaker-tuning.md](xps16-speaker-tuning.md).

### Touchpad — different hardware, same fix, no re-measurement needed

The pad is `VEN_2C2F:0033`, not the XPS 13's Goodix `GXTP7863`, and
`omarchy-hw-dell-xps-haptic-touchpad` does **not** match (so Omarchy's haptics
fix is not in play). None of that matters: hypr-momentum works at the
compositor, not the device, so the install is identical and the measurements in
[touchpad-momentum-scroll.md](touchpad-momentum-scroll.md) are XPS 13 trivia
here. Don't re-derive them unless the cursor actually misbehaves.

### Fan noise — browser workload found; turbo-off trial ongoing

The one symptom the XPS 13 and XPS 16 genuinely share is "the fan spins up on
video" — from unrelated causes. The XPS 13's is a missing VA-API driver; here
the decode stack is installed and working, and the cause turned out not to be
hardware at all: a local web page rebuilding a DOM layer every frame at 120 Hz,
holding ~54% of a core and raising the idle floor until the EC's fan trip band
was permanently within reach. See
[xps16-fan-spins-up-on-video.md](xps16-fan-spins-up-on-video.md).

Two findings from it are worth knowing before touching anything thermal here:

- **`dell_wmi_ddv` and `coretemp` under-report by ~20 °C** versus
  `x86_pkg_temp` (`/sys/class/thermal/thermal_zone10`), and are too slow to see
  what the EC reacts to. Sample the package at ≥2 Hz or you will measure a
  placid 41 °C while the chip spikes to 92 °C.
- **`platform_profile` offers only `balanced` and `performance`** here — there
  is no `low-power`, unlike the XPS 13. The GUI power-saver toggle sets the
  profile to `custom` and drives EPP directly instead.

The BIOS does expose a `Quiet` thermal mode via `dell-wmi-sysman`, settable
from Linux without rebooting into setup (it didn't fix the fan, but it's the
firmware setting that persists on its own) — details in the same doc.

**Later on 2026-09-17:** started a separate
[persistent turbo-off trial](xps16-turbo-off-trial.md), prioritizing less fan
noise over peak development performance. `/etc/tmpfiles.d/disable-cpu-turbo.conf`
sets `no_turbo=1` at boot; verified active immediately, with reboot and real-world
evaluation still pending. This differs from the earlier 75% boost cap. Keep it
enabled for the trial; the linked note covers verification and rollback.

## The software tweaks: all ported, unchanged

Everything in [hyprland-shell-tweaks.md](hyprland-shell-tweaks.md) applied
verbatim and verified live — Alt/Super swap, natural scroll, the hair-trigger
3-finger swipe, the resize-on-border trio, group tab-reorder, `SUPER+A`
select-all, `SUPER+SHIFT+S` screenshot (the `hl.unbind` was still mandatory;
Quattro still hands that key to Google Maps).

`hyprctl configerrors` was clean. Backups of every touched file are at
`*.pre-xps16`.

**No Quattro migration to worry about** — fresh 4.0.4 install, `configProvider:
lua` from the start, so [quattro-lua-migration.md](quattro-lua-migration.md) is
history, not a checklist.

### What a fresh Quattro install does *not* give you

**Current terminal (2026-09-18):** Ghostty is installed and selected as the
default for a trial, with an 11pt font override. Kitty remains installed.
See [Ghostty trial, verification, and rollback](xps16-ghostty-trial.md).
The list below describes the original fresh-install state.

The XPS 13 carried some things across from Omarchy 3 that a clean 4.0.4 install
simply lacks. These read as "already done" if you only check the XPS 13's notes:

- **No terminal but `foot`.** Ghostty and kitty are both absent — not just
  un-defaulted, *not installed*. See
  [terminal-font-size.md](terminal-font-size.md).
- **No `syncthing`.**
- **No `shell.toml`** (so the global text size is the 12px default implicitly).
- **`pacman` databases are unsynced**, so `pacman -Si <pkg>` reports "package
  not found" for packages that exist. Use `-Sy` on the first install or you
  will misdiagnose this as a missing package.

### What it *does* give you, already configured

Don't redo these; they were correct on arrival:

- `mimeapps.list` — Chrome as default browser, `mailto` → HEY.
- Monitor scale **1.6**, matching the XPS 13's explicit value. Stock `auto`
  resolved correctly here; verify rather than assume
  (`hyprctl monitors | grep scale`).
- `google-chrome` **and `intel-media-driver`** — so the "Known open gap" at the
  bottom of [post-update-checklist.md](post-update-checklist.md) does not exist
  on this machine. `chrome-flags.conf` still needed the Vulkan flags added.
- mise tools (claude, codex, gh, node).

### One correction to chrome-flags.conf

[chrome-vulkan-white-video.md](chrome-vulkan-white-video.md) gives the Vulkan
line as a whole `--enable-features=` flag. On a fresh Quattro install
`chrome-flags.conf` **already has** an `--enable-features=` line
(`TouchpadOverscrollHistoryNavigation`), and pasting a second one risks
last-wins clobbering an Omarchy default. Merge into the single existing flag
instead:

```
--enable-features=TouchpadOverscrollHistoryNavigation,Vulkan,DefaultANGLEVulkan,VulkanFromANGLE,VaapiVideoDecoder,VaapiIgnoreDriverChecks
```

## A stale verification command in this repo

[quattro-lua-migration.md](quattro-lua-migration.md) offers
`hyprctl binds | grep -c movegroupwindow` as the check for the group
tab-reorder binds. On 4.0.4 that returns **0 even when both binds are live** —
the Lua dispatcher is no longer named `movegroupwindow`, so the grep tests
nothing. Use the by-intent check instead, which is what that doc preaches
anyway:

```sh
omarchy menu keybindings --print | grep -i "in group"
```
