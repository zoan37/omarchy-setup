# Zenbook A16 coil whine: the full idea list, from first principles

Status 2026-09-26 midday. Everything measured or ear-tested so far is in the guide, section 8. This file is the
backlog: every lever there is, why it might work, what it costs, and what is known about it. Odds are honest
guesses.

## The physics, in five lines

1. Sound needs a moving part. Silicon does not move. What moves: inductor windings/cores and multilayer ceramic
   capacitors (MLCCs, which flex the board with voltage). Both sit in the switching regulators (VRMs) that feed
   the SoC rails, the memory, the Wi-Fi card, the SSD, the charger.
2. A switching regulator is inaudible while it switches steadily at hundreds of kHz. It becomes audible when its
   behaviour changes at an audible rate: burst/skip mode at light load (fires a few pulses, coasts, repeats at
   1–20 kHz), or load steps (cores waking/sleeping, DVFS voltage moves) that ring the parts.
3. Therefore every fix is one of: (a) keep the regulator out of its light-load regime, (b) make the load
   steady so the tone at least does not wander, (c) stop the part from moving (damping), (d) block or redirect
   the sound path (deck, cover, distance), (e) change the listener (masking, ear).
4. On this board the CPU rail is the main singer (tone follows CPU rail settings), the SSD link L1 state was a
   second, separately measurable one (fixed), and a third follows the Wi-Fi card's power path.
5. Unit variation is real: at least one reviewer's A16 had no audible whine; ASUS calls it a component
   characteristic, not a defect.

## A. Software: done

| Lever | Type | Result |
|---|---|---|
| NVMe PCIe link L1 off (`a16-nvme-aspm`) | (a) | mic: 8.9 kHz tone −83 → −94 dBFS. Kept. |
| NVMe + Wi-Fi PCIe links at Gen1 | (a) | ear, applied with others. Kept. |
| 12 cores offline, remaining cluster at fixed clock | (a)+(b) | ear: biggest change; 4.45 GHz cluster steadiest. Kept. |
| `cpu-sleep-0` idle state off | (a) | mic ±0, ear "helps". Kept. |
| runtime PM forced on (USB/PCI/platform, not GPU/audio) | (a) | ear, applied with others. Kept. |
| cdsp remoteproc stopped | (a) | ear, applied with others. Kept. |
| BIOS 305 → 312 | firmware | ear: slightly better. Kept. |
| fan floor 700 rpm (IDLE_PWM 25) | (e) masking | kept for feel; does not mask the tone. |

## B. Software: tried, no effect (do not retry without a mic)

GPU devfreq/runtime-PM pinning (+6 °C), cpufreq governor, USB/PCI/platform runtime PM alone, NVMe clkpm and
L1.1/L1.2 alone, NVMe APST off (hung the drive 10 min: never again), display 60 Hz / DPMS / brightness, audio
stack, keyboard backlight, Wi-Fi radio off (louder), Wi-Fi link L1 off (louder), Wi-Fi power_save, traffic,
Wi-Fi TX power 5 dBm, adsp stopped (and audio never comes back: never again), core count 6 → 3, panel
self-refresh (not active anyway).

## C. Software: untried

- **Poll idle (`idle=poll` kernel arg).** (a) in its purest form: no core ever executes WFI, the CPU rail never
  sees zero load. Cost: 6 cores spinning, several watts, fan always on, battery life halved. Needs a reboot and a
  mic to justify. Odds it changes the residual: moderate. Odds it is worth the cost: low.
- **Load pacer.** One core kept busy by a tiny loop, the cheap version of poll idle. Same logic, ~3 W.
- **Memory keep-awake.** A loop touching a few MB every millisecond so the LPDDR controller never enters
  self-refresh / the memory rail never idles. Cheap. Odds: low (memory rails were never implicated).
- **Fixed clock at 3.4 / 3.55 GHz on cpu0-5** instead of 4.45 on cpu6-11: different pitch, same steadiness.
  One-line config change if the current pitch ever grates.
- **Device-tree regulator modes.** Qualcomm RPMh regulators accept `regulator-initial-mode = HPM` and
  `regulator-allowed-modes`, which pins an LDO/SMPS out of its low-power mode. On this board the Linux-managed
  rails already report `fast` (HPM), and the CPU rails are run by the OSM/CPR hardware, not Linux. Dead end
  unless a specific rail (e.g. the Wi-Fi card's) is found in `auto`.
- **Deeper idle domains.** On glymur the idle hierarchy is cpu-sleep-0 → cluster-sleep-0 → domain-sleep-0
  (AOSS system sleep, 10 ms min residency). This kernel exposes only state0/state1 per core, so with state1
  disabled the cluster and AOSS domains should never be entered; verify with `/sys/kernel/debug/qcom_stats/`
  (`aosd`, `cxsd`, `ddr` counters: if they stop increasing, the SoC never sleeps) and
  `/sys/kernel/debug/pm_genpd/*/idle_states`. Checked 2026-09-26: `aosd`, `cxsd`, `ddr` counters are 0 and
  `apss` does not move with `cpu-sleep-0` disabled: the SoC never enters any deep domain. Nothing deeper to block.
- **GPU rail on at minimum clock.** The rejected "GPU thing" raised the clock (+6 °C). The cheaper variant keeps
  the GPU's power domain from collapsing (runtime PM `on`, autosuspend off) while clamping devfreq `max_freq` to
  the lowest OPP (310 MHz): rail stays up, clock stays low, cost a few hundred mW. The GPU idles into CX/GX
  collapse 66 ms after every frame, i.e. a power-domain toggle many times a second at the desktop, which is
  exactly the kind of periodic load step that rings parts. Tried: with the GPU device and the GMU held
  `on` at 310 MHz the `gx_clkctl_gx_gdsc` domain still reads off between frames, i.e. the GMU firmware collapses
  the graphics rail on its own and Linux cannot hold it. Dead end.
- **`adreno.disable_acd=1`.** Turns off Adaptive Clock Distribution, a GX-rail droop feature that modulates the
  GPU rail. Boot parameter / module option; untested.
- **Unbind the CPU bandwidth monitors** (`icc-bwmon`, three of them, one per cluster). They re-vote memory
  bandwidth with CPU load, so the DDR/LLCC frequency and the memory rail follow load. Unbinding freezes the
  vote (memory may sit at a low frequency: slower, but steady). Tried 2026-09-26 13:05 by ear: no change; rebound.
- **Constant DDR bandwidth vote** from userspace via the interconnect debugfs test client if the kernel has
  `CONFIG_INTERCONNECT_DEBUGFS_CLIENT`; otherwise no userspace knob (memlat devfreq is still an RFC series).
- **Regulator modes, clarified by the research:** modes are chosen in-kernel only (no sysfs/debugfs override);
  a DT overlay can raise a rail to HPM but RPMh max-aggregates across all voters so nothing can force LPM; the
  CPU rails are run by CPUCP firmware over SCMI and Linux never touches their voltage. Only a DT overlay per
  rail, and only worth it for a rail found in `auto`.
- **Wi-Fi card:** ath12k has no power-save or runtime-PM module parameters; its MHI runtime hooks are no-ops,
  so the card never runtime-suspends. What we control is 802.11 power save (`iw`), the PCIe link states and the
  link speed, all already tried.
- **Wi-Fi 2.4 GHz band.** Changes the card's load pattern, not fixed like a clock. Owner uses 5 GHz; declined.
- **Windows-side comparison.** Does the whine change with Windows "Best performance" power mode? Would tell
  whether Qualcomm's firmware DCVS behaves differently from ours. Curiosity only.

## D. Hardware on the board

- **Silicone on the VRM inductors** (plan: `silicone-damping-plan.md`). Works on parts that physically move.
  Caveat from the research: laptop VRMs use molded/shielded inductors, on which coatings help less than on the
  open toroidal chokes of desktop GPUs; and a coating traps a little heat. Expect softer, not silent.
- **Foam strip inside the bottom cover over the VRM plate.** The cover then presses on the plate and damps it,
  nothing touches the board, fully reversible. A Dell XPS 13/15 write-up did the equivalent with 1.5–2.5 mm
  thermal pads between heatpipe and back cover and reports "a permanent and recognizable reduction of coil
  whine" (plus lower temperatures). Material: **Poron 4701-30 very-soft PU foam, 0.8–1.6 mm, adhesive one
  side** (90 °C rated, insulating, no compression set) or a **1 mm self-adhesive silicone sponge sheet**
  (200 °C, ~$10 on Amazon). Avoid: EVA (softens at 70 °C), Sorbothane (2 mm minimum, 60–70 °C limit), butyl
  Dynamat/Kilmat (aluminium face, conductive), 3M VHB (stiff, bonds both sides). Alternative with a thermal
  bonus: a **1.5 mm soft thermal pad** (Arctic/Gelid) in the same place, which is exactly the XPS mod.
- **Thermal putty on the inductor bases** (Upsiren UTP-8 / TG-PP10, non-curing, non-conductive). Mass-loads
  the parts and conducts heat to the plate; a desktop VRM report calls it solved. Messier than silicone,
  easier to remove.
- **Electrical/Kapton tape over the cluster.** GPU folklore ("90 % reduction" on an R9 280X). Cheap, low odds
  on molded parts, only after the others.
- **SSD swap.** No coil-whine reports found for the PM9C1b; the SSD tone is already handled by the L1 setting,
  and the WD SN770/SN7100 idle at ~1 W regardless. No reason to swap.
- **Charger-side.** Whine while charging with the machine off is usually the board's charger IC in light-load
  mode at the end of charge, or the brick. A ROG Zephyrus G16 owner reports whine only once the 80 % battery cap
  is reached, gone below the cap or with the cap at 100 %. Test: ear on the brick vs on the chassis; brick in
  the wall with nothing attached; try charging from 40 % vs 95 %. A lower-wattage brick (30–65 W) is the most
  reliable quiet option if the charge speed is acceptable; no 65–100 W GaN model has a "never whines"
  reputation (UGREEN Nexode Pro 65 W slim and Apple 96/140 W have whine reports).
- **Exchange the unit.** Unit-to-unit variation is documented; one reviewer's A16 was silent. Owner's view:
  probably already a quiet unit, the ear is the variable. Reasonable.

## E. Sound path and listener

- **Clamshell / stand.** Lid closed with an external monitor removes the keyboard-deck opening; the bottom
  cover still radiates. Distance is the stronger lever: 30 cm further away is ~6 dB less. No published
  evidence either way.
- **Keyboard cover.** Listings claim typing-noise reduction only; a 0.2 mm silicone film does essentially
  nothing to a 5–10 kHz tone. Low odds. No heat issue on the A16 (intakes are underneath).
- **Masking.** Broadband noise at low level from the other machine's speakers raises the floor the tone must
  clear. Works, costs nothing, some people hate it.
- **Ear.** Sensitivity was worst after hours of ear-on-chassis listening; sleep resets it. An earplug in the
  sensitive ear at the desk is silly and effective. A hearing test is worth it given the old injury.

## F. Order I would do them in

The free software ideas are exhausted (GPU rail, bwmon, sleep domains: all checked, see C). Then:

1. Foam or 1.5 mm thermal pad inside the bottom cover over the VRM plate (cover off only, 15 minutes, reversible).
2. Press test on both clusters, then silicone if the press test says yes.
3. Charger test (brick vs board, charge level) and a smaller brick if it is the brick.
4. Only with a quiet room and the mic: bisect the current tweaks (`whine-round8.sh`) and drop the ones that cost
   performance for nothing.
