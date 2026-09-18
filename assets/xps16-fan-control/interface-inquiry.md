# Draft: fan-control acknowledgment and recovery on Dell XPS 16 DA16260

Status: prepared locally; not submitted or sent.

I'm investigating intermittent fan starts on a 2026 Dell XPS 16 DA16260,
BIOS 1.10.1 (July 20, 2026), running Linux 7.2.5-3-omarchy. Dell Quiet is
selected. I want to establish supported control and recovery semantics before
attempting a custom fan policy.

`dell_smm_hwmon` binds through WMI GUID
`F1DDEE52-063C-4784-A11E-8A06684B9B01`. Fan-state/RPM reads work. Earlier
per-fan automatic-mode requests returned EINVAL; high-state requests returned
success but did not produce an observed RPM change. The driver reports maximum
fan state 2. Global manual takeover has not been attempted.

Read-only analysis of the installed BIOS region found:

- Legacy `0x30a3/0x31a3` and `0x34a3/0x35a3` pairs alias the same two
  functions in `DellDiagsLegacy`. They discard the backend EFI status and
  return zero in AX.
- The backend in `DellEcMm` sends EC command `0xfa` with argument 4 for
  manual and 3 for automatic. These are static observations, not validated
  control operations on this machine.
- The diagnostic wrapper also conditionally changes internal property
  `0x429` and invokes `DellSbMm` methods that increment/decrement a counter
  and save/change/restore platform I/O state. This appears to require balanced
  acquisition/release, so retrying mode changes blindly seems inappropriate.
- `DellEcMm` contains a one-byte read transaction using `0xfa`, argument 6,
  but its meaning is unknown. We have not executed it or assumed it is a
  mode query.

Could you clarify:

1. Is host-controlled fan speed supported on DA16260, and through which
   supported WMI/SMBIOS/driver interface?
2. Is there a manual/automatic-mode query or acknowledgment that reflects
   actual EC acceptance, rather than only successful transport?
3. Are the global legacy calls appropriate on this generation? What are the
   intended balancing, retry, suspend/resume, and recovery rules for their
   additional platform-state changes?
4. Does `0xfa/6` have documented semantics relevant to this investigation?
5. Are controllable speeds discrete states, PWM percentages, or target RPM?
   Is any firmware hysteresis or minimum-running-time setting supported?

No modified firmware has been flashed, and no custom fan daemon is installed.
The goal is a supported, recoverable interface, potentially suitable for a
small upstream driver change. Raw machine firmware dumps are not attached.
