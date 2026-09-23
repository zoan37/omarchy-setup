# ASUS Zephyrus M16 (GU603ZW): quiet fans, low power, no desktop lag

Set up **2026-09-20**, with one fix on **2026-09-22** so the setup survives a reboot. Result: at idle the
fans stay at **0 RPM** and the CPU package sits at about **35–37°C** (ambient
and workload not controlled). Before the changes, fans were audible on AC
and the NVIDIA dGPU drew about 11 W at idle. Single-core boost still reaches
**4.7 GHz**, so the 165 Hz desktop stays smooth.

These are temperature and RPM readings plus the owner's subjective
confirmation, not decibel or wall-power measurements.

## Exact machine and software

| Item | Verified configuration |
|---|---|
| Machine | ASUS ROG Zephyrus M16 `GU603ZW_GU603ZW` |
| BIOS | `GU603ZW.308`, dated 2022-06-01 |
| CPU | Intel Core i9-12900H (14 cores / 20 threads), `intel_pstate` active |
| GPUs | Intel Iris Xe (Alder Lake-P) + NVIDIA RTX 3070 Ti Laptop, hybrid via supergfxd |
| Display | BOE eDP-2, 2560x1600@165 Hz, scale 1.6 (stock `auto`), VRR-capable but off |
| Omarchy / kernel | 4.0.4 (fresh Quattro install) / `7.2.5-3-omarchy` |
| Hyprland | 0.56.2, Lua config |
| `asusctl` | 6.4.0-2 |
| `supergfxctl` | 5.2.7-2 |
| `power-profiles-daemon` | 0.30-1 |

Identify with `cat /sys/class/dmi/id/product_name`. Everything below is
specific to this laptop's asusd/supergfxd stack. None of it applies to the Dell or
SER8 machines.

`asusctl` talks to `asusd` over D-Bus and needs **no sudo**. Root edits use
`pkexec` (graphical password prompt).

## Summary of what's set

| Knob | Setting | Where it lives |
|---|---|---|
| ASUS platform profile | **Quiet** on AC and battery | `/etc/asusd/asusd.ron` |
| Omarchy power profile | `power-saver` on AC and battery | `~/.local/state/omarchy/powerprofiles/{ac,battery}` |
| CPU EPP | `balance_performance` (via asusd link) | `asusd.ron` + PPD drop-in |
| Quiet fan curve | 0% below 58°C, 45% at 85°C | `/etc/asusd/fan_curves.ron` |
| GPU mode | **Integrated** (dGPU powered off) | `/etc/supergfxd.conf` |
| BIOS boot sound | off | `asusd.ron` → `armoury_settings` |
| Keyboard | static warm white `ffd9b0`, Med | `/etc/asusd/aura_19b6.ron` |
| Battery charge limit | **80%** (set 2026-09-22) | `asusd.ron` → `charge_control_end_threshold` |
| Refresh rate | **165 Hz, kept on purpose** | stock |

Copies of `asusd.ron`, `fan_curves.ron`, `supergfxd.conf`, and the PPD drop-in are in [`assets/zephyrus-m16/`](assets/zephyrus-m16/).

## 1. Quiet platform profile everywhere

By default, asusd switches to Performance on AC, which is what made the fans loud.
Set Quiet for both power sources:

```sh
asusctl profile set Quiet          # current
asusctl profile get                # expect: AC profile Quiet / Battery profile Quiet
```

If `get` still shows Performance for AC, set `platform_profile_on_ac: Quiet` in
`/etc/asusd/asusd.ron` and restart `asusd`.

**Omarchy gotcha:** Omarchy runs its own power-profile layer at login
(`omarchy powerprofiles init`). It defaults to **performance on AC** when no
preference is saved, and that overrides asusd. Persist through Omarchy:

```sh
omarchy powerprofiles set ac power-saver
omarchy powerprofiles set battery power-saver
cat ~/.local/state/omarchy/powerprofiles/{ac,battery}   # both: power-saver
```

This is the same trap as on the SER8 ([ser8-quiet-fan.md](ser8-quiet-fan.md)).
`powerprofilesctl set` alone does not survive login.

## 2. Keep boost in Quiet mode, or the whole desktop gets janky

**Symptom:** under any concurrent load (Chrome, a terminal streaming output), scrolling
and animations at 165 Hz stutter. A pure busy loop only reached **~1.66–2.2
GHz**. The chip can reach 4.7+.

**Cause:** Energy Performance Preference (EPP) `power`. It came from two
sources:

1. asusd's default link maps Quiet → `Power` and Balanced → `BalancePower`.
2. **power-profiles-daemon's `power-saver` also writes EPP `power`**, and it
   runs *after* asusd at boot. It silently undid fix #1 on the first reboot.
   Found 2026-09-22.

Note that the Quiet profile's 45/65 W package limits and the fan curve are what keep
this laptop quiet. A low EPP only slows the CPU down, and slow work also keeps the
CPU awake longer, so it doesn't save much power either.

**Fix, part 1:** in `/etc/asusd/asusd.ron` (backup first):

```ron
    platform_profile_linked_epp: true,
    profile_quiet_epp: BalancePerformance,
    profile_balanced_epp: BalancePerformance,
```

**Fix, part 2:** stop PPD from driving the CPU. PPD 0.30 has a `--block-driver`
flag, so it keeps controlling the ASUS platform profile but leaves EPP to asusd:

```sh
# /etc/systemd/system/power-profiles-daemon.service.d/no-cpu-epp.conf
[Service]
ExecStart=
ExecStart=/usr/lib/power-profiles-daemon --block-driver=intel_pstate
```

```sh
pkexec sh -c 'systemctl daemon-reload && systemctl restart power-profiles-daemon && systemctl restart asusd'
```

**Verify** after a reboot, not only right after the change. The regression only
appeared after a reboot:

```sh
powerprofilesctl list | head -4        # performance: shows PlatformDriver only, no CpuDriver
cat /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference | sort | uniq -c
                                       # expect: 20 balance_performance
timeout 4 sh -c 'while :; do :; done' & sleep 3; grep MHz /proc/cpuinfo | sort -k4 -n | tail -1
                                       # expect ~4700 (was ~1660 with EPP=power)
```

With this in place, idle stayed at 37°C with fans at 0 RPM.

**Revert:** delete the drop-in, `daemon-reload`, and restart PPD. Restore
`/etc/asusd/asusd.ron.bak.epp` for the asusd side.

**Dead ends from the lag chase (2026-09-20, Codex session).** None of these helped, so
don't chase them again: disabling turbo (still choppy), switching to Balanced,
removing Chrome's Vulkan flags, disabling hypr-momentum (worse). Lowering the
refresh rate was declined. The EPP fix above is what fixed it.

## 3. Quiet fan curve

The stock Quiet curve still spins up at idle-ish temperatures. Custom curve, same for
both fans:

```sh
asusctl fan-curve --mod-profile quiet --fan cpu --data 40c:0%,50c:0%,58c:0%,62c:5%,66c:13%,70c:22%,75c:30%,85c:45%
asusctl fan-curve --mod-profile quiet --fan gpu --data 40c:0%,50c:0%,58c:0%,62c:5%,66c:13%,70c:22%,75c:30%,85c:45%
asusctl fan-curve --mod-profile quiet --enable-fan-curves true
asusctl fan-curve --mod-profile quiet  # show
```

These values are stored in `/etc/asusd/fan_curves.ron` as PWM out of 255: `(0, 0, 0, 13, 33, 56, 77, 115)`
at `(40, 50, 58, 62, 66, 70, 75, 85)`°C. Balanced and Performance curves are
left at firmware defaults (disabled).

The curve's behavior under long sustained load hasn't been evaluated. The Quiet
profile's power limits cap how hot it can get, but keep an eye on it during
long compiles. **Revert:** `asusctl fan-curve --default` while in Quiet.

## 4. Integrated-only GPU

In hybrid mode, the RTX 3070 Ti **never runtime-suspends**. Hyprland and Chrome
keep `/dev/nvidia0` open, which costs about 11 W at idle. Switch the dGPU off entirely:

```sh
omarchy toggle hybrid gpu    # needs sudo + reboot
supergfxctl -g               # after reboot: Integrated
```

Idle package temperature went from about 58°C to 51°C at the time of the switch, with fans
at 0 RPM. The script also adds
`/etc/systemd/system/supergfxd.service.d/delay-start.conf` (a 5 s sleep to
avoid a boot freeze in Integrated mode). Leave it.

**Tradeoff:** the HDMI port is wired to the NVIDIA GPU, so external HDMI very
likely **doesn't work** in Integrated mode (not tested). No CUDA and no dGPU
gaming either. Run `omarchy toggle hybrid gpu` again and reboot to switch back.

## 5. Small stuff

```sh
asusctl armoury set BootSound 0                 # no POST chime (stored in asusd.ron)
asusctl aura static -c ffd9b0                   # warm white, not RGB
asusctl leds set med
asusctl battery limit 80                        # mostly on AC; stored in asusd.ron
```

**Why 80%:** this laptop is mostly plugged in. A lithium battery held at 100%
ages faster, and heat speeds that up. The temperature benefit is small: at the
limit, the charger stops charging and the machine runs on wall power. Near full, the battery
would otherwise keep topping itself off, which adds a little heat inside the chassis next to the
CPU. Don't expect a noticeable temperature drop; the main gain is battery lifespan.
Cost: about 20% less runtime unplugged. Before a trip, run `asusctl battery limit 100`.

## Chrome on this machine

`~/.config/chrome-flags.conf` currently has **VA-API only**. The Codex lag
session removed the `Vulkan,DefaultANGLEVulkan,VulkanFromANGLE` features, and
that didn't change the lag. Backup: `~/.config/chrome-flags.conf.bak.20260920-030402`.
Now that the real cause (EPP) is fixed, the Vulkan flags from the
[new machine checklist](new-machine-checklist.md) could be restored, but that
hasn't been re-tested here. `intel-media-driver` is installed.

Chrome is the main remaining heat source: one busy tab can hold a whole core.
Use Chrome's Task Manager (Shift+Esc) to find it, the same lesson as
[xps16-fan-spins-up-on-video.md](xps16-fan-spins-up-on-video.md).

## Not done / possible next steps

- **VRR.** The panel is VRR-capable, but VRR is off. It might save a little at idle; not
  tried.
- `intel_lpmd` is running with stock config (low-power mode forced off for
  the Balanced/Power-saver PPD profiles). Left unchanged.

## Post-update checks

Everything lives in `/etc` or user state and is not package-owned
(`pacman -Qo` finds no owner for `asusd.ron` or `supergfxd.conf`). An update
should leave it alone, but a new PPD or asusd version could change behavior.
After updates, run the three **Verify** commands from section 2, plus:

```sh
asusctl profile get; supergfxctl -g; sensors | grep -E 'Package|fan'
```
