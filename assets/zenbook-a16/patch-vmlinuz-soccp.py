#!/usr/bin/env python3
"""Enable the SoCCP remoteproc in the Zenbook A16 DTB embedded in omarchy-snapdragon's vmlinuz.efi.

The Ubuntu A16 tree ships /soc@0/remoteproc-soccp@d00000 with status = "disabled". SoCCP runs the
charger/battery firmware; UEFI starts it, and qcom_q6v5_pas (kaanapali-soccp, early_boot) attaches to
it instead of loading firmware. With the node disabled nothing brings up its GLINK edge, so
pmic_glink/qcom-battmgr never see the battery service (every property read returns EAGAIN).

This rewrites status "disabled\\0" (9 bytes, 12 padded) to "okay\\0" (5 bytes, 8 padded) and fills
the remaining 4 bytes with an FDT_NOP token, so the blob size and PE section are unchanged.
Run it on an image that already has the SCMI patch (patch-vmlinuz-dtb.py).

usage: patch-vmlinuz-soccp.py IN.efi OUT.efi
"""
import struct, sys

NODE = ['soc@0', 'remoteproc-soccp@d00000']

def patch_dtb(d):
    d = bytearray(d)
    hdr = struct.unpack_from('>10I', d, 0)
    off_struct, off_strings = hdr[2], hdr[3]
    BEGIN, END, PROP, NOP, FDT_END = 1, 2, 3, 4, 9
    p, path = off_struct, []
    while True:
        tok = struct.unpack_from('>I', d, p)[0]; p += 4
        if tok == BEGIN:
            e = d.index(b'\0', p); path.append(d[p:e].decode()); p = (e + 4) & ~3
        elif tok == END:
            path.pop()
        elif tok == PROP:
            ln, nameoff = struct.unpack_from('>II', d, p)
            s = off_strings + nameoff
            pname = d[s:d.index(b'\0', s)].decode()
            val = bytes(d[p + 8:p + 8 + ln])
            if path[1:] == NODE and pname == 'status':
                if val == b'okay\0':
                    print('already okay'); return bytes(d)
                assert val == b'disabled\0', val
                struct.pack_into('>I', d, p, 5)
                d[p + 8:p + 20] = b'okay\0\0\0\0' + struct.pack('>I', NOP)
                return bytes(d)
            p = (p + 8 + ln + 3) & ~3
        elif tok == NOP:
            pass
        elif tok == FDT_END:
            raise SystemExit('soccp status property not found')

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
                assert len(new) == total
                f[rp:rp + total] = new
                print(f'patched section #{n}')
                done = True
        off += 40
    assert done, 'A16 DTB section not found'
    open(dst, 'wb').write(f)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
