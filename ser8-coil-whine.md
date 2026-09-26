# SER8: faint coil whine, reduced with the same PCIe/idle tweaks as the Zenbook A16

**Machine:** Beelink SER8, Ryzen 7 8745HS, Crucial P3 Plus NVMe (`0000:04:00.0`), Intel Wi-Fi (`0000:02:00.0`),
TP-Link RTL8821AU USB Wi-Fi dongle, kernel 7.2.5-3-omarchy. Date: 2026-09-26.

**Symptom:** a very faint buzz "with gaps in it", audible only with hands cupped behind the ears next to the box.
The gaps track activity (it was busier while background jobs ran). Not the case fan: `fan2` sits steadily at
~755 rpm (pwm 40/255, auto, 23.4 kHz PWM frequency), and not the USB Wi-Fi dongle: unplugging it changed nothing.

**What helped (ear-judged, A/B):** the three levers that worked on the A16, applied together:

- NVMe link out of PCIe ASPM L1 (`link/l1_aspm = 0`)
- Wi-Fi link out of L1
- CPU C3 idle state disabled (`cpuidle/state3/disable = 1` on all cores)

With them on the buzz faded into the background; turning them off brought it back within a minute. Cost: a few
watts at idle on a plugged-in box, nothing else. Not bisected (too faint to bother).

**Permanent:** [`assets/ser8/ser8-whine-tweaks`](assets/ser8/ser8-whine-tweaks) +
[`.service`](assets/ser8/ser8-whine-tweaks.service), installed by
[`assets/ser8/install-ser8-whine.sh`](assets/ser8/install-ser8-whine.sh) (`sudo`), applies at boot;
`ser8-whine-tweaks off` or `systemctl disable --now ser8-whine-tweaks` restores defaults. The one-shot test
script that preceded it lives at `~/bin/ser8-whine-test.sh on|off`.

**Not tried:** the power brick (ear on the brick vs the box), fan speed (`~/bin/ser8-fan-test.sh fast|auto`),
mechanical damping. The full reasoning and every other lever is in the A16 write-up:
[`assets/zenbook-a16/coil-whine-ideas.md`](assets/zenbook-a16/coil-whine-ideas.md).
