# Beelink SER8: quieter automatic fan curve

Applied **2026-09-19** to the Ryzen 7 8745HS SER8. Idle fan speed fell from
about **1,076 RPM to 755 RPM**. The owner confirmed it sounded quiet afterward.
The short CPU load comparison peaked at 51°C with the original curve and
53°C with the new curve. This is an RPM measurement and subjective confirmation,
not a measured decibel reduction.

Two changes are active: Linux's `power-saver` profile, and a gentler minimum
fan speed programmed into the controller's automatic curve. No BIOS flash,
UEFI-variable edit, additional frequency cap, or package wattage cap was applied.

## Exact machine and software

| Item | Verified configuration |
|---|---|
| Machine | AZW / Beelink SER8, Ryzen 7 8745HS, 32 GB RAM |
| BIOS | `HPT.8xxx.SER8.V029.P8C0M0C15.13.Link`, dated 2025-02-21 |
| Kernel | `7.2.5-3-omarchy` |
| CPU driver | `amd-pstate-epp`, active mode |
| Power Profiles daemon | `0.30-1` |
| Fan controller | ITE IT8613E, revision 12, ISA address `0xa20` |
| Active fan | `fan2` / `pwm2`, platform device `it87.2592` |
| Driver | [frankcrawford/it87](https://github.com/frankcrawford/it87), commit `bc06d3488439e5fcd725c1bdcfcac994d6d95cac` |
| DKMS module version | `bc06d34.20260913` |

The fan helper deliberately checks the model, exact BIOS version, controller,
automatic mode, temperature mapping, and expected curve values before writing.
If a check fails on a fresh install or after a firmware update, inspect the
new configuration before changing those guards.

## First lever: power-saver already disables boost

The machine initially used `performance`, with boost enabled to approximately
5 GHz. The owner selected:

```sh
powerprofilesctl set power-saver
```

On this installed version, that changed all 16 CPU policies to `powersave`,
energy preference `power`, per-policy `boost=0`, and a maximum of 3,801,000 kHz.
The minimum became 405,440 kHz. A separate turbo-off service is unnecessary.

**Check the per-policy boost files.** The global
`/sys/devices/system/cpu/cpufreq/boost` still read `1` while every policy's
`boost` read `0`; looking only at the global file would give the wrong conclusion.

```sh
powerprofilesctl get
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  printf '%s boost=%s max_khz=%s\n' "${p##*/}" \
    "$(cat "$p/boost")" "$(cat "$p/scaling_max_freq")"
done
```

The daemon saved `Profile=power-saver` in
`/var/lib/power-profiles-daemon/state.ini` and its service is enabled at startup.
Early snapshots dropped from about 48°C to 35°C after the profile change,
but workloads differed, so those temperatures are not a controlled comparison.

## Finding the fan controls

Stock `sensors` exposed temperatures but no fan RPM or PWM control. There was
also no supported firmware-attributes interface for editing BIOS fan settings.
This did **not** mean Linux could never access the controller.

A targeted `sensors-detect` run identified `ITE IT8613E` at `0xa20` and reported
its driver as `to-be-written`. Only the Super-I/O probe was selected; the CPU,
IPMI, ISA sensor scan, and I2C/SMBus scans were skipped. No sensor configuration
was generated. The maintained external `it87` driver supports this exact chip.

The pinned driver built against the installed kernel headers. A temporary
`insmod` first failed with missing `vid_from_reg` / `vid_which_vrm` symbols;
loading its `hwmon-vid` dependency resolved that. Normal `modprobe it87` handles
the dependency after DKMS installation. No `force_id`, PWM-polarity override,
or ACPI resource-conflict override was required.

The resulting hwmon index was `hwmon10`, but that number can change on reboot.
The installed helper discovers the controller by name and platform-device
identity instead of hardcoding the index.

## Actual curve and the slope-unit trap

| Control | Original | Quiet |
|---|---:|---:|
| `pwm2_enable` | 2 (automatic) | 2 (automatic) |
| `pwm2_auto_start` | 60 | 40 |
| `pwm2_auto_slope` | 16 | 20 |
| Effective slope | 2 PWM/°C | 2.5 PWM/°C |
| `pwm2_auto_point1_temp` | 0 | 0 |
| `pwm2_auto_point1_temp_hyst` | 0 | 0 |
| `pwm2_auto_point2_temp` | 40000 (40°C) | 40000 |
| `pwm2_auto_point3_temp` | 90000 (90°C) | 90000 |
| `pwm2_auto_channels_temp` | 1 | 1 |
| PWM frequency | 23437 Hz | 23437 Hz |

The driver's slope value is in **eighths of a PWM unit per degree**. Writing
`2` to its sysfs slope file would mean 0.25 PWM/°C, not the intended 2 PWM/°C.
The encoding is documented beside the register reads in the
[pinned driver source](https://github.com/frankcrawford/it87/blob/bc06d3488439e5fcd725c1bdcfcac994d6d95cac/it87.c).

Between the ramp and full-speed thresholds, the nominal curve is:

```text
original: 60 + (temperature - 40) × 2
quiet:    40 + (temperature - 40) × 2.5
```

The quiet curve has a lower floor but catches the original at 80°C; the
90°C full-speed threshold remains active. The fan-off threshold stays at
0°C, so this does not intentionally stop the fan. The hardware runs the
automatic control loop; there is no background process continuously deciding RPM.

## Validation and its limits

Both curves were tested with `power-saver` active, using 16 parallel OpenSSL
SHA-256 workers for 35 seconds each, with idle/cooldown samples every 5 seconds:

```sh
openssl speed -multi 16 -seconds 35 -bytes 16384 -evp sha256
```

The trial restored the original settings on exit and had guards to stop if
CPU temperature reached 85°C or fan speed fell below 500 RPM.

| Measurement | Original | Quiet |
|---|---:|---:|
| Idle fan speed | ~1,076 RPM | ~755 RPM |
| Idle CPU sample | ~36.5°C | ~38.8°C after cooldown |
| Maximum sampled CPU temperature | 51°C | 53°C |
| Late-load fan speed | ~1,333 RPM | ~1,211 RPM |
| Reported PPT during CPU load | ~29 W | ~29 W |

After installation: fan 755 RPM, CPU 39°C, RAM sensors 40–42.2°C, SSD 32.9°C.
Stopping the service restored start=60/slope=16; starting it and invoking the
resume handler restored start=40/slope=20. The owner then confirmed the machine
had been quiet in ordinary use.

This was a short CPU test, not a prolonged combined CPU/GPU thermal soak.
No actual reboot or suspend/resume cycle was performed during setup; both
units are enabled, and the handlers were exercised directly. Verify those
transitions on the next real reboot/suspend. The PPT sensor is not a wall-power
measurement. Generic controller voltage limits and unused channels are not
board-calibrated; their alarm flags alone do not establish a hardware fault.

## Persistence and restore assets

[assets/ser8-quiet-fan/](assets/ser8-quiet-fan/) mirrors the installed files:

| Asset | Installed location / purpose |
|---|---|
| `ser8-quiet-fan` | `/usr/local/sbin/ser8-quiet-fan`: guarded apply, restore, status, and resume actions |
| `ser8-quiet-fan.service` | `/etc/systemd/system/`: applies at startup; restores the original curve on stop |
| `ser8-quiet-fan-resume.service` | `/etc/systemd/system/`: reapplies after sleep only while the main service is active |
| `dkms.conf`, `VERSION` | `/usr/src/it87-bc06d34.20260913/`: rebuilds the pinned driver for kernel updates |
| `original.txt` | `/var/lib/ser8-quiet-fan/original.txt`: recorded original settings |

DKMS source also contains the upstream `it87.c`, `compat.h`, `Makefile`, and
`COPYING`. Fetch those from the pinned commit below; third-party driver source
and compiled binaries are not vendored here. The installed setup does not
depend on the temporary research directory used during the initial trial.

### Reproduce on a matching fresh SER8 install

These steps reconstruct the installed files. Run from this repository's root
in a normal terminal, after comparing the live hardware/BIOS and original
curve against the table above. Stop if they differ. The initial kernel was
`7.2.5-3-omarchy`; compiling on a later kernel requires a new verification.

```sh
omarchy pkg add dkms gcc make git linux-omarchy-headers
test -d "/usr/lib/modules/$(uname -r)/build"

ser8_build_dir=$(mktemp -d)
git clone https://github.com/frankcrawford/it87.git "$ser8_build_dir/it87"
git -C "$ser8_build_dir/it87" checkout --detach bc06d3488439e5fcd725c1bdcfcac994d6d95cac

sudo install -d -m 0755 /usr/src/it87-bc06d34.20260913
sudo install -m 0644 "$ser8_build_dir/it87/it87.c" \
  "$ser8_build_dir/it87/compat.h" "$ser8_build_dir/it87/Makefile" \
  "$ser8_build_dir/it87/COPYING" \
  assets/ser8-quiet-fan/dkms.conf assets/ser8-quiet-fan/VERSION \
  /usr/src/it87-bc06d34.20260913/
sudo dkms add -m it87 -v bc06d34.20260913
sudo dkms build -m it87 -v bc06d34.20260913 -k "$(uname -r)"
sudo dkms install -m it87 -v bc06d34.20260913 -k "$(uname -r)"
sudo modprobe it87

sudo install -m 0755 assets/ser8-quiet-fan/ser8-quiet-fan /usr/local/sbin/
sudo install -m 0644 assets/ser8-quiet-fan/ser8-quiet-fan.service \
  assets/ser8-quiet-fan/ser8-quiet-fan-resume.service /etc/systemd/system/
sudo install -d -m 0755 /var/lib/ser8-quiet-fan
sudo install -m 0644 assets/ser8-quiet-fan/original.txt /var/lib/ser8-quiet-fan/
sudo systemd-analyze verify /etc/systemd/system/ser8-quiet-fan.service \
  /etc/systemd/system/ser8-quiet-fan-resume.service
sudo systemctl daemon-reload
powerprofilesctl set power-saver
sudo systemctl enable --now ser8-quiet-fan.service
sudo systemctl enable ser8-quiet-fan-resume.service
```

This is a fresh-install sequence, not an idempotent installer: if DKMS already
has this version, inspect `dkms status` and skip completed registration/build
steps. If another `it87` version is already loaded, installing files does not
replace the in-memory module; arrange a reload/reboot before verifying it.
The helper needs the controller to be available and configured as expected.

### Check after setup, reboot, sleep, or a kernel update

```sh
powerprofilesctl get
dkms status
modinfo -n it87
systemctl is-enabled ser8-quiet-fan.service ser8-quiet-fan-resume.service
systemctl status ser8-quiet-fan.service
ser8-quiet-fan status
journalctl -b -u ser8-quiet-fan.service -u ser8-quiet-fan-resume.service
```

Expect a DKMS installation for the **running** kernel, a module path under
`updates/dkms`, and start=40/slope=20/mode=2. RPM depends on temperature.
If a kernel update breaks the build, check matching headers and the DKMS build
log before changing the fan helper. The BIOS configuration itself was not
modified, so a fresh boot starts with the firmware's own curve until the service
successfully applies the quiet values.

### Undo / re-enable

```sh
sudo systemctl disable --now ser8-quiet-fan.service ser8-quiet-fan-resume.service
```

Stopping the main service restores start=60/slope=16. The driver remains for
monitoring, and the selected CPU power profile is unaffected. Re-enable with:

```sh
sudo systemctl enable --now ser8-quiet-fan.service
sudo systemctl enable ser8-quiet-fan-resume.service
```

If the CPU policy itself needs reverting, its previous selection was
`powerprofilesctl set performance`; that is independent of the fan services.

## Options investigated but not applied

**Additional frequency cap:** Linux exposes `scaling_max_freq`, so a 3 GHz
trial is possible. It was not applied because power-saver already disabled
boost and the fan curve improved noise without a further CPU limit.

**Package wattage cap:** RyzenAdj was built at commit
`5775fc3e6dbb25c7030ee2d100a1bdd6e8bf2d0a`. Its administrator `--info` query
recognized Hawk Point and SMU interface 15 but returned `Unable to get memory
access` / power-table error `-5`. Strict physical-memory restrictions are enabled
in this kernel. The query did not provide the current limits; no limit writes
were requested.
The separate [ryzen_smu driver](https://github.com/amkillam/ryzen_smu) is a
documented alternative for Hawk Point telemetry; it was **not installed**.
The discussed 25 W sustained / 30 W short-term cap remains an untested idea.
Do not record it as the active setup or weaken memory-access restrictions just
to reproduce this fan fix.

**BIOS fan editing:** Beelink documents
`Advanced → Hardware Monitor → Smart Fan Function → CPU Fan Setting`.
The [owner-measured V029 guide](https://www.reddit.com/r/BeelinkOfficial/comments/1hb9igq/ser8_cooling_making_it_even_dead_silent/)
helped identify the controls, but its `.15.08` firmware and reported factory
curve differ from this machine's `.15.13`. The live Linux readout supplied our
actual originals, and direct controller access made a BIOS edit unnecessary.
Beelink's separate 54 W / 65 W BIOS power modes are not Linux's power profiles.

References: [Beelink fan instructions](https://doc.bee-link.com.cn/books/ser8-bios/page/32bb9),
[Beelink power-mode instructions](https://doc.bee-link.com.cn/books/ser8-bios/page/cpu),
[RyzenAdj](https://github.com/FlyGoat/RyzenAdj),
[AMD P-State documentation](https://docs.kernel.org/admin-guide/pm/amd-pstate.html).
