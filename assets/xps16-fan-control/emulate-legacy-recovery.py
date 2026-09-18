#!/usr/bin/env python3
"""Offline BIOS 1.10.1 recovery-path experiment; no hardware access.

Runs selected DellDiagsMm and DellSbMm instructions in Unicorn. EC transport,
property storage and I/O ports are mocks; MMIO is ordinary emulated RAM.
Checks BIOS sequencing, not EC acceptance or physical register behavior.
Requires pefile and unicorn. Pass the directory of privately extracted modules.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path

import pefile
from unicorn import Uc, UC_ARCH_X86, UC_MODE_64, UC_HOOK_CODE, UC_HOOK_INSN
from unicorn.x86_const import (
    UC_X86_REG_RAX, UC_X86_REG_RCX, UC_X86_REG_RDX, UC_X86_REG_R8,
    UC_X86_REG_R9, UC_X86_REG_RIP, UC_X86_REG_RSP,
    UC_X86_INS_IN, UC_X86_INS_OUT,
)

HASHES = {
    "DellDiagsMm": "13cf29b3f5c2ba4a4b2f7632a75b20f871e16883edd7e9af2e6fce8e47f4419e",
    "DellSbMm": "0c2cb2dbc68345b2e8cd23f0ac2f3521d6d7a062544dac431828ca5a9334b43c",
}
SB = 0x100000
STACK = 0x200000
FAKE = 0x300000
STUB = 0x400000
STOP = STUB + 0x100
ERROR = 0x8000000000000007
NOT_READY = 0x8000000000000006
MMIO = 0x40006a1000
MIRROR = 0x50000000
INITIAL_PORTS = {0x1802: 0x4120, 0x1830: 0x8033, 0x187c: 0x46}


class Experiment:
    def __init__(self, images):
        self.uc = uc = Uc(UC_ARCH_X86, UC_MODE_64)
        for name, base in (("DellDiagsMm", 0), ("DellSbMm", SB)):
            p = pefile.PE(data=images[name])
            uc.mem_map(base, 0x10000)
            # RIP-relative data and direct calls retain their relative layout.
            # No original absolute protocol-table pointers are used below.
            uc.mem_write(base, p.get_memory_mapped_image())
        for addr, size in ((STACK, 0x10000), (FAKE, 0x1000), (STUB, 0x1000),
                           (MMIO, 0x1000), (0xe0000000, 0x1000),
                           (MIRROR, 0x10000)):
            uc.mem_map(addr, size)
        self.qput(0xb878, FAKE)  # Property protocol.
        self.qput(0xb880, FAKE + 0x100)  # EC I/O presence check.
        self.qput(0xb938, FAKE + 0x200)  # EC fan protocol.
        self.qput(0xb8c8, FAKE + 0x300)  # Southbridge protocol.
        uc.mem_write(0xb930, b"\x01")  # Previously saved property 0x429.
        self.qput(FAKE + 8, STUB)
        self.qput(FAKE + 0x240, STUB + 0x10)
        self.qput(FAKE + 0x248, STUB + 0x20)
        self.qput(FAKE + 0x328, SB + 0x2788)
        self.qput(FAKE + 0x330, SB + 0x27d0)
        self.qput(0xe0000048, MIRROR | 1)
        for n, value in enumerate((0x101, 0x200, 0x301, 0x400)):
            uc.mem_write(MMIO + 0xe80 + n * 8, struct.pack("<I", value))
        self.ports = INITIAL_PORTS.copy()
        self.property_value = 1
        self.events = []
        self.ec_error = False
        self.property_error = False
        self.finished = False
        uc.hook_add(UC_HOOK_CODE, self.code_hook)
        uc.hook_add(UC_HOOK_INSN, self.input_hook, None, 1, 0, UC_X86_INS_IN)
        uc.hook_add(UC_HOOK_INSN, self.output_hook, None, 1, 0, UC_X86_INS_OUT)

    def qput(self, addr, value):
        self.uc.mem_write(addr, struct.pack("<Q", value))

    def qget(self, addr):
        return struct.unpack("<Q", self.uc.mem_read(addr, 8))[0]

    def ret(self, value):
        uc = self.uc
        sp = uc.reg_read(UC_X86_REG_RSP)
        uc.reg_write(UC_X86_REG_RAX, value)
        uc.reg_write(UC_X86_REG_RIP, self.qget(sp))
        uc.reg_write(UC_X86_REG_RSP, sp + 8)

    def input_hook(self, uc, port, size, _):
        assert port in self.ports and size == (2 if port == 0x1802 else 4)
        return self.ports[port]

    def output_hook(self, uc, port, size, value, _):
        assert port in self.ports and size == (2 if port == 0x1802 else 4)
        self.ports[port] = value
        self.events.append({"io_write": hex(port), "value": hex(value)})

    def code_hook(self, uc, address, size, _):
        if address == STOP:
            self.finished = True
            uc.emu_stop()
        elif address == STUB:
            assert uc.reg_read(UC_X86_REG_RDX) == 0x429
            assert uc.reg_read(UC_X86_REG_R9) == 1
            sp = uc.reg_read(UC_X86_REG_RSP)
            value = uc.mem_read(self.qget(sp + 0x28), 1)[0]
            self.events.append({"property_429_attempt": value,
                                "error": self.property_error})
            if not self.property_error:
                self.property_value = value
            self.ret(ERROR if self.property_error else 0)
        elif address in (STUB + 0x10, STUB + 0x20):
            self.events.append({"ec_mode_attempt": "manual" if address == STUB + 0x10 else "auto",
                                "error": self.ec_error})
            self.ret(ERROR if self.ec_error else 0)
        elif not any(a <= address < b for a, b in (
            (0x3450, 0x3574), (0x247c, 0x24bc), (0x257c, 0x25bc),
            (0x25fc, 0x263c), (SB + 0x20bc, SB + 0x21f8),
            (SB + 0x2788, SB + 0x2808),
        )):
            raise RuntimeError(f"Unexpected execution at {address:#x}")

    def call(self, mode, *, ec_error=False, property_error=False):
        self.ec_error, self.property_error = ec_error, property_error
        self.events = []
        self.finished = False
        sp = STACK + 0xff08
        self.qput(sp, STOP)
        self.uc.reg_write(UC_X86_REG_RSP, sp)
        self.uc.emu_start(0x34ac if mode == "manual" else 0x3510, 0, count=10000)
        assert self.finished, "Instruction limit reached"
        return {"request": mode, "efi_result": hex(self.uc.reg_read(UC_X86_REG_RAX)),
                "sb_counter": self.qget(SB + 0x64e0),
                "property_429": self.property_value,
                "ports": {hex(k): hex(v) for k, v in self.ports.items()},
                "events": self.events.copy()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("modules", type=Path)
    args = parser.parse_args()
    images = {}
    for name, expected in HASHES.items():
        data = (args.modules / (name + ".efi")).read_bytes()
        if hashlib.sha256(data).hexdigest() != expected:
            parser.error(f"Unexpected {name} hash; refusing fixed-address emulation")
        images[name] = data
    results = {}
    x = Experiment(images)
    rows = [x.call("manual"), x.call("auto")]
    assert [r["sb_counter"] for r in rows] == [1, 0]
    assert all(r["efi_result"] == "0x0" for r in rows)
    assert x.ports == INITIAL_PORTS and x.property_value == 1
    for n, value in enumerate((0x101, 0x200, 0x301, 0x400)):
        assert struct.unpack("<I", x.uc.mem_read(MMIO + 0xe80 + n * 8, 4))[0] == value
        assert struct.unpack("<I", x.uc.mem_read(MIRROR + 0x7a50 + n * 8, 4))[0] == value
    results["balanced"] = rows

    x = Experiment(images)
    rows = [x.call("manual"), x.call("manual"), x.call("auto"), x.call("auto")]
    assert [r["sb_counter"] for r in rows] == [1, 2, 1, 0]
    assert rows[2]["ports"]["0x1802"] == "0x0"
    assert x.ports == INITIAL_PORTS
    results["duplicate_takeover_needs_two_exits"] = rows

    x = Experiment(images)
    rows = [x.call("manual"), x.call("auto", ec_error=True)]
    assert rows[-1]["sb_counter"] == 1 and rows[-1]["efi_result"] == hex(ERROR)
    assert x.ports != INITIAL_PORTS and x.property_value == 1
    results["failed_ec_restore_leaves_platform_masked"] = rows

    x = Experiment(images)
    row = x.call("manual", ec_error=True)
    assert row["efi_result"] == hex(ERROR) and row["sb_counter"] == 0
    assert x.ports == INITIAL_PORTS and x.property_value == 0
    results["failed_entry_does_not_roll_back_property"] = [row]

    x = Experiment(images)
    rows = [x.call("manual"), x.call("auto", property_error=True)]
    assert rows[-1]["efi_result"] == "0x0" and rows[-1]["sb_counter"] == 0
    assert x.ports == INITIAL_PORTS and x.property_value == 0
    results["property_restore_error_is_ignored"] = rows

    x = Experiment(images)
    row = x.call("auto")
    assert row["efi_result"] == hex(NOT_READY) and row["sb_counter"] == 0
    assert x.ports == INITIAL_PORTS
    assert any(e.get("ec_mode_attempt") == "auto" for e in row["events"])
    results["unmatched_exit_sends_ec_auto_then_returns_not_ready"] = [row]

    print(json.dumps({"offline_only": True, "module_hashes": HASHES,
                      "scenarios_passed": len(results),
                      "calls_checked": sum(map(len, results.values())),
                      "results": results}, indent=2))


if __name__ == "__main__":
    main()
