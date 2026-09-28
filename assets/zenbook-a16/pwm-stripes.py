#!/usr/bin/env python3
"""Estimate an OLED's PWM dark share from rolling-shutter photos.

Shoot a white screen with a fast shutter (1/4000 s or faster; 1/12000 s used here). The PWM
shows as stripes; this finds their direction with a 2-D FFT, folds the image onto one stripe
period and reports the share of the period below half-way between the lit and dark levels.

  pip install pillow numpy
  Y0=0.30 Y1=0.78 X0=0.14 X1=0.62 ./pwm-stripes.py photo1.jpg photo2.jpg ...

Y0/Y1/X0/X1 are the crop (fractions of height/width); keep it inside the lit screen area.
"""
import os
import sys

import numpy as np
from PIL import Image

Y0, Y1 = float(os.environ.get("Y0", "0.30")), float(os.environ.get("Y1", "0.78"))
X0, X1 = float(os.environ.get("X0", "0.14")), float(os.environ.get("X1", "0.62"))

for f in sys.argv[1:]:
    im = np.asarray(Image.open(f).convert("L"), dtype=float)
    h, w = im.shape
    raw = im[int(h * Y0):int(h * Y1), int(w * X0):int(w * X1)]
    c = raw - raw.mean()
    win = np.outer(np.hanning(c.shape[0]), np.hanning(c.shape[1]))
    F = np.abs(np.fft.fftshift(np.fft.fft2(c * win)))
    cy, cx = np.array(F.shape) // 2
    F[cy - 3:cy + 4, cx - 3:cx + 4] = 0
    iy, ix = np.unravel_index(np.argmax(F), F.shape)
    fy, fx = (iy - cy) / c.shape[0], (ix - cx) / c.shape[1]
    period = 1 / np.hypot(fx, fy)
    ang = np.arctan2(fy, fx)
    yy, xx = np.mgrid[0:c.shape[0], 0:c.shape[1]]
    phase = np.mod(xx * np.cos(ang) + yy * np.sin(ang), period) / period
    idx = np.digitize(phase.ravel(), np.linspace(0, 1, 41)) - 1
    prof = np.array([np.median(raw.ravel()[idx == k]) for k in range(40)])
    lo, hi = np.percentile(prof, 5), np.percentile(prof, 95)
    dark = np.mean(prof < (lo + hi) / 2)
    print(f"{os.path.basename(f)}: stripe period {period:.1f}px, lit {hi:.0f}, dark {lo:.0f}, "
          f"dark share {dark * 100:.0f}%")
