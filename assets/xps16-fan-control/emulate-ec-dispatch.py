#!/usr/bin/env python3
"""Offline experiment for the captured DA16260 BIOS 1.10.1 DellEcMm module.

Requires pefile and unicorn. Supply the extracted DellEcMm.efi as an argument.
No device access, firmware execution on the host, or privileged operations.
All external calls are intercepted; EC responses and access flags are synthetic.
This tests BIOS-side dispatch only, not EC semantics or hardware support.
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

EXPECTED_SHA = "020a7e5338c84237cc030db4fcefdca1caf4dc5390932bad208452a222bd7b01"
STACK = 0x100000
REQUEST = 0x200000
EC = 0x201000
FEATURES = 0x202000
MFG = 0x203000
STUB = 0x300000
STOP = STUB + 0x100
ERROR = 0x8000000000000007


def run(data, operation, argument=0, *, transport_error=False, mfg_flags=0,
        response_marker=0x20):
    pe = pefile.PE(data=data)
    uc = Uc(UC_ARCH_X86, UC_MODE_64)
    uc.mem_map(0, 0x20000)
    uc.mem_write(0, pe.get_memory_mapped_image())
    uc.mem_map(STACK, 0x10000)
    uc.mem_map(REQUEST, 0x10000)
    uc.mem_map(STUB, 0x1000)

    def qput(address, value):
        uc.mem_write(address, struct.pack("<Q", value))

    def qget(address):
        return struct.unpack("<Q", uc.mem_read(address, 8))[0]

    qput(0x15b20, EC)
    qput(0x15b40, FEATURES)
    qput(0x15e50, MFG)
    qput(EC + 0x18, STUB)
    qput(EC + 0x20, STUB + 0x10)
    qput(FEATURES + 8, STUB + 0x20)
    qput(MFG + 8, STUB + 0x30)
    uc.mem_write(REQUEST, struct.pack("<HHIQQQQ", 28, 2, 0,
                                      operation, argument, 0, 0))
    sp = STACK + 0xff08
    qput(sp, STOP)
    uc.reg_write(UC_X86_REG_RSP, sp)
    uc.reg_write(UC_X86_REG_RCX, REQUEST)
    calls = []
    gates = []
    finished = False

    def return_value(value=0):
        sp = uc.reg_read(UC_X86_REG_RSP)
        uc.reg_write(UC_X86_REG_RAX, value)
        uc.reg_write(UC_X86_REG_RIP, qget(sp))
        uc.reg_write(UC_X86_REG_RSP, sp + 8)

    # Explicit whitelist: selected dispatcher paths, version helper, access
    # helper and stack-cookie check. Unexpected execution fails closed.
    ranges = [(0xfbcc, 0x10345), (0xf4cc, 0xf588), (0xef84, 0xeff8)]

    def hook(_uc, address, size, _user):
        nonlocal finished
        sp = uc.reg_read(UC_X86_REG_RSP)
        if address == STOP:
            finished = True
            uc.emu_stop()
        elif address == 0x1202:  # Compiler stack-cookie check only.
            return_value()
        elif address == STUB + 0x20:
            return_value(0)  # No optional feature flags.
        elif address == STUB + 0x30:
            ids = [uc.reg_read(UC_X86_REG_RDX), uc.reg_read(UC_X86_REG_R8),
                   uc.reg_read(UC_X86_REG_R9)]
            assert ids == [5, 12, 0], ids
            gates.append(ids)
            uc.mem_write(uc.reg_read(UC_X86_REG_RCX), struct.pack("<I", mfg_flags))
            return_value()
        elif address in (STUB, STUB + 0x10):
            command = uc.reg_read(UC_X86_REG_RDX) & 255
            if address == STUB:
                count = uc.reg_read(UC_X86_REG_R8) & 255
                assert count == 1
                inputs = bytes([uc.reg_read(UC_X86_REG_R9) & 255])
                out_count = 0
            else:
                count = uc.reg_read(UC_X86_REG_R9) & 255
                inputs = bytes(uc.mem_read(uc.reg_read(UC_X86_REG_R8), count))
                out_count = qget(sp + 0x30) & 255
                if not transport_error and out_count:
                    # Distinct marker bytes identify output-byte selection.
                    uc.mem_write(qget(sp + 0x28), bytes(
                        (response_marker + n) & 255 for n in range(out_count)))
            calls.append({"command": hex(command), "input_hex": inputs.hex(),
                          "response_bytes": out_count})
            return_value(ERROR if transport_error else 0)
        elif not any(a <= address < b for a, b in ranges):
            raise RuntimeError(f"Unexpected code address {address:#x}")

    uc.hook_add(UC_HOOK_CODE, hook)
    uc.emu_start(0xfbcc, 0, count=10000)
    assert finished, "Instruction limit reached"
    outputs = struct.unpack("<iIII", uc.mem_read(REQUEST + 0x28, 16))
    return {"operation": operation, "argument": argument,
            "simulated_transport_error": transport_error,
            "simulated_response_marker": response_marker,
            "simulated_mfg_result": mfg_flags, "mfg_checks": gates,
            "ec_calls": calls, "output": list(outputs)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("module", type=Path)
    args = parser.parse_args()
    data = args.module.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != EXPECTED_SHA:
        parser.error(f"Unexpected module SHA-256: {digest}; refusing fixed-address emulation")
    results = []
    expected = {2: ("0x38", "00", 9), 3: ("0xfa", "0dff", 1),
                9: ("0x2e", "080000", 4), 10: ("0x2e", "0a0000", 4)}
    for op, (command, payload, count) in expected.items():
        for failure in (False, True):
            row = run(data, op, transport_error=failure)
            assert row["ec_calls"] == [{"command": command, "input_hex": payload,
                                        "response_bytes": count}], row
            assert row["output"][0] == (-1 if failure else 0), row
            assert not row["mfg_checks"], row
            if not failure and op in (9, 10):
                assert row["output"][1:3] == [0x21, 0x22], row
            results.append(row)
    for op in (0x81, 0x82):
        for flags in (0, 1, 2):
            for failure in (False, True):
                row = run(data, op, 1, transport_error=failure, mfg_flags=flags)
                assert row["mfg_checks"] == [[5, 12, 0]], row
                assert bool(row["ec_calls"]) == bool(flags), row
                assert row["output"][0] == (-1 if not flags or failure else 0), row
                if flags:
                    expected_call = (
                        {"command": "0xfa", "input_hex": "04", "response_bytes": 0}
                        if op == 0x81 else
                        {"command": "0x2e", "input_hex": "0900010100", "response_bytes": 1}
                    )
                    assert row["ec_calls"] == [expected_call], row
                results.append(row)
    # Op 0x81 accepts exactly byte value 1; 0 is not its auto-mode counterpart.
    for argument in (0, 2, 3, 255):
        row = run(data, 0x81, argument, mfg_flags=1)
        assert not row["ec_calls"] and not row["mfg_checks"], row
        assert row["output"][0] == -1, row
        results.append(row)
    # This setter passes a byte through. That is NOT proof of 256 fan speeds.
    for argument in (0, 50, 100, 255, 256, 257):
        row = run(data, 0x82, argument, mfg_flags=1)
        assert row["ec_calls"] == [{"command": "0x2e",
                                    "input_hex": bytes((9, 0, 1, argument & 255, 0)).hex(),
                                    "response_bytes": 1}], row
        assert row["output"][0] == 0, row
        results.append(row)
    for marker in (0, 1, 255):
        row = run(data, 0x82, 1, mfg_flags=1, response_marker=marker)
        assert row["output"] == [0, 0, 0, 0], row
        results.append(row)
    print(json.dumps({"module_sha256": digest, "offline_only": True,
                      "cases_passed": len(results), "results": results}, indent=2))


if __name__ == "__main__":
    main()
