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
- [`assets/k8-plus/cpu-freq-cap.service`](assets/k8-plus/cpu-freq-cap.service) is a oneshot at boot. Don't add
  `After=power-profiles-daemon.service`: that daemon is itself ordered after `multi-user.target`, so systemd
  finds an ordering cycle, drops the cap job at boot (`Found ordering cycle: cpu-freq-cap.service/start after
  power-profiles-daemon.service/start ...`), and the CPU silently boots uncapped. The daemon only changes
  EPP, not `scaling_max_freq`, so no ordering is needed.

**Later the same day the BIOS moved to Balanced too**, so a cap that fails to apply still can't exceed 54 W.
Full load with no background jobs:

| BIOS mode | CPU cap | Avg clock | Tctl | APU power |
|---|---|---|---|---|
| Balanced (54 W) | none | 4,217 MHz | 81–85 °C | ~53 W |
| **Balanced (54 W)** | **4.0 GHz** | **3,992 MHz** | **75 °C** | **~45 W** |

With the cap in place the BIOS mode barely matters (the cap holds the chip near 45 W, below either ceiling).
Balanced is kept as a firmware backstop.

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

**Update 2026-10-25: 5 GHz works now.** The saved 5 GHz profile was bound to an interface name from the
installer (`connection.interface-name wlp4s0`; the card is `wlp7s0` here), so NetworkManager refused it
("The interface names of the device and the connection didn't match"), and a fresh scan showed the 5 GHz network
at a *stronger* signal than 2.4 GHz (−56 vs −62 dBm). After rebinding:

```sh
nmcli con modify "<home-5GHz>" connection.interface-name wlp7s0 connection.autoconnect-priority 10
nmcli con modify "<home-2.4GHz>" connection.autoconnect-priority 0     # stays as the fallback
```

| | 2.4 GHz (ch 6, 20 MHz) | 5 GHz (ch 153, 80 MHz, 2×2) |
|---|---|---|
| Link rate | 144 / 130 Mbit/s | 351 / 234 Mbit/s |
| Loss to the router (50 pings) | — | 0% (avg 3.5 ms) |
| Download (Hugging Face) | ~4 MB/s | **~27 MB/s** |

The switch was done with a script under `systemd-run` that reverts to 2.4 GHz unless the router and the internet
answer on a 5 GHz link (`iw dev wlp7s0 link | grep "freq: 5"`), so a failed join can't strand a headless box. A
second way in, in case the Wi-Fi ever drops: ufw allows SSH on the direct cable to the DGX Spark from the Spark's
address only (`ufw allow in on eno1 from 10.77.0.1 to any port 22 proto tcp`), so `ssh -J <spark-wifi> k8` works.

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

> **Learned the hard way (2026-10-25):** switching the dock off while the K8 was running took the link down
> (`pciehp: Slot(0): Link Down`, `xe ... DC state mismatch`) and hung the K8. It was then powered off hard,
> and the btrfs **primary superblock** was lost. The next boots stopped at
> `A start job is running for /dev/mapper/root`, and the snapshot entries at
> `Failed to mount /dev/mapper/root` → emergency shell. Always `sudo poweroff` the K8 first, then the dock.
> See [Recovery: lost btrfs superblock](#recovery-lost-btrfs-superblock).

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

## Strata (local LLM) on the B70, and why OcuLink limits it

Set up 2026-10-25: [Strata](https://github.com/Niko1221/Strata) serving Qwen3.8-Flash-Next **IQ3_S** on the Arc
Pro B70 over OcuLink.

**Install gotchas, in order:**
- **The Terminal installer picks the wrong GPU.** `strata launch` detected the 780M iGPU (gfx1103) and asked for an
  AMD engine. `strata update --backend sycl` installs the Intel engine.
- **Intel needs the source/Docker route for the model.** `strata launch` reuses prepared files but won't prepare
  them on Intel. Strata's [Intel docs](https://github.com/Niko1221/Strata/blob/main/docs/INTEL.md):
  - add the user to the `docker` and `render` groups; `systemctl enable --now docker.socket`;
  - `docker build --pull -t strata-sycl-dev sycl/tools` (4 min here; the base is a community llama.cpp SYCL image);
  - build the engine with `AOT=bmg-g31` (6 min, no ocloc crash);
  - `./setup.sh --backend sycl --model IQ3_S --context 32768 --yes --no-start`.
- **The data folder must be under the container mount.** An earlier Terminal install had put
  `Strata-data` in `~/.local/share/strata`, so setup downloaded ~99 GB there and then stopped ("outside …, which the
  SYCL engine's container mounts"). Moving it under the checkout's parent (same disk, instant), linking the old
  path, and re-running with `--data-dir` skipped everything already done.
- **Setup misread the RAM as 1024 GB** and chose `--ple-io ram` (a 29 GB n-gram table kept in RAM). With the expert
  mirror that would overfill 64 GB. That arg was removed from `strata-iq3_s.json`; the table is read from the SSD.
- **The engine refused to start:** "2048 experts are neither in VRAM nor mirrored". `STRATA_MIRROR_MIB` defaults to
  *free* RAM minus 4 GiB, and most RAM was page cache after the download, so the mirror came out at ~21 GiB.
  `"env": {"STRATA_MIRROR_MIB": "26000"}` in the config fixed it: ready in ~45 s, 22 GiB of experts in VRAM, the rest
  in the pinned RAM mirror.

**Result: link-bound.**

| | B70 on OcuLink (K8) | RTX 4090 in its x16 slot (another PC) |
|---|---|---|
| Strata's PCIe probe, host → GPU | **7.0 GB/s** | 24.0 GB/s |
| Model | IQ3_S | IQ3_XXS |
| Decode (engine log, 300-token answers) | **19–27 tok/s** | ~50 tok/s |

GPU at 47 °C with the desk fans.

**Why:** the model doesn't fit in 32 GB, so about half its experts live in the RAM mirror and **the GPU reads the
ones each token needs across the link.** OcuLink is PCIe 4.0 ×4, about a third of an x16 slot. Strata's published
B70 numbers (30–41 tok/s for IQ3_S) were likely measured in an x16 slot.

**What follows for any eGPU here (the R9700s too):**
- A model that **fits in VRAM** doesn't care about the link.
- A model that doesn't is limited by it, and more so over Thunderbolt.
- Hosts with **unified memory** (Strix Halo, Apple Silicon) avoid this: the overflow is computed where it lives,
  at 256–800 GB/s, and only activations cross the link.
- Strata's AMD engine can also compute RAM experts on the CPU instead of pulling them over the link (it probes the
  link and sets `pcie_frac`, 0.19 here vs 0.55 default), so an R9700 on this port should do somewhat better than the
  B70, but the K8's DDR5 (~90 GB/s) is still far from a Strix Halo's 256 GB/s.

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

**Update 2026-10-27:** the first R9700 runs on **USB4 in a DEG2** (the DEG2's OcuLink mode needs a hidden switch).
`pci=noaer` and turning off amdgpu's PCIe DPM fixed the boot failure and the link; a hang when a new process starts on the
card is still open. Details in [r9700-egpu-thunderbolt.md](r9700-egpu-thunderbolt.md).

## Headless reboots: TPM2 auto-unlock of the LUKS root

Omarchy encrypts the root with LUKS and asks for the passphrase at every boot. Until it's typed, nothing on
the root runs: no Wi-Fi (iwd), no sshd, not even a ping reply. For a headless box that means a monitor and
keyboard after every reboot or power cut. (A keyboard alone is enough: the prompt is waiting, so the
passphrase can be typed blind.)

The fix is a TPM2 key in a second LUKS keyslot, which systemd unlocks in the initramfs. **The passphrase
keyslot stays**, and the prompt falls back to it if the TPM refuses (e.g. after a BIOS update changes PCR 7).

Omarchy's initramfs is busybox-based (`encrypt` hook, `cryptdevice=` on the command line), and TPM unlock needs
the systemd one. limine-mkinitcpio-hook ships systemd variants of everything Omarchy uses, including
`sd-btrfs-overlayfs` for snapshot boots.

1. **HOOKS**: a drop-in that sorts after `omarchy_*.conf`, so Omarchy's own files are untouched:
   [`assets/k8-plus/zz-tpm-unlock.conf`](assets/k8-plus/zz-tpm-unlock.conf) →
   `/etc/mkinitcpio.conf.d/zz-tpm-unlock.conf`. It drops `resume` (the systemd initramfs resumes on its own
   from the `resume=` that Omarchy already puts on the command line).
2. **Command line** in `/etc/default/limine` (back it up first): replace
   `cryptdevice=PARTUUID=<partuuid>:root` with
   `rd.luks.name=<luks-uuid>=root rd.luks.options=<luks-uuid>=tpm2-device=auto`
   (`sudo cryptsetup luksUUID /dev/nvme0n1p2` gives the LUKS UUID).
3. **Enroll** (asks for the current passphrase):
   `sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p2`.
   Test it without rebooting:
   `sudo cryptsetup open --test-passphrase --token-only /dev/nvme0n1p2` → `Key slot 1 unlocked`.
4. **Rebuild** the UKI: `sudo limine-update`. It has no `--help`, so running it with any argument (or
   without root) starts a build. Without root it can't write `/boot`, so nothing changes.
5. **Inspect** the new UKI before trusting it:

   ```sh
   d=$(mktemp -d)
   sudo objcopy -O binary --only-section=.cmdline /boot/EFI/Linux/omarchy_linux-omarchy.efi $d/cmdline
   sudo objcopy -O binary --only-section=.initrd  /boot/EFI/Linux/omarchy_linux-omarchy.efi $d/initrd
   sudo chmod 644 $d/*; tr -d '\0' < $d/cmdline; echo
   lsinitcpio $d/initrd | grep -E 'systemd-cryptsetup|token-systemd-tpm2|libtss2-esys|plymouthd|overlayfs-setup'
   ```

   `btrfs.ko` won't be listed: it's built into `linux-omarchy` (`modules.builtin`).

**Status: rolled back 2026-10-26; the K8 asks for the passphrase again.** The first reboot after this setup
came after the dock incident above, so it never got a clean test: the boot hung at the unlock step, and the
lost superblock may or may not explain all of it. With TPM unlock and a broken root filesystem
mixed together, the plain passphrase boot was the safer default. The rollback restored
`/etc/default/limine.bak.<timestamp>`, moved `zz-tpm-unlock.conf` aside, ran `sudo limine-update`, and removed
the TPM token and its keyslot (`cryptsetup token remove --token-id 0`, `cryptsetup luksKillSlot <dev> 1`) after
a `luksHeaderBackup`. To retry, redo steps 1–5 and watch the first boot with a monitor attached.

The original note: the first reboot should be watched. If it fails, type the passphrase at the prompt, or boot a snapshot from the Limine menu,
restore `/etc/default/limine.bak.<timestamp>`, delete `zz-tpm-unlock.conf`, and run `sudo limine-update`.

PCR 7 is the Secure Boot state, so kernel and initramfs updates don't break the seal. BIOS updates or Secure
Boot changes can, and then it's the passphrase once, followed by
`sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p2`.

**Trade-off:** a drive removed from the box stays encrypted, but the whole box boots to the login screen on its
own. Login, sudo and key-only SSH still protect it.

Also worth setting in the BIOS: **restore on AC power loss → Power On**, so it comes back after an outage.

## Recovery: lost btrfs superblock

Symptom: the LUKS passphrase is accepted, then `Failed to mount /dev/mapper/root` and an emergency shell
(or a systemd boot waiting forever on `/dev/mapper/root`). btrfs keeps two backup superblocks, at 64 MiB and
256 GiB, so this is usually a 10-minute fix. Everything below runs in the initramfs emergency shell (boot any
Limine entry; the standard Omarchy image includes `cryptsetup` and `btrfs`).

```sh
cryptsetup open /dev/nvme0n1p2 root      # if /dev/mapper/root isn't there yet
blkid /dev/mapper/root                    # prints nothing → no filesystem recognized
# Read-only diagnosis: the volume start should be zeros (decryption is fine),
# the primary superblock (64 KiB) lacks _BHRfS_M, the backup (64 MiB) has it.
dd if=/dev/mapper/root bs=4096 count=1 2>/dev/null | hexdump -C | head -4
dd if=/dev/mapper/root bs=4096 skip=16 count=1 2>/dev/null | hexdump -C | head -6
dd if=/dev/mapper/root bs=4096 skip=16384 count=1 2>/dev/null | hexdump -C | head -6
# Fix: copies a verified backup over the bad copy (asks before writing)
btrfs rescue super-recover -v /dev/mapper/root
mount -t btrfs -o subvol=@ /dev/mapper/root /new_root
exit                                      # boot continues into the real system
```

Afterwards, from the running system: `sudo btrfs inspect-internal dump-super -a /dev/mapper/root` (all three
copies `[match]`), `sudo btrfs device stats /` (all 0), `sudo btrfs scrub start -B /` (on 2026-10-26: 178 GiB in
36 s, no errors). Don't reach for `btrfs check --repair` or `mkfs`: they can destroy what's still intact.

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
# TPM unlock: restore /etc/default/limine.bak.<ts>, remove /etc/mkinitcpio.conf.d/zz-tpm-unlock.conf,
# sudo limine-update, then sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p2
# BIOS: SMT and power mode are changed back in setup
```
