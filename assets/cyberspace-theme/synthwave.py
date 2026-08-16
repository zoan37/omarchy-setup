#!/usr/bin/env python3
"""Generate a synthwave/cyberpunk wallpaper as SVG (rendered by rsvg-convert)."""
import random

W, H = 3200, 2000
HORIZON = int(H * 0.62)
random.seed(37)

parts = []
parts.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')

parts.append('''
<defs>
  <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#05060f"/>
    <stop offset="0.45" stop-color="#12102e"/>
    <stop offset="0.8" stop-color="#2a1052"/>
    <stop offset="1" stop-color="#4a1668"/>
  </linearGradient>
  <linearGradient id="sun" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ffd166"/>
    <stop offset="0.4" stop-color="#ff9f43"/>
    <stop offset="0.7" stop-color="#ff4fd8"/>
    <stop offset="1" stop-color="#c026b8"/>
  </linearGradient>
  <linearGradient id="floor" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#1b0b38"/>
    <stop offset="0.25" stop-color="#0d0a24"/>
    <stop offset="1" stop-color="#05060f"/>
  </linearGradient>
  <radialGradient id="sunglow" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0" stop-color="#ff4fd8" stop-opacity="0.55"/>
    <stop offset="0.6" stop-color="#ff4fd8" stop-opacity="0.18"/>
    <stop offset="1" stop-color="#ff4fd8" stop-opacity="0"/>
  </radialGradient>
  <filter id="blur6"><feGaussianBlur stdDeviation="6"/></filter>
  <filter id="blur14"><feGaussianBlur stdDeviation="14"/></filter>
  <clipPath id="sunclip">
''')
# Sun disk with horizontal slats cut out (classic synthwave sun)
sun_cx, sun_cy, sun_r = W // 2, HORIZON - 30, 420
slats = []
y = sun_cy - 40
gap, band = 26, 58
while y < sun_cy + sun_r:
    slats.append((y, y + gap))
    y += gap + band
    gap = min(gap + 8, 60)
clip_rects = []
prev = sun_cy - sun_r
for (a, b) in slats + [(sun_cy + sun_r, sun_cy + sun_r)]:
    if a > prev:
        clip_rects.append(f'<rect x="{sun_cx - sun_r}" y="{prev}" width="{2*sun_r}" height="{a - prev}"/>')
    prev = b
parts.append("\n".join(clip_rects))
parts.append('</clipPath></defs>')

# Sky
parts.append(f'<rect width="{W}" height="{HORIZON}" fill="url(#sky)"/>')

# Stars
stars = []
for _ in range(420):
    x = random.uniform(0, W)
    yy = random.uniform(0, HORIZON * 0.92)
    r = random.uniform(0.6, 2.2)
    o = random.uniform(0.25, 0.95) * (1 - yy / HORIZON * 0.5)
    c = random.choice(['#ffffff', '#cfe9ff', '#9ff2ff', '#ffd9f5'])
    stars.append(f'<circle cx="{x:.0f}" cy="{yy:.0f}" r="{r:.1f}" fill="{c}" opacity="{o:.2f}"/>')
# a few bigger glinting stars
for _ in range(14):
    x = random.uniform(0, W)
    yy = random.uniform(0, HORIZON * 0.7)
    r = random.uniform(2.5, 4)
    c = random.choice(['#9ff2ff', '#ffffff'])
    stars.append(f'<circle cx="{x:.0f}" cy="{yy:.0f}" r="{r:.1f}" fill="{c}" opacity="0.9" filter="url(#blur6)"/>')
    stars.append(f'<circle cx="{x:.0f}" cy="{yy:.0f}" r="{r*0.45:.1f}" fill="#ffffff" opacity="0.95"/>')
parts.append("\n".join(stars))

# Sun glow + sun
parts.append(f'<circle cx="{sun_cx}" cy="{sun_cy}" r="{sun_r*2.1:.0f}" fill="url(#sunglow)"/>')
parts.append(f'<g clip-path="url(#sunclip)"><circle cx="{sun_cx}" cy="{sun_cy}" r="{sun_r}" fill="url(#sun)"/></g>')

# City skyline silhouette (drawn over sun, under floor)
bx = -40
sky_parts = []
win_parts = []
while bx < W + 40:
    bw = random.randint(70, 190)
    bh = random.randint(60, 340)
    # taller towers away from center so the sun stays visible
    dist = abs((bx + bw / 2) - W / 2) / (W / 2)
    bh = int(bh * (0.45 + 0.9 * dist))
    top = HORIZON - bh
    sky_parts.append(f'<rect x="{bx}" y="{top}" width="{bw}" height="{bh}" fill="#0a0618"/>')
    # neon roof edge
    edge = random.choice(['#00e5ff', '#ff4fd8'])
    sky_parts.append(f'<rect x="{bx}" y="{top}" width="{bw}" height="3" fill="{edge}" opacity="0.85"/>')
    # occasional antenna
    if random.random() < 0.3 and bh > 150:
        ax = bx + random.randint(10, max(11, bw - 10))
        ah = random.randint(30, 80)
        sky_parts.append(f'<rect x="{ax}" y="{top-ah}" width="3" height="{ah}" fill="#0a0618"/>')
        sky_parts.append(f'<circle cx="{ax+1}" cy="{top-ah}" r="4" fill="#ff5577" opacity="0.9"/>')
    # windows
    for _ in range(int(bw * bh / 2600)):
        wx = bx + random.randint(6, max(7, bw - 12))
        wy = top + random.randint(8, max(9, bh - 14))
        wc = random.choice(['#00e5ff', '#ffd166', '#ff4fd8', '#9ff2ff'])
        if random.random() < 0.55:
            win_parts.append(f'<rect x="{wx}" y="{wy}" width="5" height="8" fill="{wc}" opacity="{random.uniform(0.5,0.95):.2f}"/>')
    bx += bw + random.randint(4, 26)
parts.append("\n".join(sky_parts))
parts.append("\n".join(win_parts))

# Floor
parts.append(f'<rect y="{HORIZON}" width="{W}" height="{H-HORIZON}" fill="url(#floor)"/>')

# Grid: glow pass then sharp pass
def grid_lines():
    lines = []
    vp_x = W / 2
    # radial lines: converge at vanishing point on horizon
    n_rad = 33
    for i in range(n_rad + 1):
        t = i / n_rad
        x_bottom = -W * 1.6 + t * (W * 4.2)
        lines.append(f'<line x1="{vp_x}" y1="{HORIZON}" x2="{x_bottom:.0f}" y2="{H}"/>')
    # horizontal lines with perspective spacing
    n_h = 22
    for i in range(1, n_h + 1):
        t = (i / n_h) ** 2.4
        yy = HORIZON + t * (H - HORIZON)
        lines.append(f'<line x1="0" y1="{yy:.0f}" x2="{W}" y2="{yy:.0f}"/>')
    return "\n".join(lines)

parts.append(f'<g stroke="#00e5ff" stroke-width="7" opacity="0.5" filter="url(#blur14)">{grid_lines()}</g>')
parts.append(f'<g stroke="#5ff0ff" stroke-width="2.2" opacity="0.85">{grid_lines()}</g>')

# Horizon glow line
parts.append(f'<rect x="0" y="{HORIZON-4}" width="{W}" height="8" fill="#ff4fd8" opacity="0.6" filter="url(#blur14)"/>')
parts.append(f'<rect x="0" y="{HORIZON-1}" width="{W}" height="2" fill="#ff9ee8" opacity="0.9"/>')

# Subtle vignette
parts.append(f'''<radialGradient id="vig" cx="0.5" cy="0.45" r="0.75">
  <stop offset="0.6" stop-color="#000000" stop-opacity="0"/>
  <stop offset="1" stop-color="#000000" stop-opacity="0.35"/>
</radialGradient>
<rect width="{W}" height="{H}" fill="url(#vig)"/>''')

parts.append('</svg>')

with open('synthwave.svg', 'w') as f:
    f.write("\n".join(parts))
print("wrote synthwave.svg")
