#!/usr/bin/env python3
"""Zenbook A16 eDP brightness probe (documented eDP registers only, volatile).

  edp-lum.py show                 # 0x721 mode, 0x722-3 AUX level, 0x734-6 target millinits
  edp-lum.py aux <0..65535>       # AUX mode (0x721=0x02), write 16-bit level to 0x722/0x723
  edp-lum.py nits <n>             # eDP 1.5 luminance mode (0x721 bit7) with target n nits
  edp-lum.py reset                # back to what Linux uses: AUX mode, 0x07FF
"""
import os, sys
AUX = os.environ.get("AUXDEV", "/dev/drm_dp_aux2")
fd = os.open(AUX, os.O_RDWR)
rd = lambda a, n: os.pread(fd, n, a)
wr = lambda a, b: os.pwrite(fd, bytes(b), a)

def show():
    m = rd(0x721, 1)[0]; lv = rd(0x722, 2); t = rd(0x734, 3)
    print(f"mode=0x{m:02x} lum_ctrl={'on' if m & 0x80 else 'off'} aux_level=0x{lv[0]:02x}{lv[1]:02x} "
          f"target={int.from_bytes(t, 'little')/1000:.1f} nits")

cmd = sys.argv[1] if len(sys.argv) > 1 else "show"
if rd(0x400, 3) != b"\x00\x12\xfb":
    sys.exit("unexpected sink OUI; refusing")
if cmd == "aux":
    v = int(sys.argv[2], 0); wr(0x721, [0x02]); wr(0x722, [v >> 8, v & 0xff])
elif cmd == "nits":
    mn = int(float(sys.argv[2]) * 1000); wr(0x734, list(mn.to_bytes(3, "little"))); wr(0x721, [0x82])
elif cmd == "reset":
    wr(0x721, [0x02]); wr(0x722, [0x07, 0xff])
show()
