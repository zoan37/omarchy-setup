# XPS 16 DA16260: custom fan-control investigation

Investigated 2026-09-18, BIOS 1.10.1, kernel 7.2.5-3-omarchy.
Status: **investigation paused; direct fan control is not validated.**
The installed 1.10.1 BIOS region was captured read-only and its fan command
path traced. Dell's current diagnostic client was also inspected offline.
The 120 Hz display, turbo-off trial, and Dell Quiet profile remain in place.

## Current decision — 2026-09-18

The user has not noticed the fan noise today and prefers to revisit this only
if it returns. This is an observation, not evidence that the underlying cause
has been fixed. No custom fan controller is installed, and the F12 diagnostic
test has **not** been performed.

The investigation established that Dell's inspected fan test uses the same
legacy interface as Linux and tests low/high states. BIOS and client return
codes can mask failures; actual manual control and reliable recovery remain
unproven. Offline checks passed: 33 EC-dispatch cases, six recovery scenarios
(12 calls), and 25 diagnostic-client cases. These simulations do not establish
hardware acceptance.

If the noise returns:

1. Use the read-only recorder below during normal browsing and note the time
   of the audible burst, workload, and whether AC power was connected.
2. If further investigation is warranted, save work and enter **F12 →
   Diagnostics** at reboot. The quick test starts automatically; **Esc →
   Advanced Test** allows selecting individual tests. Select the fan tests if
   offered, and record each fan's displayed RPMs, pass/fail result, any error
   and validation codes, and behavior after exiting. Available tests vary.
   See [Dell's diagnostic instructions](https://www.dell.com/support/kbdoc/en-us/000181163/how-to-enter-the-built-in-diagnostics-32-bit-diagnostics-supportassist-epsa-epsa-and-psa).
3. Compare those observations with the evidence below before considering
   another live control experiment. A passing Dell test would establish a
   baseline, not prove that a persistent Linux controller is reliable.

The remaining sections preserve the investigation in chronological stages;
their proposed next steps are deferred under this decision. Vendor binaries,
machine firmware dumps and decompiled code remain outside this repository.

## What we know

Fan bursts persist with turbo disabled. An earlier 30-second capture saw roughly
45–49 °C CPU package temperatures and fans rising from zero to around 3300 RPM.
That does not identify the trigger or prove cooling was unnecessary. Firmware
may consider other sensors, accumulated heat, or thresholds we cannot see.
The sampled X video used Chrome's `VaapiVideoDecoder` with platform decoding
enabled; software video decoding is not established as the cause of that burst.

The previous controllability test failed before requesting low speed:

- Both `pwm*_enable=2` writes returned `EINVAL`.
- Fallback `pwm*=255` writes returned success, but subsequent PWM/RPM readings
  stayed at zero. The user heard no fan. Ignored writes and immediate firmware
  overrides cannot be distinguished by that test.
- No manual-off or low-speed command was sent. Successful automatic restoration
  was **not** demonstrated. The transient probe exited; nothing was enabled at boot.

Local evidence is under `~/.local/state/xps16-fan-test/`: `RESULT.md`, `probe.py`,
`probe-journal.txt`, and `after.json`. Do not rerun that probe as a fan controller.

## What is available in BIOS?

Dell documents **Power → Thermal Management**, visible with **Advanced Setup**
enabled. The local firmware attributes expose these four choices:

| Preset | Purpose |
|---|---|
| Optimized | Balance noise, temperatures, and performance |
| Quiet | Reduce fan noise, potentially sacrificing performance |
| Cool | Favor cooler surfaces with more fan activity |
| Ultra Performance | Favor performance with more fan activity |

The live `dell-pc` platform profile is already `quiet`. Neither the reviewed
model-specific setup documentation nor the exported BIOS settings exposed a
temperature/RPM curve editor, fan-start temperature, or hysteresis setting.
This does not establish what undocumented firmware features may exist.

The BIOS also lists Turbo Boost, C-state control, and SpeedStep. Turbo is already
disabled through Linux for this trial; C-states and SpeedStep support energy
saving and are not knobs to disable in pursuit of quieter idle operation.
No BIOS settings were changed during this investigation.

Sources: [exact-model BIOS settings](https://www.dell.com/support/manuals/en-us/xps-da16260-laptop/xps-16-da16260-service-manual/system-setup-options?guid=guid-6a8ed6f0-16b2-4f4f-a768-19cdd6b7084f&lang=en-us),
[Advanced Setup](https://www.dell.com/support/manuals/en-us/xps-da16260-laptop/xps-16-da16260-service-manual/view-advanced-setup-options?guid=guid-f57cda4e-5cc6-4bf1-b7a0-7a4c31106c5b&lang=en-us),
[Dell's preset descriptions](https://www.dell.com/support/manuals/en-us/power-manager/power-manager_ug/thermal-management?guid=guid-d6b7de5c-0b5c-4594-83e6-063ec77ed108).

## Hardware interface: the unresolved prerequisite

This machine binds `dell_smm_hwmon` through WMI GUID
`F1DDEE52-063C-4784-A11E-8A06684B9B01`. Legacy port-based utilities are not a
drop-in replacement. `dell_ddv` supplies separate read-only sensor access.
See the [i8kutils hardware guide](https://github.com/Wer-Wolf/i8kutils/wiki/Hardware-Guide).

The upstream driver can expose per-fan enable attributes using a heuristic;
their presence is not proof of working automatic/manual switching. Some models
instead need whitelisted global mode commands. The reviewed whitelist has no
DA16260 entry. Reading enable=1 alone does not prove firmware control is off.
See [kernel interface documentation](https://docs.kernel.org/hwmon/dell-smm-hwmon.html).

The reported maximum state here is 2. The driver's PWM conversion maps requests
onto discrete states, so 0–255 does not imply 256 independently selectable speeds.
Assume off/low/high until measurements establish otherwise. The existing WMI
transport already carries the fan calls: a model-specific driver fix could be
enough, without a custom thermal subsystem or whole-kernel fork. That is a
possible implementation route, not a demonstrated fix.
See [upstream driver source](https://github.com/torvalds/linux/blob/master/drivers/hwmon/dell-smm-hwmon.c).

Next backend work:

1. Obtain source matching the installed Omarchy kernel and compare its WMI
   response handling and fan-control logic with upstream. Upstream source is
   explanatory evidence, not proof of the exact installed implementation.
2. Use the installed driver's existing dynamic-debug callsite to trace requests
   and responses; a rebuild is not needed for this initial logging. Establish a model-specific command from Dell evidence,
   a validated same-model implementation, or focused firmware analysis.
3. Test automatic restoration first. Only after that succeeds, test a bounded
   manual high/low request and confirm actual RPM response and persistence.
4. If a supported command pair is established, add an exact-model DMI entry and
   contribute it upstream. If not, a userspace curve editor cannot solve this.

Avoid random firmware opcode scans, blindly borrowing an older XPS's commands,
or continuously overwriting firmware decisions. Kernel documentation reports
side effects from these model-dependent commands.

## Proposed fan policy once the backend works

The goal is fewer audible transitions during normal browsing while retaining
cooling under sustained work. A useful policy would have:

- **Hysteresis:** start cooling above one threshold; stop only below a lower one.
- **Persistence:** brief, moderate spikes do not immediately start a fan. A high
  raw temperature bypasses the delay.
- **Slow decreases:** hold a low state long enough to remove accumulated heat,
  rather than immediately cycling back to off. Higher cooling demand wins over
  minimum-off or ramp timers.
- **Multiple sensors:** separate CPU, memory, and board limits. Do not take the
  maximum Celsius value across unlike sensors and apply a CPU threshold to it.
- **Verified recovery:** restore firmware control on sensor loss, stale data,
  actuation failure, process failure, and before suspend. Revalidate after resume.
  A `finally` block alone cannot handle a killed or wedged process; a separate
  watchdog and kernel-supported restoration are needed. Software watchdogs also
  cannot guarantee recovery from a kernel hang.

Exact temperatures and delays remain unset: the board sensors' meanings and
limits need validation. A policy simulator can compare candidate switching
behavior, but replaying stock-fan temperatures cannot prove that reduced cooling
would keep temperatures safe. Controlled live testing would still be necessary.

If low fan speed is itself loud, fewer starts may require longer audible running
or a warmer chassis. Software cannot guarantee both complete silence and the
same temperatures/performance.

## Recorder available now

[`assets/xps16-fan-control/record.py`](assets/xps16-fan-control/record.py) uses only
Python's standard library and runs without root. It discovers Dell DDV fans,
hwmon temperatures, and thermal zones; records aggregate CPU utilization; and
reports sampled fan starts/stops alongside temperatures. It does not poll
`dell_smm`, write fan controls, or collect browser URLs/process command lines.
Sensor errors are retained as missing data, never interpreted as zero RPM.

Capture 15 minutes while using the browser normally:

```bash
cd ~/omarchy-setup
python assets/xps16-fan-control/record.py record --duration 900 \
  --output "$HOME/.local/state/xps16-fan-test/browsing-$(date +%Y%m%d-%H%M%S).jsonl"
```

The script prints the saved filename. Summarize that file:

```bash
python assets/xps16-fan-control/record.py summarize /path/to/recording.jsonl
```

Ctrl+C ends a capture and preserves completed samples. No service is installed.
Discovery runs at startup; restart the recorder after suspend or driver reload.
Records include read duration because sensors are sequential reads, not an atomic
snapshot. A 2-second default interval can miss shorter events. CPU utilization
is across all cores (unlike Chrome's per-core percentage).

Validation: a 60-second live capture produced 30 samples with no sensor read
errors; CPU package was 44–46 °C and both fans stayed stopped. No burst was
captured, so this does not explain the intermittent behavior. The longest sensor
read pass was 191 ms. Synthetic start/stop and missing-reading checks passed.
The capture and summary are `readonly-baseline.jsonl` and
`readonly-baseline-summary.json` in the local evidence directory above.

Another DA16260 Omarchy owner reported using Dell Quiet to reduce unwanted fan
activity in [Omarchy PR #6346](https://github.com/omacom/omarchy/pull/6346). That
supports exposing Dell's presets, not a verified custom controller for this model.

## Firmware-interface investigation: 2026-09-18 follow-up

**No verified manual-control backend found yet.** Investigation now includes
local decompilation, not only searching for utilities. No fan-control writes,
BIOS changes, replacement modules, or ACPI overrides were performed in this
follow-up. Temporary driver debug logging was restored to its original disabled
state after four read-only queries.

### Work completed on this laptop

- Copied DSDT plus 28 SSDTs and nine WMI binary MOF schemas into
  `~/.local/state/xps16-fan-research/`. All 29 ACPI table lengths/checksums validate.
  The Windows license table was not copied.
- Disassembled the ACPI tables with ACPICA `iasl` and decoded the WMI schemas
  with [pali/bmfdec](https://github.com/pali/bmfdec), commit
  `c7b72f6ece126a8f686d66402009a14cb032a769`.
  Combined ACPI disassembly encountered duplicate names; individual disassembly
  succeeded for all 29 tables. These are analysis outputs, not replacement tables.
- Compared the exposed interfaces with DellFanManagement source at commit
  `0fc35c682c8013403ce6ff5796e9c9f8015d8685` and
  [Dell's public token definitions](https://github.com/dell/libsmbios/blob/master/doc/token_list.csv).
- Obtained upstream Linux v7.2.5 `dell-smm-hwmon.c`. Its debug callsite at line
  326 matches the installed driver's reported location. Omarchy patch equivalence
  has not been established; this is not a byte-for-byte source provenance claim.
- Enabled only the installed `dell_smm_call` diagnostic message, read both fan
  states and RPMs once, then restored logging. All four calls returned zero
  status with zero state/RPM, taking 3180–4344 microseconds. This confirms working
  read transport, not functioning fan actuation. Saved as `read-only-smm-trace.json`.

### What the decompiled interfaces reveal

| Route | Local evidence | Implication |
|---|---|---|
| LegacyDiags over WMI | `DIAG.WMDM` marshals registers and forwards through `GENS(0x23, ...)` into SMM | The ACPI wrapper does not reveal the fan policy or accepted SMM command set |
| SMBIOS `BFn` / BIOS tokens | Interface exists; known fan-override and fan-speed tokens are absent from the exported table | Windows token-based examples are not a demonstrated fallback here |
| EC `OpaqueAccess.FixedCmd` | `ECMO.WMFC` calls `ECDV.FCEX`; that method simply returns zero | The advertised fixed-command entry point is a stub in the captured DSDT |
| EC `OpaqueAccess.VarCmd` | MMIO buffer/doorbell path exists | A possible research lead, but the schema supplies no fan command IDs or semantics |
| DDV | Explicit fan and thermal sensor query methods | Useful telemetry; no identified manual fan-control method |

Local source references: `acpi/DSDT.dsl` around lines 39365–39545 (LegacyDiags),
41758 (`FCEX`), and 86152–86250 (EC dispatch), plus `bmof/*-20.mof` and
`bmof/*-25.mof`. `fan-token-inventory.json` records which known configuration
tokens were checked. Fan RPM sensor tokens are exposed separately; absence of
configuration tokens is not absence of readable sensors or proof that every
undocumented control route is impossible.

The Windows project's
[token backend](https://github.com/AaronKelley/DellFanManagement/blob/0fc35c682c8013403ce6ff5796e9c9f8015d8685/DellSmbiosSmiLib/DellSmbiosSmi.cs)
uses override tokens `02FD/02FE` and fan-speed tokens `0332`–`0335`, `0405/0406`.
All are absent here, as is Dell's `03C4` auto-curve intensity token. The project's
maintainer describes a changed interface and missing control support on newer
Dell generations in [issue #14](https://github.com/AaronKelley/DellFanManagement/issues/14).
That issue spans other models; it does not establish a permanent restriction on
the DA16260. Exact-model searches found no validated replacement command.

### What needs decompiling or recompiling next?

1. **Interface descriptions:** already decompiled locally. No firmware changes
   were needed, and existing
   [kernel dynamic debug](https://docs.kernel.org/admin-guide/dynamic-debug-howto.html)
   provides initial tracing without rebuilding anything.
2. **SMM/EC command implementation:** inspect an official BIOS update image offline.
   [BIOSUtilities](https://github.com/platomav/BIOSUtilities) includes a Dell PFS
   extractor; [UEFITool](https://github.com/LongSoft/UEFITool) can inspect firmware
   volumes. The follow-up below extracted BIOS 1.9.0 and traced its diagnostic
   handler with Capstone. The later installed-image follow-up also traces 1.10.1;
   static analysis alone does not demonstrate a working control API.
3. **Linux module:** only after identifying the command and its recovery behavior,
   build a narrow driver change against the installed kernel headers. A known
   global command pair could fit the existing driver; a new EC protocol would
   need more work. A whole-kernel rebuild is not the starting requirement.
4. **BIOS rebuild/flash:** there is currently no evidence this is required or a
   justified path. Studying a downloaded image is different from modifying it.

The next useful milestone is an evidence-backed command with confirmed RPM
response and a working automatic-mode restoration path. A curve daemon remains
dependent on that result; compiling code alone cannot create a firmware feature.

## Official BIOS extraction and command tracing

### Image provenance and limits

Dell publishes a combined **XPS 14 DA14260 / XPS 16 DA16260 BIOS 1.9.0**
package, dated July 10, 2026:
[Dell download page](https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=6RJ7J).
Downloaded `XPS_DA14260_DA16260_1.9.0.exe` (26,356,832 bytes) and verified its
SHA-256 against Dell's published value:

```text
c8d3932a8396780c5a4f2f720a248022d71180a6cdd45f02213d57e441b4da72
```

**This is older than the installed 1.10.1.** These findings apply to the
downloaded package, not proven behavior of the running firmware. Searches,
LVFS metadata, and Dell's exact-model `0DBA` client catalog did not yield a
matching 1.10.1 BIOS package during this investigation. The model catalog
contained drivers/utilities but no BIOS entry.

Extracted Dell PFS with BIOSUtilities 25.7.1 and firmware volumes with
UEFIExtract A75. Used `pefile` and Capstone 5.0.9 for static x86-64 analysis.
Analysis dependencies live in a local Python virtual environment. No BIOS
updater was executed, firmware flashed, or fan-control command sent.

The package contains system BIOS plus EC 1.4.2 and backup EC 1.0.0 payloads.
PFS reconstruction fills an omitted initial BIOS region; it is an update-image
reconstruction, not a complete SPI flash dump. The extracted EC payloads have
not themselves been disassembled. The trace below concerns BIOS-side code
that sends commands to the EC.

### Concrete command path found in 1.9.0

The older global manual/automatic commands are present, with actual calls
through to EC I/O. This makes them evidence-backed candidates for further
investigation; it does **not** validate running them on 1.10.1.

All addresses below are relative virtual addresses in the named extracted
PE modules, not live kernel or firmware addresses.

| Layer | Static evidence | Meaning |
|---|---|---|
| `DellDiagsLegacy` | Command table at `0x6200`; entries for command bytes `30/31/34/35` at `0x6500`–`0x6530` | The traditional `0x30a3/0x31a3` and `0x34a3/0x35a3` pairs reach the same two handlers |
| Legacy handlers | `0x2878` jumps to `0x2844`; `0x28b4` jumps to `0x2880` | Two aliases, not four independent control implementations |
| Diagnostic protocol | GUID `31e9fb14-51e2-46e9-9f81-f2ca52fcb2b4`; table in `DellDiagsMm` at `0xa418` | Manual calls offset `+0x50` → `0x3374`; automatic calls `+0x58` → `0x33d8` |
| EC protocol | GUID `f8beaa12-ad44-4092-5582-49f244451f95`; table in `DellEcMm` at `0x13de0` | Manual calls offset `+0x40` → `0xdc14`; automatic calls `+0x48` → `0xdc34` |
| EC I/O arguments | Both EC functions pass command `0xfa`, one argument; manual passes `4`, automatic passes `3` | Distinct BIOS-to-EC requests exist; actual EC acceptance remains unverified |
| EC I/O transport | GUID `7310e28e-96ea-4360-946e-5adc6be8f531`; `DellEcIoMm` table `0x5190`, method `+0x18` → `0x1654` | Copies command/argument bytes into the transport buffer and calls the send/read path |

The mode names come from tracing the existing legacy command semantics; they
are not recovered source-level function names. `0xfa` is an internal EC
command here, **not an instruction to write that byte to an arbitrary port**.

**Critical finding: the legacy global-mode handlers discard the backend's
return status and return zero in AX.** A successful Linux write or SMM return
therefore cannot establish that automatic restoration or manual takeover
worked. The backend can report failure that the outer layer hides. This is
specific evidence from 1.9.0; it does not retroactively prove the cause of the
earlier unsuccessful PWM test.

There are additional side effects to understand: `DellDiagsMm` calls helper
`0x3318` before switching modes, conditionally writing an internal property
numbered `0x429`. It also conditionally invokes another backend afterward.
Their full purpose and model-dependent execution remain unresolved. Bypassing
the BIOS and sending only the EC bytes could omit required coordination.

Per-fan requests also have a real path: protocol method `+0x20` in
`DellDiagsMm` reaches `0x30b4`, then EC method `+0x10` at `0xd95c`, and helper
`0xd780` sends EC command `0x2e` with five argument bytes. The helper reads
response bytes back. This proves a BIOS-side implementation exists, not which
fan states the installed EC accepts or whether firmware immediately overrides
them. It does not establish a programmable temperature/RPM curve.

### Reproducing the evidence and next milestone

Local artifacts are under `~/.local/state/xps16-fan-research/`:

- `download-manifest.json`: package source, checksum, and version mismatch.
- `bios-1.9.0/`: extracted components and UEFI volumes.
- `modules-1.9.0/`: extracted PE modules and assembly listings.
- `inspect-fan-path.py`: offline evidence extractor; run with
  `analysis-env/bin/python inspect-fan-path.py` from that directory.
- `fan-path-evidence.txt`: selected command entries, protocol tables,
  disassembly, and SHA-256 values for the four modules in this trace.

Downloaded vendor firmware and machine-derived analysis artifacts are kept
outside this repository. The evidence script ran successfully against the
checksum-verified package.

At this stage, the next task was to obtain/compare 1.10.1 and resolve mode-switch
side effects. Then design a bounded test that establishes automatic-mode
recovery and confirms actual RPM response/persistence; a zero return code is
insufficient. Only after that should an exact-model driver change or curve
daemon be considered. **There is still no demonstrated need to rebuild or
flash a modified BIOS, and no reliable custom fan controller yet.**

## Installed 1.10.1 captured and compared

The version gap above is now resolved for the BIOS-side fan-command path.
DMI reports 1.10.1 dated July 20, 2026; ESRT reports version `0x010a0100` with
firmware class `2c1b48e9-b12c-4cc3-a00b-2ab01b08e229`.

Further download checks found 1.8.2 in LVFS stable, 1.9.0 in LVFS testing,
and at most 1.8.2.0 in the Microsoft Update Catalog for that exact firmware
identifier. Dell's driver-bootstrap API returned HTTP 403. No cached recovery
image was present in `/boot`, and fwupd was not installed. None of those
download channels was used to update or downgrade the laptop.

Instead, the already-bound Linux SPI/MTD driver exposes `/dev/mtd1ro`.
Opening it with `O_RDONLY` and reading its upper 32 MiB, offset `0x2000000`,
successfully copied the BIOS region. An initial whole-device read at offset
zero failed with `EIO`; its empty output was removed. No protection was disabled,
no driver loaded, and no flash writes or unlock operations were performed.
This is a BIOS-region capture, not a complete 64 MiB chip dump.

The capture and derived files remain local, with private permissions. The
capture SHA-256 is:

```text
7fad1686cffb44adab7bcc55a73ad661ca969b48420f0ab371144b6684fe0e8e
```

UEFIExtract parsed the region successfully. Comparison of extracted modules:

| Module | Comparison with downloaded 1.9.0 |
|---|---|
| `DellDiagsLegacy` | Entire PE module identical, including handlers that hide backend errors |
| `DellSbMm` | Entire PE module identical, including the conditional platform-state helper |
| `FanIdm` | Entire PE module identical |
| `DellDiagsMm`, `DellEcMm`, `DellEcIoMm`, `DellThermalDebugMmDriver` | Changed; relevant fan-mode paths were retraced rather than assumed identical |

Confirmed 1.10.1 addresses:

| Function | Installed-image evidence |
|---|---|
| Diagnostic protocol table | `DellDiagsMm` at `0xa428`; manual `+0x50` → `0x34ac`, automatic `+0x58` → `0x3510` |
| Per-fan request | `DellDiagsMm` `+0x20` → `0x31ec`; EC dispatcher at `0xd978`, helper `0xd79c` |
| EC manual/automatic | `DellEcMm` table still at `0x13de0`; `+0x40` → `0xdc30`, `+0x48` → `0xdc50` |
| EC command arguments | Still `0xfa` with one argument: manual `4`, automatic `3` |
| EC transport | `DellEcIoMm` table still `0x5190`; `+0x18` → `0x1654`, send/read helper now `0x3558` |

### Why this is not yet a simple safe toggle

Tracing the extra backend identified protocol
`bdcffdbd-aac1-4704-8f49-ec25064324c0`, implemented by `DellSbMm`.
Its table at `0x6260` maps `+0x28` to `0x2788` and `+0x30` to `0x27d0`.
The manual path increments an internal counter; the automatic path decrements
it, and only restores the saved platform state when the counter reaches zero.
The first manual call saves state and writes hardware I/O registers at
`0x1802`, `0x1830`, and `0x187c`; restoration also touches MMIO registers.
Their full hardware meanings have not been established here. These helpers
are conditional on successful EC transport and available protocols; static
analysis does not prove their runtime execution or initial counter value.

This is concrete evidence that repeated manual-mode calls cannot be treated
as an idempotent operation. Multiple successful acquisitions may require
matching releases. A controller must not retry the command blindly or have
multiple independent cleanup paths send uncoordinated restores. An interrupted
request can leave ambiguous ownership, especially because the legacy handler
hides backend errors. Sending an automatic command alone cannot prove recovery.

The other helper, now `DellDiagsMm:0x3450`, still conditionally writes property
`0x429` under GUID `417acee0-6fa9-4a82-99d7-f9b1dd271e48`: zero on manual entry,
the saved value on automatic entry. Its purpose remains unidentified. Direct
EC writes would bypass these BIOS-side steps, so they are not yet a validated
alternative either.

### Evidence and requirements for a live probe

Local research artifacts:

- `installed-capture-manifest.json`: acquisition method, version and search results.
- `installed-bios-region-1.10.1.bin`: private BIOS-region capture.
- `modules-1.10.1/` and `installed-module-comparison.json`: extracted modules,
  hashes, assembly and comparisons.
- `inspect-installed-fan-path.py` and `installed-fan-path-evidence.txt`:
  reproducible offline checks of the capture hash, table addresses and code.

The evidence script completed successfully. No live manual/automatic command
was sent during this follow-up. BIOS recompilation or flashing is still not
needed to continue investigating the interface.

A live probe needs more than a whitelist entry: first establish an observable
mode/EC acknowledgment and recovery path, and resolve the additional platform
state changes. Any later probe should have one owner, one balanced transition
pair, no blind retries, independent temperature/RPM observation, and a bounded
high-speed request before considering low or off. Automatic recovery must be
demonstrated through behavior or a validated state query, not an AX=0 response.
Neither a persistent service nor a custom curve has been installed.

## Mode-readback investigation

**Result: no validated global-mode readback or recovery verification found.**
The bounded high-speed takeover test was not run. This is an interface gap,
not something that compiling a controller alone resolves.

The reviewed upstream v7.2.5 driver explicitly describes the global automatic/
manual switch as write-only because it has no command to retrieve its current
state. Its separate per-fan `pwmX_enable` read maps fan state 3 to automatic and
every other state to manual. That heuristic is not a verified global-mode
query on this laptop. See
[driver implementation](https://github.com/gregkh/linux/blob/v7.2.5/drivers/hwmon/dell-smm-hwmon.c#L848).
Earlier successful status/RPM reads therefore do not close the recovery gap.

### Additional BIOS routes examined

- `DellThermalDebugMmDriver` in installed 1.10.1 has a dispatcher at `0x2bc0`.
  Operations 2–5 and 9–16 explicitly return `EFI_UNSUPPORTED`. Operations
  17–25 delegate to protocol `898415a1-06f1-4c21-b83a-c555cf2f2364` via helper
  `0x2a88`. A literal-GUID search across 849 extracted PE bodies found only
  this consumer, at `0x40e0`, and no identified provider. That does not rule
  out dynamically constructed GUIDs or a provider outside the captured region;
  it does mean a usable backend has not been established. The delegated
  operations' meanings remain unidentified.
- `DellEcMm:0x5144` constructs EC command `0xfa` with argument `6` and reads
  one response byte. It is a research lead, **not a proven fan-mode query**.
  Its response semantics and an appropriate public calling route are unknown.
  It was not executed. Numerical proximity to the mode commands `3/4` is not
  evidence that it reports their state.
- Internal property `0x429` remains unidentified. Dell's public SMBIOS token
  `0429` names ASPM, but these are different interfaces/namespaces; matching
  numbers alone do not justify identifying the internal property as ASPM.

Evidence: local `audit-mode-readback.py` and `mode-readback-evidence.txt`.
The offline script ran successfully; it never accesses hardware.

### EC code is encrypted in the available update package

All four EC components extracted from the downloaded BIOS 1.9.0 package
(EC 1.4.2 and backup EC 1.0.0 variants) have a Microchip `PHCM` header,
header version 5, and flags byte `header[6] = 0x80`.

The encryption flag was checked against Microchip's official
[MEC175x image generator](https://github.com/MicrochipTech/CPGZephyrDocs/tree/main/MEC175x/SPI_image_gen).
Its ELF debug information names `Header.FwEncrypted` at structure offset
`0x52`; the `Header.Marshal` routine at `0x562069`–`0x562072` maps that field
to bit 7 of output header byte 6. Its header-version encoder emits version
5 or 6. This confirms the encryption indication using the relevant newer
format, rather than relying only on entropy or an older chip's documentation.
The generator was inspected statically, never executed.

This prevents straightforward disassembly of those EC payloads with the
artifacts currently available. It does **not** establish the installed EC
version, prove that every diagnostic route is unavailable, or imply that
BIOS flashing is necessary. The captured installed BIOS region contained no
literal `PHCM` header; it is not a captured plaintext EC image.

Local `ec-encryption-audit.json` records component hashes and header fields.
`mec175x-encryption-evidence.txt` records the generator disassembly and DWARF
field mapping. Generator SHA-256:
`a68f585aa369c468fea7c2ec4686fcf81b1028a82208983f0385768a77ebc21d`.

### Next step identified at that stage

Obtain model-specific interface guidance or a reviewed working implementation
that explains mode acknowledgment and restoration, including the conditional
platform-state changes. A dedicated mode query would be useful, but an
independently validated behavioral recovery procedure could also suffice;
the present investigation has established neither.

A [technical inquiry draft](assets/xps16-fan-control/interface-inquiry.md)
captures the exact questions for Dell or the Linux driver maintainers. It has
not been sent or published. No fan writes, firmware changes, debug-mode
activation, or kernel-module changes were made in this investigation.

## Further reverse engineering: a reachable EC dispatcher

**2026-09-18 result:** installed BIOS 1.10.1 exposes another EC interface through
Dell SMBIOS class 28, select 2. One fixed query succeeded through the existing
Linux WMI driver. This is a new research route, not validated fan control.

### Registration and command mapping

`DellEcMm:0x10391` registers handler `0xfbcc` for class `0x1c`, select 2.
The registration protocol is `67666768-9c64-4caa-baf4-ca3e4cb7697a`.
Its producer, `DellSmBiosDaCiMm`, installs a table at `0x20ce0`; registration
method `0x3770` takes a class and inclusive selector range. This confirms
that the two register arguments containing 2 describe select 2, rather than
an assumed operation or access flag. Handler input 0 chooses a sub-operation.

The following mapping was checked against extracted machine code and an
offline Unicorn emulator with simulated protocol services:

| Input 0 | EC command / argument bytes | Result in the BIOS handler |
| --- | --- | --- |
| `2` | `38 / 00` | Reads 9 bytes and converts three character pairs into a packed value resembling a version. |
| `3` | `fa / 0d ff` | Reads one byte into output 1; meaning unknown. Input 0 = 4 is a related setter and was not called. |
| `9` | `2e / 08 00 00` | Reads four bytes; copies response bytes 1 and 2 into outputs 1 and 2. Meaning unknown. |
| `10` | `2e / 0a 00 00` | Same output-byte mapping as operation 9, with a different EC subcommand. Meaning unknown. |
| `0x81`, input 1 = 1 | `fa / 04` | Same EC command as manual takeover; requires the manufacturing-mode check below. |
| `0x82`, input 1 = 1 | `2e / 09 00 01 01 00` | Gated setter in the fan-command family; reads one response byte but does not inspect it. Exact control meaning unknown. |

These are observed BIOS transactions, not a public EC specification. In
particular, operations 3/9/10 have not been established as global-mode,
fan-duty, or curve queries. Receiving data is not enough to establish their
side effects or units. Only operation 2 was invoked on the laptop.

### Manufacturing-mode gate and error behavior

The setters at operations `0x81` and `0x82` call `DellEcMm:0xef84`.
It queries protocol `332ccfed-e5e7-49ab-820d-e34a54ed3f57` with IDs
`5, 12, 0` and rejects a zero result or an EFI error.

The identified producer is `DellMfgModeMm`, table `0x4170`, method
`0x2b84`. This is a variadic flag query, terminated by 0. Its mapper
`0x3d24` maps ID 5 to mask `0x40` and ID 12 to `0x2000`; the caller accepts
either flag. Their descriptive mode names and the live flag values remain
unknown. No manufacturing flag was enabled, and no gate was bypassed.

Unlike the legacy global switch's unconditional success response, these
operations convert an EC transport EFI error to SMBIOS status -1. However,
that still does **not** prove EC acceptance. Operation `0x82` ignores its
one-byte EC reply; a synthetic nonzero reply still produces status 0 when
the simulated transport succeeds. This route therefore does not yet solve
the acknowledgment or automatic-recovery problem. No paired automatic
restore operation has been identified in this dispatcher.

### Single live query

The existing `/dev/wmi/dell-smbios` device was opened read-only. Using the
[Linux WMI ABI](https://github.com/gregkh/linux/blob/v7.2.5/include/uapi/linux/wmi.h)
and [driver implementation](https://github.com/gregkh/linux/blob/v7.2.5/drivers/platform/x86/dell/dell-smbios-wmi.c),
the fixed class/select/input tuple was `(28, 2, [2, 0, 0, 0])`.
Opening a device read-only does not itself make arbitrary ioctls safe;
this query was selected by tracing its specific BIOS handler first.

- Time: `2026-09-18T15:09:48Z`.
- Required buffer size: 32,776 bytes.
- Returned outputs: `[0, 66817, 0, 0]`; status 0, value `0x010501`.
- Elapsed call time: 5.131 ms.
- The value appears to encode **EC version 1.5.1**. This interpretation is
  inferred from the BIOS decoder and version-shaped value, not independently
  confirmed by a named Dell version field.

This establishes that class 28/select 2 is reachable in the current boot.
It does not establish that its gated control operations are available.
The apparent EC version also differs from the downloadable BIOS 1.9.0
package's EC 1.4.2 payload; that older payload should not be treated as the
installed EC image.

### Reproducibility and next investigation

[emulate-ec-dispatch.py](assets/xps16-fan-control/emulate-ec-dispatch.py)
requires `pefile` and `unicorn` and accepts the privately extracted
`DellEcMm.efi`. It refuses a different module SHA-256, maps code only into
emulated memory, intercepts all selected external calls, and stops on
unexpected execution. It never opens hardware devices. No vendor firmware
bytes are included in the repository.

All **20 offline cases passed**, checking command bytes, byte selection,
transport success/failure, and rejection/acceptance with synthetic
manufacturing-query results. These tests validate BIOS-side behavior under
the stated mocks; they do not emulate the embedded controller.

Local artifacts in `~/.local/state/xps16-fan-research/`:

- `ec-dispatch-emulation.json`: complete simulated results.
- `query-ec-version.py` and `ec-version-query-result.json`: fixed live query
  and its result; the script has no arbitrary command argument.
- `modules-1.10.1/DellSmBiosDaCiMm.*` and `DellMfgModeMm.*`: additional
  extracted modules and disassembly used for registration and gate tracing.

The next useful reverse-engineering target is the meaning of the two-byte
query results and the EC reply ignored by the setter, plus a matched restore
path. Firmware-side callers or matching diagnostic software could identify
these without guessing live commands. This follow-up made no fan-control
writes, cooling-profile changes, BIOS modifications, or kernel changes.

## Recovery-path follow-up: failure handling verified offline

**2026-09-18:** additional reverse engineering confirmed several ways the
legacy takeover/restore sequence can leave partial state behind. No additional
live EC commands were issued in this follow-up. The two-byte query meanings
remain unresolved; no custom curve or controller was installed.

### Search results and limits

Scanning the extracted PE bodies for both core-EC protocol GUIDs identified
18 modules. Candidate indirect calls at offsets `0x1f0`, `0x1f8`, and `0x250`
in the diagnostics modules belong to the diagnostics protocol, not the core-EC
protocol. In particular, `DellDiagsMm:0x1bc0` locates GUID
`31e9fb14-51e2-46e9-9f81-f2ca52fcb2b4`. Matching a method offset alone would
have produced a false lead to the `fa / 06` query.

A separate scan of literal EC-I/O GUID consumers for `mov edx/dl, 0x2e/0xfa`
found no additional identified caller of the class-28 queries. The additional
real transactions found were a `2e / 03 ...` read in `DellAdvSysMgmtMm` and
`fa / 0f 04 ff` in `DellErrorHandlerMm`; neither identifies operations 8/10.
Other immediate-value hits were unrelated string processing. These are
bounded literal/instruction-pattern searches: indirect wrappers, dynamically
formed commands and code outside the captured region can evade them.

`DellSimulatedECMm` and the thermal-debug/diagnostic DXE modules were also
extracted for inspection; no meaning for the query bytes was established.
Generic setup resources contain fan-control labels, including desktop fan
zones. Their presence does not establish availability on this laptop.

### What the legacy recovery sequence actually does

[emulate-legacy-recovery.py](assets/xps16-fan-control/emulate-legacy-recovery.py)
runs the installed `DellDiagsMm` routines `0x34ac`/`0x3510` and `DellSbMm`
routines `0x2788`/`0x27d0`/`0x20bc` in Unicorn. It validates the module hashes
before using fixed addresses. EC calls, property storage and I/O are mocked;
MMIO is emulated RAM. Unexpected execution and unexpected I/O ports fail
closed. No host device or physical memory access occurs.

Six scenarios, comprising 12 calls, passed:

| Simulated sequence | Observed BIOS-side result |
| --- | --- |
| One manual entry, one automatic exit | Counter goes 0 → 1 → 0; saved I/O values and property are restored in the model. |
| Two manual entries, one exit | Counter remains 1; saved platform I/O state is not restored until a second exit. |
| Manual entry succeeds, automatic EC transport fails | Counter remains 1 and platform I/O remains masked; the property has already been restored. |
| Manual EC transport fails | The property has already been changed to 0 and is not rolled back; the platform counter remains 0. |
| Automatic property write fails, EC transport succeeds | Internal restore returns success and restores the saved I/O state, but the property remains changed. The property-write error is discarded. |
| Automatic exit without a matching entry | EC automatic command is attempted, then the southbridge helper returns `EFI_NOT_READY` because its counter is 0. |

These are outcomes of the actual BIOS instructions under the specified mocks,
not observed failures on the laptop. The EC model reports transport status;
it does not prove the controller obeys either mode request. Physical register
locking, write semantics, concurrent firmware activity and suspend/resume are
not represented by the model.

The first successful entry saves state and writes I/O `0x1802 = 0`,
`0x1830 &= 0x23`, and `0x187c = 0`. The final balanced exit restores the
saved values, preserving the current `0x23` bits at `0x1830`. It also restores
saved bit-0 values at four MMIO registers starting at `0x40006a1e80`, stride
8, and writes corresponding values through a second register mapping.
The full hardware meaning of those MMIO operations remains unverified.

Consequently, this legacy path has stateful effects beyond choosing a fan
level. Blind retries are not idempotent, and a process-exit handler cannot
guarantee recovery if the EC transport has failed. The previously traced
outer legacy wrapper further masks internal EFI errors by forcing AX=0.
These findings do not explain the user's intermittent fan bursts.

### Additional class-28 checks

The original dispatcher harness now passes **33 cases**. Added cases verify:

- Operation `0x81` rejects input-byte values 0, 2, 3 and 255 before the mode
  gate. Static control flow accepts only byte value 1. Changing its argument
  to 0 is therefore not a matching automatic-restore command.
- Operation `0x82` passes the low byte of input 1 into EC transaction
  `2e / 09 00 01 xx 00`, including truncation of 256 to 0 and 257 to 1.
  This says nothing about valid EC ranges, units, RPMs or supported fan-speed
  granularity; the parameter's meaning remains unknown.
- Synthetic reply bytes 0, 1 and 255 all yield the same successful output
  when transport succeeds. The reply is ignored; its status meaning is still
  unknown, so no value has been assumed to mean accepted or rejected.

### Artifacts and consequence for a controller

Local results are saved as `legacy-recovery-emulation.json` and the updated
`ec-dispatch-emulation.json`. Search records are in
`core-ec-consumer-scan.json`, `ec-command-callsite-scan.json`, and
`property429-callsite-scan.json` under the existing private research directory.
Both emulator scripts are in this repository; the vendor binaries remain
outside it.

We have a software-level restore path, but not a verified recovery mechanism
for a persistent controller. The useful remaining evidence would be a named
EC query/acknowledgment and a restore method validated for the same control
route, potentially from a matching Dell diagnostic client or EC specification.
Until then, installing a controller would hide unresolved interface behavior
behind a temperature curve. No firmware recompilation is needed for this
continuing interface investigation.

## Dell diagnostic-client investigation — 2026-09-18

Inspected the current publicly downloadable SupportAssist hardware diagnostics
offline. No Dell installer or diagnostic was run on this laptop, and this
investigation made no fan, EC, firmware or power-setting changes.

### Package provenance

The [official SupportAssist bootstrap](https://downloads.dell.com/serviceability/catalog/SupportAssistInstaller.exe)
identifies Dell's [agent catalog](https://saupdates.dell.com/serviceability/catalog/SUPPORTASSISTAGENTCATALOG.CAB).
That catalog supplied the x64 5.2.1.2141
[HWDIAGS package](https://saupdates.dell.com/serviceability/Catalog/x64/5.2.1.2141/HWDIAGS.cab).
Its 71,755,845-byte download matched the catalog SHA-256:
`61874374b46cd56895f817a9e40cd20979e5bb72ca70632b289164e3615c678a`.
This is a generic PC diagnostics package, not proof of runtime support for
the DA16260. A separate UEFI diagnostics download found during research was
for servers and was excluded.

The relevant extracted modules are:

| Module | File version | SHA-256 |
| --- | --- | --- |
| FanDiagnostic.dll | 2.2.0.452 | `4022193b29be79ad4f26baf9b607af242453a8b6f3863203b38fe3ae5b04389d` |
| BIOSIntf.dll | 4.0.1.0 | `22efd37d5058d5e11789b54339237f8d9d7c2c15d032a837689f2c61302d3d87` |

Vendor binaries, decompiled code and download manifests remain in the private
research directory, under `diagnostics/`, outside this repository.

### Named test and the actual transport

The mixed native/managed `FanDiagnostic.dll` contains `cFan.fFanSpeedTest`
(metadata token `0x06000012`, RVA `0x4398`). Its BIOS-backed test saves the
initial fan state, tests states **1 and 2**, samples RPM against tolerances,
and attempts to restore the saved state. It pairs manual entries with
automatic exits, including nested entry/exit sequences. This supplies evidence
for discrete low/high testing; it does not establish an arbitrary PWM curve,
valid RPM targets, or a readable global automatic/manual mode.

The client protocol table at RVA `0x7b780` maps to these native wrappers:

| Purpose | Table slot | Wrapper RVA | Legacy AX request |
| --- | --- | --- | --- |
| Read per-fan state | `0x18` | `0x10d60` | `0x00a3` |
| Set per-fan state | `0x20` | `0x10d70` | `0x01a3` |
| Read RPM | `0x28` | `0x10d90` | `0x02a3` |
| Enter manual control | `0x50` | `0x10e90` | `0x30a3` |
| Return to automatic control | `0x58` | `0x10ea0` | `0x31a3` |

The state setter passes the fan index in BL and the low byte of the level in
BH. Its third argument does not become a separate RPM or PWM target in this
wrapper. Byte truncation alone says nothing about which values the EC accepts.

For the initialized WMI route, the wrappers go through the adapter at
`0xba40`, then `BIOSIntf!CDiagsIntf.Execute` (RVA `0x40e90`).
`CDiagsIntf.InitializeDiagsClass` (`0x42990`) selects **LegacyDiags.Execute**
with EAX/EBX/ECX/EDX byte arrays. The laptop's decoded MOF advertises exactly
that class, method and argument layout under GUID
`F1DDEE52-063C-4784-A11E-8A06684B9B01`.

Thus the inspected client uses the same legacy interface already investigated
on Linux. Matching diagnostic protocol-table offsets initially suggested a
possible direct protocol route, but tracing the wrappers rules that out for
this path. No named client for the unresolved class-28 EC queries was found
in this fan-test path. Server fan classes in the same DLL are separate paths
and are not evidence of laptop percentage control.

### Error handling checked with actual client instructions

[emulate-diagnostic-client.py](assets/xps16-fan-control/emulate-diagnostic-client.py)
requires the exact DLL hash and runs its native wrappers and adapter in
Unicorn. Windows initialization, logging, runtime helpers and transport are
mocked; execution outside the selected routines/mocks is rejected. It does
not run the managed test, Windows provider, BIOS or EC.

**25 cases passed**, checking the five request encodings, normal/failure
responses, synthetic transport errors and low-byte argument truncation.
Notable outcomes:

- A mocked transport error combined with a changed AX of 0 still yields a
  successful wrapper result. This probes status propagation; it does not
  establish that this combination occurs on the machine.
- AX `0xffff` is detected as failure. With unchanged request registers, most
  tested operations also fail. The RPM adapter has a special case that leaves
  AX `0x02a3` unchanged, which the RPM wrapper returns as numeric 675 under
  this synthetic scenario. This is not a measured fan speed.
- Raw managed IL inspection independently confirmed 15 matched control-call
  sites in `cFan.fFanSpeedTest` immediately discard their return values with
  `pop`. The test relies on RPM observations to assess fan performance.

The local reports are `diagnostics/client-shim-emulation.json` and
`diagnostics/fan-test-il-analysis.json`. These findings add client-side
limitations to the previously demonstrated BIOS-side status masking; they do
not establish the cause of intermittent fan bursts.

### Consequence and next useful check

This package confirms Dell's test sequence, but supplies no additional
acknowledgment or verified emergency recovery mechanism. It is insufficient
evidence for installing a persistent controller or declaring manual takeover
successful based on a return code.

The next useful hardware observation is the built-in Dell diagnostic fan test:
record whether each fan reaches the reported low/high speeds, any RPM values
or error codes shown, and whether it returns to normal behavior after exit.
The [DA16260 service manual](https://www.dell.com/support/manuals/en-us/xps-da16260-laptop/xps-16-da16260-service-manual/f12-one-time-boot-menu?guid=guid-71da763a-3f2f-4021-8ef7-3e50da009c74&lang=en-us)
documents **F12 → Diagnostics**. Select the fan-specific test if offered;
its exact available controls must be observed on this machine. This requires
the user to save work and reboot, so it was not started by this offline task.
A passing pre-boot test would establish a vendor-controlled baseline, not
prove that the Linux legacy route or a long-running custom curve is reliable.
