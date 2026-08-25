# XPS 13 (DX13260): second speaker amp was dead — fixed upstream (PR #7032)

**Status 2026-08-26: RESOLVED. The whole EQ saga in
[xps13-speaker-pops-and-eq.md](xps13-speaker-pops-and-eq.md) was tuning around
broken hardware. Do not re-apply the `dell-xps-13-2026-deharsh` profile.**

## What was wrong

The DX13260 has two CS35L56 smart amps as *sidecars* of the CS42L43 codec
(audio via the codec, control over SPI). On kernel 7.1 the `sof_sdw` machine
driver didn't know this model needs the `SOC_SDW_SIDECAR_AMPS` quirk, so the
amps bound but never loaded their DSP firmware:

```
cs35l56 spi-cs35l56-left: Cirrus Logic CS35L56 Rev B2 OTP1 fw:4.2.1 (patched=0)
```

and nothing else — no `.wmfw`, no `AMPL/AMPR Speaker Switch` mixer controls,
no bass. "Sounds like only tweeters" (as @stevenharms put it) is exactly right.
The kernel fix is Linux `efd80de2de9d` (7.2+).

## The fix

Omarchy PR [#7032](https://github.com/basecamp/omarchy/pull/7032) (spencerbull,
merged 2026-08-25 — *after* the v4.0.1 tag, so it ships in the next release)
adds the `dell-xps13-sidecar-amps` package: a modprobe override
(`/usr/lib/modprobe.d/dell-xps13-sidecar-amps.conf` → `options snd_soc_sof_sdw
quirk=65536`) plus a boot-image rebuild, gated on product `DX13260` + SKU
`0E53`. It's already in the `omarchy` pacman repo, so on 4.0.1:

```sh
omarchy audio tuning off          # retire the old EQ first
sudo pacman -S --needed dell-xps13-sidecar-amps
sudo dell-xps13-sidecar-amps-apply
reboot
```

(`omarchy-pkg-add` needs a TTY for sudo; plain pacman is fine.) Later
`omarchy update` runs migration `1787666837` which does the same thing —
harmless if already installed.

## Verify after reboot

```sh
cat /sys/module/snd_soc_sof_sdw/parameters/quirk      # 65536
journalctl -b -k | grep -E 'cs35l56.*(wmfw|Calibration)'
amixer -c0 controls | grep -E 'AMP[LR] Speaker Switch'
```

Expected: both `spi-cs35l56-{left,right}` load
`cs35l56-b2-dsp1-misc-10280e53-spkid1.wmfw` + `ampl.bin`/`ampr.bin` (Cirrus fw
v4.5.9, "Roma 0E53" tuning), then `Calibration applied`; `AMPL`/`AMPR Speaker
Switch` present and on.

## Consequences for the old tuning

- What you hear now is Dell's own Cirrus voicing with **no** user-space EQ.
  Result on first listen: clearly better, real bass.
- The `dell-xps-13-2026-deharsh` soft profile boosted 180 Hz and gutted the
  mids to fake bass that didn't exist — on working amps it will sound muddy.
  Leave it off. The restore kit (`assets/xps13-speaker-tuning/`,
  `~/.local/share/omarchy-xps13-tuning/`) is historical.
- The WirePlumber no-suspend rule
  (`~/.config/wireplumber/wireplumber.conf.d/90-speaker-no-suspend.conf`) is
  unrelated to the EQ and can stay; re-check whether the start/stop pops even
  exist with the firmware loaded before keeping it.
- If a Waves-style polish layer ever feels needed (as the XPS 14/16
  `dell-xps-2026` profile provides for those SKUs), build a *new* small curve
  against this baseline — don't resurrect the old one.
- The package is temporary by design: remove it once every bootable kernel is
  7.2+; upstream migrations should handle that.
