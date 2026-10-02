## Display: stock Hyprland shows the A16's wide-gamut OLED oversaturated and a bit fuzzy; two monitor options fix it (plus panel caps and PWM notes)

Display findings on the same image (v0.2.2-1, kernel 7.2.0-18, Hyprland 0.56). Details are in [zoan37/omarchy-setup](https://github.com/zoan37/omarchy-setup/blob/master/zenbook-a16-omarchy-snapdragon.md#17-display-10-bit-composition-and-edid-color-management-2026-10-02), section 17, and the [OLED notes](https://github.com/zoan37/omarchy-setup/blob/master/zenbook-a16-oled-comfort.md).

### 1. The fix: `cm = "edid"` and `bitdepth = 10`

As shipped, Hyprland composes in 8-bit (`XRGB8888`) with the `srgb` color preset, i.e. it treats the panel as an sRGB screen. The panel is a wide-gamut Samsung OLED (`ATNA60HR07-0`, EDID primaries R 0.683/0.316, G 0.245/0.714, B 0.140/0.044, DCI-P3 class). So all sRGB content is stretched to the wider primaries: oversaturated colors, and slightly fuzzy text, because the anti-aliased and colored edges get stretched too.

One line in `~/.config/hypr/monitors.lua`, after the default `hl.monitor` line:

```lua
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.6, bitdepth = 10, cm = "edid" })
```

`hyprctl monitors -j` then shows `XRGB2101010` and `colorManagementPreset: edid`. In daily use this is one of the biggest improvements on this laptop: colors look right, and text is sharper, more readable and easier to focus on. Before, it looked a bit fuzzy.

Notes:
- **`cm = "edid"`** does most of the visible work: sRGB content is mapped to the panel's real primaries.
- **`bitdepth = 10`** makes composition 10-bit, but **the eDP link stays at 8 bpc** (`/sys/kernel/debug/dri/1/eDP-1/dp_debug` shows `bpp = 24`). At 2880×1800@120, 30 bpp needs 709.6 MHz × 30 = 21.3 Gbit/s, but HBR2 ×4 carries 17.3 Gbit/s, so `msm_dp_panel_get_supported_bpp()` falls back to 24. The panel supports DSC 1.2 (DPCD `0x060` = 0x01), but msm doesn't do DSC on eDP. The 60 Hz mode uses the same 709.633 MHz pixel clock (a stretched vertical front porch), so it doesn't help either. The 10-bit composition still reduces banding, especially with software (gamma) dimming.
- With the Lua config, `hyprctl keyword monitor …` fails ("keyword can't work with non-legacy parsers. Use eval."). To try it live, use `hyprctl eval 'hl.monitor({ … })'`.

For the image, this could be a DMI-matched default for the A16 (and probably any wide-gamut OLED SKU).

### 2. Panel capabilities (read-only EDID + DPCD dump, `/dev/drm_dp_aux2`)

| Item | Value |
|---|---|
| Panel | Samsung `ATNA60HR07-0`, DPCD 1.4, eDP 1.5 (`0x700` = 0x06) |
| Color | 10 bpc input, DCI-P3 + BT.2020/PQ, HDR static metadata type 1; 500 cd/m² full screen, 1100 cd/m² peak |
| Refresh | 120 Hz and 60 Hz modes at the same pixel clock. Adaptive Sync 30–120 Hz (msm `vrr_range` 30–120, but Hyprland reports `vrr: false`) |
| Link | HBR2 ×4 (rate table 1.62/2.7/5.4), DSC 1.2 capable |
| Self refresh | PSR2 with Y-coordinates (`0x071` = 0x76, i.e. link training required on PSR exit), Panel Replay (`0x0B0` = 0x07) |
| Backlight | AUX brightness, 16-bit, vblank-synced (`0x702` = 0x86); panel luminance control capable (`0x703` = 0xf4); no PWM-frequency control |

### 3. PWM flicker (for flicker-sensitive users)

- Notebookcheck measured this panel at **960 Hz with 56 % amplitude at every brightness, including 100 %**. That is 8 pulses per 120 Hz frame. The AMD Zenbook S16 with the same panel measured identically, so the PWM belongs to the panel, not the host.
- MyASUS "OLED Flicker-Free Dimming" is software dimming. G-Helper's source shows it's an ASUS Splendid gamma command. My phone-camera stripe measurements show it barely changes the waveform on this panel.
- The DSDT panel XML for ATNA60HR07-0 (published in aarch64-laptops/build) has no init sequence or custom AUX writes. So Windows doesn't configure the panel in any way that Linux misses, and no host-side PWM control is known.
- A MyASUS-style equivalent on Omarchy (panel fixed at 100 %, brightness keys drive hyprsunset gamma) is [`a16-dim`](https://github.com/zoan37/omarchy-setup/blob/master/assets/zenbook-a16/a16-dim). What helps most in practice is a bright room. 10-bit composition makes the gamma dimming band less.

### 4. Self refresh, for whoever picks up PSR on msm

`msm.psr_enabled=1` flickers black on this panel: section 16.2 of the notes covers the missing link training on PSR exit and vblank being turned off on entry. I also wrote a "link standby" variant (`DP_PSR_MAIN_LINK_ACTIVE` when the sink requires training on exit, like i915). It's in [assets/zenbook-a16/kmod/](https://github.com/zoan37/omarchy-setup/tree/master/assets/zenbook-a16/kmod). It's **untested**: the test boot that carried it also had a gpucc-glymur backport, and that boot went black after login, with a `clk_branch_toggle` warning right after the patched gpucc module loaded.
