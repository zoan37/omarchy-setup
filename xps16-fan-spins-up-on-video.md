# XPS 16: fan spins up on YouTube / x.com video

**Symptom:** the fan ramps while watching video in Chrome — YouTube, x.com —
and while scrolling an x.com timeline with several YouTube tabs open. It runs
~2200–3300 RPM for 60–90 s at a time, then stops, then comes back.

**Cause: a local web page burning ~54% of a CPU core, continuously.** Not video
decode, not the fan curve, not the power limits. My own Cubo portfolio
dashboard rebuilt a layer of DOM labels over a three.js scene on every
animation frame, at the panel's full 120 Hz. Any tab doing that holds the
package around 45–47 °C, which parks the machine inside the EC's fan trip band
so that *anything* extra — a video, a scroll — tips it over.

**The fan was behaving correctly the entire time.** Four separate OS-side
thermal levers were tried before the actual load was found; none of them
mattered, and the dead-ends list below is the useful residue of that.

Fixed in the page itself (zoan37/cubo `dffec9a`): labels are created once and
mutated in place instead of recreated per frame, and the render loop pauses
when the tab is hidden or scrolled out of view. That tab measured **~54% → ~21%
focused, and 0% backgrounded.**

If you are here because the fan is spinning *right now*, skip to
[Catch it in the act](#catch-it-in-the-act) — that is the diagnostic that
finally worked, and it takes about ten seconds.

## Not the XPS 13's problem

[xps13-fan-spins-up-on-video.md](xps13-fan-spins-up-on-video.md) has the same
symptom from a completely different cause: Omarchy's detection regex misses
`Wildcat Lake` and installs no VA-API driver, so Chrome decodes video in
software. **That does not apply here**, and it was verified on this machine
rather than assumed:

```bash
pacman -Q intel-media-driver libvpl vpl-gpu-rt
#  -> intel-media-driver 26.2.4-1 / libvpl 2.17.0-1 / vpl-gpu-rt 26.2.4-1
ls /usr/lib/dri/iHD_drv_video.so        # present
```

The regex contains both `panther\ lake` and `arc`, and this iGPU is
`8086:b080` Arc B390, so the install path works normally. **Hardware decode is
fine on this machine.** Video was never CPU-bound during any test here: with a
4K YouTube video fullscreen, aggregate CPU stayed at 6–27% and the package
never left 34–36 °C, with both fans at 0 RPM for the full 60 s.

## Read the right sensor — this is the trap

`dell_wmi_ddv` and `coretemp` both report a "CPU" temperature that is **~20 °C
below** the real package temperature, and they update far too slowly to see
what the EC reacts to. Sampling them makes the machine look idle while it is
spiking:

```bash
# Simultaneous readings, same instant, fan audibly running:
cat /sys/class/thermal/thermal_zone10/temp   # 63000  <- x86_pkg_temp, the real one
cat /sys/class/hwmon/hwmon5/temp1_input      # 46000  <- coretemp "Package id 0"
cat /sys/class/hwmon/hwmon3/temp1_input      # 41000  <- dell_ddv "CPU"
```

Use **`thermal_zone10` (`x86_pkg_temp`)** and sample at **≥2 Hz**. At 5-second
intervals on `dell_ddv` the entire phenomenon is invisible — an early pass here
logged a placid 41–44 °C while the package was spiking to 92 °C.

Sensor map on this machine:

| Path | Driver | What |
|---|---|---|
| `/sys/class/thermal/thermal_zone10` | `x86_pkg_temp` | **the package temp that matters** |
| `/sys/class/hwmon/hwmon3` | `dell_wmi_ddv` | `fan1`=Video Fan, `fan2`=CPU Fan, 8 labelled temps |
| `/sys/class/hwmon/hwmon4` | `dell_smm_hwmon` | same fans, plus `pwm*`, `fan*_max` (3900) |
| `/sys/class/hwmon/hwmon5` | `coretemp` | per-core + package |

Both fan sensors are live and trustworthy — `fan1_max` is populated at 3900 and
readings track what you can hear. A `0` genuinely means stopped.

## What the fan actually responds to: not package temperature

Pooling 560 samples at 4 Hz across two configs, fan state versus package temp:

```
45C   n=46    fan_on= 96%
46C   n=244   fan_on= 39%
47C   n=145   fan_on= 17%
48C   n=27    fan_on= 48%
49C   n=74    fan_on= 24%
50C   n=23    fan_on=  9%
```

The correlation is **inverse**. That is not a broken sensor — it is causality
running backwards from the naive reading: the fan turns on, and the package
gets cooler. Package temperature is a *lagging consequence* of fan state, not
its trigger.

Practical consequence: **any A/B test scored on peak temperature is measuring
the wrong variable.** A change can genuinely lower peak temps and leave fan
behaviour untouched, which is exactly what happened below.

## The real correlate: idle floor, not bursts

The strongest pattern in the data is not about video at all:

| | package | fans |
|---|---|---|
| Early session, Chrome freshly used | 33 °C | 0 / 0, stayed off through a 60 s 4K video *and* a 120 s x.com scroll |
| Later, after hours of Chrome uptime | 45–47 °C | cycling 2200–3300 RPM, on ~40% of samples |

The machine's **idle floor rose ~12 °C over a few hours of Chrome uptime**. At
a 33 °C floor nothing could provoke the fan; at a 45 °C floor it cycles
constantly and any small load tips it over. Video and scrolling are the
*trigger* that crosses the line, not the thing that moved the line.

What moved it: Chrome accumulating continuous background work. At the point of
measurement there were 44 Chrome processes / 33 renderers, a load average of
2.3, and **131.8 minutes of accumulated Chrome CPU time**. Two processes stood
out:

```
PID 119673  --type=renderer     peak 100.5%, ~48% sustained, alive 16:31 onward
PID  48983  --type=gpu-process  33:51 CPU-minutes over 5.5 h
```

Chrome's own Task Manager (**Shift+Esc**, with the Process ID column enabled)
named it immediately, which is the step that should have come first:

```
Tab: Portfolio - Cubo AI        CPU 54.0    PID 243366
Tab: <an x.com timeline>        CPU 14.0    PID 243806
App: <a YouTube video>          CPU  3.0    PID 243143
```

So there were two separate things, and conflating them cost hours: the
**Portfolio tab held a continuous ~54% floor**, while x.com video tabs *burst*
on top of it. The bursts are what you hear; the floor is what makes them
audible. On a 45 °C floor a burst trips the fan; on the 33 °C floor the machine
had at the start of the evening, nothing could.

The page was a three.js solar-system visualisation whose animation loop did
this every frame:

```js
labelsDiv.innerHTML = '';                       // wipe every label
for (const p of planets) {
    const lbl = document.createElement('div');  // recreate it
    lbl.innerHTML = `${p.symbol}<br><span ...>`;// + an HTML parse, per planet
    labelsDiv.appendChild(lbl);
}
```

At 120 Hz that is 120 × (number of assets) element creations, `innerHTML`
parses, style recalcs and layout passes **per second**, all on the renderer's
main thread. The WebGL scene itself was cheap — the profile put the cost on the
main thread (8584 ticks) versus the compositor (1152), with the GPU frequently
reading 0 MHz.

### A counting trap that hid this for hours

On 16 cores, **two fully pegged cores show up as ~12% aggregate CPU.** Every
`top`/`%Cpu(s)` reading during this investigation said 91% idle while ~2.3
cores were continuously busy, which is why "the CPU is basically idle" was
repeated long after it stopped being true. Watch **load average** and
**per-process** CPU, not the aggregate.

Related: `ps -eo pcpu` reports a process's **lifetime average**, not current
CPU. It produces smoothly drifting numbers with no relation to what is
happening now. Use two-pass `top -bn2` for instantaneous values.

## Catch it in the act

The ten-second diagnostic. While the fan is audibly running:

```bash
# 1. Name the process, instantaneously (not ps lifetime averages)
top -bn2 -d1 -o %CPU | awk '/^ *PID/{p++} p==2' | head -12

# 2. Map a hot renderer PID to an actual tab
#    Chrome: Shift+Esc -> Task Manager -> sort by CPU
#    Right-click the column header -> enable "Process ID" to match PIDs exactly

# 3. Package temp + fans at the same moment
echo "pkg=$(( $(cat /sys/class/thermal/thermal_zone10/temp)/1000 ))C \
fans=$(cat /sys/class/hwmon/hwmon3/fan1_input)/$(cat /sys/class/hwmon/hwmon3/fan2_input)"
```

Closing the responsible tab drops the idle floor back toward the mid-30s, and
the fan stops within ~90 s (EC spin-down hysteresis).

**Do this first.** Every other measurement in this document is downstream of
not having done it. Chrome's Task Manager names the tab in seconds; `top` alone
only ever gives you a PID, and a PID doesn't tell you which page to fix.

## Dead ends — already measured, don't re-chase

Everything below was tested on this machine, on 2026-09-17. None of it changed
fan behaviour.

- **VA-API / hardware decode.** Installed and working; see the top of this doc.
  The XPS 13 fix is a no-op here. 4K YouTube fullscreen: 6–27% CPU, 34–36 °C,
  fans 0 RPM for 60 s.

- **`energy_performance_preference` + turbo clock cap.** Setting all 16 cores
  to `balance_power` and `max_perf_pct=75` (ceiling 5.2 GHz → 3.9 GHz)
  **worked, on the wrong metric**: peak package under an identical 45 s scroll
  protocol fell **92 °C → 60 °C**, with samples above 70 °C going 4 → 0. Fan
  behaviour did not improve — measured fan-on rate went *up* (46% → 58%). This
  is the clearest demonstration that temperature is not the fan's input.

- **RAPL power limits.** Stock is `41 W` PL1 / `65 W` PL2 / `175 W` peak.
  **Halving them changes nothing.** Controlled burst test (1.5 s of 4-core
  load, 4 s idle, ×12, from a settled fans-off baseline):

  ```
  PL 41/65W   peak=51C  mean=47C  fan_on=40%  maxrpm=3264
  PL 20/30W   peak=50C  mean=47C  fan_on=30%  maxrpm=3313
  ```

  1 °C of peak, max RPM slightly *higher*, and the fan_on difference is inside
  run-to-run noise. RAPL is **not** locked on this machine — the writes stick
  and read back — so this is a real negative result, not a failed write. The
  XPS 13's "cap PL1 for near-silence" advice does not transfer.

- **BIOS `ThermalManagement` = `Quiet`.** Genuinely exists and is settable from
  Linux, which is worth knowing (see below) — but it did not fix this. Fan-on
  rate 40%, max RPM 3232, i.e. unchanged within noise.

- **`platform_profile`.** Only `balanced` and `performance` exist here; there
  is **no `low-power`**, unlike the XPS 13. Switching the GUI power mode to
  power-saver sets `platform_profile` to `custom` and EPP to `power` — ppd
  drives EPP directly because the ACPI profile has nothing quieter to offer.
  No effect on the fan.

- **`thermald`.** Active by default here (`--adaptive`), unlike the XPS 13
  where it is inactive. Logs show it starting cleanly and doing nothing
  interesting. Not implicated.

- **Manual PWM fan control.** `dell_smm_hwmon` exposes `pwm1`/`pwm1_enable` and
  `pwm2`/`pwm2_enable`, meaning this machine *is* in the driver's fan-control
  whitelist — but **do not use it.** Both read `pwm*_enable=1` (BIOS automatic
  control nominally *disabled*) with `pwm*=0`, while the fans demonstrably
  still ramp to 3300 RPM on their own. The EC reclaims control within seconds,
  which matches the kernel's own documentation of this behaviour. Fighting the
  EC for fan control means risking a machine stuck at `pwm=0` under load. Not
  worth it for fan noise.

  (Note this differs from the XPS 13, where `pwm1_enable` reads `2`.)

- **`fan_type()` / erratic-fan firmware bug.** The kernel documents a class of
  Dell machines where *reading fan type* destabilises the fan
  (Studio XPS 8000/8100, Inspiron 580/3505). Plausible-looking here, since
  `dell_smm`'s `fan1_label`/`fan2_label` come back **empty** while `dell_ddv`'s
  are populated. Investigated and **dropped**: nothing on this system polls
  those sensors — no waybar temperature widget, no `sensors` loop, no
  `libsmbios`/`i8kutils` installed. The symptom predates any monitoring.

- **I/O wait inflating load average.** Checked because load sat at ~1.5–2.4
  while CPU read 91% idle. Not it: no processes in `D` state,
  `/proc/pressure/io` flat at 0.00, nvme nearly idle. The load figure is a
  slowly decaying average from the earlier busy period.

## Worth knowing: the BIOS has a Quiet thermal mode

It didn't fix this, but it is undocumented elsewhere in this repo and is
reachable from Linux without rebooting into setup. `dell-wmi-sysman` exposes
136 firmware attributes, including:

```bash
cat /sys/class/firmware-attributes/dell-wmi-sysman/attributes/ThermalManagement/possible_values
#  -> Optimized;Cool;Quiet;UltraPerformance;
cat /sys/class/firmware-attributes/dell-wmi-sysman/attributes/ThermalManagement/default_value
#  -> Optimized
```

Set it (needs root; `current_value` is root-read-only):

```bash
echo Quiet | sudo tee \
  /sys/class/firmware-attributes/dell-wmi-sysman/attributes/ThermalManagement/current_value
```

Writes are gated on the BIOS admin password **only if one is set** — check with
`cat /sys/class/firmware-attributes/dell-wmi-sysman/authentication/Admin/is_enabled`
(`0` here, so writes go through unauthenticated).

This is a **firmware setting: it persists across reboots and survives
`omarchy update`.** `Quiet` and `Cool` trade sustained performance for noise by
capping CPU power; `Optimized` is stock. Revert with the same command and
`Optimized`.

## Keeping the low-power settings, if you want them

**These did not fix the fan** — that was the page, above. But they are a
reasonable quiet/battery tradeoff in their own right, and they were left on for
a while after the investigation, so here is how to re-apply them deliberately
rather than by re-deriving the numbers.

What they cost: burst CPU. PL2 at 30 W and a 3.9 GHz ceiling are invisible for
browsing and video, and noticeable on a long compile or an export.

`/usr/local/bin/xps16-quiet`:

```bash
#!/bin/bash
# usage: xps16-quiet on|off      (runtime only; resets on reboot)
case "$1" in
  on)  EPP=balance_power;       PCT=75;  PL1=20; PL2=30 ;;
  off) EPP=balance_performance; PCT=100; PL1=41; PL2=65 ;;
  *)   echo "usage: $0 on|off"; exit 1 ;;
esac
for c in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
  echo "$EPP" > "$c"
done
echo "$PCT" > /sys/devices/system/cpu/intel_pstate/max_perf_pct
R=/sys/class/powercap/intel-rapl:0
echo "$((PL1 * 1000000))" > $R/constraint_0_power_limit_uw
echo "$((PL2 * 1000000))" > $R/constraint_1_power_limit_uw
printf 'EPP=%s  max_perf_pct=%s  PL1/PL2=%s/%sW\n' \
  "$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference)" \
  "$(cat /sys/devices/system/cpu/intel_pstate/max_perf_pct)" \
  "$(( $(cat $R/constraint_0_power_limit_uw) / 1000000 ))" \
  "$(( $(cat $R/constraint_1_power_limit_uw) / 1000000 ))"
```

`sudo chmod +x /usr/local/bin/xps16-quiet`, then `sudo xps16-quiet on`.

Note RAPL is **not** locked on this machine — the writes stick and read back,
which is worth knowing because on plenty of Dell firmware they silently revert.
The script echoes the values back so a silent revert is visible.

### Making it survive a reboot

Only do this after living with it for a few days; it is a permanent cap on
burst performance.

```ini
# /etc/systemd/system/xps16-quiet.service
[Unit]
Description=Quiet power limits for XPS 16
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/xps16-quiet on
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now xps16-quiet.service
```

Caveat: `power-profiles-daemon` also writes EPP when the GUI power mode
changes, and it will win on any later toggle. The RAPL limits and
`max_perf_pct` are unaffected by it. Disable with
`sudo systemctl disable --now xps16-quiet.service`, which takes effect at the
next boot — run `sudo xps16-quiet off` to clear it immediately.

## Revert everything this doc touches

The CPU-side knobs are all runtime-only and reset on reboot:

```bash
# EPP + clock ceiling back to stock
for c in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
  echo balance_performance | sudo tee $c > /dev/null
done
echo 100 | sudo tee /sys/devices/system/cpu/intel_pstate/max_perf_pct

# RAPL back to stock 41 W / 65 W
echo 41000000 | sudo tee /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw
echo 65000000 | sudo tee /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw
```

The BIOS thermal mode is the only change that persists — revert it explicitly
with `ThermalManagement` = `Optimized` as above.

## Survives `omarchy update`?

Nothing here is a file in a package-owned path, so there is nothing for an
update to clobber. The BIOS attribute lives in firmware and is untouched by the
OS entirely. `/usr/local/bin/xps16-quiet` and the systemd unit above are both
outside pacman's reach, so they survive updates too.

Left alone, the CPU knobs don't survive a *reboot*, let alone an update — and
since none of them fixed the fan, stock is the right default. Turn them on
deliberately for battery or quiet, not as a fix for this.

## The lesson, for next time

The symptom pointed at video, so the investigation started at video decode and
worked outward through thermal and power tuning — four levers, all of them
firmware-controlled and none of them movable from Linux. The actual cause was
an ordinary application bug in a page I wrote, findable in about ten seconds
with a tool built into the browser.

**When a laptop is hot, find out what is running before tuning how it runs.**
`top` plus Chrome's Task Manager, in that order, before touching a single knob.

Two specific traps worth remembering, both of which actively delayed this:

- **A 16-core aggregate hides a small number of busy cores.** `%Cpu(s)` read
  "91% idle" throughout, while ~2.3 cores were pinned. Watch load average and
  per-process CPU instead.
- **`ps -eo pcpu` is a lifetime average, not current CPU.** It yields smoothly
  drifting numbers that look like data and mean nothing about the present.
  Two-pass `top -bn2`, or read `/proc/<pid>/stat` deltas yourself.

## Still open

- **The Vulkan flags are untested.** Omarchy forces
  `Vulkan,DefaultANGLEVulkan,VulkanFromANGLE` on every machine
  ([chrome-vulkan-white-video.md](chrome-vulkan-white-video.md)). On a brand-new
  Xe3 iGPU driving 3200x2000@120 Hz at fractional scale 1.6, Chrome's
  gpu-process averaged 25–30% of a core, and some of that may be the ANGLE
  path rather than the page. Worth an A/B against a launch without them.
  Remember the relaunch gotcha: `chrome://restart` re-execs with the old
  command line and reads no config — full quit, then launch from the wrapper,
  and verify with `pgrep -a -f '^/opt/google/chrome/chrome '`.
- **Whether the idle floor still creeps** with the page fixed. If it does,
  something else is accumulating; log `thermal_zone10` at 0.5 Hz across a
  Chrome restart and compare.
