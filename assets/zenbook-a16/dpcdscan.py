#!/usr/bin/env python3
"""Read-only DPCD scanner: reads [start,end) in 16-byte chunks from /dev/drm_dp_auxN with pread.
Writes a JSON map {addr_hex: [bytes]} of chunks that read successfully and are not all zero,
plus a list of chunks that errored. Never writes to the device."""
import json, os, sys, time
dev, start, end, out = sys.argv[1], int(sys.argv[2], 0), int(sys.argv[3], 0), sys.argv[4]
fd = os.open(dev, os.O_RDONLY)
data, errs, t0 = {}, [], time.time()
for a in range(start, end, 16):
    try:
        b = os.pread(fd, 16, a)
    except OSError as e:
        errs.append(a); continue
    if any(b): data[f"{a:05x}"] = list(b)
os.close(fd)
json.dump({"data": data, "errors": errs, "range": [start, end]}, open(out, "w"))
print(f"{out}: {len(data)} non-zero chunks, {len(errs)} error chunks, {time.time()-t0:.1f}s")
