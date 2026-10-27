# Radeon AI PRO R9700 as a Thunderbolt 5 eGPU (Minisforum DEG2): fast or stable, not both yet

**Setup:** ASRock Radeon AI PRO R9700 Creator 32 GB (RDNA4, Navi 48, `1002:7551`) in a Minisforum **DEG2**
(Intel JHL9480 Thunderbolt 5 controller) with its own ATX PSU, connected with the USB-C cable from the box to
a USB4 port on the [GMKtec K8 Plus](k8-plus-egpu.md) (Ryzen 7 8845HS). Omarchy, kernel `7.2.8-9-omarchy`,
`linux-firmware-amdgpu 20260916`, Mesa/RADV `26.2.5`, `bolt 0.9.11`. Date: 2026-10-27.

**Result (partial):** with two kernel options, llama.cpp Vulkan runs the card at normal R9700 speed
(Qwen3-30B-A3B Q4_K_M: **~3,000–3,300 tok/s prompt, ~120–125 tok/s generation**) for a few minutes. **It still hangs
under sustained load:** a soak test of back-to-back runs got through 2 runs (~1 minute) and then hit `ring sdma0
timeout` with the 60 s timeout in place. So the options fix the boot-time failure and get short jobs through,
not the underlying problem, which looks like the dock's link to the GPU (below). No driver install is needed:
`amdgpu` and the RDNA4 firmware are already in Omarchy.

**Update, same evening:** a `llama-server` that loads the model **once** ran 14.5 minutes (36 requests) with no
errors, but at only ~22 tok/s generation. The pattern across all the hangs: **CPU writes to VRAM through the BAR
survive this link; the GPU's own DMA reads from system RAM (`sdma` jobs) are what hang.** See
[Server soak](#server-soak-load-once-is-stable-dma-is-not).

## Symptoms, in the order they showed up

1. **Nothing on the bus** with the OcuLink cable plugged in. The DEG2 has a physical **OCuLink / TB5 mode
   switch** (reviews call it hard to reach, and listings put it on the front panel or under a cover). Only the
   selected port works; in TB5 mode the OcuLink port is dead (`PresDet-` on the K8's OcuLink root port).
2. **Over USB-C, the dock is seen but no GPU.** `boltctl list` shows the dock (`TBGAA`) as `connected`, not
   `authorized`, so no PCIe tunnel is set up.
3. **After authorizing, the card is marked dead within a minute of boot**, though `amdgpu` keeps using it:

   ```
   pcieport 0000:00:03.1: AER: Uncorrectable (Non-Fatal) error message received from 0000:09:00.0
   pcieport 0000:09:00.0: PCIe Bus Error: severity=Uncorrectable (Non-Fatal), type=Transaction Layer
   pcieport 0000:09:00.0:   device [1002:1479] error status/mask=00100000/00000000
   amdgpu 0000:0a:00.0: pci_channel_io_perm_failure: state(3)!!
   snd_hda_intel 0000:0a:00.1: AER: can't recover (no error_detected callback)
   pcieport 0000:09:00.0: AER: device recovery failed
   ```

   After that, the memory clock stayed at 96 MHz, power sensors returned `Device or resource busy`, and the first
   heavy job hung the GPU (`ring gfx_0.0.0 timeout`, `MES(1) failed to respond`, `SMC is not ready`). Only a full
   power cycle of the dock brings it back.
4. **With that fixed, loading a model still hung the copy engine:** `ring sdma0 timeout` → `Ring sdma0 reset
   failed` → GPU reset.

## Causes

- **The boot-time error is harmless, and the kernel's recovery for it is what broke the card.** Status bit 20 is
  *Unsupported Request*; the logged TLP header is a message from the GPU function (`0a:00.0`), code `0x10` = LTR
  (a latency-tolerance report). The R9700's internal PCIe switch (`1002:1479`) rejected it. The kernel then
  started AER recovery, the card's HDMI audio function has no recovery callback, recovery failed, and the whole
  device was marked as permanently failed.
- **The dock-to-GPU link inside the DEG2 runs at 2.5 GT/s with receiver errors.** The JHL9480's downstream port
  logs `RxErr+`, trains at 2.5–5 GT/s instead of 16, and **resets its own target speed to 2.5 GT/s** when asked to
  retrain (`setpci ... CAP_EXP+30.w`). That's the dock's firmware falling back, below anything Linux controls. At
  ~250 MB/s, large copies during model load take long enough to trip `amdgpu`'s default 10 s job timeout.
- **What's not the cause:**
  - **ASPM** was already disabled on every link in the chain.
  - **The K8's USB4 tunnel ports report a fake `2.5GT/s x1`** in `LnkCap`, and the kernel prints `limited by 2.5
    GT/s PCIe x1 link at 0000:00:04.1`. That's normal for USB4 tunnels and isn't the real speed. Forcing
    `amdgpu.pcie_gen_cap=0x000F001F` made the GPU side ask for 32 GT/s, but the JHL9480 kept 2.5 GT/s anyway.
- **The USB4 link itself came up at 20 Gb/s (`2 lanes * 10 Gb/s`)** on both of the K8's USB4 ports, with the
  dock's own cable. That's a separate open question (cable, retimers, or this dock unit).

## What helps (partial fix)

1. **Authorize the dock** once. `--policy auto` makes it authorize itself on later boots and on other ports:

   ```sh
   boltctl list                                   # status: connected
   sudo boltctl enroll --policy auto <dock-uuid>  # status: authorized; the GPU appears in lspci
   ```

2. **Two kernel options** in `/etc/default/limine` (back it up first), then `sudo limine-update`:

   ```sh
   KERNEL_CMDLINE[default]+=" pci=noaer"
   KERNEL_CMDLINE[default]+=" amdgpu.lockup_timeout=60000,60000,60000,60000"
   ```

   - `pci=noaer` stops the kernel from acting on AER reports, so the rejected LTR message is ignored instead of
     killing the device. **Trade-off:** real PCIe errors (a failing cable, NVMe) also go unreported and unhandled.
   - `amdgpu.lockup_timeout` is in ms, per engine (gfx, compute, SDMA, video). 60 s instead of 10 s let a full
     `llama-bench` run (two passes, then the five-test table below) finish where the default timed out. It doesn't
     stop the hang: in the soak test an SDMA job never completed (`signaled seq=2982, emitted seq=2984`), and the
     timeout only fired later. That points at lost or corrupted transfers on the noisy link, not slowness.
   - The K8 also has `amdgpu.pcie_gen_cap=0x000F001F` from the investigation. It changed nothing measurable and
     can be left out.

3. **Power cycle the dock** if the card was already in the failed state: shut the host down, turn the dock off and
   on, then boot the host. A reboot alone doesn't reset a hung card.

## Benchmark

llama.cpp Vulkan (`-DGGML_VULKAN=ON`, commit `11924d4c1`, 2026-08-02), all layers on the R9700, flash attention on:

```sh
./llama-bench -m Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf -dev Vulkan1 -ngl 99 -fa 1 -p 512,4096 -n 128,512 -r 3
```

| Test | tok/s |
|---|---|
| pp512 | 3,067 |
| pp4096 | 2,811 |
| tg128 | 123 |
| tg512 | 118 |

The run above was taken with the GPU forced to its highest power level
(`echo high | sudo tee /sys/bus/pci/devices/<gpu>/power_dpm_force_performance_level`, back to `auto` after).

> **Measurement trap:** under load, the R9700 keeps its memory clock at **96 MHz for about 12 s** before jumping to
> 1,258 MHz. A short `llama-bench` run (`tg128` with the default power level) finishes inside that window and reports
> **~20 tok/s** and ~600 tok/s prompt. Longer runs, or the `high` power level, give the real numbers. Watch
> `pp_dpm_mclk` during a run to tell the two apart.

**What the capped link costs:** once a model is fully in VRAM, generation barely touches the link. Model loads
are slower, and anything that streams weights across the link every token (MoE experts in system RAM, e.g.
Strata or `--n-cpu-moe`) is limited by it. See the Strata section of [k8-plus-egpu.md](k8-plus-egpu.md).

## Verify

```sh
boltctl list | grep -E 'status|rx speed'           # authorized
grep -oE 'pci=noaer|amdgpu.lockup_timeout=[^ ]*' /proc/cmdline
sudo dmesg | grep -c perm_failure                  # 0
# Link chain from the GPU up to the root port: speed and error bits at each hop
G=$(lspci -D -d 1002:7551 | cut -d' ' -f1); p=$G
while :; do
  echo "$p $(sudo lspci -vvv -s $p | grep -m1 LnkSta: | xargs) | $(sudo lspci -vvv -s $p | grep -E 'UESta:|CESta:' | grep -oE '[A-Za-z]+\+' | tr '\n' ' ')"
  p=$(basename "$(dirname "$(readlink -f /sys/bus/pci/devices/$p)")"); case $p in pci*) break;; esac
done
vulkaninfo --summary | grep -A2 'R9700'            # RADV GFX1201
```

## Undo

Restore the backed-up `/etc/default/limine` (or delete the two lines) and run `sudo limine-update`.
`sudo boltctl forget <dock-uuid>` removes the enrollment.

## Soak test: hangs after about a minute

Back-to-back `llama-bench -p 4096 -n 1024 -r 1` runs, logging temperatures and GPU errors after each:

| Run | Prompt tok/s | Generation tok/s | Edge / junction |
|---|---|---|---|
| 1 | 3,292 | 125.1 | 42 / 58 °C |
| 2 | 3,285 | 125.1 | 47 / 58 °C |
| 3 | hung: `ring sdma0 timeout` → `Ring sdma0 reset failed` → `MES(1) failed to respond` | | |

Temperatures were low, so it isn't heat. The hung card needs the full power-cycle order again (host off, dock off and
on, host on). A hung GPU also leaves `llama-bench` as a zombie, and `echo 1 > .../remove` blocks in D state; use
`sync` and `systemctl poweroff -f` rather than waiting on a normal shutdown.

## Server soak: load once is stable, DMA is not

`llama-server` (same build, `-ngl 99 -fa on -c 8192`), model loaded once, then back-to-back 512-token requests:

| Run | Model load | Result | Generation |
|---|---|---|---|
| Default settings | 21 s, fine | **14.5 min, 36 requests, 0 failures, 0 GPU errors**; junction leveled off at 73 °C | **21.7 tok/s** |
| `GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1` | **hung**: `Ring sdma1 reset failed` | no requests | n/a |

**Why the server is slow when `llama-bench` isn't:** the server reads the logits (vocabulary × 4 bytes, ~600 KB here)
after every token for sampling. With a 256 MB BAR, llama.cpp keeps that output in host-visible VRAM, so the CPU reads
it across the link with uncached loads. Each one is a round trip over Thunderbolt at 2.5 GT/s, so every step costs a fixed
~40 ms: `eval time = 46 ms per token`, and even a 15-token prompt pass takes ~490 ms. `llama-bench` doesn't sample, so it
never pays this.

**Why the obvious fix hangs:** `GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1` moves those transfers, and the weight upload, to
DMA on the GPU's SDMA engines. The model load then hung. Every hang so far has been a GPU job that never completed
(`signaled seq` < `emitted seq`). A DMA read is a *non-posted* request that waits for a completion from the host; a CPU
write is *posted* and needs none. On a link logging receiver errors, a lost completion would stall a DMA job forever while
CPU writes still get through.

### Smaller DMA reads: stable once loaded, loads still a gamble

Lowering the GPU's **Max Read Request Size from 512 to 128 bytes** (DevCtl bits 14:12, on both the GPU and its audio
function; runtime only, resets on reboot) made the DMA path work:

```sh
G=$(lspci -D -d 1002:7551 | cut -d' ' -f1)
for f in ${G%.0}.0 ${G%.0}.1; do sudo setpci -s $f CAP_EXP+08.w=0000:7000; done   # value:mask → MRRS = 128
sudo lspci -vvv -s $G | grep -o 'MaxReadReq [0-9]* bytes'
```

| Run (`GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1`, MRRS 128) | Result |
|---|---|
| `llama-server` soak, 15 min | **70 requests, 0 failures, 0 GPU errors, 40.1 tok/s** (vs 21.7), junction 74 °C |
| `llama-bench` tg128, default vs the env setting | 122 vs 118 tok/s, so the setting itself costs little |
| 4th model load that boot | **hung** (`ring gfx_0.0.0 timeout` → `GPU Recovery Failed`) |

So with all of the above, a server that loads once runs stably at 40 tok/s, but each model load is roughly a 1-in-4 chance
of a hang that needs a dock power cycle. The remaining ~16 ms per token over `llama-bench` is server-side (logits,
sampling) and not yet tracked down. None of this fixes the link itself (`RxErr+` is still logged); it only makes failures
rarer. The next test is a second DEG2 unit.

## Later tests: errors at idle, loads still hang

- **The error bits are sticky**, so earlier `RxErr+` readings could have been left over from boot-time link training.
  After clearing them (`setpci -s <dev> ECAP_AER+10.l=ffffffff`, write-1-to-clear) and re-reading every 0.5 s at idle:
  the dock's JHL9480 port toward the GPU logged `RxErr` in **11 of 20** windows, and the K8's own USB4 tunnel root port
  logged **`BadDLLP` in 20 of 20**. The links take errors continuously, even idle at 2.5 GT/s.
- **`thunderbolt.clx=0`** (USB4 link low-power states off): no change in either error rate. Removed again.
- **The 128-byte read size is now applied by a udev rule** for the GPU (`1002:7551`) and its audio function (`1002:ab40`):

  ```
  # /etc/udev/rules.d/90-r9700-egpu-mrrs.rules
  ACTION=="add|bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x1002", ATTR{device}=="0x7551", RUN+="/usr/bin/setpci -s %k CAP_EXP+08.w=0000:7000"
  ACTION=="add|bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x1002", ATTR{device}=="0xab40", RUN+="/usr/bin/setpci -s %k CAP_EXP+08.w=0000:7000"
  ```

- **Repeated model loads** (`llama-bench -p 64 -n 16`, all fixes active): loads 1–2 fine, **load 3 hung** (`sdma0`).
- **Power cap:** the driver allows **210–300 W** (`power1_cap_min`/`max`; 150 W is refused with `Invalid argument`). At
  210 W, **load 2 hung** (`sdma1`), before any full-power run, so power draw isn't the trigger.

Summary: the fixes above change how often a GPU copy is lost, not whether it is. The USB4 link speed (20 of 80 Gb/s) and
the host-side `BadDLLP` don't involve the GPU at all, which points at the DEG2's Thunderbolt side or its interop with the
AMD USB4 host. Next: read the link from a Thunderbolt 5 Mac (`system_profiler SPThunderboltDataType SPPCIDataType`, which
lists the dock and the GPU's link speed even with no driver), and the R9700 on OcuLink in a DEG1.

## Still open

- **The main question: is the 2.5 GT/s + `RxErr` link (and the hang) this DEG2 unit, or JHL9480 docks with RDNA4 in
  general?** Next test: the same card in a second DEG2, then with a different 40 Gb/s cable. It matters for a Mac (Thunderbolt-only) host, since this link is inside the dock and doesn't
  depend on the host.
- **The same card over OcuLink** (DEG2 in OCuLink mode, or a DEG1), for a baseline without the Thunderbolt chip.
- **ROCm/HIP over Thunderbolt:** PCIe atomics usually aren't routed through USB4 bridges (`AtomicOpsCtl: ReqEn-`
  here), so HIP may not work. Untested.
- **The 256 MB BAR:** `amdgpu` tries to resize BAR 0 to 32 GB and fails (`BAR 0 [mem size 0x800000000 64bit pref]:
  failed to assign`), so it stays at 256 MB.
- Other reports of TB5 docks being unstable with AMD GPUs or AMD hosts:
  [Framework forum](https://community.frame.work/t/help-wanted-egpu-bootloop-issues/82128?page=4),
  [Framework DEG2 thread](https://community.frame.work/t/deg2-egpu-fw-13-issues/85095),
  [egpu.io build with a JHL9480 dock](https://egpu.io/forums/builds/2025-14-tuxedo-infinitybook-pro-14-gen10-890m-rai312chx-rtx-3090-64gbps-usb4v1tb5-minisforum-deg2-win11-25h2-daisy-chained-rtx-3090-via-ut4g/).
