#!/usr/bin/env python3
"""Burn-in for one GPU: VRAM pattern test, then sustained bf16 matmul with result checks.

Usage: gpu_burn.py --gpu N --minutes M [--vram-passes P] [--out results.json]
Run one process per GPU (HIP_VISIBLE_DEVICES is not needed; --gpu picks the device).
"""
import argparse, json, os, sys, time

import torch


def log(gpu, msg):
    print(f"{time.strftime('%H:%M:%S')} gpu{gpu} {msg}", flush=True)


def vram_test(dev, gpu, passes):
    """Fill most of VRAM with index-derived patterns and verify. Returns (GiB tested, mismatches)."""
    free, total = torch.cuda.mem_get_info(dev)
    chunk = 512 * 1024 * 1024 // 4  # int32 elements per 512 MiB chunk
    bufs = []
    keep_free = 1536 * 1024 * 1024  # scratch is allocated separately
    while True:
        free, _ = torch.cuda.mem_get_info(dev)
        if free - chunk * 4 < keep_free:
            break
        try:
            bufs.append(torch.empty(chunk, dtype=torch.int32, device=dev))
        except torch.OutOfMemoryError:
            break
    gib = len(bufs) * chunk * 4 / 2**30
    log(gpu, f"vram: {gib:.1f} GiB allocated of {total / 2**30:.1f} GiB")
    base = torch.arange(chunk, dtype=torch.int32, device=dev)
    scratch = torch.empty_like(base)
    bad = 0
    for p in range(passes):
        for i, b in enumerate(bufs):
            seed = (i * 2654435761 + p * 40503) & 0x7FFFFFFF
            b.copy_(base)
            b.bitwise_xor_(seed)
            if p % 2:
                b.bitwise_not_()
        torch.cuda.synchronize(dev)
        for i, b in enumerate(bufs):
            seed = (i * 2654435761 + p * 40503) & 0x7FFFFFFF
            torch.bitwise_xor(base, seed, out=scratch)
            if p % 2:
                scratch.bitwise_not_()
            if not torch.equal(b, scratch):
                step = chunk // 64
                bad += sum(int((b[k:k + step] != scratch[k:k + step]).sum().item()) for k in range(0, chunk, step))
        log(gpu, f"vram pass {p + 1}/{passes}: mismatches so far {bad}")
    del scratch
    del bufs, base
    torch.cuda.empty_cache()
    return gib, bad


def compute_burn(dev, gpu, minutes):
    """Sustained bf16 GEMM; every ~10 s recompute a fixed fp32 GEMM and compare with the first result."""
    n = 8192
    g = torch.Generator(device=dev).manual_seed(1234 + gpu)
    a = torch.randn(n, n, device=dev, dtype=torch.bfloat16, generator=g)
    b = torch.randn(n, n, device=dev, dtype=torch.bfloat16, generator=g)
    c = torch.empty(n, n, device=dev, dtype=torch.bfloat16)
    ca = torch.randn(2048, 2048, device=dev, dtype=torch.float32, generator=g)
    cb = torch.randn(2048, 2048, device=dev, dtype=torch.float32, generator=g)
    ref = (ca @ cb).clone()
    # Keep a big resident buffer so VRAM is in use (and heating) during the compute phase too.
    free, _ = torch.cuda.mem_get_info(dev)
    ballast = torch.empty(max(0, free - 3 * 2**30) // 2, dtype=torch.float16, device=dev)
    ballast.fill_(1.0)

    end = time.time() + minutes * 60
    iters, checks, check_bad, max_diff = 0, 0, 0, 0.0
    t0 = time.time()
    next_check, next_report = t0 + 10, t0 + 60
    while time.time() < end:
        for _ in range(20):
            torch.matmul(a, b, out=c)
        torch.cuda.synchronize(dev)
        iters += 20
        now = time.time()
        if now >= next_check:
            r = ca @ cb
            d = float((r - ref).abs().max().item())
            checks += 1
            max_diff = max(max_diff, d)
            if d != 0.0:
                check_bad += 1
                log(gpu, f"CHECK MISMATCH: max abs diff {d}")
            if not torch.isfinite(c).all():
                check_bad += 1
                log(gpu, "CHECK: non-finite values in GEMM output")
            next_check = now + 10
        if now >= next_report:
            tflops = 2 * n**3 * iters / (now - t0) / 1e12
            log(gpu, f"compute: {iters} GEMMs, {tflops:.1f} TFLOPS bf16 avg, checks {checks} bad {check_bad}")
            next_report = now + 60
    el = time.time() - t0
    del ballast
    return {"gemms": iters, "seconds": round(el, 1), "tflops_bf16": round(2 * n**3 * iters / el / 1e12, 1),
            "checks": checks, "check_mismatches": check_bad, "max_check_diff": max_diff}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gpu", type=int, required=True)
    ap.add_argument("--minutes", type=float, default=30)
    ap.add_argument("--vram-passes", type=int, default=2)
    ap.add_argument("--out")
    args = ap.parse_args()
    dev = torch.device(f"cuda:{args.gpu}")
    torch.cuda.set_device(dev)
    props = torch.cuda.get_device_properties(dev)
    log(args.gpu, f"{props.name} {getattr(props, 'gcnArchName', '')} pci {props.pci_bus_id if hasattr(props, 'pci_bus_id') else ''}")
    res = {"gpu": args.gpu, "name": props.name, "arch": getattr(props, "gcnArchName", ""),
           "total_gib": round(props.total_memory / 2**30, 2), "started": time.strftime("%F %T")}
    if args.vram_passes:
        gib, bad = vram_test(dev, args.gpu, args.vram_passes)
        res.update(vram_gib_tested=round(gib, 1), vram_mismatches=bad)
    if args.minutes > 0:
        res.update(compute_burn(dev, args.gpu, args.minutes))
    res["finished"] = time.strftime("%F %T")
    ok = res.get("vram_mismatches", 0) == 0 and res.get("check_mismatches", 0) == 0
    res["ok"] = ok
    log(args.gpu, ("PASS " if ok else "FAIL ") + json.dumps(res))
    if args.out:
        with open(args.out, "w") as f:
            json.dump(res, f, indent=1)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
