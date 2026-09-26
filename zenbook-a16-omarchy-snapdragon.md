# ASUS Zenbook A16 (UX3607OA, Snapdragon X2 Elite Extreme): Omarchy Snapdragon install and fixes

Set up 2026-09-25. Everything below was done from the Beelink SER8 over SSH after the first boot;
the laptop-side user is `napdivad`, hostname `zenbook`. Image: community build
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
| Install, encrypted root, GRUB, 120 Hz OLED, GPU, keyboard, touchpad, brightness keys, USB-C charging | Works |
| Wi-Fi 7 (QCC2072) | Works after the board-file fix below |
| Speakers, microphone | Work after the UCM fix below |
| CPU frequency scaling | Works after the device-tree patch below (355 MHz – 3.6/4.45 GHz, 3 policies) |
| Bluetooth | No adapter: needs a device-tree patch (serdev node + regulators + `w-disable2` polarity, see jc372 patch 0001). Firmware is already in the image. Not done yet |
| Battery percentage | Empty (`qcom-battmgr` waits for a supplier on this kernel). Charging works |
| Fan | EC-controlled, readable, **not** controllable (see EC section) |
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

## 7. Embedded controller / fan (research, no control yet)

- EC on `/dev/i2c-9` (`a84000.i2c`): address `0x76` (RAM read cmd `0x52`, WMI tunnel cmd
  `0x51`) and `0x5b` (byte ops: cmd `0x10` = `{dev,reg}` pointer, `0x11` = data). FixItFoundry's
  `glymur-ec-read.sh rpm` / `glymur-ec-block.sh` are installed in `/usr/local/bin`. Rules: two
  separate `i2ctransfer`s (no repeated start), never poll under CPU load.
- Idle fan ≈ 1980 RPM at 37 °C (EC policy floor). Two rotors, one tach (`0x0602/0x0603`).
- The firmware ACPI tables were dumped through `/proc/kcore` (STRICT_DEVMEM blocks `/dev/mem`;
  `iomem=relaxed` does not help on arm64): `~/Downloads/omarchy-snapdragon/acpi/DSDT.dsl` on the
  SER8, `~/acpi/DSDT.aml` on the laptop.
- The `0xC4` mailbox (`ECCW`) works: **keyboard backlight** = `ECCW(1,0x81,4)` then
  `ECCW(1,0x87,level 0-3)` (verified); Fn-lock = `ECCW(2,0x84,x)`. The "OS present" handshake
  `ECCW(2,0x83,1)` is accepted but the `0xC9` fan-curve block engine (WMI `0x00110024/25/32`,
  methods GDFC/GFLB/SUFC) never clears its control byte, even immediately after. ACPI FAN0 has no
  `_FSL`; WMI `0x00110019` (Normal/Quiet/Turbo/Full) only programs PEP0 temperature limits.
  Untried: `IC10._DSM` functions 1/2 (cmd `0x20`/`0x23` on `0x76`) as a possible enable.

## 8. Loose ends

- Passwordless sudo for the SSH work (`/etc/sudoers.d/99-napdivad-nopasswd`) was removed at the
  end of the session. The SER8's SSH key remains in `~/.ssh/authorized_keys`.
- Handoff notes from the laptop-side Claude session: `~/zenbook-a16-power-investigation.md`.

## 9. Personal config ported from the other machines (2026-09-25)

Applied over SSH, all user-level, backups as `~/.config/hypr/*.bak-20260925`:

- `input.lua`: `altwin:swap_alt_win`, `touchpad.natural_scroll = true`,
  `touchpad.disable_while_typing = false`, three-finger horizontal workspace swipe with the loose
  gesture tuning ([hyprland-shell-tweaks.md](hyprland-shell-tweaks.md)).
- `looknfeel.lua`: resize on border (`extend_border_grab_area = 15`).
- `bindings.lua`: group move-window bindings, SUPER+A select-all, SUPER+SHIFT+S screenshot.
- Ghostty `local.conf` (font-size 11, `ctrl+enter=unbind`) + the trailing `config-file` include
  ([terminal-font-size.md](terminal-font-size.md), [ghostty-ctrl-enter.md](ghostty-ctrl-enter.md)).
  **Ghostty is not packaged for this ARM build** (`target not found`; only foot, kitty and
  alacritty exist in the ALARM repos), so the terminal is **kitty**:
  `sudo pacman -S kitty && omarchy-default-terminal kitty`, with the kitty font-size trick from
  [terminal-font-size.md](terminal-font-size.md) staged (`local.conf` 11pt, active `font_size 9.0`
  line, trailing `include local.conf`).
- `git config --global user.name/email` set to zoan37; `gh auth login` still to do.
- Not ported: Chrome Vulkan/ANGLE flags (x86 GPU specific), hypr-momentum (needs cmake +
  Hyprland headers via hyprpm; untried on this kernel/arch), Cyberspace theme.

### Fan daemon v3.1 "whisper" (2026-09-26): Mac-style policy

Measured on the A16 fan (mailbox tach byte ≈ rpm/250): it keeps spinning down to PWM 20 and starts reliably
from rest at PWM 25 (PWM 30 ≈ 800 rpm, 45 ≈ 1400 rpm, 75 ≈ 2500 rpm, 120 ≈ 3700 rpm). The kernel's own
limits are 95 °C passive / 115 °C critical, so the SoC can run warm. The policy is now:

- **Input:** hottest CPU/GPU zone, smoothed with a ~60 s exponential average (5 % per 3 s sample).
- **Off until warm:** fan starts only when the *smoothed* temperature passes 68 °C. A 45 s burst of 8 busy
  threads peaks at 82 °C instantaneous and never moves the fan; a 12-thread all-core load takes ~45 s to
  start it.
- **Whisper stage:** it starts at PWM 30 (~800 rpm) and climbs 1 count per 3 s along
  `68 °C:30 → 78:45 → 85:90 → 90:150 → 95:220` (4 counts per step above 82 °C smoothed).
- **Fast path with hysteresis:** a ~10 s average above 88 °C engages an 8-count-per-step ramp; it releases
  only 5 °C lower, so the fan cannot hunt around the threshold (v3 did).
- **Exponential spin-down:** each step the duty may fall by 1/25 of its value, so after a load ends the fan
  decays 160 → 30 in ~2.5 min, idles at whisper, and turns off once the smoothed value has been below 58 °C for
  2 min (and it has run ≥ 3 min). Idle result: 0 rpm.
- **Safety:** ≥ 97 °C or any I2C error hands control back to the EC's own curve; the 60 % clock cap from
  section 6 still engages at 85 °C instantaneous and does most of the sustained-load work silently.
- Mailbox transactions in the daemon and `a16-fan.sh` share `/run/lock/a16-fan.lock`, so `a16-fan.sh status`
  no longer garbles the daemon's writes.

Knobs live in [`/etc/default/a16-fan`](assets/zenbook-a16/a16-fan.conf) (values only on assignment lines:
systemd keeps inline `#` comments as part of the value, which broke v2); `systemctl restart a16-fan-daemon`
after editing. Watch it with `journalctl -fu a16-fan-daemon`.
