# RTX 4090 PC (Windows + WSL): BIOS update, CPU power limits and a 350 W GPU cap

**Not an Omarchy machine.** This is the Windows 11 + WSL2 box that runs the long CUDA jobs alongside the
Omarchy machines. It's here so the whole lab's power caps live in one place. Date: 2026-10-24.

**Machine:** MSI PRO Z790-P WIFI (MS-7E06), Intel Core i9-13900K, MSI GeForce RTX 4090 Gaming X Trio
(subsystem `1462:5103`), driven over SSH into WSL.

## Why

- **The 13900K is a Raptor Lake part.** That generation degrades at high voltage and power, and Intel's fix
  ships as microcode `0x12F` in board BIOS updates. The board was on **A.90 (2023-09-07)**, which predates
  that fix.
- **Unlimited, the CPU pulled ~265–290 W** under an all-core load: hot, loud, and for long CUDA jobs with
  CPU-side work it buys little.
- **The 4090 runs flat out for hours.** A cap trades a few percent of speed for much less heat.

## BIOS: A.90 → A.K0 (microcode 0x12F)

1. Download the MS-7E06 BIOS **A.K0** (`7E06vAK`) from MSI. The image inside is `E7E06IMS.AK0`.
2. Format a USB stick **FAT32** and copy the image to its root (check the SHA-256 after copying).
3. Reboot, enter the BIOS (Del), **M-Flash**, pick the file, and let it run. Don't power off.
4. Afterwards the BIOS reports **A.K0 / V10.K**, microcode **0x12F**.

**Gotcha: no BIOS screen.** The monitor was on the **motherboard's HDMI** (the iGPU), so with the 4090
installed the BIOS never appeared there. Move the cable to the **4090's HDMI** before flashing.

Before flashing, the Windows event log showed **no WHEA hardware errors** in the previous 60 days.

## CPU power limits: PL1 160 W / PL2 200 W

Set in the BIOS (CPU power limits, after loading the update's defaults):

| Limit | Value | Measured |
|---|---|---|
| PL1 (sustained) | **160 W** | package ~157 W (max 162), ~132% of base clock |
| PL2 (short boost) | **200 W** | package ~199 W (max 203), ~140% of base clock |
| before: unlimited | — | ~265–290 W peaks |

**Turbo stays on.** The Windows power plan's minimum and maximum processor state are both 100%. Lowering
the maximum below 100% disables turbo entirely, which is a much bigger loss than the power limits.

**Intel XTU and ThrottleStop don't work here.** Memory Integrity (HVCI) and the Hyper-V hypervisor that WSL2
needs block their low-level MSR access. Set the limits in the BIOS instead.

## GPU cap: 350 W at every boot

The RTX 4090's default limit is 450 W. `nvidia-smi -pl` needs admin rights and resets on reboot, so a
scheduled task reapplies it:

- **Task:** "GPU power cap 350W", runs as **SYSTEM**, trigger **at startup + 30 s** (gives the driver
  time to load).
- **Action:** `nvidia-smi -pl 350`

```powershell
# elevated PowerShell
$a = New-ScheduledTaskAction -Execute "nvidia-smi.exe" -Argument "-pl 350"
$t = New-ScheduledTaskTrigger -AtStartup; $t.Delay = "PT30S"
Register-ScheduledTask -TaskName "GPU power cap 350W" -Action $a -Trigger $t -User "SYSTEM" -RunLevel Highest
```

## Running Windows tools from WSL over SSH

Interop over a non-interactive SSH session needs **full paths**, and the working directory must be on a
Windows drive, or the `.exe` fails to start:

```sh
cd /mnt/c && /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command '...'
```

## Verify

```sh
# from WSL
nvidia-smi --query-gpu=power.limit --format=csv,noheader          # 350.00 W
cd /mnt/c && /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command \
  "(Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion; Get-ScheduledTask 'GPU power cap 350W' | Select State"
```

## Undo

- **GPU:** `Unregister-ScheduledTask "GPU power cap 350W"` (elevated). The limit returns to 450 W on reboot.
- **CPU:** BIOS power limits back to their defaults.
- **BIOS:** don't roll back below the 0x12F microcode.
