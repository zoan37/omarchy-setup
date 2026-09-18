#!/usr/bin/env python3
"""Offline experiment on Dell's fan diagnostic Windows shim; no hardware access.

Requires pefile and unicorn; supply the privately extracted FanDiagnostic.dll.
Executes its native fan wrappers and legacy-call adapter in emulated memory.
Windows transport, logging, initialization and runtime helpers are mocks.
This does not execute the managed test or model BIOS/EC acceptance.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path

import pefile
from unicorn import Uc, UC_ARCH_X86, UC_MODE_64, UC_HOOK_CODE
from unicorn.x86_const import (
    UC_X86_REG_RAX, UC_X86_REG_RCX, UC_X86_REG_RDX, UC_X86_REG_R8,
    UC_X86_REG_R9, UC_X86_REG_RIP, UC_X86_REG_RSP,
)

SHA256 = "4022193b29be79ad4f26baf9b607af242453a8b6f3863203b38fe3ae5b04389d"
STACK, FAKE, STOP = 0x200000, 0x300000, 0x300800
METHODS = {
    "state": (0x18, 0x10d60, 0x00a3),
    "set": (0x20, 0x10d70, 0x01a3),
    "rpm": (0x28, 0x10d90, 0x02a3),
    "manual": (0x50, 0x10e90, 0x30a3),
    "auto": (0x58, 0x10ea0, 0x31a3),
}


def experiment(p, name, transport_status, response_ax, fan=1, level=2):
    uc = Uc(UC_ARCH_X86, UC_MODE_64)
    base = p.OPTIONAL_HEADER.ImageBase
    uc.mem_map(base, (p.OPTIONAL_HEADER.SizeOfImage + 4095) & ~4095)
    uc.mem_write(base, p.get_memory_mapped_image())
    uc.mem_map(STACK, 0x10000)
    uc.mem_map(FAKE, 0x1000)

    def qput(a, v):
        uc.mem_write(a, struct.pack("<Q", v))

    def qget(a):
        return struct.unpack("<Q", uc.mem_read(a, 8))[0]

    def dget(a):
        return struct.unpack("<I", uc.mem_read(a, 4))[0]

    def ret(v=0):
        sp = uc.reg_read(UC_X86_REG_RSP)
        uc.reg_write(UC_X86_REG_RAX, v)
        uc.reg_write(UC_X86_REG_RIP, qget(sp))
        uc.reg_write(UC_X86_REG_RSP, sp + 8)

    # Select the initialized CDiagsIntf/WMI branch, with a mock logger.
    uc.mem_write(base + 0x86bf4, struct.pack("<I", 1))
    qput(base + 0x869b0, FAKE)
    qput(FAKE, FAKE + 0x100)
    for off in (0x18, 0x50):
        qput(FAKE + 0x100 + off, FAKE + 0x200)
    calls = []
    finished = False
    # Only these DLL code ranges and explicitly mocked functions may run.
    ranges = ((0x10d60, 0x10da0), (0x10e90, 0x10eaf),
              (0xba40, 0xc0aa), (0x12450, 0x124ee), (0x12590, 0x12623))

    def hook(uc, address, size, _):
        nonlocal finished
        rva = address - base
        if address == STOP:
            finished = True
            uc.emu_stop()
        elif address == FAKE + 0x200:
            ret()  # Log output.
        elif rva == 0x27940:
            ret(uc.reg_read(UC_X86_REG_RAX))  # Cookie check preserves return value.
        elif rva in (0x136e0, 0x12929, 0x1292f, 0x12935):
            ret()  # Alternate transport absent; ctor/dtor/init.
        elif rva == 0x29645:
            dest = uc.reg_read(UC_X86_REG_RCX)
            count = uc.reg_read(UC_X86_REG_R8)
            assert count == 0x17c and STACK <= dest < STACK + 0x10000
            uc.mem_write(dest, bytes([uc.reg_read(UC_X86_REG_RDX) & 255]) * count)
            ret(dest)
        elif rva == 0x1293b:
            sp = uc.reg_read(UC_X86_REG_RSP)
            eaxbuf = uc.reg_read(UC_X86_REG_R8)
            ebxbuf = qget(sp + 0x28)
            ecxbuf = qget(sp + 0x38)
            edxbuf = qget(sp + 0x48)
            lengths = [dget(a) for a in (
                uc.reg_read(UC_X86_REG_RDX), uc.reg_read(UC_X86_REG_R9),
                qget(sp + 0x30), qget(sp + 0x40))]
            assert lengths == [4, 4, 4, 4], lengths
            calls.append(dict(eax=dget(eaxbuf), ebx=dget(ebxbuf),
                              ecx=dget(ecxbuf), edx=dget(edxbuf)))
            if response_ax is not None:
                uc.mem_write(eaxbuf, struct.pack("<H", response_ax))
            ret(transport_status)
        elif not any(start <= rva < end for start, end in ranges):
            raise RuntimeError(f"Unexpected execution: {address:#x} (RVA {rva:#x})")

    offset, rva, command = METHODS[name]
    assert qget(base + 0x7b780 + offset) == base + rva
    sp = STACK + 0xf008
    qput(sp, STOP)
    uc.reg_write(UC_X86_REG_RSP, sp)
    uc.reg_write(UC_X86_REG_RCX, fan)
    uc.reg_write(UC_X86_REG_RDX, level)
    uc.reg_write(UC_X86_REG_R8, 0)
    uc.hook_add(UC_HOOK_CODE, hook)
    uc.emu_start(base + rva, STOP + 1, count=10000)
    assert finished, "Instruction limit exceeded"
    expected_ebx = 0 if name in ("manual", "auto") else fan & 255
    if name == "set":
        expected_ebx |= (level & 255) << 8
    assert calls == [dict(eax=command, ebx=expected_ebx, ecx=0, edx=0)], calls
    result = uc.reg_read(UC_X86_REG_RAX) & 0xffffffff
    return dict(method=name, transport_status=transport_status,
                response_ax=response_ax, fan=fan, level=level,
                request=calls[0], result=result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dll", type=Path)
    args = parser.parse_args()
    data = args.dll.read_bytes()
    if hashlib.sha256(data).hexdigest() != SHA256:
        raise SystemExit("Unexpected DLL hash; refusing fixed-address execution")
    p = pefile.PE(data=data)
    results = []
    for name in METHODS:
        for status, ax in ((0, 0), (0, 0xffff), (1, None), (1, 0)):
            r = experiment(p, name, status, ax)
            if ax == 0:
                expected = 0
            elif name == "rpm" and ax is None:
                expected = 0x2a3  # Existing special case for unchanged RPM input.
            elif name in ("state", "rpm"):
                expected = 0xffff
            else:
                expected = 0x80000003
            assert r["result"] == expected, r
            results.append(r)
    for level in (0, 1, 255, 256, 257):
        r = experiment(p, "set", 0, 0, fan=257, level=level)
        assert r["result"] == 0
        results.append(r)
    print(json.dumps(dict(dll_sha256=SHA256, hardware_access=False,
                         scope="Native client shim with mocked Windows transport; not BIOS or EC",
                         cases_passed=len(results), results=results), indent=2))


if __name__ == "__main__":
    main()
