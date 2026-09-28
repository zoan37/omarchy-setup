#!/usr/bin/env python3
"""Generate the Zenbook A16 speaker-tuning variants from ASUS's own Dolby tuning.

Source: the Windows Dolby DAX3 driver package (dax3_ext_qc.inf), file
QCASD_DEV_0FCD_SUBSYS_16D41043_AUCD_SUBSYS_16D41043.xml -- 16D41043 is this
machine's audio subsystem ID (Windows devlist: QCASD\\VEN_QCOM&DEV_0FCD&SUBSYS_16D41043).
Tuning version 115, dated 12/04/2025. Every Dolby profile except "off" carries
the same speaker correction, which has two parts:

  audio-optimizer-bands  20-band correction curve, in 1/16 dB, at fixed band
                         centres (band_20_freq, fs_48000)
  speaker-peq-filters    narrow parametric filters (type 1 = peaking), gain in dB

The "voice" profiles use a different optimizer curve: less bass lift and a
treble roll-off. That's the `soft` variant here.

The optimizer is reproduced as one peaking biquad per band centre, with the
gains solved iteratively so the chain's response hits the target at each
centre, and the Q set so each band spans neighbour to neighbour (the top band
is a high shelf). Output is a
filter-chain fragment per variant; `flat` is the untouched boost + crossover.

    python3 build-variants.py   # writes variants/*.conf next to this script
"""
import cmath
import math
import os

FS = 48000.0
BANDS = [47, 141, 234, 328, 469, 656, 844, 1031, 1313, 1688,
         2250, 3000, 3750, 4688, 5813, 7125, 9000, 11250, 13875, 19688]

# 1/16 dB, as in the XML
OPTIMIZER = {
    "asus": [-18, 80, 68, -41, -50, -20, -74, -112, -113, -30,
             -72, -92, -96, -62, -58, -58, -6, 11, 8, -2],
    "soft": [-58, 43, 42, -40, -50, -16, -78, -112, -115, -44,
             -92, -86, -88, -54, -54, -56, -6, -53, -106, -158],
}

# (f0, gain dB, Q), enabled filters only; identical for both speakers and all profiles.
# (A fifth, -4.5 dB @ 2600 Hz Q 5, is present but disabled.)
PEQ = [(380, -4.0, 5.0), (495, -9.3, 5.0), (1450, 4.0, 4.0), (7900, -5.0, 6.0)]


def biquad(kind, f0, gain, q):
    """RBJ cookbook biquads, the formulas behind PipeWire's bq_peaking / bq_highshelf."""
    a = 10 ** (gain / 40)
    w0 = 2 * math.pi * f0 / FS
    cw, alpha = math.cos(w0), math.sin(w0) / (2 * q)
    if kind == "bq_peaking":
        return [1 + alpha * a, -2 * cw, 1 - alpha * a], [1 + alpha / a, -2 * cw, 1 - alpha / a]
    k = 2 * math.sqrt(a) * alpha
    return ([a * ((a + 1) + (a - 1) * cw + k), -2 * a * ((a - 1) + (a + 1) * cw), a * ((a + 1) + (a - 1) * cw - k)],
            [(a + 1) - (a - 1) * cw + k, 2 * ((a - 1) - (a + 1) * cw), (a + 1) - (a - 1) * cw - k])


def resp_db(filters, f):
    z = cmath.exp(-1j * 2 * math.pi * f / FS)
    total = 0.0
    for kind, f0, g, q in filters:
        b, a = biquad(kind, f0, g, q)
        h = (b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z)
        total += 20 * math.log10(abs(h))
    return total


def band_q(i):
    """Bandwidth spans neighbour to neighbour, so adjacent bands overlap without ripple."""
    lo = BANDS[i - 1] if i > 0 else BANDS[0] ** 2 / BANDS[1]
    hi = BANDS[i + 1] if i + 1 < len(BANDS) else BANDS[-1] ** 2 / BANDS[-2]
    n = hi / lo
    return max(0.5, min(3.0, math.sqrt(n) / (n - 1)))


def band_filter(i):
    # A peaking band this close to Nyquist is squeezed narrow by the bilinear
    # transform, so the top band is a shelf starting midway from its neighbour.
    if i == len(BANDS) - 1:
        return "bq_highshelf", round(math.sqrt(BANDS[-2] * BANDS[-1])), 0.707
    return "bq_peaking", BANDS[i], band_q(i)


def fit(target):
    shape = [band_filter(i) for i in range(len(BANDS))]
    gains = list(target)
    for _ in range(400):
        filters = [(k, f, g, q) for (k, f, q), g in zip(shape, gains)]
        err = [t - resp_db(filters, f) for f, t in zip(BANDS, target)]
        if max(abs(e) for e in err) < 0.02:
            break
        gains = [g + 0.5 * e for g, e in zip(gains, err)]
    return filters, err


def render(name, eq):
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "90-tuning.conf")) as fh:
        base = fh.read()
    if not eq:
        return base.replace("# Asus Zenbook A16 (UX3607OA) speaker boost.",
                            "# Asus Zenbook A16 (UX3607OA) speaker boost. Variant: flat (no EQ).", 1)

    nodes, links_l, links_r = [], [], []
    for ch in ("l", "r"):
        prev = f"sub_{ch}"
        for i, (kind, f0, g, q) in enumerate(eq):
            n = f"eq{i:02d}_{ch}"
            nodes.append(f'          {{ type = builtin name = {n} label = {kind} '
                         f'control = {{ "Freq" = {f0:.1f} "Q" = {q:.3f} "Gain" = {g:.2f} }} }}')
            (links_l if ch == "l" else links_r).append(
                f'          {{ output = "{prev}:Out" input = "{n}:In" }}')
            prev = n
        (links_l if ch == "l" else links_r).append(
            f'          {{ output = "{prev}:Out" input = "limiter:in_{ch}" }}')

    out = base.replace("# Asus Zenbook A16 (UX3607OA) speaker boost.",
                       f"# Asus Zenbook A16 (UX3607OA) speaker boost. Variant: {name}.\n"
                       f"# GENERATED by build-variants.py from ASUS's Windows Dolby tuning -- edit that, not this.", 1)
    out = out.replace(
        '          { type = builtin name = sub_r label = bq_highpass control = { "Freq" = 80.0 "Q" = 0.707 } }\n',
        '          { type = builtin name = sub_r label = bq_highpass control = { "Freq" = 80.0 "Q" = 0.707 } }\n'
        f'          # ASUS speaker correction ({name}): optimizer bands, then speaker PEQ\n'
        + "\n".join(nodes) + "\n", 1)
    out = out.replace(
        '          { output = "sub_l:Out"       input = "limiter:in_l" }\n'
        '          { output = "sub_r:Out"       input = "limiter:in_r" }\n',
        "\n".join(links_l + links_r) + "\n", 1)
    assert out.count("eq00_l") >= 2 and 'input = "limiter:in_l"' in out, "template changed"
    return out


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    os.makedirs(os.path.join(here, "variants"), exist_ok=True)
    with open(os.path.join(here, "variants", "flat.conf"), "w") as fh:
        fh.write(render("flat", None))

    probe = [100, 141, 200, 234, 300, 380, 495, 700, 1000, 1450, 2000, 3000, 4000, 6000, 7900, 10000, 14000, 18000]
    print("net EQ, dB (before the +6 dB limiter drive):")
    print("Hz     " + " ".join(f"{f:>6}" for f in probe))
    for name, raw in OPTIMIZER.items():
        bands, err = fit([v / 16 for v in raw])
        eq = bands + [("bq_peaking", f, g, q) for f, g, q in PEQ]
        print(f"{name:6} " + " ".join(f"{resp_db(eq, f):6.1f}" for f in probe)
              + f"   (fit err max {max(abs(e) for e in err):.2f} dB)")
        with open(os.path.join(here, "variants", f"{name}.conf"), "w") as fh:
            fh.write(render(name, eq))


if __name__ == "__main__":
    main()
