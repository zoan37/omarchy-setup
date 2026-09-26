## Follow-up (2026-09-26): fan control works, 0 rpm at idle; dual boot with Windows; a few more findings

Since the report above, the fan row in the status table is out of date, so here is what changed. Everything is documented with scripts in [zoan37/omarchy-setup → zenbook-a16-omarchy-snapdragon.md](https://github.com/zoan37/omarchy-setup/blob/master/zenbook-a16-omarchy-snapdragon.md) (sections 7, 10–12). Nothing here needs to go into the image; it is offered as reference for A16 owners and for whoever picks up the ASUS EC driver.

### Fan: the EC mailbox accepts manual PWM, including 0

The register map from [omerfaruknehir/asus-zenbook-a14-ec](https://github.com/omerfaruknehir/asus-zenbook-a14-ec) (Snapdragon Zenbook A14) works unchanged on the A16. EC at `0x5b` on `/dev/i2c-9` (`a84000.i2c`), mailbox device `0xC4`:

- write = `0x31 ← feature`, `0x32 ← value`, `0x30 ← bank`, wait for `0x30` to read 0
- bank `0x01`: `0x82` fan mode (0 auto / 2 manual), `0x8c` select fan 0/1, `0x8a` PWM 0–255, `0x0a` PWM readback, `0x09` tach (≈ rpm/250), `0x02` mode readback

Measured on this unit: PWM 120 → 3720 rpm, 75 → 2520, 30 → ~800, **0 → fan off**, mode 0 restores the EC's own curve. The fan keeps spinning down to PWM 20 and starts from rest at 25. Two rotors, tachs in EC RAM at `0x0602/3` and `0x0624/5`. The `0xC9` fan-curve block engine is dead on Windows too, so the mailbox is the way. Why the EC's *automatic* curve idles at ~1980 rpm under Linux but at 0 under Windows was not isolated (some handshake the ASUS platform driver does); manual mode sidesteps it. The verification was done from factory Windows through the ASUS WMI classes (`ATD_STS.ec_write_command_byte(commandcode=value, param0=feature, param1=bank)`; `IecToolkitInterface.SystemMethod` for EC RAM), scripts in the repo.

On top of that I run a small userspace daemon (`a16-fan-daemon`, bash + `i2ctransfer`, systemd) that puts the EC in manual mode and applies a smoothed curve: hottest CPU/GPU zone with a ~60 s exponential average, fan off until the smoothed value passes 68 °C (kernel trips are 95 °C passive / 115 °C critical), first stage at ~800 rpm, 1-count-per-3 s ramps, fast path above 88 °C with hysteresis, exponential spin-down, and any I2C error or ≥ 97 °C hands control back to the EC. Result: **0 rpm at idle and through short bursts** (a 45 s 8-thread burst peaks at 82 °C and never starts the fan); a 12-thread all-core load starts it after ~45 s. The numbers are personal taste, so I would not suggest shipping a curve, but the mode/PWM interface itself might be worth a note in the README for people asking about fan noise, since the stock EC curve on Linux is what makes the machine audible at idle.

### Dual boot with factory Windows 11

- A generic Windows 11 ARM64 ISO cannot boot this firmware: the loader is rejected with Secure Boot on, WinPE lacks X2 Elite drivers with it off, and the firmware only enumerates MBR (not GPT) USB sticks. ASUS Cloud Recovery (F2 → MyASUS) restores factory Windows but wipes the disk.
- The installer's "install into free space" mode then worked fine next to Windows (after `manage-bde -off C:`; it refuses BitLocker volumes, and ≥ 32 GB free). Same clock fix as in the report.
- The firmware dropped the installer's boot entry and booted Windows; creating the entry from Windows with `bcdedit /copy {bootmgr}` pointing at `\EFI\oma-snap\grubaa64.efi` on `OMARCHY_EFI` stuck permanently. A GRUB entry chainloading `\EFI\Microsoft\Boot\bootmgfw.efi` from the Windows ESP works.
- `clk_ignore_unused pd_ignore_unused` can be dropped on the A16 without regressions (display, Wi-Fi, input, audio, GPU); I boot without them.

### Negative result worth recording

Deleting `mode-switch`/`orientation-switch` from `phy@fd5000`/`phy@fde000` (the UCSI/battery fix used elsewhere) gives a black screen on this kernel: new `msm_dp_display_host_phy_init` WARNING and eDP link training fails, and `qcom-battmgr` is still empty (device links to `a600000.usb`/`a800000.usb` fail). So battery percentage on the A16 needs more than that patch.

Still open on my side: Bluetooth (serdev DT node, the in-place DTB patch has too little slack for it), battery telemetry, camera, suspend. Happy to test anything.
