#!/usr/bin/env python3
"""Patch the ASUS Zenbook A16 device tree embedded in omarchy-snapdragon's vmlinuz.efi.

The Ubuntu/Stubble kernel image carries ~40 DTBs as `.dtbauto` PE sections and picks one by
SMBIOS hardware ID at boot. This script finds the A16 tree (root compatible
asus,zenbook-a16-ux3607oa), inserts `arm,no-completion-irq;` into /firmware/scmi (makes the
SCMI core poll, which is what lets scmi-cpufreq probe on Glymur), writes the modified tree back
into the same section and updates the section's VirtualSize (without that the stub prints
"found bad dt blob in PE section N").

usage: patch-vmlinuz-dtb.py IN.efi OUT.efi
"""
import struct, sys

def patch_dtb(d):
    d = bytearray(d)
    (magic, totalsize, off_struct, off_strings, off_rsvmap, version, last_comp,
     boot_cpu, size_strings, size_struct) = struct.unpack_from('>10I', d, 0)
    assert magic == 0xd00dfeed and off_strings > off_struct
    if b'arm,no-completion-irq' in d:
        return bytes(d)  # already patched
    BEGIN, END, PROP, NOP, FDT_END = 1, 2, 3, 4, 9
    p, path, target = off_struct, [], None
    while True:
        tok = struct.unpack_from('>I', d, p)[0]; p += 4
        if tok == BEGIN:
            e = d.index(b'\0', p); name = d[p:e].decode(); p = (e + 4) & ~3
            path.append(name)
            if path[1:] == ['firmware', 'scmi']:
                target = p
        elif tok == END:
            path.pop()
        elif tok == PROP:
            ln, _ = struct.unpack_from('>II', d, p); p = (p + 8 + ln + 3) & ~3
        elif tok == FDT_END:
            break
    assert target, "no /firmware/scmi node"
    name = b'arm,no-completion-irq\0'
    d[target:target] = struct.pack('>III', PROP, 0, size_strings)
    size_struct += 12; off_strings += 12
    d[off_strings + size_strings:off_strings + size_strings] = name
    size_strings += len(name)
    while len(d) % 4: d += b'\0'
    struct.pack_into('>10I', d, 0, magic, len(d), off_struct, off_strings, off_rsvmap,
                     version, last_comp, boot_cpu, size_strings, size_struct)
    return bytes(d)

def main(src, dst):
    f = bytearray(open(src, 'rb').read())
    pe = struct.unpack_from('<I', f, 0x3c)[0]
    nsec = struct.unpack_from('<H', f, pe + 6)[0]
    optsz = struct.unpack_from('<H', f, pe + 20)[0]
    off = pe + 24 + optsz
    done = False
    for n in range(nsec):
        name = f[off:off + 8].rstrip(b'\0').decode(errors='replace')
        vsz, va, rsz, rp = struct.unpack_from('<IIII', f, off + 8)
        if name == '.dtbauto':
            total = struct.unpack_from('>I', f, rp + 4)[0]
            blob = bytes(f[rp:rp + total])
            if b'asus,zenbook-a16-ux3607oa' in blob:
                new = patch_dtb(blob)
                assert len(new) <= rsz, f"patched DTB ({len(new)}) exceeds section raw size ({rsz})"
                f[rp:rp + rsz] = new + b'\0' * (rsz - len(new))
                struct.pack_into('<I', f, off + 8, len(new))
                print(f"patched section #{n}: dtb {total} -> {len(new)} bytes (raw size {rsz})")
                done = True
        off += 40
    assert done, "A16 DTB section not found"
    open(dst, 'wb').write(f)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
