# Radeon AI PRO R9700 as a Thunderbolt 5 eGPU (Minisforum DEG2): link fixed, process-switch hang open

**Setup:** ASRock Radeon AI PRO R9700 Creator 32 GB (RDNA4, Navi 48, `1002:7551`) in a Minisforum **DEG2**
(Intel JHL9480 Thunderbolt 5 controller, NVM 62.42) with its own ATX PSU, connected with the 80 Gbps USB-C cable
from the box to a USB4 port on the [GMKtec K8 Plus](k8-plus-egpu.md) (Ryzen 7 8845HS). Omarchy, kernel
`7.2.8-9-omarchy`, `linux-firmware-amdgpu 20260916`, Mesa/RADV `26.2.5`, `bolt 0.9.11`. Date: 2026-10-27.

**Result:**
- **Two bugs found and fixed:** the card being marked dead at boot (`pci=noaer`), and the dock-to-GPU link stuck at
  2.5 GT/s with constant receiver errors. That turned out to be **amdgpu's PCIe link power management**, not the dock:
  with `amdgpu.ppfeaturemask=0xfff7bffb` the link trains at **16 GT/s x4 with zero errors**.
- **One bug still open:** a GPU job stalls (`ring gfx_0.0.0`/`sdma0`/`sdma1 timeout`, then a failed reset) when a **new
  process** starts using the card after another exited, typically on the 2nd–3rd model load after boot. A
  **single long-lived process** (`llama-server`) ran two 15-minute soaks with no errors.
- Loaded models run at normal R9700 speed: Qwen3-30B-A3B Q4_K_M at **~3,000 tok/s prompt, ~120 tok/s generation** in
  `llama-bench`.
- No driver install is needed: `amdgpu` and the RDNA4 firmware are already in Omarchy.

> **Correction:** earlier versions of this page blamed the DEG2's hardware for the 2.5 GT/s link (`RxErr` at idle, the
> dock "refusing" 16 GT/s). That was wrong. Turning off PCIe DPM fixed it completely. Thanks to a tip in the
> [Framework thread](https://community.frame.work/t/help-wanted-egpu-bootloop-issues/82128) (`ppfeaturemask=0xfff7bffb`).

## Current configuration

`/etc/default/limine` (back it up first; then `sudo limine-update` and reboot):

```sh
KERNEL_CMDLINE[default]+=" pci=noaer"
KERNEL_CMDLINE[default]+=" amdgpu.lockup_timeout=60000,60000,60000,60000"
KERNEL_CMDLINE[default]+=" amdgpu.ppfeaturemask=0xfff7bffb"
KERNEL_CMDLINE[default]+=" amdgpu.dcdebugmask=0x800"
```

| Setting | Why | Needed? |
|---|---|---|
| `pci=noaer` | A harmless rejected LTR message at boot otherwise gets the card marked `pci_channel_io_perm_failure` | **yes** |
| `amdgpu.ppfeaturemask=0xfff7bffb` | The default `0xfff7bfff` minus `PP_PCIE_DPM_MASK` (`0x4`): the GPU stops switching its link between 2.5 and 16 GT/s | **yes** (fixes the link) |
| `amdgpu.lockup_timeout=60000,...` | 60 s instead of 10 s per engine (gfx, compute, SDMA, video) | helped while the link was at 2.5 GT/s; untested since |
| `amdgpu.dcdebugmask=0x800` | Turns off display idle power states (IPS); used in [drm/amd #5036](https://gitlab.freedesktop.org/drm/amd/-/work_items/5036) and [#5100](https://gitlab.freedesktop.org/drm/amd/-/work_items/5100) | didn't stop the hang; harmless |

Also in place:

- **Dock authorized** once, with `--policy auto` so it authorizes itself on later boots and other ports:
  `sudo boltctl enroll --policy auto <dock-uuid>` (before that, `boltctl list` shows it `connected`, not `authorized`,
  and the GPU never appears).
- **GPU Max Read Request 128 bytes** (from 512) via a udev rule. It made the DMA path much more stable while the link was
  at 2.5 GT/s; untested since the link fix:

  ```
  # /etc/udev/rules.d/90-r9700-egpu-mrrs.rules
  ACTION=="add|bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x1002", ATTR{device}=="0x7551", RUN+="/usr/bin/setpci -s %k CAP_EXP+08.w=0000:7000"
  ACTION=="add|bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x1002", ATTR{device}=="0xab40", RUN+="/usr/bin/setpci -s %k CAP_EXP+08.w=0000:7000"
  ```

- **Hyprland kept off the R9700**, so the desktop only uses the 780M and the eGPU is compute-only. Hyprland is started
  by the systemd user manager, so `~/.config/environment.d/` reaches it. `AQ_DRM_DEVICES` is colon-separated, so
  `/dev/dri/by-path` names (which contain colons) don't work; a udev symlink does:

  ```
  # /etc/udev/rules.d/89-igpu-symlink.rules
  SUBSYSTEM=="drm", KERNEL=="card*", ATTRS{vendor}=="0x1002", ATTRS{device}=="0x1900", SYMLINK+="dri/igpu"
  # ~/.config/environment.d/90-hyprland-igpu.conf
  AQ_DRM_DEVICES=/dev/dri/igpu
  ```

  Before this, `fuser` showed Hyprland, Xwayland and logind holding the R9700's `card0`/`renderD129`; after, nothing.
  It didn't stop the hang either.

- **The DEG2 mode switch:** the dock has a physical **OCuLink / TB5** switch (hard to reach; listings put it on the
  front panel or under a cover). Only the selected port works.

## Bug 1: card marked dead at boot (fixed: `pci=noaer`)

```
pcieport 0000:00:03.1: AER: Uncorrectable (Non-Fatal) error message received from 0000:09:00.0
pcieport 0000:09:00.0: PCIe Bus Error: severity=Uncorrectable (Non-Fatal), type=Transaction Layer
pcieport 0000:09:00.0:   device [1002:1479] error status/mask=00100000/00000000
amdgpu 0000:0a:00.0: pci_channel_io_perm_failure: state(3)!!
snd_hda_intel 0000:0a:00.1: AER: can't recover (no error_detected callback)
pcieport 0000:09:00.0: AER: device recovery failed
```

Status bit 20 is *Unsupported Request*. The TLP header is a message from the GPU function, code `0x10` = LTR (a
latency-tolerance report), which the card's own internal switch (`1002:1479`) rejected. The kernel started AER
recovery, the HDMI audio function has no recovery callback, and the whole card was marked permanently failed. After that
the memory clock stayed at 96 MHz, power sensors returned `Device or resource busy`, and the first heavy job hung it.
`pci=noaer` makes the kernel ignore AER reports. **Trade-off:** real PCIe errors (a failing cable, NVMe) go unhandled too.

## Bug 2: dock link at 2.5 GT/s with errors (fixed: PCIe DPM off)

| | PCIe DPM on (default) | `ppfeaturemask=0xfff7bffb` |
|---|---|---|
| JHL9480 downstream port → GPU | 2.5 GT/s x4, target kept snapping back to 2.5 GT/s | **16 GT/s x4**, target holds |
| `RxErr` on that port, idle | 11 of 20 half-second windows | **0 of 20** |
| `BadDLLP` on the K8's USB4 tunnel root port | 20 of 20 | 20 of 20 (unchanged; effect unknown) |
| GPU `pp_dpm_pcie` | `0: 2.5GT/s`, `1–2: 16GT/s` | all three levels 16 GT/s |

With PCIe DPM on, the GPU drops its link to 2.5 GT/s at idle and asks for 16 GT/s under load; over the dock each switch
means retraining the link, and that's where the receiver errors and the stuck speed came from. Error counts here are
measured after clearing the sticky AER bits (`setpci -s <dev> ECAP_AER+10.l=ffffffff`, write-1-to-clear) and re-reading
every 0.5 s.

Things that did **not** fix the link, for the record: `amdgpu.pcie_gen_cap=0x000F001F`, forcing the JHL9480 target speed
with `setpci`, `power_dpm_force_performance_level=high`, `thunderbolt.clx=0`, and a power cap. ASPM was already off.

**Still odd:** the USB4 link comes up at **20 Gb/s** (`2 lanes * 10 Gb/s` in `boltctl`) on both of the K8's USB4 ports
with the 80 Gbps cable. The K8's USB4 tunnel root ports also report a fake `2.5GT/s x1` in `LnkCap`; that part is normal.

## Bug 3 (open): a GPU job stalls on the next process's model load

Every hang has the same shape: a job never completes (`signaled seq=N, emitted seq=N+1` or `N+2`), the ring reset fails
(`MES(1) failed to respond`, `SMC is not ready`, `GPU Recovery Failed`), and only a dock power cycle recovers the card.

Repeated model loads (`~/egpu-tests/load-loop.sh`: `llama-bench -p 64 -n 16 -r 1` in a loop, a new process each time):

| Settings on top of `pci=noaer` + 128-byte reads | Result |
|---|---|
| PCIe DPM on (link at 2.5 GT/s) | load 3 hung (`sdma0`) |
| + 210 W power cap (the driver's minimum; range 210–300 W) | load 2 hung (`sdma1`) |
| PCIe DPM off (link at 16 GT/s, 0 errors) | load 2 hung (`gfx`) |
| + GFXOFF off too (`ppfeaturemask=0xfff73ffb`) | load 2 hung (`gfx`) |
| PCIe DPM off + `dcdebugmask=0x800` + Hyprland off the card | **load 1** hung (`gfx`) |
| + `power_dpm_force_performance_level=high` | load 3 hung (`sdma1`) |
| + SCLK deep sleep off too (`ppfeaturemask=0xfff7bff3`) | load 2 hung (`gfx`); `pp_dpm_sclk` still showed `S: 0Mhz` at idle |

One long-lived process, by contrast:

| `llama-server`, model loaded once, back-to-back 512-token requests | Result |
|---|---|
| Default settings, link at 2.5 GT/s | **14.5 min, 36 requests, 0 errors**, 21.7 tok/s |
| `GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1` + 128-byte reads, link at 2.5 GT/s | **15 min, 70 requests, 0 errors**, 40.1 tok/s |

So the trigger looks like **the GPU going idle and a new process's work arriving**, not load itself. It matches open
RDNA4 eGPU reports: [#5036](https://gitlab.freedesktop.org/drm/amd/-/work_items/5036) (RX 9060 XT in a DEG2: GPU dies
on Vulkan teardown at game exit), [#5100](https://gitlab.freedesktop.org/drm/amd/-/work_items/5100) (RX 9070 XT in a
DEG2: MES hangs under load, while Windows on the same hardware is fine),
[#5294](https://gitlab.freedesktop.org/drm/amd/-/work_items/5294) (RX 9070 XT on OcuLink in a DEG1: ring timeouts when
work arrives in deep idle). None of them has a fix yet.

**Practical workaround for now:** run one `llama-server` that loads the model once and stays up.

**Notes from the hunt:**
- Don't read `/sys/kernel/debug/dri/<n>/amdgpu_gfxoff` on this setup: the read never returned, and the next load hung.
  Check `/sys/module/amdgpu/parameters/ppfeaturemask` instead.
- A hung GPU leaves `llama-bench` as a zombie, and `echo 1 > /sys/bus/pci/devices/<gpu>/remove` blocks in D state. Use
  `sync` and `systemctl poweroff -f`, then turn the dock off and on, then boot.
- Over SSH, `pkill -f <pattern>` kills its own shell when the remote command line contains the pattern. Kill by PID.

## Benchmark

llama.cpp Vulkan (`-DGGML_VULKAN=ON`, commit `11924d4c1`, 2026-08-02), all layers on the R9700, flash attention on,
measured while the link was still at 2.5 GT/s:

```sh
./llama-bench -m Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf -dev Vulkan1 -ngl 99 -fa 1 -p 512,4096 -n 128,512 -r 3
```

| Test | tok/s |
|---|---|
| pp512 | 3,067 |
| pp4096 | 2,811 |
| tg128 | 123 |
| tg512 | 118 |

Taken with `power_dpm_force_performance_level=high`. With the default level a back-to-back run gave the same
(3,290 / 125).

> **Measurement trap:** under load, the R9700 keeps its memory clock at **96 MHz for about 12 s** before jumping to
> 1,258 MHz. A short run finishes inside that window and reports **~20–26 tok/s**. Watch `pp_dpm_mclk` during a run.

**`llama-server` was slower** (21.7 tok/s by default, 40 tok/s with `GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1`) because it
reads the logits back after every token. With a 256 MB BAR those sit in host-visible VRAM and the CPU reads them across
the link. Measured at 2.5 GT/s; not yet re-measured at 16 GT/s.

## Verify

```sh
boltctl list | grep -E 'status|rx speed'                      # authorized
grep -oE 'pci=noaer|amdgpu\.[a-z_]+=[^ ]*' /proc/cmdline
printf '%x\n' $(cat /sys/module/amdgpu/parameters/ppfeaturemask)  # fff7bffb
sudo dmesg | grep -c perm_failure                             # 0
# Link chain from the GPU to the root port: speed and error bits at each hop
G=$(lspci -D -d 1002:7551 | cut -d' ' -f1); p=$G
while :; do
  echo "$p $(sudo lspci -vvv -s $p | grep -m1 LnkSta: | xargs) | $(sudo lspci -vvv -s $p | grep -E 'UESta:|CESta:' | grep -oE '[A-Za-z]+\+' | tr '\n' ' ')"
  p=$(basename "$(dirname "$(readlink -f /sys/bus/pci/devices/$p)")"); case $p in pci*) break;; esac
done
```

## Undo

Restore a backed-up `/etc/default/limine` (or delete the lines) and run `sudo limine-update`. Delete
`/etc/udev/rules.d/89-igpu-symlink.rules`, `/etc/udev/rules.d/90-r9700-egpu-mrrs.rules` and
`~/.config/environment.d/90-hyprland-igpu.conf`. `sudo boltctl forget <dock-uuid>` removes the enrollment.

## Still open

- **Bug 3** above. Next: add these results to [#5100](https://gitlab.freedesktop.org/drm/amd/-/work_items/5100).
- **The same card on OcuLink** (DEG2 in OCuLink mode, or a DEG1), to see whether bug 3 needs Thunderbolt at all
  ([#5294](https://gitlab.freedesktop.org/drm/amd/-/work_items/5294) suggests not).
- **A Thunderbolt 5 Mac as host:** `system_profiler SPThunderboltDataType SPPCIDataType` lists the dock and the GPU's
  link speed even with no driver.
- **ROCm/HIP over Thunderbolt:** PCIe atomics usually aren't routed through USB4 bridges (`AtomicOpsCtl: ReqEn-`
  here). Untested.
- **The 256 MB BAR:** `amdgpu` tries to resize BAR 0 to 32 GB and fails (`failed to assign`).
- **The 20 Gb/s USB4 link** with an 80 Gbps cable.
