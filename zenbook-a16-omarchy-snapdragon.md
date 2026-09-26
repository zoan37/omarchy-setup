# ASUS Zenbook A16 (UX3607OA, Snapdragon X2 Elite Extreme): Omarchy Snapdragon install and fixes

First installed 2026-09-25 (whole disk); reinstalled 2026-09-26 **alongside factory Windows 11** after an
ASUS Cloud Recovery (section 10). Everything below was done from the Beelink SER8 over SSH after the first
boot; the laptop-side user is `napdivad`, hostname `zenbook`. Image: community build
[bprendie/omarchy-snapdragon](https://github.com/bprendie/omarchy-snapdragon) **v0.2.2-1**
(Omarchy 4.0.3, Arch Linux ARM userspace, Ubuntu Concept kernel `7.2.0-18-qcom-x1e`, Quattro
installer). Full test report filed upstream as
[issue #2](https://github.com/bprendie/omarchy-snapdragon/issues/2)
(copy in [assets/zenbook-a16/upstream-issue-2-report.md](assets/zenbook-a16/upstream-issue-2-report.md)).
Identify the machine with `cat /proc/device-tree/model` → `ASUS Zenbook A16 (UX3607OA)`. BIOS 312 (section 10).

Other A16 Linux work worth knowing: [FixItFoundry/zenbook-a16-linux](https://github.com/FixItFoundry/zenbook-a16-linux)
(Fedora, most complete hardware bring-up; source of the cpufreq fix and the EC/fan research),
[jc372/A16UbuntuBuild](https://github.com/jc372/A16UbuntuBuild) (Ubuntu; Wi-Fi board file recipe,
Bluetooth device-tree patch), [Hekatomb/LinuxOnAsusUX3607OA](https://github.com/Hekatomb/LinuxOnAsusUX3607OA)
(UEFI quirks).

## Status

| Area | State |
|---|---|
| Install, encrypted root, GRUB, 120 Hz OLED, GPU, keyboard, touchpad, brightness keys, keyboard backlight, USB-C charging | Works |
| Wi-Fi 7 (QCC2072) | Works after the board-file fix below |
| Speakers, microphone | Work after the UCM fix below. The tweeters stay silent until the speaker filter in section 14 routes them (also +6 dB limited boost) |
| CPU frequency scaling | Works after the device-tree patch below (355 MHz – 3.6/4.45 GHz, 3 policies) |
| Fan | **Controlled from Linux** through the EC mailbox (section 7); `a16-fan-daemon` keeps it at **0 rpm at idle** with a Mac-style whisper policy (section 11) |
| Windows 11 dual boot | Works: factory Windows restored by ASUS Cloud Recovery, Omarchy in the freed space, firmware entry "Omarchy (GRUB)", GRUB chainloads Windows (section 10) |
| Bluetooth | No adapter: needs a device-tree patch (serdev node + regulators + `w-disable2` polarity, see jc372 patch 0001). Firmware is already in the image. Not done yet |
| Battery percentage | **Works** after enabling the SoCCP remoteproc in the DTB (section 13): %, Wh, charge cycles, time left, 75–80 % charge limit all read. Power panel needs a small `omarchy-battery-status` patch |
| Coil whine | Traced with a mic to the SSD's PCIe link L1 state; `a16-nvme-aspm.service` keeps that link active, loudest tone −10 dB. Ear-judged extras in `a16-whine-tweaks.service` + `a16-cpuidle-nosleep.service` (PCIe links Gen1, 12 cores offline, cpu6-11 fixed at 4.45 GHz, runtime PM on, cdsp stopped, no deep idle; costs performance). Remainder is hardware (section 8) |
| Suspend | **Broken**: never resumes, machine resets. Sleep targets masked (section 8) |
| Touchpad palm rejection | Custom behavioral filter `a16-palm-filter.service` (section 15); libinput's disable-while-typing stays off for games |
| Camera | Not tested |
| Black screen after LUKS unlock | Intermittent eDP link-training failure (`link training on sink failed. ret=-110`), any entry. Power-cycle. Also the backlight boots at 5 %, which looks black on the OLED |

## 1. Flash and install

1. Download the four parts + checksums from the release, `sha256sum -c SHA256SUMS.parts`,
   `cat …part-{00,01,02,03} > omarchy-snapdragon-v0.2.2-1.iso`, verify against the `.sha256`.
2. `sudo dd if=….iso of=/dev/sdX bs=4M status=progress oflag=direct conv=fsync`. To verify the
   stick, unmount everything first (udisks auto-mounts the ISO's third `OMADIAG` partition and
   flips its FAT dirty byte, which breaks the hash) and hash with `iflag=direct`.
3. Laptop: F2 → disable Secure Boot. Power on mashing Esc → boot the stick.
4. **The install phase fails with "Could not sync mirrors … (unexpected error)"** because the live
   system boots with a stale clock (no readable RTC) and GnuPG rejects the repo signature made
   2026-09-15 as "from the future". In the failure menu choose *Drop to shell*:
   ```
   date -s "2026-09-25 22:00"     # anything after the signing date
   pacman -Syy                    # must list oma-snap, oma-snap-local, offline with no error
   bash /root/.automated_script.sh
   ```
   Not a pacman sandbox issue (pacman 7.1 in the image has no `DownloadUser`).
5. First boot after install went black after the passphrase; a power-cycle fixed it. The firmware
   boots Omarchy by default; no efibootmgr/EDK2 tricks were needed.

## 2. Remote access (SSH from the SER8)

- Laptop: `sudo systemctl enable --now sshd` and, because Omarchy's ufw is on,
  `sudo ufw allow from 192.168.0.24 to any port 22 proto tcp`.
- SER8 has two interfaces on the LAN and default-routes to the laptop from `.25`, so connect
  with `ssh -b 192.168.0.24 napdivad@192.168.0.21`.
- Files were moved with a FAT-formatted USB stick (`mkfs.vfat -n A16FIX -I /dev/sdX`, whole
  device) or a `python3 -m http.server 53317` on the SER8 (53317 is the LocalSend port ufw already
  allows).

## 3. Wi-Fi: QCC2072 board file

**Symptom:** `ath12k_wifi7_pci … failed to fetch board data for …subsystem-device=e14f…qmi-board-id=255,variant=UX3407Q`,
`qmi failed to load board data file:-2`, no wlan device. Upstream `board-2.bin` lacks the A16.

**Fix:** [assets/zenbook-a16/make-a16-board-2.sh](assets/zenbook-a16/make-a16-board-2.sh) downloads
the official ASUS Qualcomm BSP (7z SFX, ~400 MB), extracts `bdwlan_qcc2072_1p0_ncm820A.elf`
(the INF maps `SUBSYS_E14F105B` to it; the A14 copy floating around is a different build), and
wraps it into upstream `board-2.bin` with `ath12k-bdencoder` under both key names.
Local copy of the result: `~/Downloads/omarchy-snapdragon/wifi/build/board-2.bin`
(sha256 `5c3dcb3e…`). Not committed here (vendor blob).

**Install:** `sudo ./install-wifi-board.sh board-2.bin`
([assets/zenbook-a16/install-wifi-board.sh](assets/zenbook-a16/install-wifi-board.sh)), then
**reboot** (`modprobe -r ath12k` hangs). The driver reads
`/usr/lib/firmware/<release>/…`, a read-only bind mount of
`/usr/lib/oma-snap/sets/<id>/firmware/<release>/`, so plain `/lib/firmware` is shadowed; the script
writes into the set. `set.json`'s sha256 for the file is then stale; nothing at boot checks it.

**Verify:** `nmcli device` shows `wlan0`; `sudo dmesg | grep -c "failed to fetch board data"` → 0.
Also enabled power save: `nmcli connection modify <con> 802-11-wireless.powersave 3`.

## 4. Audio: UCM file name

**Symptom:** PipeWire shows only "Dummy Output"; kernel: `MultiMedia1 Playback: ASoC: no backend
DAIs enabled … possibly missing … UCM profile`; `alsaucm -c hw:0 list _verbs` →
`failed to import hw:0 use case configuration -2`.

**Cause:** alsa-lib looks up `ucm2/conf.d/<driver>/<card long name>.conf`; the image ships the
file under the device-tree model name.

**Fix:**
```
cd /usr/share/alsa/ucm2/conf.d/glymur
sudo ln -s GLYMUR-ASUS-Zenbook-A16-UX3607OA.conf "ASUSTeKCOMPUTERINC.-ZenbookA16UX3607OA-1.0-UX3607OA.conf"
systemctl --user restart wireplumber pipewire pipewire-pulse
```
**Verify:** `wpctl status` lists "Built-in Audio Speaker playback" (4 channels) and "Internal
microphones"; `speaker-test -t sine -f 440 -c 2 -l 1` at 25 % is audible. The symlink is unowned
by any package, so updates keep it. **Revert:** remove the symlink.

## 5. CPU frequency scaling: device-tree patch

**Symptom:** `/sys/devices/system/cpu/cpufreq/` empty; `modprobe scmi-cpufreq` →
`arm-scmi: timed out in resp`, `probe … failed with error -110`. Cores never leave boot clock.

**Cause** (FixItFoundry): the Glymur firmware answers SCMI perf (0x13) in shared memory but never
rings the mailbox doorbell. Fix is one DT property on `/firmware/scmi`: `arm,no-completion-irq;`.

**How the DTB is delivered:** embedded in `vmlinuz.efi` as a `.dtbauto` PE section, hwid-matched
by the stub. [assets/zenbook-a16/patch-vmlinuz-dtb.py](assets/zenbook-a16/patch-vmlinuz-dtb.py)
patches it in place (169 bytes of slack in the section; it also updates the section's
VirtualSize, otherwise the stub says "found bad dt blob in PE section 8").
```
python3 patch-vmlinuz-dtb.py /usr/lib/oma-snap/sets/*/vmlinuz.efi vmlinuz-scmipoll.efi
sudo mkdir -p /boot/oma-snap/custom && sudo cp vmlinuz-scmipoll.efi /boot/oma-snap/custom/
sudo cp -n /boot/oma-snap/grub/grub.cfg /boot/oma-snap/grub/grub.cfg.orig-20260925
# append assets/zenbook-a16/grub-custom-entries.cfg (fix PARTUUID / fs-uuid / entry hash), then:
sudo sed -i 's/^set default=.*/set default=oma-snap-custom-noignore/' /boot/oma-snap/grub/grub.cfg
echo scmi-cpufreq | sudo tee /etc/modules-load.d/scmi-cpufreq.conf
```
The installer-built entry stays in the menu as fallback. The `noignore` entry additionally drops
`clk_ignore_unused pd_ignore_unused` (hard-coded in `oma-snap-boot-stage/publish`); a boot without
them was clean (display, Wi-Fi, input, audio all fine), so it is the default.

**Verify:** `ls /sys/devices/system/cpu/cpufreq/` → `policy0 policy6 policy12`;
`cat …/policy0/scaling_driver` → `scmi`; idle clusters drop to 355 MHz; cooling devices
`cpufreq-cpu0/6/12` appear. `Failed to get FC for protocol 13` messages are harmless.

**Caveat:** oma-snap's kernel-update tooling may regenerate `grub.cfg` (dropping the custom
entries) and, per upstream issue #1, regenerated entries may not boot on mkinitcpio 42. Keep the
install USB.

## 6. Quiet-ish thermal profile (userspace)

The Ubuntu DTB has only 115 °C critical trips and no cooling maps, so ASUS's "Quiet" profile
(which on this platform only lowers throttle temperatures) is emulated by
[assets/zenbook-a16/a16-quiet-thermal](assets/zenbook-a16/a16-quiet-thermal) +
[.service](assets/zenbook-a16/a16-quiet-thermal.service): cap all policies to 60 % of max above
85 °C, release below 78 °C. Install to `/usr/local/bin` and `/etc/systemd/system`,
`systemctl enable --now a16-quiet-thermal`. Logs `cap on/off` via `logger`. It does nothing at
idle. **Revert:** `systemctl disable --now a16-quiet-thermal`.

## 7. Embedded controller and fan: from "not controllable" to manual PWM

The fan was the one thing that mattered most (goal: Mac-level silence). On the stock EC curve Linux idled at
≈1980 rpm while Windows idles with the fan **off**, so the EC clearly allows it. This section is the path
from research to a working control; the daemon built on it is in section 11.

### 7.1 Linux-side research (2026-09-25)

- EC on `/dev/i2c-9` (`a84000.i2c`), two addresses: `0x76` (RAM read RECM cmd `0x52`, RAM write WECM
  cmd `0x54`, WMI tunnel cmd `0x51` + doorbell WECM `0x0C7C=1`) and `0x5b` (byte ops: cmd `0x10` =
  `{dev,reg}` pointer, `0x11` = data). FixItFoundry's [`glymur-ec-read.sh`](assets/zenbook-a16/glymur-ec-read.sh)
  and [`glymur-ec-block.sh`](assets/zenbook-a16/glymur-ec-block.sh) are installed in `/usr/local/bin`.
  Wire rules: two separate `i2ctransfer`s (no repeated start), never poll under CPU load.
- Firmware ACPI tables were dumped through `/proc/kcore` (STRICT_DEVMEM blocks `/dev/mem`; `iomem=relaxed`
  does not help on arm64) and decompiled with iasl: `~/Downloads/omarchy-snapdragon/acpi/DSDT.dsl` on the SER8.
- **Mailbox device `0xC4` on `0x5b` works from Linux.** ECCW (write) = `0x31=feature, 0x32=value, 0x30=bank`,
  wait for `0x30 → 0`; ECCR (read) = `0x31=feature, 0x30=bank`, wait, read `0x32`, clear it. Verified with the
  keyboard backlight: `ECCW(1,0x81,4)` then `ECCW(1,0x87,level 0-3)`. Fn-lock = `ECCW(2,0x84,x)`.
- Dead ends, all confirmed on Windows too: the `0xC9` fan-curve *block engine* (GDFC/GFLB/SUFC, WMI
  `0x00110024/25/32`) never clears its control byte, even right after the "OS present" handshake
  `ECCW(2,0x83,1)`, and reads the same stuck `6E=0x20/6F=0xC0` under Windows, so it is not the mechanism.
  ACPI `FAN0` has no `_FSL`. WMI `0x00110019` (Normal/Quiet/Turbo/Full) only programs PEP0 temperature limits.
  The tunnel (`0x51`) answers (fan trip sub `0x85` acked, DSTS `0x00100071` returns `41 00 01`) but does not
  wake the engine. Sweeps: [ec-dumps/ec-sweep-linux-2026-09-25.txt](assets/zenbook-a16/ec-dumps/ec-sweep-linux-2026-09-25.txt).

### 7.2 Windows-side reverse engineering (2026-09-25 night, after the Cloud Recovery)

Factory Windows exposes the same EC through ASUS WMI classes in `root/wmi`, which made it possible to read
the EC while the fan was genuinely off and to try writes with the vendor stack present:

| WMI | What it does |
|---|---|
| `ATD_STS.ec_read_byte(haddr=dev, laddr=reg)` | raw `0x5b` byte read (`dev` = `0xC4` mailbox, `0xC9` engine) |
| `ATD_STS.ec_read_command_byte(commandcode=feature, param0=bank)` | ECCR |
| `ATD_STS.ec_write_command_byte(commandcode=VALUE, param0=feature, param1=bank)` | ECCW (argument order is the trap) |
| `IecToolkitInterface.SystemMethod(InData=[0x2357<<32 \| 0x00800007, op 0/1, addr, len, 0,0,0])` | RECM / WECM; `OutData[0]` status, `[1]` value |
| `AsusAtkWmi_WMNB.DSTS(0x00110035)` | fan rpm / 100 |

Scripts (run from an elevated PowerShell as `powershell -File`, never through `cmd`/ssh quoting):
[windows/win-ssh.ps1](assets/zenbook-a16/windows/win-ssh.ps1) (OpenSSH Server + key; the firewall rule must be
`Set-NetFirewallRule -Profile Any` on a "Public" network), [win-ecdump.ps1](assets/zenbook-a16/windows/win-ecdump.ps1)
and [win-capture-silent.ps1](assets/zenbook-a16/windows/win-capture-silent.ps1) (full EC RAM dumps, results in
[ec-dumps/](assets/zenbook-a16/ec-dumps/)), [win-fantest.ps1](assets/zenbook-a16/windows/win-fantest.ps1) (the
write experiment), [win-status.ps1](assets/zenbook-a16/windows/win-status.ps1).

**Result (win-fantest):** the register map from
[omerfaruknehir/asus-zenbook-a14-ec](https://github.com/omerfaruknehir/asus-zenbook-a14-ec) (Snapdragon
Zenbook A14) works unchanged on the A16, bank `0x01`:

| feature | meaning |
|---|---|
| `0x82` write | fan mode: `0` auto, `2` manual |
| `0x02` read | current mode |
| `0x8c` write | select fan `0`/`1` (two rotors) |
| `0x8a` write | PWM `0..255` for the selected fan; **`0` = fan off, accepted** |
| `0x0a` / `0x09` read | PWM readback / tach byte (≈ rpm/250) |

Measured: PWM 120 → 3720 rpm, 75 → 2520 rpm, 0 → off; mode 0 restores the EC's own curve. The EC RAM diff
fan-on vs fan-off (16-bit tachs at `0x0602/3` and `0x0624/5`, duty bytes `0x063e/f`, `0x0648/9`, state bytes
`0x061d/0x063b/0x064b`) showed no host flag. Why the EC's *automatic* curve idles at 0 under Windows but at
≈1980 rpm under Linux was never isolated (probably a handshake the ASUS platform driver does); manual mode
makes it moot. A Qualcomm engineer has posted an upstream `asus-glymur-ec` driver (fan, two temps, keyboard
backlight) that should eventually replace all of this.

### 7.3 Linux control

[`a16-fan.sh`](assets/zenbook-a16/a16-fan.sh) (`status | manual <pwm> | auto`) drives the same mailbox
with `i2ctransfer`; it shares `/run/lock/a16-fan.lock` with the daemon. Fan floor measured on 2026-09-26:
keeps spinning down to PWM 20, starts reliably from rest at PWM 25 (30 ≈ 800 rpm, 45 ≈ 1400, 75 ≈ 2500,
120 ≈ 3700). The EC's board temperature (bank 5 feature `0x02`) reads 0 on the A16.

## 8. Loose ends and open items

- **Passwordless sudo** (`/etc/sudoers.d/99-napdivad-nopasswd`) is currently present for the SSH work;
  remove with `sudo rm /etc/sudoers.d/99-napdivad-nopasswd` when done (`~/grant-sudo.sh` re-creates it).
  The SER8's key is in `~/.ssh/authorized_keys`.
- **Bluetooth:** needs the `wcn7850-bt` serdev node + regulators + `w-disable2` polarity from jc372's
  patch 0001 in the DTB. The in-place patcher only has ~169 bytes of slack in the PE section, so a bigger
  DTB means rebuilding the section (or a proper kernel package).
- **Battery telemetry:** fixed 2026-09-26 (section 13).
- **Suspend is broken (found 2026-09-26):** the idle timer put the machine into `suspend (deep)` and it never
  resumed; the firmware reset it instead, which looked like a random reboot (journal ends at `PM: suspend entry
  (deep)`, no crash record). Sleep is now disabled: `systemctl mask sleep.target suspend.target hibernate.target
  hybrid-sleep.target suspend-then-hibernate.target` (also step 5b of `apply-a16-fixes.sh`), so idle only locks the
  screen and the lid does not sleep. Unmask the same targets to retry after a kernel update. Camera untested.
- **Black screen after LUKS unlock:** intermittent eDP link-training failure on any entry (seen again on the boot
  after that reset); hold power ~10 s and boot again.
- **Coil whine (2026-09-26), solved as far as software can: it is the NVMe SSD's PCIe link power state.**
  With the fan stopped, a high tone is audible with an ear at the middle of the keyboard (not at desk distance).
  Ear-based tests (charger, brightness, screen off, CPU load, clocks pinned, Wi-Fi off, audio off, keyboard
  backlight off, BIOS 305 → 312, fan masking at 700/1250 rpm, cores kept out of `cpu-sleep-0`) were inconclusive
  or placebo, and it is present under Windows too. **A USB webcam mic at the keyboard centre settled it**
  ([whine-mic/](assets/zenbook-a16/whine-mic/): `pw-record` 6 s + a pure-Python FFT that prints narrow peaks;
  `whine-verify.sh` alternates a setting and averages 4 takes). Result, level of the strongest narrow tone at the
  keyboard, 3–4 takes per row, repeatable to ±2 dB:

  | SSD link (`0005:01:00.0/link/l1_aspm`) | 6.8 kHz tone | 8.9 kHz tone |
  |---|---|---|
  | L1 on (stock) | −97 dBFS | **−83 dBFS** |
  | L1 off | **−92 dBFS** | −94 dBFS |

  So the Samsung MZVL8512HFLU's regulator sings at 8.9 kHz when its link parks in L1 and at a quieter 6.8 kHz
  when the link is held active: about 10 dB less at the loudest tone, and a lower pitch. Forcing ASPM off
  system-wide gives the same 6.8 kHz tone; USB / PCI / platform runtime-PM, GPU pinning, cpufreq governor, the
  `cpu-sleep-0` idle state and the fan made **no measurable difference** (all within ±2 dB), so those services
  were removed/disabled again. Disabling only the L1.1 or L1.2 substate is not enough; link clock-PM does not
  matter. Disabling the SSD's own APST (`nvme set-feature -f 0x0c -v 0`) hung the admin queue for ~10 min before
  applying and did not help: do not do that on the root disk. **Permanent fix:**
  [`a16-nvme-aspm`](assets/zenbook-a16/a16-nvme-aspm) + [`.service`](assets/zenbook-a16/a16-nvme-aspm.service)
  write `0` to the NVMe controller's `link/l1_aspm` at boot (`a16-nvme-aspm off` restores it); Wi-Fi and
  everything else keep their normal power saving. Cost: the SSD link never enters L1 (tens of mW). The remaining
  6.8 kHz tone was chased further with the mic (`whine-round6.sh`, `whine-round7.sh`): display 60 Hz, screen
  off, brightness min/max and the audio stack change nothing; it is tied to the **Wi-Fi card's power path** but
  in the wrong direction for a fix: Wi-Fi radio off makes it 9 dB louder, Wi-Fi link L1 off 6 dB louder, traffic
  and `power_save` no change. The stock Wi-Fi state (connected, L1 on) is already its quietest, so the current
  configuration is the measured optimum: ≈ −93 dBFS at 6.8 kHz, ≈ −100 at 8.9 kHz, versus −83 stock. The
  remainder is the board's parts; the owner hears it with the left ear more than the right (ear sensitivity),
  and not at all with the laptop in front of them. The XPS machines' silence is inductor selection, not CPU
  vendor. Do not re-investigate beyond this.
  **Round 8 (2026-09-26 morning, ear-judged, room too noisy for the mic):** the untested knobs were applied all
  at once and the owner judged it "helps more, if not the same", so they stay on as
  [`a16-whine-tweaks`](assets/zenbook-a16/a16-whine-tweaks) + [`.service`](assets/zenbook-a16/a16-whine-tweaks.service)
  with values in [`/etc/default/a16-whine`](assets/zenbook-a16/a16-whine.conf): NVMe PCIe link retrained at
  **Gen1** (root port LnkCtl2 target speed + LnkCtl retrain via `setpci`; stock Gen4 x4), Wi-Fi link at **Gen1**
  (stock Gen3 x1), **twelve cores offline** and the survivors at a **fixed clock** (`scaling_min_freq` =
  `scaling_max_freq`: one clock, one voltage, no regulator transitions). By ear on the 3.6 GHz cluster (cpu0-5):
  3.6 steadiest, 2.5 "oscillates more", 1.5 "a bit more static"; then A/B/A/B against the first 4.45 GHz
  cluster (cpu6-11, its own rail) at a fixed 4.45 GHz: "4.45 seems better". Final: **cpu0-5 and cpu12-17
  offline, cpu6-11 at 4.45 GHz** (cpu0 can be hot-unplugged on this kernel). Caution: the first version of the
  script only re-onlined the *configured* set on stop, so `systemctl restart` after changing `OFFLINE_CPUS`
  stranded the machine on cpu17 alone and it hard-reset seconds later (journal ends mid-start, not a suspend);
  the script now onlines every CPU before applying or removing the set. Core count below six makes no
  difference (three cores at 4.45 GHz sounded the same, restored to six). Owner's verdict on the end state:
  with the laptop on the left there is still a high tone, but it is now **consistent** instead of wandering, and
  a steady tone is one the brain can filter, which the oscillating one never was; that steadiness is the fixed
  clock (one voltage on the core rail, no light-load mode transitions), so it helps twice: lower peak and easier
  habituation. Alternative pitches if it ever grates: cpu0-5 at 3.6 (tried, different pitch), 3.4 or 3.55 (untried),
  plus a second batch the owner rated as the bigger win ("less piercing pitch, more like a normal buzz"):
  `cpu-sleep-0` idle state disabled again (`a16-cpuidle-nosleep.service`, now enabled: the mic saw nothing, the
  ear does), **runtime PM forced `on`** for every USB/PCI/platform device except the GPU and the audio path (the
  four WSA884x speaker amps and both soundwire controllers stay `auto`, so the speaker path is powered down
  whenever nothing plays; ear: no worse, possibly better), and the unused
  **compute DSP (`cdsp`) stopped** (`adsp` stays up for audio). GPU devfreq pinned to max was tried too and
  reverted (power, +6 °C). Costs, in order of pain: multi-thread CPU performance drops to roughly a third and
  single-thread is at full speed on the prime cores; SSD sequential throughput is capped near
  0.9 GB/s instead of ~6 (random-IO latency barely changes, desktop use does not notice); Wi-Fi is capped near
  2 Gbit/s over the link (no home connection reaches that); everything runs at 4.45 GHz (idle cores still
  clock-gate, so the battery cost is small, but any real work draws more and runs warmer) and peripherals never enter their low-power modes (a few hundred
  mW). Not mic-verified: if a quiet room comes back, run `whine-round8.sh` (in `whine-mic/`) to see which knobs
  actually move the tones, then drop the others. `a16-whine-tweaks off` or `systemctl disable --now
  a16-whine-tweaks a16-cpuidle-nosleep` restores stock without a reboot.
  **Every remaining lever, with odds and research:** [coil-whine-ideas.md](assets/zenbook-a16/coil-whine-ideas.md).
  **Hardware damping (planned, 2026-09-26; full step-by-step in
  [silicone-damping-plan.md](assets/zenbook-a16/silicone-damping-plan.md)):** the TechPowerUp teardown (review page 5) shows the VRM: a cluster
  of ~15 dark cube inductors around a putty-covered PMIC to one side of the SoC (CPU/GPU rails, the likely singer)
  and a smaller cluster of ~8 on the other side next to the Wi-Fi card. They face the **bottom cover**, under the
  fans and heatpipe assembly (10 Torx T5 on the cover, 6 around the fans, 4 on the CPU plate), and the cooler has
  a VRM plate resting on them. Plan: battery connector off, chopstick press test on the cluster with the machine
  running (pitch change ⇒ damping will help), then ASI 388 neutral-cure electronics silicone applied by toothpick
  as a thin fillet around each inductor base and a bridge between neighbours, nothing on the tops (heatsink pad)
  or on the PMICs. Skins in ~20 min, reassemble after a few hours, full cure 7 days. Expectation: softer, not
  silent; capacitor/board-flex noise is untouched. Ends any exchange option.
  Also tried by ear, no change: the audio DSP (`adsp`) stopped, display 60 Hz, Wi-Fi TX power limited to 5 dBm,
  three cores instead of six. **Do not stop `adsp` at runtime:** after `start` the q6apm buffer allocation times
  out, `clk_q6dsp_prepare` warns and the sound card never re-registers (driver rebind fails with -22); only a
  reboot brings audio back. Stopping `cdsp` is fine.
- **Fn-lock / hotkey mode (paused):** on Windows the F-row is in hotkey mode; here it boots in F-key mode and
  Fn+Esc does nothing. The DSDT's Fn switch is `ECCW(2,0x84, 0x04|0x08 [|KFSK 0x80])` (WMI `0x00100023`); writing
  0x04 or 0x08, with or without the `ECCW(2,0x83,1)` "OS present" handshake the driver sends at load, changed
  nothing. Captured scan codes (bare F1-F12 = KEY_F1..F12; Fn+F row = 149 113 114 115 228 224 225 Meta+P 99 191
  248 212 148, i.e. vendor key, mute, vol-, vol+, kbd backlight, bright-, bright+, display, PrtSc, touchpad
  toggle, mic mute, camera, vendor key). Plan if resumed: swap in Hyprland (`bindings.lua`: bare F-keys →
  the `media.lua` commands, XF86 keys → synthesized F-keys with `send_key_state`). **Fn+F10 toggles the touchpad**
  (`omarchy-toggle-touchpad`), which is easy to hit by accident; `omarchy-toggle-touchpad on` restores it.
- **Keyboard backlight:** `ECCW(1,0x81,4)` makes the host own the backlight (the EC then ignores the backlight
  key); `ECCW(1,0x87,level)` with the DSDT's table values 0x00/0x55/0xAA/0xFF sets it; `ECCW(1,0x81,0)` hands it
  back to the EC. There is no `/sys/class/leds/*kbd_backlight*`, so `omarchy-brightness-keyboard` has nothing to
  drive; the EC handles the key itself (and runs a slow breathing effect by default).
- The `oma-snap` kernel-update tooling may regenerate `grub.cfg`; keep the install stick and
  [`apply-a16-fixes.sh`](assets/zenbook-a16/apply-a16-fixes.sh).

## 9. Personal config ported from the other machines (2026-09-25, re-applied 2026-09-26)

Applied over SSH, all user-level, backups as `~/.config/hypr/*.bak-<date>`:

- `input.lua`: `altwin:swap_alt_win`, `touchpad.natural_scroll = true`,
  `touchpad.disable_while_typing = false`, three-finger horizontal workspace swipe with the loose
  gesture tuning ([hyprland-shell-tweaks.md](hyprland-shell-tweaks.md)).
- `looknfeel.lua`: resize on border (`extend_border_grab_area = 15`).
- `bindings.lua`: group move-window bindings, SUPER+A select-all, SUPER+SHIFT+S screenshot.
- **Ghostty is not packaged for this ARM build** (`target not found`; only foot, kitty and alacritty exist
  in the ALARM repos), so the terminal is **kitty**: `sudo pacman -S kitty && omarchy-default-terminal kitty`,
  with the kitty font-size trick from [terminal-font-size.md](terminal-font-size.md) (`local.conf` 11pt,
  active `font_size 9.0` line, trailing `include local.conf`).
- Display: 2880x1800 OLED at Hyprland scale 1.6 (2.0 is too big; the OLED's PenTile-ish text looks softer
  than the XPS panels at first, brighter helps). `git config --global user.name/email` set to zoan37.
- Not ported: Chrome Vulkan/ANGLE flags (x86 GPU specific), hypr-momentum (needs cmake + Hyprland headers via
  hyprpm; untried on this arch), Cyberspace theme.

## 10. Windows 11 dual boot (2026-09-25/26)

Wanted for the EC work (section 7.2) and kept because factory Windows is useful. The path that worked, and
the one that did not:

1. **Generic Windows 11 ARM64 ISO does not boot this laptop.** Tried on a 28 GB stick (FAT32, `install.wim`
   split into `.swm` parts). Findings: the firmware does not parse GPT USB sticks at all (UEFI shell shows
   `BLK0` with no filesystem; MBR + FAT32 shows up as `FS2`), with Secure Boot on the loader is rejected
   ("USB boot failed", 2011-CA-signed `bootaa64.efi`), with Secure Boot off WinPE has no X2 Elite drivers and
   the machine resets to the ASUS logo. GRUB chainloading it needed `insmod part_msdos` and got as far as the
   Windows installer once, then the same reset. Abandoned.
2. **ASUS Cloud Recovery** (F2 → MyASUS → Cloud Recovery) downloads and restores factory Windows 11 with all
   drivers. It **wipes the whole SSD**, so Omarchy had to be reinstalled afterwards. On first Windows boot:
   local account, updates deferred; then in an elevated PowerShell `irm http://192.168.0.24:53317/win-ssh.ps1 | iex`
   ([win-ssh.ps1](assets/zenbook-a16/windows/win-ssh.ps1)) for SSH from the SER8, `powercfg /change standby-timeout-ac 0`.
3. **Make room:** `manage-bde -off C:` (the Omarchy installer refuses BitLocker volumes; wait for
   "Percentage Encrypted: 0%"), then `Resize-Partition` C: down to 273.6 GB, leaving ~200 GB unallocated.
4. **Omarchy alongside:** boot the install stick (Esc at power-on; sometimes the USB entry only appears after a
   full power-off), `date -s` fix from section 1, installer's *install into free space* mode (needs ≥ 32 GB
   free; it creates its own 2 GB ESP `OMARCHY_EFI` and a LUKS root). A failed first run leaves those two
   partitions behind and the next run says "no free space": delete them in the installer's partition tool
   (write) and run again.
5. **Boot entry:** the firmware dropped the installer's entry and booted Windows. Fixed from Windows with
   [win-bcd.ps1](assets/zenbook-a16/windows/win-bcd.ps1): mount `OMARCHY_EFI` as `S:`,
   `bcdedit /copy {bootmgr} /d "Omarchy (GRUB)"`, set `device partition=S:`, `path \EFI\oma-snap\grubaa64.efi`,
   `displayorder … /addfirst`. That entry has survived every reboot since. A "Windows Boot Manager" GRUB entry
   chainloads `\EFI\Microsoft\Boot\bootmgfw.efi` from the Windows ESP (`search --fs-uuid 5A72-4BA1`;
   [win-grub-windows-entry.ps1](assets/zenbook-a16/windows/win-grub-windows-entry.ps1) appended it from
   Windows, `apply-a16-fixes.sh` step 4 does the same from Linux).
6. **Reapply everything:** `sudo bash apply-a16-fixes.sh` from the bundle (board-2.bin, UCM symlink, patched
   kernel + GRUB entries + Windows entry, thermal service, fan script/daemon/config, EC scripts, Wi-Fi power
   save), then section 9.

Resulting layout of `nvme0n1` (476.9 GB): p1–p11 Qualcomm/ASUS firmware partitions, p12 `SYSTEM` Windows ESP
(450 MB, uuid `5A72-4BA1`), p13 MSR, p14 `OS` Windows C: (273.6 GB, NTFS, mountable read-only with `ntfs3`),
p15 `RECOVERY`, p16 `MYASUS`, p17 `OMARCHY_EFI` (2 GB, uuid `6212-AA9B`, `/boot`), p18 `OMARCHY_ROOT` (198 GB
LUKS, uuid `43b1e5d2-…`, btrfs). GRUB menu: legacy entry, installer kernel entry, Firmware settings, Windows
Boot Manager, **SCMI polling / no clk-pd-ignore (default)**, SCMI polling / stock flags. Never touch p12–p16.

### BIOS updates on this Snapdragon model (done 2026-09-26: 305 → 312)

There is no separate BIOS download. The firmware ships inside ASUS's **Qualcomm Board Support Package**
(`SOCPackage_forWebSite_Qualcomm_Z_V1.312.4500.0_50616.exe`, 2026-07-23, "CRITICAL"; the same file the Wi-Fi
board file came from) as a Windows firmware-class driver (`UX3607OA_312.inf`, "ASUS UEFI BIOS", resource
`RES_{E2BB821E-…}`). Running the installer only stages it; **the flash happens on the next boot of Windows**
(Windows' boot path hands the capsule to the firmware, progress screen, restart). Booting Omarchy after the
installer does nothing, and Linux keeps reading the old version (ESRT `entry0 ver=773` = 0x305). Verified
after the Windows boot: BIOS 312, Secure Boot still off, "Omarchy (GRUB)" still first in the firmware boot
order. Windows also rolled the Secure Boot CA/keys (event 1808) at the same time. Owner's impression afterwards: the
coil whine is **somewhat quieter than before** (still audible with the left ear at the deck, less with the
right; inaudible with the laptop in front of them). Subjective, but the only lever that moved it at all.

## 11. Fan daemon: 0 rpm at idle, Mac-style behaviour under load

[`a16-fan-daemon`](assets/zenbook-a16/a16-fan-daemon) + [`.service`](assets/zenbook-a16/a16-fan-daemon.service)
+ [`/etc/default/a16-fan`](assets/zenbook-a16/a16-fan.conf). It puts the EC in manual mode and owns the fan;
any I2C error, a trip temperature, or `systemctl stop` hands control back to the EC's automatic curve
(`ExecStopPost` runs `a16-fan.sh auto`; `Restart=always`).

History, all 2026-09-26: **v1** simple curve, trip 85 °C → first time the laptop was silent at idle on Linux.
**v2** exponential smoothing + hysteresis + slew limits so an app install would not spin the fan; it silently
fell back to auto because inline `# comments` in `/etc/default/a16-fan` become part of the value under
systemd's `EnvironmentFile` (comments on their own lines now). **v3/v3.1 "whisper"** after measuring the fan
floor and reading the kernel trips (95 °C passive / 115 °C critical, so the SoC may run warm):

- **Input:** hottest CPU/GPU zone, smoothed with a ~60 s exponential average (5 % per 3 s sample).
- **Off until warm:** fan starts only when the *smoothed* temperature passes 68 °C. A 45 s burst of 8 busy
  threads peaks at 82 °C instantaneous and never moves the fan; a 12-thread all-core load takes ~45 s to
  start it.
- **Whisper stage:** starts at PWM 30 (~800 rpm) and climbs 1 count per 3 s along
  `68 °C:30 → 78:45 → 85:90 → 90:150 → 95:220` (4 counts per step above 82 °C smoothed).
- **Fast path with hysteresis:** a ~10 s average above 88 °C engages an 8-count-per-step ramp; it releases
  only 5 °C lower, so the fan cannot hunt around the threshold (v3 did).
- **Exponential spin-down:** each step the duty may fall by 1/25 of its value, so after a load ends the fan
  decays 160 → 30 in ~2.5 min, idles at whisper, and turns off once the smoothed value has been below 58 °C
  for 2 min (and it has run ≥ 3 min). Idle result: 0 rpm.
- **Safety:** ≥ 97 °C or any I2C error hands control back to the EC; the 60 % clock cap from section 6 still
  engages at 85 °C instantaneous and does most of the sustained-load work silently (a long compile is slower
  than it would be with the fan doing the work; raise `HOT`/`COOL` in `a16-quiet-thermal` to trade noise for
  speed).

Edit the conf and `systemctl restart a16-fan-daemon`; watch with `journalctl -fu a16-fan-daemon`.

**Idle floor (chosen 2026-09-26): `IDLE_PWM=25`, ~700 rpm always on (the slowest speed the fan holds).** Instead of stopping, the fan idles at the
whisper duty and ramps from there; after a load it decays back to the floor. This is the Mac behaviour (MacBook Pro
fans never stop, they sit at their minimum), it is harmless for the bearing (continuous slow running wears less
than stop/start), draws a fraction of a watt, and the owner preferred the feel of it. `IDLE_PWM=0` gives a fully
stopped fan at idle, which was the state for the first day.

**How it compares to a MacBook Pro (honest assessment):** at idle and in bursty everyday use it is level or
better: 0 rpm idle, bursts tolerated by policy, and a first stage (~800 rpm) below Apple's ~1200–1500 rpm
floor. Under sustained all-core load a Mac is ahead: it keeps full clocks and uses the fan, its fan/heat pipe/
chassis are designed together, and its SMC runs a real thermal model over many sensors instead of a 3 s loop
over sysfs. Subjectively on this A16: the fan, when it does run, is a smooth whoosh rather than a whine, and
the ceraluminum chassis stays cool to the touch.

## 12. Negative results: do not retry as-is

- **USB-PHY DT patch for battery telemetry** (delete `mode-switch` / `orientation-switch` from `phy@fd5000`
  and `phy@fde000`, FixItFoundry's UCSI fix): built as `vmlinuz-scmipoll-usbphy.efi`, booted twice, black
  screen both times with a new `msm_dp_display_host_phy_init` WARNING and eDP link training failed;
  `qcom-battmgr` was still empty (the device links to `a600000.usb`/`a800000.usb` still fail). Removed from
  GRUB and `/boot/oma-snap/custom`. Not needed: the real battery fix was the SoCCP node (section 13).
- **Generic Windows ARM ISO on this firmware:** see section 10 item 1.
- **`0xC9` block engine** for fan curves: dead on Linux and Windows alike; the `0xC4` mailbox is the way.
- **`pacman` sandbox theory** for the installer mirror error: a no-op (no `DownloadUser` in the image); it was
  the clock.

## 13. Battery: enable the SoCCP remoteproc (2026-09-26)

**Symptom:** no battery in the bar. `/sys/class/power_supply/qcom-battmgr-bat` exists but every read
(`status`, `present`, …) returns `Resource temporarily unavailable` (EAGAIN): `qcom-battmgr` is bound but the
charger service behind PMIC GLINK never comes up.

**Cause:** on Glymur the battery/charger firmware runs on the **SoCCP**, which UEFI starts (Windows'
`qcsubsys_ext_soccp8480.inf` uses "LiveHandoff": it attaches, never loads). The Ubuntu A16 DTB ships
`/soc@0/remoteproc-soccp@d00000` with `status = "disabled"`, so nothing brings up its GLINK edge. The
7.2.0-18 `qcom_q6v5_pas` has the `kaanapali-soccp` early-boot path (`qcom_pas_attach`), so enabling the node
is enough: it attaches to the running SoCCP without requesting `soccp.mbn` (which isn't installed anywhere,
only a generic Kaanapali one). Same model FixItFoundry uses on 7.3-rc3.

**Fix:** [patch-vmlinuz-soccp.py](assets/zenbook-a16/patch-vmlinuz-soccp.py) rewrites that `status` to
`"okay"` in the embedded DTB (same size; 4 spare bytes become an FDT_NOP), applied on top of the SCMI image:
```
python3 patch-vmlinuz-soccp.py /boot/oma-snap/custom/vmlinuz-scmipoll.efi vmlinuz-scmipoll-soccp.efi
sudo cp vmlinuz-scmipoll-soccp.efi /boot/oma-snap/custom/
# GRUB entry 'oma-snap-custom-soccp' = the noignore entry with this image; now the default.
```
`grub.cfg` also got a `load_env` / `next_entry` one-shot block after `set default`, so
`sudo grub-editenv /boot/oma-snap/grub/grubenv set next_entry=<id>` boots a test entry once.
Backup of the pre-change cfg: `grub.cfg.bak-20260926-soccp`.

**Verify:** `cat /sys/class/remoteproc/*/name` lists `soccp` with state `attached`;
`upower -i /org/freedesktop/UPower/devices/battery_qcom_battmgr_bat` shows %, energy-full 70.28 Wh
(design 70.0), charge-cycles, time to empty, thresholds 75/80 %. First boot: display, Wi-Fi, audio fine.
There is no `capacity` sysfs file (UPower computes % from energy).

**Power panel (Omarchy bug):** `omarchy-battery-status` picks the battery with `upower -e | grep BAT` and reads
cycles/thresholds from `/sys/class/power_supply/BAT*`, so on Snapdragon the panel showed no %, size, cycles
or time. [fix-omarchy-battery-status.sh](assets/zenbook-a16/fix-omarchy-battery-status.sh) (installed as
`/usr/local/bin/fix-omarchy-battery-status`) patches `/usr/bin/omarchy-battery-status` in place: match
`BAT|_bat$`, use the found battery's sysfs path, and take `abs(power_now)` (qcom-battmgr reports it negative
while discharging). A `/usr/local/bin` override doesn't work: quickshell's PATH starts with
`/usr/share/omarchy/bin`, which symlinks to `/usr/bin`. The pacman hook
[zz-omarchy-battery-status.hook](assets/zenbook-a16/zz-omarchy-battery-status.hook) re-applies it after every
`omarchy` upgrade. Worth upstreaming. Right-click the bar battery icon to toggle the % next to it.

## 14. Speakers: tweeters were silent, plus a limited +6 dB boost (2026-09-26)

**Symptom:** the speakers were quiet and dull even at 100 %. Nothing had been turned off: every WSA884x amp
had BOOST/COMP/DAC on and `PA Volume` at max (6/6), the `WSA*_RX* Digital Volume` controls sat at their
81 = −3 dB ceiling (the machine driver caps them because `VISENSE` speaker protection is off on Linux), the
ASM stream volume was unity (8192), and PipeWire was at 100 %. The coil-whine tweaks (section 8) exclude the
audio path and don't change gain. Omarchy's own `omarchy audio tuning` ships only a Dell XPS profile
(`status` → "nothing ships for this laptop").

**Cause:** the speaker sink is 4 channels (`FL FR RL RR`) and the machine has 2 woofers and 2 tweeters.
PipeWire's upmix leaves `RL`/`RR` silent for stereo sources (sink monitor: a stereo tone gave peak 0 on both
rear channels), and **`RL`/`RR` are the tweeters**. Per-channel sine tones recorded with the internal mic,
dB above the room noise:

| Channel | 100 Hz | 200 | 400 | 1 k | 3 k | 8 k | Driver |
|---|---|---|---|---|---|---|---|
| FL | −3.2 | −7.7 | 14.4 | 29.5 | 29.5 | 13.5 | woofer, left |
| FR | −2.9 | −3.1 | 16.3 | 21.3 | 26.4 | 19.3 | woofer, right |
| RL | −6.9 | −1.8 | −4.2 | 7.0 | 32.3 | 45.4 | tweeter, **right** |
| RR | 0.3 | −6.9 | −6.7 | 4.3 | 34.6 | 45.8 | tweeter, **left** |

(The mic rolls off below ~300 Hz, so the low columns say nothing.) The tweeter sides are **crossed**: with the
stereo mic, `RL` was 6.1 dB louder in the right capsule and `RR` 4.4 dB louder in the left. The woofers
leaned the normal way, but only by 0.7/1.4 dB. Confirmed by ear through the finished filter: a left-only
burst came from the left and a right-only one from the right.

**Fix:** a PipeWire filter-chain in front of the speaker sink,
[90-tuning.conf](assets/zenbook-a16/speaker-boost/90-tuning.conf):

- 80 Hz highpass (the woofers can't reproduce anything lower, and removing it frees limiter headroom);
- `+6 dB` into the LSP stereo lookahead limiter with the ceiling at −1 dBFS (`alr`/`boost` off, 5 ms
  lookahead, 20 ms release), so quiet and mid-level material gets louder while the peaks stay below the stock
  maximum;
- woofers fed full range from the limiter output, the same as before;
- tweeters fed through a 2 kHz 4th-order highpass (two Butterworth biquads) so they never see bass, trimmed
  by −3 dB. Without the trim, the highpass phase shift let tweeter peaks overshoot the ceiling on full-scale
  noise (`RR` hit 32768), and with it they peak at 21–25 k against a 29195 ceiling;
- outputs wired explicitly as `FL=woofer L, FR=woofer R, RL=tweeter R, RR=tweeter L`, with
  `channelmix.disable` on the playback side so nothing remixes them.

It reuses Omarchy's speaker-tuning names (`omarchy_speaker_tuning` sink, host config
`~/.config/pipewire/omarchy-speaker-tuning.conf`, user unit `omarchy-speaker-tuning.service`), so the volume
keys and the audio panel resolve through it to the physical sink (`omarchy-audio-output-sink`), and
`omarchy audio tuning off` removes it cleanly. `omarchy audio tuning on` finds no match for this laptop and
leaves it alone.

**Install** (as the user, needs the UCM fix from section 4):
```
bash assets/zenbook-a16/speaker-boost/install-speaker-boost.sh
```
That installs `lsp-plugins-lv2`, copies Omarchy's host config and unit plus our `90-tuning.conf` into
`~/.config`, enables the unit, makes `omarchy_speaker_tuning` the default sink, and moves running streams
onto it.

**Verify:** `omarchy audio tuning status` shows "Host service: active (enabled)" and "Tuning sink: present",
`pactl get-default-sink` gives `omarchy_speaker_tuning`, and `omarchy-audio-output-sink` gives
`alsa_output.platform-sound.HiFi__Speaker__sink`. For the routing, play a left-only file to
`omarchy_speaker_tuning` while recording the speaker sink's monitor with 4 channels: only `FL` and `RR` carry
it, and `RR` has no 300 Hz content.

**Tuning knobs:** `g_in` (2.0 = +6 dB; above that, loud music starts to sound squashed with a release this
short), the tweeter `Freq` and trim `Mult`. After editing, run
`systemctl --user restart omarchy-speaker-tuning.service`. **Revert:** `omarchy audio tuning off`, which also
resets the default sink to the speakers. The tweeters go silent again.

**Not done:** there's no EQ voicing (the Windows side has Dolby). The current voicing is flat apart from the
crossover.

## 15. Touchpad palm rejection: a behavioral filter (2026-09-26)

**Symptom:** while typing, a palm touches the (large, 150×98 mm) touchpad. The pointer jumps, and a tap-to-click
selects text or moves the caret somewhere else.

**Why stock libinput doesn't cover it:** `disable_while_typing` is **off** in `~/.config/hypr/input.lua` on
purpose ([browser games](browser-game-pointer-lock.md): libinput mutes the pad while a WASD key is held).
libinput's other palm signals don't apply here. This PixArt `093A:3012` pad reports **no contact size and no
pressure**, only positions and `ABS_MT_TOOL_TYPE`. That last one does carry the firmware's palm flag, which
fires reliably for a hand resting at the top-left corner by the keyboard. (The XPS 16 pad reported pressure,
but palms and fingers pressed equally hard, and the lack of a usable signal there was one reason it went back.)

**Approach:** judge a touch by *behavior* instead of shape: when it lands relative to typing, where it lands,
and how it moves. [a16-palm-filter](assets/zenbook-a16/a16-palm-filter) (python-evdev) grabs the real pad,
classifies every contact, and re-emits only the accepted ones on a uinput clone,
"hid-over-i2c 093A:3012 Touchpad (palm filter)" (same ranges, resolution, bus and IDs). libinput and
Hyprland treat the clone as the touchpad, so taps, gestures, scrolling and your Hyprland settings all
behave as before. If the daemon dies, the grab goes away and the raw pad works again.

At touch-down, a contact is:

| Condition | Result |
|---|---|
| Firmware palm flag (`MT_TOOL_PALM`) | hidden for its lifetime |
| Ctrl/Alt/Super held | passed through (modifier+pointer is deliberate) |
| Typing: ≥ 2 quick keystrokes in the last 1.2 s and the newest < 0.5 s ago | held back until it travels 10 mm with no keystroke in between. A hand reaching for the pad sweeps; a palm creeps |
| Within 3 s of typing, landing in a side strip (10 mm) or the top strip (8 mm) | held back until it travels 8 mm |
| Within 1.2 s of a keystroke | held back until it travels 4 mm |
| Another finger already down (and not at an edge) | passed through (two-finger scroll) |
| Otherwise | passed through |

A held-back contact becomes a palm on the next keystroke. If it's lifted without moving, it's swallowed, so palm
taps never click. A physical click lets it through. A finger that sits still (< 1.5 mm over 0.8 s) while
typing resumes is hidden, which covers a hand resting on the pad before typing. It comes back as a new touch once
it moves 5 mm. A "keystroke" means a key pressed and released within 0.3 s, so keys held longer, like WASD in
a game, never mute the pad. That's what libinput's disable-while-typing gets wrong for games. The daemon
counts keystrokes by timing only, and key codes are never stored or logged.

**Install:**
```
sudo pacman -S --needed python-evdev libinput-tools
sudo install -m755 assets/zenbook-a16/a16-palm-filter /usr/local/bin/
sudo install -m644 assets/zenbook-a16/a16-palm-filter.service /etc/systemd/system/
sudo install -m644 assets/zenbook-a16/a16-palm.conf /etc/default/a16-palm
sudo systemctl daemon-reload && sudo systemctl enable --now a16-palm-filter
```
Leave `disable_while_typing = false` in Hyprland: the filter replaces it.

**Verify:** `hyprctl devices | grep -A1 palm-filter` lists the clone. `journalctl -u a16-palm-filter -f`
logs one line for every contact the filter hid, swallowed or let through late (reason, duration, travel,
start position as % of the pad). Normal fingers aren't logged. `python3 assets/zenbook-a16/test-a16-palm-filter.py`
replays 20 synthetic scenarios against the logic (no hardware needed). `sudo a16-palm-filter --dry`
classifies and logs without grabbing, so you can watch it next to the stock behavior.

**Tuning:** all thresholds are environment variables (see the script header). Set them in `/etc/default/a16-palm`,
then `sudo systemctl restart a16-palm-filter`. First live tuning, the same day: a "typing" touch was
originally hidden for its whole lifetime. The log then showed rejected contacts that swept 30–55 mm in 0.2 s,
which was a hand moving from the keyboard to the pad within half a second of the last key. So those touches are
now held back and let through after 10 mm instead.

**Revert:** `sudo systemctl disable --now a16-palm-filter`. The virtual pad disappears and the real one is
used again straight away.
