## Battery telemetry fixed: the A16 DTB ships the SoCCP remoteproc disabled (one-property fix, probably worth taking into the image)

Follow-up to the battery note above. Battery %, energy, charge cycles, time left and the charge thresholds all work now on the stock 7.2.0-18 kernel. No new modules and no firmware files are needed. Details and scripts are in [zoan37/omarchy-setup](https://github.com/zoan37/omarchy-setup/blob/master/zenbook-a16-omarchy-snapdragon.md) section 13.

### Cause

`qcom-battmgr` was bound and `/sys/class/power_supply/qcom-battmgr-bat` existed, but every property read returned `EAGAIN`: the charger service behind PMIC GLINK never came up. On Glymur that service runs on the **SoCCP**. UEFI starts the SoCCP, and Windows only attaches to it (`qcsubsys_ext_soccp8480.inf` uses LiveHandoff / `SubsysUefiLoadedImageAction`). The A16 tree in the image has

```
/soc@0/remoteproc-soccp@d00000   compatible = "qcom,glymur-soccp-pas", "qcom,kaanapali-soccp-pas"   status = "disabled"
```

so nothing brings up its GLINK edge. The image's `qcom_q6v5_pas` already has the kaanapali-soccp early-boot path (`qcom_pas_attach`). With the node set to `okay`, it attaches to the running SoCCP and never requests `soccp.mbn`, which is fine because that file isn't shipped anywhere (only a generic Kaanapali one). FixItFoundry's 7.3-rc3 tree uses the same attach model (their notes say upstream does too).

### Fix

Set `status = "okay"` on that node in the A16 DTB. I did it in place in the `.dtbauto` section of `vmlinuz.efi`: the blob size is unchanged because the 4 spare bytes become an `FDT_NOP` ([patch-vmlinuz-soccp.py](https://github.com/zoan37/omarchy-setup/blob/master/assets/zenbook-a16/patch-vmlinuz-soccp.py)). For the image, the cleaner route is `&remoteproc_soccp { status = "okay"; };` in the board DTS.

Result on first boot: `/sys/class/remoteproc/*` shows `soccp` `attached`, and `upower` reports 70.28 Wh full (70.0 Wh design), charge-cycles, time to empty, and start/end thresholds 75/80 %. Display, Wi-Fi, audio, cpufreq and fan control are unaffected. So the USB-PHY `mode-switch`/`orientation-switch` patch from my earlier negative result is **not** needed for battery on the A16.

### Omarchy side: the power panel shows nothing on Qualcomm

With telemetry working, the bar icon was right, but the power panel popup still had no percentage, size, cycles or time. `omarchy-battery-status` picks the battery with `upower -e | grep BAT`, and reads cycles and thresholds from `/sys/class/power_supply/BAT*`. On Snapdragon the UPower device is `battery_qcom_battmgr_bat` and the sysfs node is `qcom-battmgr-bat`. `qcom-battmgr` also reports `power_now` negative while discharging, so the panel showed "-9.3W". Local fix ([fix-omarchy-battery-status.sh](https://github.com/zoan37/omarchy-setup/blob/master/assets/zenbook-a16/fix-omarchy-battery-status.sh), re-applied by a pacman hook):

```diff
-battery=$(upower -e 2>/dev/null | grep BAT | head -n 1)
+battery=$(upower -e 2>/dev/null | grep -E 'BAT|_bat$' | head -n 1)
-... cat "$power_supply_path"/BAT*/charge_control_end_threshold ...
+... cat "$battery_path"/charge_control_end_threshold ...      (same for start threshold and cycle_count)
-'BEGIN { print microwatts / 1000000 }'
+'BEGIN { w = microwatts / 1000000; print (w < 0 ? -w : w) }'
```

This affects every Snapdragon machine running Omarchy, not just the A16, so it probably belongs upstream in Omarchy itself. It could also be carried as a patch in the image in the meantime.

Still open on my side: Bluetooth, suspend, camera.
