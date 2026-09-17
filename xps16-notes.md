# Dell XPS 16 (DA16260): what carried over from the XPS 13, and what didn't

**Set up 2026-09-17** on a fresh Omarchy `4.0.4-1` install, kernel
`7.2.5-3-omarchy`. The headline: **every hardware fix in this repo is XPS
13-specific and none of them apply here**, while every software tweak ported
across unchanged. Two of the three hardware problems are fixed upstream on this
machine, and the third was never this machine's problem.

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

## The hardware fixes: all three skip this machine

### Panel Replay / PSR — fixed in-kernel, do not add the drop-in

Do **not** create a `dell-xps16-*-display.conf` analogue of
[xps13-panel-replay-scroll-judder.md](xps13-panel-replay-scroll-judder.md).
That doc's own upstream trail names the fix: the `intel_dpcd_quirks[]` entry for
**XPS 16 DA16260** is commit `cb8d155b0806`, landed in **7.2-rc1**. This machine
runs 7.2.5, so it is carrying its own quirk. The XPS 13 needed the cmdline
workaround precisely because no quirk existed for `DX13260`.

Omarchy also auto-applies its Panther Lake fix here, which the XPS 13 never
got because the hardware gate didn't match Wildcat Lake:

```sh
cat /etc/limine-entry-tool.d/intel-panther-lake-fred.conf   # -> KERNEL_CMDLINE[default]+=" fred=on"
cat /proc/cmdline | grep -o 'fred=on'
```

Scrolling was smooth out of the box; no judder to chase. If it ever regresses,
read the state before adding anything — the quirk disables Panel Replay but
leaves PSR2 selective fetch available, which is the mode that juddered on the
XPS 13:

```sh
sudo cat /sys/kernel/debug/dri/0000:00:02.0/eDP-1/i915_psr_status
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
