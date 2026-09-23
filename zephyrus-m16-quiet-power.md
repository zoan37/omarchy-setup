# ASUS Zephyrus M16 (GU603ZW): quiet fans, low power, no desktop lag

Set up **2026-09-20**, with further tuning through **2026-09-23**. The current baseline uses
both fans **off through the 66°C curve point**, rising to 10% at 70°C, a **3.8 GHz**
CPU cap, and a **165 Hz** desktop with VRR. The September 23 five-minute trial averaged
55°C with both fans off in ~87% of measured samples; heavier activity still triggered
brief fan ramps and temperature spikes. See section 9 for the measurements and tradeoff. Earlier fans-off and 4.7 GHz results
below describe previous configurations. Before the changes, fans were audible on AC
and the NVIDIA dGPU drew about 11 W at idle.

These are temperature and RPM readings plus the owner's subjective
confirmation, not decibel or wall-power measurements.

## Exact machine and software

| Item | Verified configuration |
|---|---|
| Machine | ASUS ROG Zephyrus M16 `GU603ZW_GU603ZW` |
| BIOS | `GU603ZW.311`, dated 2022-12-22 (released 2023-02-17, latest; flashed 2026-09-22 from 308 via EZ Flash) |
| CPU | Intel Core i9-12900H (14 cores / 20 threads), `intel_pstate` active |
| GPUs | Intel Iris Xe (Alder Lake-P) + NVIDIA RTX 3070 Ti Laptop, Integrated mode via supergfxd (NVIDIA powered off) |
| Display | BOE eDP-2, 2560x1600@165 Hz, scale 1.6 (stock `auto`), VRR on |
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
| Quiet fan curve | **Both fans 0 PWM through 66°C**, 10% at 70°C, 30% at 80°C, 45% at 90°C; occasional ramps under load | `/etc/asusd/fan_curves.ron` |
| Fan-curve guard | re-applies the curve if the EC drops to firmware mode | `zephyrus-fan-curve-guard.timer` |
| CPU power cap | **30 W sustained / 35 W burst** (was 60 / 135) | `asusd.ron` → `ac/dc_profile_tunings.Quiet` |
| GPU mode | **Integrated** (dGPU powered off) | `/etc/supergfxd.conf` |
| BIOS boot sound | off | `asusd.ron` → `armoury_settings` |
| Keyboard | static warm white `ffd9b0`, Med | `/etc/asusd/aura_19b6.ron` |
| Battery charge limit | **80%** (set 2026-09-22) | `asusd.ron` → `charge_control_end_threshold` |
| CPU idle states | **C8 + C10 disabled** (less coil whine) | `zephyrus-no-deep-cstates.service` |
| Refresh rate | **165 Hz, kept on purpose**, with **VRR on** | `~/.config/hypr/looknfeel.lua` (`misc.vrr = 1`) |
| CPU max clock | **3.8 GHz cap** (was 5.0 GHz boost) | `zephyrus-cpu-freq-cap.service` |
| Panel overdrive | **off** | `asusd.ron` → `armoury_settings.PanelOverdrive` |

Copies of `asusd.ron`, `fan_curves.ron`, `supergfxd.conf`, the PPD drop-in, and the C-state, fan-guard, and clock-cap scripts + units are in [`assets/zephyrus-m16/`](assets/zephyrus-m16/).

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

Note that the power cap (section 7) and the fan curve are what keep this laptop
quiet. A low EPP only slows the CPU down, and slow work also keeps the
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
                                       # expect up to ~3800 with the section 8 cap (was ~1660 with EPP=power)
```

With this in place, idle stayed at 37°C with fans at 0 RPM.

**Revert:** delete the drop-in, `daemon-reload`, and restart PPD. Restore
`/etc/asusd/asusd.ron.bak.epp` for the asusd side.

**Dead ends from the lag chase (2026-09-20, Codex session).** None of these helped, so
don't chase them again: disabling turbo (still choppy), switching to Balanced,
removing Chrome's Vulkan flags, disabling hypr-momentum (worse). Lowering the
refresh rate was declined. The EPP fix above is what fixed it.

## 3. Quiet fan curve

**Previous curve (2026-09-22, evening): a constant low baseline instead of fans-off.**
Replaced by the September 23 fans-off retry in section 9. The commands here are retained
as the alternative for a steady hum instead of occasional ramps. Even with the
66°C start below, the fans still briefly spun up whenever a busy Chrome tab pushed the
package from ~60–64°C past the threshold. Since the fans were off, heat built up in the chassis and
kept the resting temperature near the start point. **The EC has a hardware minimum
speed:** 3%, 5%, 7% and 10% PWM all ran at **~2,000–2,200 RPM** (the same
speed as the bursts), so there is no whisper-quiet in-between. A steady hum is less
noticeable than start/stop bursts at the same speed, and it keeps the chip cooler (57 → 53–55°C) and the
keyboard deck cooler:

**Baseline on the CPU fan only.** With both fans at the baseline, the CPU fan held 2,000 RPM
but the GPU fan hunted between 1,900 and 2,100 RPM in a ~4 s cycle, right at the bottom of its range. The two
slightly different speeds beat against each other, making an audible oscillating "wah-wah". The dGPU
is off and both fans share the heat pipes, so the GPU fan now stays off until 66°C and
joins at the ramp:

```sh
asusctl fan-curve --mod-profile quiet --fan cpu --data 30c:7%,40c:7%,50c:7%,60c:7%,66c:7%,70c:10%,80c:30%,90c:45%   # stored as 18/255
asusctl fan-curve --mod-profile quiet --fan gpu --data 30c:0%,40c:0%,50c:0%,60c:0%,66c:0%,70c:10%,80c:30%,90c:45%
asusctl fan-curve --mod-profile quiet --enable-fan-curves true
```

Stored at `(30, 40, 50, 60, 66, 70, 80, 90)`°C as PWM CPU `(18, 18, 18, 18, 18, 26, 77, 115)` and
GPU `(0, 0, 0, 0, 0, 26, 77, 115)`. The package sits at ~50°C, the same as with both fans running.

**A single fan still wobbles a little, and the curve can't fix it.** With temperature flat at 47–50°C,
the CPU fan alone also cycles ~1,900–2,100 RPM about every 4 s, which is audible as a slow rise and fall.
Stepping the baseline through 20/28/36/45/55 PWM (7–21%) gave a ~200 RPM swing at every level
(2,000–2,100 at 20 was a lucky 15 s sample; a longer sample at 18 read 1,900–2,200).
It's the EC's own closed-loop RPM control. Linux only gets the curve and
`pwm1_enable` 0/2 (full/auto) on `asus-nb-wmi`, with no direct duty control, so nothing
from Linux removes it. A higher baseline only adds loudness. Kept at 18/255 (lowest
reliable). The alternative is the fans-off curve below: silence plus occasional bursts.
(5% rather than 3% so the fan reliably starts; both sound the same.) To go back to silence
with occasional bursts, use the fans-off curve below.

### Previous curves

The stock Quiet curve spins the fans up at idle-ish temperatures. The first custom curve
(2026-09-20) started at 58°C, but at light use the package sits at **55–58°C**, and
whenever a single core boosts to 4.4–4.9 GHz it spikes to 65–79°C for a split second
**even at ~12 W** (that core's high voltage, not total power). The fans answered every
spike, so they spun up briefly while scrolling X or playing YouTube. Since the power cap (section 7) keeps
sustained temperatures low, the curve now waits until 66°C (2026-09-22). Same
curve for both fans:

```sh
C=40c:0%,50c:0%,60c:0%,66c:0%,70c:10%,75c:20%,80c:30%,90c:45%
asusctl fan-curve --mod-profile quiet --fan cpu --data $C
asusctl fan-curve --mod-profile quiet --fan gpu --data $C
asusctl fan-curve --mod-profile quiet --enable-fan-curves true
```

`fan_curves.ron` stores this as PWM out of 255: `(0, 0, 0, 0, 26, 51, 77, 115)` at
`(40, 50, 60, 66, 70, 75, 80, 90)`°C. The Balanced and Performance curves stay at firmware
defaults (disabled).

**Measured (45 s of scrolling X, then YouTube, sampled every 0.5 s):**

| Setup | Avg pkg power | Peak | Peak temp | Fan running |
|---|---|---|---|---|
| 58°C curve, 60/135 W limits | 13.1 W | 49.5 W | 73°C | 43 of 90 samples |
| 58°C curve, 30/35 W cap | 12.1 W | 38.8 W | 73°C | 38 of 90 |
| **66°C curve, 30/35 W cap** | **9.9 W** | 24.4 W | 79°C (single blip) | **0 of 90** |

**Under sustained load** (all 20 threads for 60 s): fans stayed off until about 70°C at
~30 s, then held **70–71°C** at ~3,000 RPM, and switched off ~20 s after the load ended.

**Check the hardware, not asusctl.** The EC sometimes silently drops back to its
firmware curve (`pwm*_enable=2`) while `asusctl` still reports the custom curve as
enabled. It happened after the BIOS flash and after every `systemctl restart asusd`,
even though asusd logs that it wrote the curve. When it happens, the stock curve
spins up at 55°C.

```sh
h=$(dirname "$(grep -l asus_custom_fan_curve /sys/class/hwmon/hwmon*/name)")
cat $h/pwm1_enable $h/pwm2_enable            # expect 1 1 (2 = firmware curve)
paste $h/pwm1_auto_point{1..8}_temp          # expect 30 40 50 60 66 70 80 90
```

**Guard:** `zephyrus-fan-curve-guard.timer` runs every 30 s (first run 20 s after
boot). While the platform profile is `quiet` and either fan reads `pwm_enable != 1`,
it switches the curve off and on with `asusctl`, which makes asusd write it
again. It logs only when it fixes something (`journalctl -u zephyrus-fan-curve-guard`).
Verified: it caught and repaired the reset after an asusd restart.

```sh
sudo install -m 755 assets/zephyrus-m16/zephyrus-fan-curve-guard /usr/local/bin/
sudo install -m 644 assets/zephyrus-m16/zephyrus-fan-curve-guard.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now zephyrus-fan-curve-guard.timer
```

**Revert:** `asusctl fan-curve --default` while in Quiet, and
`sudo systemctl disable --now zephyrus-fan-curve-guard.timer`.

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
asusctl armoury set boot_sound 0                # no POST chime (stored in asusd.ron)
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

## 6. Coil whine: disable the C8/C10 idle states

A faint high-pitched whine at idle, audible only with the room quiet and an ear
close. It was still there on battery, so it wasn't the charger. It got louder
("dudh-dhu") under a full 20-thread load, and the dGPU is off in Integrated mode, which points at
the CPU's power-stage coils. At idle the CPU enters and leaves its deepest sleep states
thousands of times a second, and that on/off switching is what makes the coils sing. The XPS 13 has none of
this: a ~15 W chip pulling small currents through small coils.

**Test:** the idle states on this CPU are `POLL, C1E, C6, C8, C10`. Disabling only
**C8 and C10** made the whine "way less" (owner, 2026-09-22). C6 is still allowed.

**Cost:** measured with the RAPL package counter over alternating 10–15 s windows, on
AC with Chrome open. Deep states on averaged 4.4–5.7 W (with one 12.4 W
background spike), off averaged 5.9–6.8 W. That's about **0.5–1.5 W**, near the noise
floor, with no temperature or fan change (50°C, 0 RPM). The cost is likely larger at true idle
on battery; not measured.

**Persisted** with a script that matches states by *name* (so a BIOS or kernel reorder
can't disable the wrong one) and a oneshot unit that runs at boot and after every
resume from suspend or hibernate:

```sh
sudo install -m 755 assets/zephyrus-m16/zephyrus-no-deep-cstates /usr/local/bin/
sudo install -m 644 assets/zephyrus-m16/zephyrus-no-deep-cstates.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now zephyrus-no-deep-cstates.service
```

**Verify:**

```sh
for s in /sys/devices/system/cpu/cpu0/cpuidle/state*; do echo "$(cat $s/name) disable=$(cat $s/disable)"; done
# expect C8 and C10 = 1, others 0. Check again after a suspend/resume.
```

**Revert:** `sudo systemctl disable --now zephyrus-no-deep-cstates.service`, then
reboot, or write `0` to those `disable` files. If you want it stronger, disabling C6 too
was tested next (below) and wasn't worth it.

**C6 tested too (2026-09-22), and left on.** Two 15 s rounds each way with C8/C10
off: C6 on 5.9 / 6.0 W, C6 off 5.9 / 6.6 W, 57°C both ways, fans off. The cost was
small (≤0.6 W), but the owner "couldn't even tell much" difference in the whine. The whine that remains,
faint at idle and while browsing, is the board's normal response to load changes. No
idle-state setting fixes it.

## 7. Power cap: 30 W sustained / 35 W burst

Without tuning, the Quiet profile still allowed the firmware's full **60 W sustained
(`ppt_pl1_spl`) / 135 W burst (`ppt_pl2_sppt`)**. While scrolling or loading pages, the CPU
fired brief 40–50 W multi-core bursts that nothing interactive needs.
asusd stores these limits as a per-profile, per-power-source "tuning" that is off by default:

```sh
asusctl armoury set ppt_pl1_spl 30     # stored in ac_profile_tunings.Quiet (current power source)
asusctl armoury set ppt_pl2_sppt 35
asusctl profile tuning true            # enables that tuning group
```

`asusctl` only writes the group for the current power source. The battery (`dc`) group
was added to `/etc/asusd/asusd.ron` by hand with asusd stopped (backup
`asusd.ron.bak.ppt`):

```ron
    dc_profile_tunings: {
        Quiet: (
            enabled: true,
            group: {
                PptPl2Sppt: 35,
                PptPl1Spl: 30,
            },
        ),
```

**Check it with a real load, not the registers.** Both `intel-rapl` and `intel-rapl-mmio` still report
135 W, because the EC enforces the limit separately. A 20-thread busy loop measured through
the RAPL energy counter held a **flat 35 W** from the first second, and the package reached only 63°C
after 10 s. The firmware attributes read the new values:

```sh
cat /sys/class/firmware-attributes/*/attributes/ppt_pl{1_spl,2_sppt}/current_value   # 30 35
```

**Tradeoff:** single-core boost still reaches ~4.7–4.9 GHz, so scrolling and UI feel
the same, but long all-core jobs (big compiles) get roughly 30–40% slower than at 60 W
(estimate, not benchmarked). **Revert:** `asusctl profile tuning false`, on AC and again
on battery, or set both values back to 60/135.

## 8. Clock cap, VRR, and panel overdrive (2026-09-23)

The last software levers, tested together over the same 45 s of scrolling X and then YouTube
(0.5 s samples, CPU fan on the steady baseline):

| | Avg pkg power | Peak | Avg temp | **Peak temp** | Max clock |
|---|---|---|---|---|---|
| Before | 6.7 W | 25.7 W | 51.4°C | **73°C** | 5,000 MHz |
| Clock cap + VRR + overdrive off | 9.7 W | 31.4 W | 51.2°C | **61°C** | 3,800 MHz |

The observed win in this short test was **a lower peak temperature**: the top boost bins (4.4–5.0 GHz) need a large
voltage jump, and that caused the split-second 65–79°C blips. Average power didn't measurably
change. The uncontrolled 45 s windows cannot establish a power difference: work duration and
background activity can change with frequency, so a lower clock does not guarantee lower
average power. These measurements do not establish watt savings from the three changes. No flicker with
VRR, and scrolling stays smooth at 3.8 GHz (more than twice the 1.7 GHz that caused the section 2 jank).

**Clock cap:** 3.8 GHz on every policy. That's also the E-cores' own maximum, so only P-core boost is
trimmed (roughly 15–20% single-thread). Applied at boot and after resume. A profile re-set, which
is what happens on AC plug/unplug, didn't reset it.

```sh
sudo install -m 755 assets/zephyrus-m16/zephyrus-cpu-freq-cap /usr/local/bin/
sudo install -m 644 assets/zephyrus-m16/zephyrus-cpu-freq-cap.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now zephyrus-cpu-freq-cap.service
cat /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq | sort | uniq -c   # 20 3800000
```

**VRR:** the BOE panel is VRR-capable. In `~/.config/hypr/looknfeel.lua`:

```lua
hl.config({
  misc = {
    vrr = 1,
  },
})
```

Check it with `hyprctl monitors | grep vrr` → `vrr: true`, and `hyprctl configerrors` should be empty.

**Panel overdrive** (extra pixel drive for faster response in games; costs a little power and
can cause halo artifacts): `asusctl armoury set panel_overdrive 0`, which asusd persists as
`PanelOverdrive: 0`.

**Revert:** `sudo systemctl disable --now zephyrus-cpu-freq-cap.service`, then write
`5000000` back to the `scaling_max_freq` files (or reboot). Remove the `misc.vrr` block and run
`hyprctl reload`. Run `asusctl armoury set panel_overdrive 1`.

**Not done:** undervolting is almost certainly locked on 12th-gen (Plundervolt mitigation).
Repasting is risky because ROG models of this era often use liquid metal. Dusting the fans and
heatsink, and raising the rear for intake airflow, are the remaining physical options.

## 9. Further quiet/power trials (2026-09-23, Codex follow-up)

**Method:** a separate Chromium 152 window automatically scrolls a fixed local page at
165 Hz (text, gradients and 300 cards, no network or extensions). The user's Chrome
154 session remains open, so background activity is still a confounder. Seven 35 s clock
rounds alternate configurations; discard the first 5 s of each. This tests a scrolling
workload, not page-loading speed or every website. JavaScript frame callback intervals
are a responsiveness proxy, not measured display presentation times.

The new [`zephyrus-power-sample`](assets/zephyrus-m16/zephyrus-power-sample) uses
actual monotonic elapsed time, handles RAPL counter wrap, and finds fans by their labels.
The previous shell sampler assumed exactly 0.5 s and selected the first fan glob.
Both measure CPU **package energy**, not whole-laptop or wall power, and sample every 0.5 s.

```sh
# Run from this repo, in separate terminals. Leave the test window visible.
python3 assets/zephyrus-m16/zephyrus-scroll-test --seconds 300
pkexec python3 assets/zephyrus-m16/zephyrus-power-sample --seconds 45 > /tmp/zephyrus-power.jsonl
```

The scrolling helper requires matching `chromium` and `chromedriver` (both already
installed here), creates its own temporary profile, prints the log directory, and closes
only its own browser when finished. It does not change the user's Chrome profile.

### Clock reductions: reverted

| P-core / E-core maximum | Average package W in each round | Frame intervals >9.1 ms |
|---|---|---|
| Original 3.8 / 3.8 GHz | 8.292, 8.327, 8.132 | 0–0.061% |
| 3.8 / 2.4 GHz | 8.579, 8.343 | 0.020–0.040% |
| 3.2 / 2.4 GHz | 8.197, 8.175 | 0–0.020% |

No useful demonstrated saving: the most restrictive cap was only ~0.06 W below the
baseline mean, less than the variation between baseline rounds. Restored **3.8 GHz on
all policies**, leaving EPP `balance_performance` on all CPUs. The kernel's
`/sys/devices/cpu_core/cpus` and `/sys/devices/cpu_atom/cpus` masks
were read locally: **P threads 0–11; E cores 12–19**. No process affinities were changed.

### VRR versus panel self-refresh: reverted

With VRR on, i915 reports PSR disabled. Turning VRR off at the **same 165 Hz** enables
PSR1. The kernel driver explicitly excludes PSR with VRR; see
[Intel display driver](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/i915/display/intel_psr.c).
However, enabled is not the same as spending time in self-refresh: our samples showed
`IDLE`, rather than establishing substantial residency.

Two 25 s measured windows per setting, ordered on/off/off/on, averaged **5.83 / 5.73 /
5.96 / 6.03 W**. The screen content was uncontrolled for this initial trial. No useful
saving demonstrated; restored **VRR on**. FBC was already enabled, DMC firmware loaded,
and the DC5 entry counter nonzero. No i915 module parameters were forced.

### Fans-off retry with the existing 3.8 GHz cap: kept

The earlier fans-off trial preceded the clock cap, so this was worth retrying with the
current CPU settings. Changed only the CPU fan's first five points from 18 to 0 PWM;
the GPU curve already matched. The cap stays **3.8 GHz**, EPP stays
`balance_performance`, C8/C10 stay disabled, and the normal higher-temperature ramp remains:

```sh
asusctl fan-curve --mod-profile quiet --fan cpu --data 30c:0%,40c:0%,50c:0%,60c:0%,66c:0%,70c:10%,80c:30%,90c:45%
asusctl fan-curve --mod-profile quiet --enable-fan-curves true
```

**Measured:** a five-minute trial, first 15 s excluded for fan spin-down, 564 samples:
both fans off **86.7%** of samples, CPU fan peak **2,100 RPM**, GPU fan **0 throughout**.
Average package temperature **55.1°C**, peak **75°C**; average package power **12.24 W**.
The first part used the local scroll page, later activity was uncontrolled regular desktop
and browsing, so that power number is **not an A/B saving**. Temperatures were mostly
around 49–51°C initially, then around 59°C in the final minute with heavier activity.
Raw numerical summaries are in
[`2026-09-23-trial-summary.json`](assets/zephyrus-m16/2026-09-23-trial-summary.json).

The CPU fan first returned during heavier activity around 3½ minutes in, then stopped
again. **This trades the constant hum for longer silent periods plus occasional ramps; it
does not eliminate fan bursts or temperature spikes.** The owner heard the initial quiet
period and reported the fan gone and whine no longer noticeable. That is subjective sound
evidence, not proof of an electrical coil-whine reduction. No C-state change was made. Subsequent heavier Chrome activity also reached ~3,100 RPM;
this curve does not promise silence under sustained load.
The five-minute test also does not establish long-session thermal equilibrium.

**Verify:** both `pwm*_enable` read `1`; both curves are PWM
`0 0 0 0 0 26 77 115` at `30 40 50 60 66 70 80 90`°C. The fan guard remains active.
The fan-curve file was backed up to `/etc/asusd/fan_curves.ron.bak.<epoch>` before testing,
and the repo copy matches the retained live curve. asusd persists it for the Quiet profile
on AC and battery; reboot/resume with this revision has not yet been tested.

**Revert to the steady CPU fan**, without changing the GPU curve or any CPU setting:

```sh
asusctl fan-curve --mod-profile quiet --fan cpu --data 30c:7%,40c:7%,50c:7%,60c:7%,66c:7%,70c:10%,80c:30%,90c:45%
asusctl fan-curve --mod-profile quiet --enable-fan-curves true
```

### Disconnected Ethernet runtime power: kept

The onboard RTL8125 was disconnected but forced `power/control=on` and stayed active.
Two `auto → on` trials consistently changed **active → suspended after roughly 10–15 s**,
then resumed to active with `on`. No kernel warnings during the trials. Installed
[`80-zephyrus-ethernet-pm.rules`](assets/zephyrus-m16/80-zephyrus-ethernet-pm.rules),
matching this ASUS controller's PCI vendor/device and subsystem IDs. The
[r8169 driver](https://github.com/torvalds/linux/blob/master/drivers/net/ethernet/realtek/r8169_main.c)
only schedules this idle suspend when the interface is down or has no carrier, and enables
PHY wake when suspending a running interface.

**Result:** the unused device now reaches `suspended`. Watt savings and wired cable
reconnect have **not** been measured/tested; the laptop's active connection is Wi-Fi.
This is independent of CPU fan RPM and is not claimed as a coil-whine fix.

```sh
pkexec install -m 644 assets/zephyrus-m16/80-zephyrus-ethernet-pm.rules /etc/udev/rules.d/
pkexec udevadm control --reload-rules
pkexec udevadm trigger --action=bind /sys/bus/pci/devices/0000:2c:00.0
# After 15 s without an Ethernet cable: auto / suspended
cat /sys/bus/pci/devices/0000:2c:00.0/power/{control,runtime_status}
```

**Revert:** remove `/etc/udev/rules.d/80-zephyrus-ethernet-pm.rules`, reload udev rules,
and write `on` to `/sys/bus/pci/devices/0000:2c:00.0/power/control` using `pkexec`.
This does not disable or unbind the interface.

### Other findings / left unchanged

- A live 12 s process sample found a Chrome renderer using ~24% of one CPU and its GPU
  process ~12%. Do not identify a tab from a renderer PID alone or blindly freeze it.
- Chrome's [Energy Saver](https://support.google.com/chrome/answer/12929150?hl=en)
  operates when unplugged or at low battery and may affect visual smoothness; it is
  not an AC power fix. No Chrome settings were changed.
- `intel_lpmd` still has low-power mode forced off. Global core confinement can also
  constrain foreground work; it was not enabled in this pass. No claimed saving.
- Audio power-save timeout is already 10 s; NVMe APST latency policy is nonzero
  (100000 µs). The latter alone does not verify actual APST residency. Wi-Fi power
  saving is off and left unchanged; no blanket USB/PCIe power tuning was applied.
- C8/C10 remain disabled. No electrical/acoustic instrument measured coil whine;
  the owner's listening report is the sound evidence.

## BIOS update (308 → 311)

Linux can't flash it and fwupd isn't used, but no Windows is needed either. Download the **EZ Flash**
zip from ASUS (`GU603ZWAS311.zip`, SHA256 `0de27aab…ffbf7d2a`), unzip
`GU603ZWAS.311` onto a FAT32 USB, then F2 → F7 (Advanced) → Advanced → ASUS
EZ Flash 3. Effect on the faint idle coil whine not tested.

Almost everything survived, because it lives in Linux. The boot order stayed on Limine. The flash
reset the boot sound, so the chime played once, but asusd restores `boot_sound 0` from
`asusd.ron` at startup (`journalctl -b -u asusd | grep boot_sound`).

**The fan curve did not survive.** `asusctl` still reported it as enabled, but the EC
was back in firmware mode (`pwm1_enable=2`) and ran the fans at ~1,800 RPM at 50°C. The same
thing turned out to happen on every asusd restart. See section 3 for the hardware check and
the guard timer that now repairs it automatically.

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

- **VRR is already on.** The September 23 follow-up below tests its interaction with panel self-refresh.
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
