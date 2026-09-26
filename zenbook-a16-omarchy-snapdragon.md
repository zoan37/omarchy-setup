# ASUS Zenbook A16 (UX3607OA, Snapdragon X2 Elite Extreme): Omarchy Snapdragon install and fixes

First installed 2026-09-25 (whole disk); reinstalled 2026-09-26 **alongside factory Windows 11** after an
ASUS Cloud Recovery (section 10). Everything below was done from the Beelink SER8 over SSH after the first
boot; the laptop-side user is `napdivad`, hostname `zenbook`. Image: community build
[bprendie/omarchy-snapdragon](https://github.com/bprendie/omarchy-snapdragon) **v0.2.2-1**
(Omarchy 4.0.3, Arch Linux ARM userspace, Ubuntu Concept kernel `7.2.0-18-qcom-x1e`, Quattro
installer). Full test report filed upstream as
[issue #2](https://github.com/bprendie/omarchy-snapdragon/issues/2)
(copy in [assets/zenbook-a16/upstream-issue-2-report.md](assets/zenbook-a16/upstream-issue-2-report.md)).
Identify the machine with `cat /proc/device-tree/model` → `ASUS Zenbook A16 (UX3607OA)`.

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
| Speakers, microphone | Work after the UCM fix below |
| CPU frequency scaling | Works after the device-tree patch below (355 MHz – 3.6/4.45 GHz, 3 policies) |
| Fan | **Controlled from Linux** through the EC mailbox (section 7); `a16-fan-daemon` keeps it at **0 rpm at idle** with a Mac-style whisper policy (section 11) |
| Windows 11 dual boot | Works: factory Windows restored by ASUS Cloud Recovery, Omarchy in the freed space, firmware entry "Omarchy (GRUB)", GRUB chainloads Windows (section 10) |
| Bluetooth | No adapter: needs a device-tree patch (serdev node + regulators + `w-disable2` polarity, see jc372 patch 0001). Firmware is already in the image. Not done yet |
| Battery percentage | Empty (`qcom-battmgr` cannot link to `a600000.usb`/`a800000.usb`, so the PMIC GLINK battery manager never comes up). Charging works. The USB-PHY DT patch that fixes this on FixItFoundry's kernel breaks the panel here (section 12) |
| Suspend, camera | Not tested / known gap |
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
- **Battery telemetry:** see section 12 for what not to do; needs the USB-controller/SoCCP side of the DT.
- **Camera, suspend:** untested. **Black screen after LUKS unlock:** intermittent eDP link-training failure
  on any entry; power-cycle. Not seen since the reinstall (0 occurrences in the current dmesg).
- Coil whine while charging powered-off (stops once booted): not investigated.
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
  GRUB and `/boot/oma-snap/custom`. The battery fix needs the USB controller / SoCCP side too.
- **Generic Windows ARM ISO on this firmware:** see section 10 item 1.
- **`0xC9` block engine** for fan curves: dead on Linux and Windows alike; the `0xC4` mailbox is the way.
- **`pacman` sandbox theory** for the installer mirror error: a no-op (no `DownloadUser` in the image); it was
  the clock.
