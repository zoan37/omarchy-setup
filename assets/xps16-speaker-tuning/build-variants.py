#!/usr/bin/env python3
"""Generate XPS 16 tuning variants from the packaged dell-xps-2026 chain.

The variants are the upstream chain plus a small corrective stage appended
after s12 and before the limiter. Additive rather than re-fitted on purpose:

  * The upstream chain stays byte-identical inside each variant, so a diff
    against a future omarchy release shows exactly what we added and nothing
    else, and `stock` is a verbatim copy rather than a reconstruction.
  * Nothing here is measured. Re-fitting 13 biquads by ear would produce a
    curve nobody could reason about; four named corrective bands can be
    argued about, adjusted, and reverted one at a time.
  * Every corrective band is a CUT, so no variant can clip. They lower output
    slightly, which is itself part of the goal.

Run:  python3 build-variants.py   (writes variants/*.conf)
"""

import pathlib
import re

UPSTREAM = pathlib.Path(
    "/usr/share/omarchy/default/audio/tunings/dell-xps-2026/filter-chain.conf"
)
OUT = pathlib.Path(__file__).resolve().parent / "variants"

# Why these four bands -- PARTLY SUPERSEDED, read the "clear" note below first.
# The 1400 Hz reasoning here was wrong: computing stock's net response showed
# the +6.92 dB is cancelled by a wide cut, and that stock is not bright at all.
# soft/softer are kept because they do reduce fatigue (by lowering energy where
# hearing is most sensitive, not by correcting a tonal error), but `clear` is
# the better-aimed fix. Left in place rather than rewritten so the mistake
# stays visible.
#
# The upstream curve was fitted on the XPS 14 (SKU 0DB9) and, by upstream's own
# comment, applied to the XPS 16 (0DBA) "on report that this profile suits it,
# not measured".
#
# The band choices reuse the diagnosis from the XPS 13 work (see
# assets/xps13-speaker-tuning/variants/soft.conf) but NOT its curve, which was
# compensating for a dead amplifier and must not be resurrected:
#
#   1400 Hz  Upstream puts +6.92 dB here at Q 2.9. This is the "whiny / nasal"
#            band the XPS 13 notes identified at 1.6 kHz. A narrow boost of
#            that size on speech is the most likely single cause of "sharp".
#            Partially offset, not erased: upstream scoops 600-900 Hz hard, so
#            removing all of 1.4 kHz leaves speech hollow.
#   3000 Hz  Presence / bite. Upstream is already net-negative here (-10.09 at
#            Q 0.5 against +3.09 at Q 1.05), so this is a nudge, wide and small.
#   5500 Hz  Sibilance -- "s" and "t" sounds, the part that actually hurts.
#            Upstream only has a -1.34 dB shelf at 6 kHz, so this band is
#            close to untouched. The XPS 13 notes landed on 5 kHz Q 1.1 for the
#            same complaint.
#   9000 Hz  Air. A gentle shelf so the top does not sound truncated after the
#            5.5 kHz cut.
VARIANTS = {
    # Added 2026-09-17 after actually computing stock's net response, which
    # disproved the rationale the soft/softer bands were written on. The
    # +6.92 dB at 1355 Hz is NOT an absolute boost -- upstream's wide -10.09 dB
    # at Q 0.5 swallows it, leaving a net -3.37 dB there. Stock is not bright
    # either: 300-1200 Hz averages -8.29 dB against -7.73 dB over 2k-8k.
    #
    # What IS real is a narrow local peak: -3.21 dB at 1322 Hz standing
    # +5.96 dB above its own neighbours (900-1050 and 1900-2200 Hz average
    # -9.17 dB). That prominence is the "whiny/nasal" signature, and soft's
    # wide Q 2.0 band only shaves it -- most of soft's effect is a broadband
    # 3-5 dB drop across 1.4k-9k, which buys comfort by lowering energy where
    # hearing is most sensitive and pays for it in detail.
    #
    # So: flatten the peak surgically instead. Q 3.0 at 1330 Hz brings 1322 Hz
    # into line with its neighbours (residual peak -8.20 dB), and the 5.5 kHz
    # sibilance cut stays because upstream barely touches that band (-1.34 dB
    # shelf at 6 kHz). The wide 3 kHz band and the 9 kHz shelf are dropped --
    # they were the veiling. Costs -0.88 dB pink-weighted vs soft's -1.52 dB.
    "clear": [
        ("bq_peaking", 1330.0, 3.0, -6.0),
        ("bq_peaking", 5500.0, 1.2, -3.5),
    ],
    "soft": [
        ("bq_peaking", 1400.0, 2.0, -3.0),
        ("bq_peaking", 3000.0, 0.8, -2.5),
        ("bq_peaking", 5500.0, 1.1, -3.5),
        ("bq_highshelf", 9000.0, 0.7, -2.0),
    ],
    # Same bands, deeper. Expected failure direction is dull/boxy -- that is
    # the trade, same as the XPS 13 "soft" variant made.
    "softer": [
        ("bq_peaking", 1400.0, 2.0, -5.0),
        ("bq_peaking", 3000.0, 0.8, -4.0),
        ("bq_peaking", 5500.0, 1.1, -5.5),
        ("bq_highshelf", 9000.0, 0.7, -3.5),
    ],
}

HEADER = """# Dell XPS 16 DA16260 (SKU 0DBA) -- "{name}" variant. EXPERIMENTAL, UNMEASURED.
#
# The packaged dell-xps-2026 chain, verbatim, plus {n} corrective cuts appended
# before the limiter. Built by build-variants.py -- edit the band table there,
# not this file, or the next rebuild discards your change.
#
# Corrective stage ({name}):
{bands}
#
# Everything below the corrective nodes is upstream's, unmodified. Upstream
# fitted it on the XPS 14 and carried it to the XPS 16 unmeasured; these cuts
# are a by-ear correction for "sharp / hurts my ear" on the 16, not a fit.
# Tuned by ear on 2026-09-17. No measurement rig was used. If you ever measure
# this properly, replace the whole approach rather than nudging these numbers.
"""


def build(name, bands):
    src = UPSTREAM.read_text()

    for ch in ("l", "r"):
        nodes = "\n".join(
            f'          {{ type = builtin name = c{i}_{ch}      label = {lab:<12} '
            f'control = {{ "Freq" = {f} "Q" = {q} "Gain" = {g} }} }}'
            for i, (lab, f, q, g) in enumerate(bands)
        )
        # Insert the corrective nodes right after upstream's last EQ node.
        anchor = re.search(
            rf'^.*name = s12_{ch}\b.*$', src, re.M
        )
        if not anchor:
            raise SystemExit(f"could not find s12_{ch} in upstream chain")
        src = src[: anchor.end()] + "\n\n" + nodes + src[anchor.end() :]

        # Rewire: s12 -> c0 -> ... -> cN -> limiter
        old_link = f'{{ output = "s12_{ch}:Out" input = "limiter:in_{ch}" }}'
        if old_link not in src:
            raise SystemExit(f"could not find the s12_{ch}->limiter link")
        chain = [f's12_{ch}'] + [f'c{i}_{ch}' for i in range(len(bands))]
        new_links = "\n          ".join(
            f'{{ output = "{a}:Out" input = "{b}:In" }}'
            for a, b in zip(chain, chain[1:])
        )
        new_links += (
            f'\n          {{ output = "c{len(bands)-1}_{ch}:Out" '
            f'input = "limiter:in_{ch}" }}'
        )
        src = src.replace(old_link, new_links)

    desc = "\n".join(
        f"#   {f:>6.0f} Hz  {g:+.1f} dB  Q {q}  ({lab.replace('bq_','')})"
        for lab, f, q, g in bands
    )
    header = HEADER.format(name=name, n=len(bands), bands=desc)
    # Replace upstream's own header comment block with ours, keeping its body.
    body = src[src.index("context.modules"):]
    return header + "\n" + body


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    (OUT / "stock.conf").write_text(UPSTREAM.read_text())
    print(f"wrote {OUT/'stock.conf'} (verbatim upstream)")
    for name, bands in VARIANTS.items():
        p = OUT / f"{name}.conf"
        p.write_text(build(name, bands))
        print(f"wrote {p} ({len(bands)} corrective bands)")
