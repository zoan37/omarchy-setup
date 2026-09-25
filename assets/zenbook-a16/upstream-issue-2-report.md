# ASUS Zenbook A16 UX3607OA (X2 Elite Extreme): v0.2.2-1 physical test report

Tested 2026-09-25 on a retail UX3607OA (BIOS UX3607OA.305, 48 GB, OLED 2880x1800). Image: `omarchy-snapdragon-v0.2.2-1.iso` (SHA-256 `e99a97e8…`), written with `dd`. Secure Boot disabled in F2 setup, booted from USB via Esc.

**Result: installed and running as a daily desktop after three fixes (clock, Wi-Fi board file, UCM file name) plus one device-tree change for CPU frequency scaling.** Details and reproducible fixes below.

## 1. Installer fails: "Could not sync mirrors … (unexpected error)" — stale clock

**Symptom.** Live boot, configurator and partitioning all work. The "Installing Arch + Omarchy" phase fails immediately with archinstall `Could not sync mirrors: ['/usr/bin/pacman', '-Syy'] … error: failed to synchronize all databases (unexpected error)`. `pacman -Syy` from the shell fails the same way; the `oma-snap-local` and `offline` databases sync, `oma-snap` does not.

**Root cause.** `pacman -Syy --debug` shows, for `oma-snap.db`:
```
debug: signature timestamp is greater than system time.
debug: summary: key missing
debug: status: No public key
```
The A16 live system boots with a clock earlier than 2026-09-15 (the RTC is not readable on this kernel; `qseecom: untested machine` also means no EFI time source), so GnuPG treats the signed repository as coming from the future and refuses the key. pacman collapses that into "unexpected error". The installer log also shows "Skipping waiting for automatic time sync".

**Fix (works).** In the installer shell:
```
date -s "2026-09-25 22:00"    # anything after the repo signing date
pacman -Syy
bash /root/.automated_script.sh
```
**Suggestion.** Before the install phase, set the clock to at least the ISO build date when the system time is older than it (or wait for NTP if networked). This will hit every A16 until the RTC works.

## 2. Wi-Fi: QCC2072 has no board-data entry — fixed with a board-2.bin rebuild

**Symptom.** `ath12k_wifi7_pci 0004:01:00.0: Wi-Fi 7 Hardware name: qcc2072 hw1.0`, firmware `WLAN.COL.1.0.c2-00277` loads, then:
```
failed to fetch board data for bus=pci,vendor=17cb,device=1112,subsystem-vendor=105b,subsystem-device=e14f,qmi-chip-id=33,qmi-board-id=255,variant=UX3407Q from ath12k/QCC2072/hw1.0/board-2.bin
qmi failed to load board data file:-2
```
No wireless device appears. Upstream linux-firmware `board-2.bin` (even the 2026-09-21 update) has entries for subsystem `e15a` (A14) but not `e14f` (A16).

**Fix (works, Wi-Fi 7 connects, 5 ms LAN latency).** Rebuild `board-2.bin` with `ath12k-bdencoder` from qca-swiss-army-knife: take upstream `board-2.bin`, add the vendor image `bdwlan_qcc2072_1p0_ncm820A.elf` from ASUS's UX3607OA "Qualcomm Board Support Package" (V1.312.4500.0, `QualcommBSP/WIFI_BT/qcwlancol8480/`; the INF maps `SUBSYS_E14F105B` to exactly that file) under both names:
```
bus=pci,vendor=17cb,device=1112,subsystem-vendor=105b,subsystem-device=e14f,qmi-chip-id=33,qmi-board-id=255,variant=UX3407Q
bus=pci,vendor=17cb,device=1112,subsystem-vendor=105b,subsystem-device=e14f,qmi-chip-id=33,qmi-board-id=255
```
Same recipe as jc372/A16UbuntuBuild and Hekatomb/LinuxOnAsusUX3607OA. Note the A14 copy of that file (e.g. in chrispouliot/nixos) is a different build; use the A16 package.

**Packaging note.** On the installed system the driver reads `/usr/lib/firmware/<release>/…`, which is a read-only bind mount of `/usr/lib/oma-snap/sets/<id>/firmware/<release>/`. A file placed in plain `/lib/firmware/ath12k/…` is shadowed; it must go into the set directory (and `set.json`'s sha256 for it then no longer matches). `modprobe -r ath12k` hangs; reboot to reload.

## 3. No CPU frequency scaling — fixed with one device-tree property

**Symptom.** `/sys/devices/system/cpu/cpufreq/` is empty; all 18 cores stay at boot clock, no cpufreq cooling devices. Loading `scmi-cpufreq` gives:
```
arm-scmi: timed out in resp(caller: do_xfer+0x158/0x878)
arm-scmi: Failed to query supported version for protocol 0x13.
scmi-cpufreq scmi_dev.3: probe with driver scmi-cpufreq failed with error -110
```
**Root cause** (FixItFoundry/zenbook-a16-linux finding, confirmed here): the PDP0/CPUCP firmware answers SCMI perf (0x13) in shared memory but never rings the mailbox doorbell, so interrupt-mode transfers time out.

**Fix (works).** Add `arm,no-completion-irq;` to `/firmware/scmi` in `glymur-asus-zenbook-a16-ux3607oa` DTB. The DTB is embedded in `vmlinuz.efi` as a `.dtbauto` PE section (hwid-matched); I patched it in place (the section had 169 bytes of slack; the section's VirtualSize must be updated too or the stub reports "found bad dt blob in PE section 8"). With `scmi-cpufreq` in `modules-load.d`: three policies (cpu0/6/12), 355 MHz – 3.61/4.45 GHz, `scmi` driver, cpufreq cooling devices created, stable under load. The "Failed to get FC for protocol 13" messages are benign.

Also tested: booting **without** `clk_ignore_unused pd_ignore_unused` (kept `arm64.nopauth`) works on the A16: display, Wi-Fi, keyboard/touchpad, cpufreq all fine, no new errors. Worth making optional in `oma-snap-boot-stage/publish` for machines where it's proven.

## 4. Intermittent black screen after LUKS unlock (eDP link training)

Roughly 1 in 3 boots (any entry, patched or stock) the panel stays black after the passphrase; the kernel log shows
```
[drm:msm_dp_ctrl_link_train_1_2 [msm]] *ERROR* link training #2 on phy 0 failed. ret=-110
[drm:msm_dp_ctrl_link_train [msm]] *ERROR* link training on sink failed. ret=-110
```
The system is otherwise up (SSH works, Hyprland reports eDP-1 enabled). A power cycle fixes it. FixItFoundry carries eDP `LINK_RATE_SET` patches for this. Note also that the live/installed backlight defaults to ~5 % (102/2047), which looks black on the OLED; brightness keys do work.

## 5. Hardware status table (installed system, patched kernel)

| Area | Result |
|---|---|
| Boot/storage | Installer finishes (after clock fix); NVMe, encrypted root, GRUB entry boots; firmware boots Omarchy by default (no efibootmgr tricks needed) |
| Panel/unlock | Passphrase prompt visible; desktop at 120 Hz; intermittent link-training failure (§4) |
| GPU | Accelerated (GMU firmware v5.2.38 loads), no GPU resets seen |
| Wi-Fi | Works after board-2.bin rebuild (§2); power save on, stable |
| Bluetooth | No adapter. Firmware (`hmtbtfw20.tlv`, `hmtnv20.*`) is present; the DTB lacks the `qcom,wcn7850-bt` serdev node under uart14 and its regulators, and `w-disable2-gpios` polarity keeps the combo disabled (see jc372 patch 0001) |
| Speakers/mic | **Work after a one-line UCM fix.** As shipped, PipeWire shows only "Dummy Output" and the kernel logs `MultiMedia1 Playback: ASoC: no backend DAIs enabled … possibly missing … UCM profile`; `alsaucm -c hw:0` fails with `failed to import hw:0 use case configuration -2`. Cause: alsa-lib looks the UCM file up by the card **long name** (`ASUSTeKCOMPUTERINC.-ZenbookA16UX3607OA-1.0-UX3607OA`), but the image installs it as `conf.d/glymur/GLYMUR-ASUS-Zenbook-A16-UX3607OA.conf` (the DT model, which is also truncated to 31 chars as the card short name). Fix: `ln -s GLYMUR-ASUS-Zenbook-A16-UX3607OA.conf /usr/share/alsa/ucm2/conf.d/glymur/ASUSTeKCOMPUTERINC.-ZenbookA16UX3607OA-1.0-UX3607OA.conf`, restart wireplumber. Result: 4-channel "Speaker playback" sink, test tone and YouTube audible, internal microphones record signal. The four `sdw:x:0:0217:0204` WSA884x amps bind to `wsa884x-codec`; the early `qcom-apm … CMD timeout for [1001021]` and the "no matching ACPI device found, ignoring peripheral" lines are apparently harmless |
| Keyboard/touchpad | Work (hid-asus 0B05:4B42 binds); brightness keys work; keyboard backlight: no driver, but it is controllable through the EC mailbox (`ECCW(1,0x81,4)` then `ECCW(1,0x87,level)`, verified) |
| Battery/charging | Charges, but `/sys/class/power_supply/qcom-battmgr-*` reads empty (`waiting_for_supplier`; `pmic_glink: Failed to create device link … supplier fd5000.phy`) |
| USB-C | Charging works (desktop shows charging state); data devices not tested; `/sys/class/typec` is empty (UCSI PPM not initialised) |
| Fan | EC-controlled, no Linux interface; idle floor ~1980 RPM at 37 °C. RPM readable over I2C (FixItFoundry method) |
| Suspend | Not tested |
| Camera | Not tested (known gap) |

## 6. Also observed

- The installed system's first boot after install went black after unlock; second boot was fine (likely §4).
- Open issue #1 (regenerated boot entries unbootable on mkinitcpio 42) not exercised; the installer-built entry boots.
- The `oma_snap_set` initramfs hook does not hash-verify set contents, so a modified `board-2.bin` in the set boots fine; `set.json` is just stale.

Happy to test candidate builds. Logs, the patched DTB diff and the rebuilt `board-2.bin` are available on request.
