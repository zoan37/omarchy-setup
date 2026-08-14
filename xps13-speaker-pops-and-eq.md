# XPS 13 (DX13260): speaker pops on play/stop + piercing female speech

Three stacked fixes on top of the `dell-xps-13-2026-deharsh` speaker tuning.

**Provenance warning:** that tuning profile is NOT shipped by Omarchy — it's
our own creation, written into the package-owned path
`/usr/share/omarchy/default/audio/tunings/dell-xps-13-2026-deharsh/` so that
`omarchy audio tuning` picks it up. An Omarchy update deletes the whole
directory (symptom: `omarchy audio tuning status` → "nothing ships for this
laptop"). Restore kit: `~/.local/share/omarchy-xps13-tuning/` (also mirrored in
this repo at `assets/xps13-speaker-tuning/`) — run
`sudo bash ~/.local/share/omarchy-xps13-tuning/restore.sh`, then
`omarchy audio tuning on --force`. Variant-swap helper: `~/.local/bin/xps13-tuning`.
Dependency: `lsp-plugins-lv2` (pacman) provides the LV2 limiter the chain uses.

**Hardware:** CS42L43 codec on SoundWire, driving two CS35L56 smart amps as
sidecars (audio from the codec, control over an SPI bridge —
`/sys/bus/spi/devices/spi-cs35l56-{left,right}`).

**Test clip** (opens cold on female speech, good for A/B):
https://x.com/GadSaad/status/2088245049226060087 — a MacBook plays it with no
start pop and only a *tiny* stop pop, which is the realistic target; the
waveform being cut mid-sample on stop is inherent on every platform.

## Fix 1: EQ revision — female speech still pierced on the packaged soft profile

The packaged soft profile cuts 1.6k/3.2k/5k/7k+, but leaves a coverage dip
around 2.2–2.5 kHz (between the 1.6k and 3.2k bands) and its 5 kHz cut is
narrow (Q 1.6), so ~4.3 kHz presence and ~6 kHz sibilance slip through — right
where female-voice "pierce" lives.

Local edit in `~/.config/pipewire/omarchy-speaker-tuning.conf.d/90-tuning.conf`
(both channels):

```
3.2 kHz peaking:  Q 1.0 -> 0.8,  gain -7.0 -> -7.5 dB
5.0 kHz peaking:  Q 1.6 -> 1.1,  gain -4.0 -> -5.0 dB
```

Confirmed better by ear. Apply with
`systemctl --user restart omarchy-speaker-tuning`.

If pierce ever returns on specific material, next lever is a tone sweep to find
the exact driver resonance and one narrow deep notch — not more broad cutting
(the profile is already at the edge of dull).

## Fix 2: start-of-playback pop — WirePlumber sink suspend

**Symptom:** video that opens cold on speech gets a pop / mangled first
syllable. **Cause:** the speaker sink suspends after idle; the amp path
cold-starts mid-first-syllable when playback begins. macOS hides this class of
transition with mute-then-ramp amp sequencing; Linux's coordination between
sink suspend and amp power-down is looser.

`~/.config/wireplumber/wireplumber.conf.d/90-speaker-no-suspend.conf`:

```
monitor.alsa.rules = [
  {
    matches = [
      { node.name = "alsa_output.pci-0000_00_1f.3-platform-sof_sdw.HiFi__Speaker__sink" }
    ]
    actions = {
      update-props = {
        session.suspend-timeout-seconds = 0
      }
    }
  }
]
```

Scoped to the internal speaker sink only (HDMI sinks still suspend). Confirmed:
start pop gone. Survives omarchy updates (it's not part of the tuning
fragment).

## Fix 3: stop-of-playback snap — PCM stops clocking on stream end

**Symptom:** with fix 2 in place, a snap/pop remained when *stopping* a video.
**Cause:** suspend-timeout 0 keeps the ALSA device open, but when the last
stream ends the sink drops to IDLE and the PCM stops clocking — ASoC DAPM
tears down the codec→amp path, and that mute/power-down step is the snap.

Fix: make the tuning filter-chain process continuously, so silence is always
flowing and the PCM never stops. In `90-tuning.conf`:

```
capture.props = {
  node.name   = "omarchy_speaker_tuning"
  media.class = Audio/Sink
  node.always-process = true      # added
}
playback.props = {
  node.name     = "omarchy_speaker_tuning_output"
  node.passive  = false           # was true
  ...
}
```

Verified: speaker PCM (`/proc/asound/card0/pcm2p/sub0/status`) stays RUNNING
with nothing playing. Outcome by ear: stop-snap clearly better, though still
slightly behind the Mac — the remaining edge is likely Apple's firmware-level
mute-and-ramp around every gain/mute transition, which isn't reachable from
userspace here. The residual tiny pop on stop is partly the content cut itself,
which macOS exhibits too.

**Dead end (don't re-chase):** the CS35L56s' runtime-PM state
(`/sys/bus/spi/devices/spi-cs35l56-*/power/runtime_status`, 100 ms autosuspend)
reads `suspended` even *while audio is audibly playing* — it reflects only the
SPI control bus, not the amp audio path. Forcing `power/control=on` there does
nothing for the pops.

## Costs and revert

- Fix 2+3 keep the codec path powered and the chain processing silence
  constantly: a small constant DSP load plus amp idle draw. Acceptable so far;
  revert if battery life visibly regresses.
- Revert fix 3: `node.passive = true`, remove `node.always-process`, restart
  the tuning service. Revert fix 2: delete the wireplumber file, restart
  wireplumber. Revert fix 1: `omarchy audio tuning on --force` reinstalls the
  packaged fragment.

## Overwrite caveat

Two layers of clobber, now both handled:

- An **omarchy update deletes the profile** from `/usr/share/omarchy/...` (see
  provenance warning at top) → restore with the restore kit.
- `omarchy audio tuning on --force` reinstalls `90-tuning.conf` from that
  profile. As of 2026-08-14 the profile and the restore kit's `soft.conf` are
  **synced with fixes 1 and 3 baked in**, so a reinstall no longer reverts
  them. If future fragment edits are made, re-sync all three copies (installed
  fragment, `/usr/share` profile, restore-kit variant — and this repo's
  `assets/`). Backups sit next to the fragment as `90-tuning.conf.bak.*`.

Worth upstreaming eventually: the EQ revision to the `dell-xps-13-2026-deharsh`
profile (it's marked experimental), and possibly `always-process` as a tuning
option, since the pop mechanism applies to every machine running the
filter-chain in front of amps with aggressive power-down.
