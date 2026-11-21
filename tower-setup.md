# 4× R9700 tower: setup, burn-in and power limits

Set up **2026-11-14** on Omarchy 4.5.0, kernel `7.2.15-1-omarchy`. ASRock WRX90 WS EVO
(BIOS 12.09), AMD Threadripper PRO 9955WX (16 cores), 128 GB RAM, 2× Samsung 9100 PRO
2 TB, **4× ASRock Radeon AI PRO R9700 32 GB** (blower cards, gfx1201), ASRock PG-1600G
1600 W PSU, Intel X710 dual 10GBASE-T (not cabled yet), ASPEED BMC. Wi-Fi through a USB
MT7921U adapter. Noctua CPU cooler blowing up; front fans intake, top and rear exhaust.

Hostname `tower`. Desktop config was copied from the [EVO X3](evo-x3-setup.md), whose tweaks
are the [new machine checklist](new-machine-checklist.md) ones.

## Checks at first boot

- All four cards at **PCIe 5.0 x16** (`current_link_speed` 32.0 GT/s, width 16).
- Genuine cards: PCI ID `1002:7551` (Navi 48), subsystem vendor `1849` (ASRock), 32 GB
  each. Worth checking: one Amazon "R9700" delivered the same week had a cheaper card
  inside the box.
- The boot log says the firmware does not hand AER to Linux on this board (`_OSC: platform
  does not support [AER LTR DPC]`), so PCIe errors would not be logged. A load test is the
  way to find a bad slot or card.
- **Idle cards runtime-suspend.** Their sensors read 0 and `power1_cap` returns EBUSY until
  woken: `echo on | sudo tee /sys/bus/pci/devices/<card>/power/control`.

## Packages

```sh
sudo pacman -Sy
sudo pacman -S --needed rocminfo amdsmi rocm-smi-lib python-pytorch-rocm vulkan-tools nvtop btop \
  ghostty syncthing cmake hyprpm github-cli
```

That pulls ROCm 7.2 and PyTorch 2.14 (8.7 GB download, 35 GB installed). Tools land in
`/opt/rocm/bin` (not on `PATH`). `rocminfo` lists four `gfx1201` "AMD Radeon AI PRO R9700"
agents; `torch.cuda.device_count()` is 4. Torch's device order is not PCI order (device 0
was `f3:00.0`).

## Burn-in

Scripts in [assets/tower/](assets/tower/), run as the user (ROCm needs no root):

- `gpu_burn.py --gpu N --minutes M --vram-passes P`: fills ~30 GiB of the card's VRAM with
  index-derived patterns and verifies them, then runs sustained 8192² bf16 GEMMs while a
  fixed fp32 GEMM is recomputed every 10 s and compared bit-for-bit with its first result.
- `gpu_monitor.py OUT.csv 5`: logs edge, **junction (hotspot)**, memory temperature, power,
  cap, fan, busy %, clocks, PCIe link and CPU Tctl every 5 s from sysfs (run with sudo; it
  wakes suspended cards).
- `summarize.py monitor.csv run.log`: per-card averages and maxima for each test window.

Results (room ~20 °C, case closed):

| Test | Per card | Hotspot | VRAM | Hotspot − edge | Fans | Errors |
|---|---|---|---|---|---|---|
| Each card alone, 300 W, 4 min | ~117 TFLOPS | 89-92 °C | 74-80 °C | 24-35 °C | 3,100-3,400 rpm | 0 |
| All four, 300 W, 13 min (then the breaker tripped) | ~117 TFLOPS | 93-94 °C | 78-86 °C | | ~3,600 rpm | 0 |
| **All four, 210 W, 15 min** | **88-93 TFLOPS** | **82-84 °C** | **73-82 °C** | 13-22 °C | 2,300-2,600 rpm | 0 |

One card has a larger hotspot-to-edge gap than the others (34-35 °C against 24-28 °C) but the
same hotspot once the case is warm: its edge sensor reads low. Reddit's "one hot card"
reports are a hotspot well above its siblings, usually 40 °C+ above edge.

## Power: the breaker tripped

With all four cards at the stock 300 W and the CPU boosting, the tower drew roughly
**1,600 W from the wall** and tripped a 15 A circuit that also had a laptop charger on it
(the breaker showed an orange flag; reset it fully OFF, then ON). The logs show a clean power
cut: no GPU errors, nothing thermal.

Rough draw at the wall:

| State | Draw |
|---|---|
| Idle | ~200-250 W |
| LLM, layers split across cards | ~500-700 W |
| All four busy, 300 W cap | ~1,450-1,600 W |
| All four busy, **210 W cap, CPU boost off** | **~1,050-1,100 W** |

A 15 A / 120 V circuit trips at 1,800 W and should carry at most 1,440 W for hours. So the
tower now runs capped, on a circuit with nothing else heavy, plugged into the wall or a 15 A
strip, not a splitter.

### GPU power cap (210 W, the minimum the cards accept; stock 300 W)

```sh
sudo install -Dm755 assets/tower/tower-gpu-power-cap /usr/local/bin/tower-gpu-power-cap
sudo install -Dm644 assets/tower/tower-gpu-power-cap.service /etc/systemd/system/tower-gpu-power-cap.service
sudo systemctl daemon-reload && sudo systemctl enable --now tower-gpu-power-cap
```

`sudo tower-gpu-power-cap 250` sets any value from 210 to 300 W for the session; `off` restores
300 W. The cap survives the cards runtime-suspending and resuming (checked).

**Boot race (fixed 2026-11-15):** on the first real boot the service ran before amdgpu had probed the
cards (the driver came up only after the disk was unlocked), found nothing, and exited cleanly, so the
cards stayed at 300 W. The script now waits up to 3 minutes for all four cards (`TOWER_GPUS`, default 4).
After a reboot, check that `journalctl -u tower-gpu-power-cap -b` lists four `cap 210 W` lines.

### CPU boost off (4.5 GHz base instead of 5.45 GHz)

```sh
sudo install -Dm755 assets/tower/tower-cpu-boost /usr/local/bin/tower-cpu-boost
sudo install -Dm644 assets/tower/tower-cpu-boost-off.service /etc/systemd/system/tower-cpu-boost-off.service
sudo systemctl daemon-reload && sudo systemctl enable --now tower-cpu-boost-off
```

During the 300 W test, eight busy-waiting threads on one CCD pushed Tctl to 92 °C (the other
CCD sat at 34 °C). With boost off, the same test ran the CPU at ~60 °C. The power profile
(`amd-pstate-epp`) is still `performance`. AMD's RAPL limits can't be written from Linux;
a hard package limit would have to be set in the BIOS (PPT / cTDP).

## Desktop and SSH

Copied from the X3 (each replaced file has a `.bak.<timestamp>`): the Alt/Super swap,
border resize, group tab reorder and screenshot binds, `hyprpm reload -n` at startup, the
clock format, Ghostty as default terminal at 11 pt with Ctrl+Enter as CSI-u, the Vulkan and
VA-API Chrome flags, and `cleanupPeriodDays` for Claude Code. Also: syncthing (user service,
ufw open), Avahi kept off `docker0`, and the [clock refresh hook](bar-clock-stale-after-resume.md).

SSH was already on, key-only, with ufw rules for both home networks (`192.168.0.0/24` and
`192.168.1.0/24`). The tower is in `lan-connect.sh` (see [lan-ssh-self-healing.md](lan-ssh-self-healing.md)).

**Passwordless sudo:** `omarchy-sudo-passwordless` is temporary by design (it adds
`/etc/sudoers.d/99-omarchy-nopasswd-<uid>` plus a transient timer that removes it). For a machine run over
SSH, add a permanent rule instead, from another machine, typing the password once:

```sh
ssh -t tower 'echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/zz-nopasswd >/dev/null && sudo chmod 440 /etc/sudoers.d/zz-nopasswd && sudo visudo -c'
```

It survives reboots (checked). Anyone with the SSH key then has root, so keep SSH key-only and LAN-scoped.

**Not fully headless:** the disk is LUKS-encrypted (Omarchy's default), so every reboot stops at the
passphrase prompt until someone types it at the tower. Options for later: TPM2 auto-unlock
(`systemd-cryptenroll`; needs the initramfs to use the systemd hooks), or the BMC's remote console once
its network port is cabled.

## Not done

- `gh auth login` and `hyprpm update` + hypr-tab-drag need a terminal on the tower itself.
- Wi-Fi dropped every ~30 h and a USB replug hung: an mt76 bug on kernel 7.2.15, see
  [tower-wifi-mt7921u-wedge.md](tower-wifi-mt7921u-wedge.md) (patched modules installed 2026-11-21; remove at kernel ≥ 7.3.4).
- The Wi-Fi is weak (−70 dBm, one spatial stream, ~9 MB/s from the package mirror) because the
  router is outside the house. A USB extension cable moves the adapter out of the GPU exhaust
  and toward a window; the 10 GbE port to the switch is the real fix for copies between machines.
- No model engine yet (llama.cpp / vLLM on ROCm).

## Verify

```sh
for h in /sys/class/drm/card*/device/hwmon/hwmon*; do cat $h/power1_cap; done   # 210000000 each (wake cards first)
cat /sys/devices/system/cpu/cpufreq/boost                                         # 0
systemctl is-enabled tower-gpu-power-cap tower-cpu-boost-off                      # enabled enabled
/opt/rocm/bin/rocminfo | grep -c gfx1201                                          # 4
```
