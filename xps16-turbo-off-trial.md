# XPS 16: persistent turbo-off trial for less fan noise

**Started 2026-09-17. Status: enabled, evaluation ongoing.** On the Dell XPS 16
DA16260 (Intel Core Ultra X9 388H), CPU turbo boost is disabled immediately and
configured to remain disabled after reboot. The preference is less fan noise,
even at the expense of development performance. Leave this setting in place
unless deliberately ending the trial.

This is a noise/performance experiment, **not a confirmed fix for fan cycling**.
The earlier [fan investigation](xps16-fan-spins-up-on-video.md) found a busy
Cubo page; during this later session, Chrome's Task Manager also showed
OpenSea using about 40% CPU. Background browser work remains a plausible heat
source. Turbo may amplify it, but was not established as the cause.

## What changed

Created `/etc/tmpfiles.d/disable-cpu-turbo.conf` with exactly:

```conf
# Disable Intel CPU turbo boost at boot. Remove this file to undo persistence.
w /sys/devices/system/cpu/intel_pstate/no_turbo - - - - 1
```

Applied it immediately with:

```bash
sudo systemd-tmpfiles --create /etc/tmpfiles.d/disable-cpu-turbo.conf
```

`no_turbo=1` prevents the Intel P-state driver from selecting turbo speeds;
`0` allows them again. This is a Linux setting, not a BIOS change. The existing
`systemd-tmpfiles-setup.service` applies the file at boot; no additional service
was installed. See the [kernel documentation](https://docs.kernel.org/admin-guide/pm/intel_pstate.html#global-attributes).

To reproduce on this machine after reinstalling:

```bash
sudo tee /etc/tmpfiles.d/disable-cpu-turbo.conf >/dev/null <<'EOF'
# Disable Intel CPU turbo boost at boot. Remove this file to undo persistence.
w /sys/devices/system/cpu/intel_pstate/no_turbo - - - - 1
EOF
sudo chmod 0644 /etc/tmpfiles.d/disable-cpu-turbo.conf
sudo systemd-tmpfiles --create /etc/tmpfiles.d/disable-cpu-turbo.conf
```

## Verified state and performance tradeoff

Readback immediately after applying was `no_turbo=1`. Every CPU policy's
`scaling_max_freq` dropped to its non-turbo limit:

| Cores | Turbo-off ceiling, verified | Hardware turbo maximum reported before the change |
|---|---|---|
| 4 performance | 2.1 GHz | 5.1–5.2 GHz |
| 8 efficiency | 1.7 GHz | 4.0 GHz |
| 4 low-power efficiency | 1.6 GHz | 3.7 GHz |

These are ceilings, not constant operating speeds. Cores can still slow down
or sleep when idle. The turbo maxima were not guaranteed operating speeds,
especially with the existing power limits. Clock ratios alone do not give an
honest application slowdown percentage.

Typing, terminals, SSH, and network-bound work may feel similar. Compilation,
bundling, CPU-heavy tests, IDE indexing, and busy web pages may be noticeably
slower. No before/after development benchmark has been run.

Other settings were left as found:

- Linux power profile: `power-saver`; CPU EPP: `power`.
- Dell platform profile: `quiet`; SoC Power Slider: `balanced`.
- Existing `max_perf_pct=75` and RAPL PL1/PL2 limits of 20 W / 30 W.
- Display: 3200×2000 at 120 Hz, scale 1.6.

The earlier `xps16-quiet.service` example was **not installed**. The runtime
clock/power limits may reset on reboot; this trial makes only `no_turbo=1`
persistent. A future comparison needs to account for those other settings.

## Evaluate during normal development

Both fans were stopped in spot checks before and after the change, so that
alone does not demonstrate improvement. There has been no controlled fan-noise
comparison or reboot verification yet.

Use the laptop normally for a few days and note fan frequency/duration,
editor responsiveness, and familiar build/test times. For an A/B comparison,
keep the workload, browser tabs, power source, and other power limits alike.
Check Chrome's Task Manager when a tab stays busy; disabling turbo does not
remove that work. If recording temperatures, use the sensor guidance in the
[earlier investigation](xps16-fan-spins-up-on-video.md#read-the-right-sensor--this-is-the-trap)
and identify sensors by name rather than assuming their numeric paths persist.

After reboot, an Omarchy update, or a power-profile change, verify:

```bash
cat /sys/devices/system/cpu/intel_pstate/no_turbo   # expected: 1
cat /etc/tmpfiles.d/disable-cpu-turbo.conf
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  printf '%s: ' "${p##*/}"
  cat "$p/scaling_max_freq"                       # kHz
done
```

The file is local configuration under `/etc`, outside Omarchy's packaged
files, and should survive ordinary updates. It applies at boot, not as a
continuous watchdog against another tool changing `no_turbo` later.

## Temporarily compare, or end the trial

Allow turbo for the current session:

```bash
echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo
```

Return to the trial with `echo 1` to the same path, or reboot while the
tmpfiles rule remains installed. Other power limits still apply in either case.

To end the trial permanently, remove the boot rule **and** restore turbo now:

```bash
sudo rm /etc/tmpfiles.d/disable-cpu-turbo.conf
echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo
cat /sys/devices/system/cpu/intel_pstate/no_turbo   # expected: 0
```

Removing the file alone does not restore turbo in the current session;
writing `0` alone does not remove the boot-time override. This rollback leaves
Dell Quiet mode, the Linux power profile, and the other power limits unchanged.
