# XPS 16: taming the packaged tuning's sharpness, with switchable variants

**Built 2026-09-17.** The packaged `dell-xps-2026` tuning
([xps16-notes.md](xps16-notes.md)) auto-matches this laptop and sounds mostly
good, but fatigues the ear — "sharp", painful on speech after a while.
Unsurprising: upstream's own comment says the curve was fitted on the **XPS 14**
(SKU `0DB9`) and extended to the XPS 16 (`0DBA`) *"on report that this profile
suits it, not measured."*

This adds a small corrective stage on top and a `xps16-tuning` switcher, so the
curve is a runtime choice rather than a decision baked in once.

**Settled on `soft`.** `clear` and `softer` are kept selectable.

Kit lives in `assets/xps16-speaker-tuning/`; installed copies go to
`~/.local/share/omarchy-xps16-tuning/` and `~/.local/bin/xps16-tuning`.

## Do not port the XPS 13 curve

[xps13-sidecar-amps.md](xps13-sidecar-amps.md) is explicit: the
`dell-xps-13-2026-deharsh` profile *"boosted 180 Hz and gutted the mids to fake
bass that didn't exist — on working amps it will sound muddy. Leave it off."*
The XPS 16's amps work. What carried across was the **diagnosis** in
`assets/xps13-speaker-tuning/variants/soft.conf` — which bands cause which
complaint — not a single filter coefficient.

## Shadowing, not overwriting

`omarchy-audio-tuning`'s `tuning_match()` iterates
`$OMARCHY_PATH/default/audio/tunings/*/` in glob order and returns the **first**
directory whose `match_*` predicate passes. So `dell-xps-16-custom` is selected
ahead of `dell-xps-2026`, and the packaged files are never modified.

Two things follow, both deliberate:

- `stock` is a **byte-identical copy** of upstream's chain (`cmp`-verified at
  install), so A/B against upstream is honest rather than a reconstruction.
- `match_sku` is narrowed to **`0DBA` only**. The packaged profile also claims
  `0DB9` (XPS 14), where upstream actually measured. Shadowing tuning for
  hardware we have never touched would be wrong.

`restore.sh` needs root only because `/usr/share/omarchy` is root-owned; it
chowns the directory to the invoking user afterwards, so variant switching
needs no sudo. Same arrangement as the XPS 13 kit.

## Additive corrective stage, generated not hand-edited

`build-variants.py` reads the packaged chain and appends corrective biquads
after `s12`, rewiring `s12 -> c0 -> ... -> cN -> limiter` on both channels.
Reasons for generating rather than hand-editing:

- The upstream chain stays verbatim inside every variant, so a diff against a
  future Omarchy release shows exactly what we added.
- Re-fitting 13 biquads by ear would produce a curve nobody could reason about.
  A handful of named bands can be argued about and reverted one at a time.
- **Every corrective band is a cut**, so no variant can clip. Output drops
  slightly, which also means upstream's lookahead limiter (`th=0.891`) engages
  less often — marginally better dynamics, not just a tonal change.

`restore.sh` warns if the packaged chain no longer matches `variants/stock.conf`
— that is the signal to re-run the generator, and it would otherwise fail
silently.

## What the variants actually do

Computed from the biquad transfer functions at 48 kHz (`soft` minus `stock`):

| Hz | soft | softer | clear |
|---|---|---|---|
| 200 | −0.04 | −0.06 | ~0 |
| 1000 | −1.58 | −2.61 | −1.61 |
| 1330 | −3.84 | −6.4 | **−6.14** |
| 2000 | −3.08 | −5.01 | −1.20 |
| 3000 | −3.85 | −6.17 | −1.16 |
| 5500 | −4.89 | −7.76 | −3.55 |
| 12000 | −2.31 | −3.95 | −0.42 |

Pink-weighted mean: `soft` −1.52 dB, `softer` −2.49 dB, `clear` −0.88 dB.
**Bass is untouched in all of them** (−0.04 dB at 200 Hz) — everything comes out
of the upper mids and treble.

## The mistake, kept on the record

`soft` and `softer` were designed on a rationale that turned out to be **wrong**,
and the wrong version is left in `build-variants.py` rather than quietly
rewritten.

The claim was that upstream's **+6.92 dB at 1355.7 Hz (Q 2.884)** was an
absolute boost and the cause of the sharpness. Computing stock's net response
disproved it:

```
stock at 1355 Hz:  -3.37 dB     (the wide -10.09 dB at Q 0.5 swallows the boost)
stock 300-1200 Hz: -8.29 dB mean
stock 2k-8k:       -7.73 dB mean   -> only +0.55 dB apart; stock is NOT bright
```

There was no bright tilt to correct, and that +6.92 dB is filling a dip rather
than creating a peak.

**What is real** is a narrow *local* prominence:

```
stock local peak:                       -3.21 dB @ 1322 Hz
neighbours (900-1050 & 1900-2200 Hz):   -9.17 dB mean
                                 -> peak stands +5.96 dB above them
```

A ~6 dB narrow peak at 1.3 kHz is a textbook nasal/whiny signature on speech.
So the band was right and the reasoning was wrong — it is a peak against its own
neighbours, not against flat.

Which means **most of what `soft` does is not the fix it claims**: its Q 2.0
band only shaves that peak, and the rest of its effect is a broadband 3–5 dB
drop across 1.4k–9k. That reduces fatigue by lowering energy where hearing is
most sensitive — a real mechanism, but a blunt one, and the detail loss is the
price of the bluntness rather than of the correction.

`clear` was then built to aim properly: `-6.0 dB @ 1330 Hz, Q 3.0` flattens the
peak into line with its neighbours (residual peak −8.20 dB), keeps the 5.5 kHz
sibilance cut (upstream only has a −1.34 dB shelf at 6 kHz, so that band is
nearly untouched), and drops the wide 3 kHz band and 9 kHz shelf that were doing
the veiling.

**`soft` was still preferred by ear**, and that is the call that counts. `clear`
is the smaller overall change but intervenes harder in one narrow notch, which
is a reasonable thing to dislike. Both stay selectable.

### Everything above is modelled, not measured

The transfer functions are exact about **what the filter does** and say nothing
about what the drivers and room produce. A 6 dB peak in the chain could be
sitting on a driver dip and be inaudible. The math only narrowed down which
band to move; ears decided. If a measurement rig ever appears, replace this
whole approach rather than nudging the numbers.

## Install

```sh
sudo bash ~/.local/share/omarchy-xps16-tuning/restore.sh
omarchy audio tuning on --force
xps16-tuning soft
```

Switching afterwards needs no root:

```sh
xps16-tuning            # list variants, mark the active one, print live status
xps16-tuning soft       # settled default
xps16-tuning clear      # surgical 1.33k notch + sibilance, keeps detail
xps16-tuning softer     # deeper; expected failure direction is dull/boxy
xps16-tuning stock      # packaged curve, byte-identical
xps16-tuning off        # no EQ at all, raw Cirrus voicing
```

Only the internal speaker sink is affected — headphones and the jack are
untouched, as is the Cirrus amplifier firmware and its protection.

## Bug fixed here, still open on the XPS 13

`omarchy-audio-tuning` reads `$OMARCHY_PATH` under `set -u` and dies with:

```
/usr/bin/omarchy-audio-tuning: line 10: OMARCHY_PATH: unbound variable
```

Omarchy's shell profile exports it, so this is invisible interactively and
breaks in every non-login shell — over ssh, from cron, from a keybind. Hit
while running `omarchy audio tuning status` on the XPS 13 over ssh.

`xps16-tuning` defaults it (`export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"`).
**`~/.local/bin/xps13-tuning` on the XPS 13 still needs the same one-line
backport.**
