# K8 Plus as an eGPU compute host: BIOS, updates over SSH, Arc Pro B70 on OcuLink

**Machine:** GMKtec NucBox K8 Plus (see [k8-plus-setup.md](k8-plus-setup.md)), Ryzen 7 8845HS,
Omarchy 4.0.6 updated with `omarchy update`, kernel `7.2.8-9-omarchy`. Date: 2026-10-24.

**Goal:** a headless GPU compute box. One Intel Arc Pro B70 (32 GB) today, one AMD Radeon AI PRO R9700
(32 GB) from about 2026-10-28, both as external GPUs in Minisforum docks (DEG1 OcuLink, DEG2 USB4), each
with its own ATX PSU.

## BIOS: SMT was off, power mode was Quiet

Out of the box, Linux saw **8 threads** and `/sys/devices/system/cpu/smt/control` read `notsupported`.
That value means the firmware disabled SMT; Linux can't turn it back on. Two BIOS changes:

| Setting | Was | Now | Effect |
|---|---|---|---|
| SMT | Disabled | **Enabled** | 8 → **16 threads** |
| Power mode | Quiet | **Performance** | all-core ~4.4–4.5 GHz sustained (30 s, 16 threads), Tctl 86 °C; single core 5.1 GHz |

To get into setup without timing the Del key: `sudo systemctl reboot --firmware-setup`.

Retail listings give the three modes as **Silent 35 W, Balanced 54 W, Performance 65 W (70 W peak)**. The
8845HS is a 35–54 W part, so Performance is an unlocked mode above its standard range. These numbers are
from store listings; GMKtec's BIOS documentation wasn't checked.

### CPU frequency cap: 4.0 GHz

The BIOS stays on Performance, and a Linux frequency cap trims heat instead: no reboot, and it's adjustable.
Full load (16 busy threads, about 20 s each, a light background job also running):

| Cap | Avg all-core clock | Tctl | APU power (`amdgpu` `power1_input`) |
|---|---|---|---|
| none (5.1 GHz boost) | 4,416 MHz | 88 °C | ~45 W |
| **4.0 GHz** | 3,992 MHz (−10%) | **74 °C** | ~45 W |
| 3.5 GHz | 3,493 MHz (−21%) | 64 °C | ~34 W |

The power sensor is averaged and picks up the background job, so treat the watts as rough; temperature is
the cleaner signal. An earlier reading under moderate load, uncapped, showed 63 W. **4.0 GHz** is the
chosen cap: 14 °C cooler for about 10% less all-core clock.

- [`assets/k8-plus/cpu-freq-cap`](assets/k8-plus/cpu-freq-cap) writes `MAX_MHZ` (default 4000) to every
  core's `scaling_max_freq`.
- [`assets/k8-plus/cpu-freq-cap.service`](assets/k8-plus/cpu-freq-cap.service) is a oneshot at boot.

```sh
sudo install -Dm755 assets/k8-plus/cpu-freq-cap /usr/local/bin/cpu-freq-cap
sudo install -Dm644 assets/k8-plus/cpu-freq-cap.service /etc/systemd/system/cpu-freq-cap.service
sudo systemctl daemon-reload && sudo systemctl enable --now cpu-freq-cap
sudo MAX_MHZ=3500 /usr/local/bin/cpu-freq-cap     # try another value live (until reboot)
```

The BIOS power mode is the **ceiling**. The Omarchy power profile (`powerprofilesctl`) only decides how
eagerly the CPU uses that budget, so with the BIOS on Quiet, "performance" in Omarchy can't go past Quiet's cap.
`ryzenadj` can change the AMD limits live, but it's unofficial and the BIOS can reset it. Set the
ceiling in the BIOS and dial down from Omarchy.

## Wi-Fi: 5 GHz lost ~40% of packets

On the 5 GHz network the K8 dropped about 40% of packets. Another machine on the same router, on 2.4 GHz,
had 0% loss to the router and to the internet. Joining the **2.4 GHz** network fixed it, at about 8 MB/s.
The card is an Intel AX200, so this looks like signal strength (the desk has docks and PSUs around it), not
a driver bug. Long term the box should be on Ethernet; see the ARP flux note in
[k8-plus-setup.md](k8-plus-setup.md) before plugging a cable in with Wi-Fi up.

## Running `omarchy update` over SSH

A plain `sudo pacman -Syu` is refused by Omarchy's guard hook
(`/usr/share/libalpm/hooks/00-omarchy-update-guard.hook`, "Woah partner..."), and nothing is changed.
`omarchy update -y` is the supported path, but over a non-interactive SSH command it fails twice:

1. **`sudo -v` asks for a password** even with `NOPASSWD: ALL`. `omarchy-update-stay-awake` runs
   `sudo -v`, and by default `-v` needs *every* sudoers entry for the user to be passwordless. The
   stock `%wheel ALL=(ALL:ALL) ALL` isn't. Fix, in the same drop-in that grants NOPASSWD:

   ```sh
   # /etc/sudoers.d/<user>-nopasswd   (mode 440, check with: sudo visudo -cf <file>)
   Defaults:<user> verifypw=any
   <user> ALL=(ALL) NOPASSWD: ALL
   ```

   Passwordless sudo is a choice for a lab box on a home LAN. Remove the file to undo it.

2. **`OMARCHY_PATH: unbound variable`** in `omarchy-update-dev`. `~/.bashrc` sets it, but a
   non-interactive `ssh host 'cmd'` doesn't read `.bashrc`. Set it explicitly:

   ```sh
   ssh k8 'export OMARCHY_PATH=/usr/share/omarchy; omarchy update -y </dev/null'
   ```

## Intel compute stack

```sh
sudo pacman -S --needed intel-oneapi-dpcpp-cpp intel-compute-runtime intel-graphics-compiler \
  level-zero-loader level-zero-headers clinfo
```

Versions on 2026-10-24: DPC++ `2026.0.0_947`, compute-runtime `26.35.39758.10`, IGC `2.41.5`, Level Zero
`1.32.0`. oneAPI lives in `/opt/intel/oneapi`; run `source /opt/intel/oneapi/setvars.sh` before `sycl-ls`
or `icpx`.

## Arc Pro B70 on OcuLink: first light

Order: card in the DEG1, PSU 24-pin to the dock, PCIe power to the card, OcuLink cable to the K8 with the
K8 **off** (OcuLink isn't hot-pluggable). Then dock/PSU on, then the K8. Power down in the reverse order.

| Check | Result |
|---|---|
| Device | `Intel Corporation Battlemage G31 [Arc Pro B70] [8086:e223]`, driver `xe` |
| Link | root port `00:01.1` and the card's upstream port at **16 GT/s x4** (PCIe 4.0 x4, OcuLink's maximum) |
| BAR | **32 GB** (Resizable BAR works through the OcuLink root port) |
| SYCL | `[level_zero:gpu] Intel(R) Arc(TM) Pro B70 Graphics 20.2.0 [1.17.39758]` |
| OpenCL | `Intel(R) OpenCL Graphics (discrete)`, NEO 26.35 |

The GPU function itself (`03:00.0`) reports **2.5 GT/s x1**. That's normal for Arc: the card has an
internal PCIe switch, and the real link is on the switch's upstream port (`01:00.0`). Check that port, not the GPU:

```sh
for d in 0000:00:01.1 0000:01:00.0; do
  echo "$d $(cat /sys/bus/pci/devices/$d/current_link_speed) x$(cat /sys/bus/pci/devices/$d/current_link_width)"
done
sudo lspci -vv -s 03:00.0 | grep -A1 'Physical Resizable BAR'
```

## B70 power cap: 200 W

The card's default cap is **275 W** (`power1_cap` in the `xe` hwmon). Intel exposes no voltage control on
Linux, so "undervolting" means a power cap, the same approach as an `nvidia-smi -pl` cap. The cap is
**200 W** (first 225 W, lowered the same day to quiet the coil whine), set at boot by a small service:

- [`assets/k8-plus/b70-power-cap`](assets/k8-plus/b70-power-cap): finds every `xe` hwmon and writes
  `CAP_W` (default 200) to `power1_cap`.
- [`assets/k8-plus/b70-power-cap.service`](assets/k8-plus/b70-power-cap.service): oneshot at boot.
- [`assets/k8-plus/install-b70-power-cap.sh`](assets/k8-plus/install-b70-power-cap.sh): `sudo` from the
  repo root.

Readings at near-idle: about **40 W** card power (from `energy1_input` over 5 s), GPU 35 °C, VRAM 38 °C, fan
about 1,080 rpm. 40 W at idle is high. Arc cards are known for it when PCIe ASPM is off, which is common
behind OcuLink. Not investigated yet.

**For the R9700s** (300 W board power each), the plan is to start at about 250 W with `rocm-smi`. The
reason is the wall circuit, not the PSUs (each card has its own): a 15 A, 120 V circuit carries about
1,440 W continuous, and four cards at stock power plus the hosts can exceed that.

## Coil whine

Under load there's audible coil whine from the B70 or its PSU (source not isolated yet). High-power
GPUs and PSUs commonly whine under load; it's harmless, and the pitch follows the load. Things to try,
cheapest first:

1. Find the source: listen with the PSU and the card separated, or swap in another PSU.
2. A lower power cap (it's at 200 W now) often lowers or changes the pitch.
3. Distance: a closet, another room, or a rack.

The [SER8](ser8-coil-whine.md) and Zenbook A16 whine fixes were about idle power states (ASPM, C3). This
is load whine, so those levers don't apply.

## PCIe map: one free x4 port

`lspci -tv` on the K8 Plus:

| Root port | Link | Used by |
|---|---|---|
| `00:01.1` | x4 Gen4 | **free**: the OcuLink port (shares lanes with the second M.2 slot) |
| `00:01.3`, `00:02.1` | x1 | the two I226-V 2.5GbE |
| `00:02.2` | x1 (x2 max) | AX200 Wi-Fi |
| `00:02.5` | x4 Gen4 | boot NVMe |
| `00:03.1`, `00:04.1` | tunnels | two USB4 controllers |

So the K8 has **one direct-PCIe GPU slot (OcuLink) plus two USB4 ports**. The CPU (16 threads) can usefully
feed about two GPUs. Planned layout:

| Port | Card | Why |
|---|---|---|
| OcuLink (DEG1) | R9700 | ROCm wants PCIe atomics. Over a USB4 dock's bridge they're usually not routed, and USB4 hotplug also leaves a 32 GB card with a 256 MB BAR |
| USB4 (DEG2) | B70 | Level Zero doesn't need PCIe atomics |

## Verify

```sh
nproc                                                    # 16
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq # 4000000
cat /sys/devices/system/cpu/smt/control                  # on
source /opt/intel/oneapi/setvars.sh >/dev/null; sycl-ls  # level_zero:gpu ... Arc(TM) Pro B70
systemctl is-enabled b70-power-cap                       # enabled
for h in /sys/class/hwmon/hwmon*; do [ "$(cat $h/name)" = xe ] && cat $h/power1_cap; done   # 200000000
```

## Undo

```sh
sudo systemctl disable --now b70-power-cap cpu-freq-cap
sudo rm /etc/systemd/system/b70-power-cap.service /usr/local/bin/b70-power-cap \
  /etc/systemd/system/cpu-freq-cap.service /usr/local/bin/cpu-freq-cap
# power1_cap returns to 275 W and the CPU to 5.1 GHz boost on the next boot
sudo rm /etc/sudoers.d/<user>-nopasswd
# BIOS: SMT and power mode are changed back in setup
```
