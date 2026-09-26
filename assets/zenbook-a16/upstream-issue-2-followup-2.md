## Update: coil whine on the A16 traced to the NVMe link's ASPM L1 state (mic-measured); suspend resets the machine; BIOS 312

Three more findings since the last comment, all documented with scripts in [zoan37/omarchy-setup](https://github.com/zoan37/omarchy-setup/blob/master/zenbook-a16-omarchy-snapdragon.md).

### Coil whine → SSD PCIe link power state

Once the fan is at 0 rpm a faint high tone is audible with an ear at the keyboard (present under Windows too, so not a Linux problem as such). Ear-based tests were unreliable, so I put a USB webcam mic at the keyboard centre and ran a small pure-Python FFT over 6 s `pw-record` clips, toggling one setting at a time (scripts in `assets/zenbook-a16/whine-mic/`). Result, strongest narrow tone at the keyboard, averaged over 4 takes, repeatable to ±2 dB:

| Samsung MZVL8512HFLU link (`/sys/bus/pci/devices/0005:01:00.0/link/l1_aspm`) | 6.8 kHz | 8.9 kHz |
|---|---|---|
| L1 on (kernel default) | −97 dBFS | **−83 dBFS** |
| L1 off | −92 dBFS | −94 dBFS |

So the SSD module's regulator sings at 8.9 kHz whenever its link parks in L1, and at a quieter 6.8 kHz when the link is held active. Writing `0` to that one `l1_aspm` file at boot takes ~10 dB off the loudest tone without touching Wi-Fi or the rest of the system (a oneshot service does it; `pcie_aspm=off`/`policy=performance` give the same result but cost more). Things that measured as no effect: the `cpu-sleep-0` cpuidle state, USB/PCI/platform runtime PM, GPU devfreq/runtime PM, cpufreq governor, fan speed, display refresh/brightness/DPMS, the audio stack, and the BIOS update. The remaining 6.8 kHz tone follows the Wi-Fi card's power path but its default state is already its quietest (radio off +9 dB, Wi-Fi link L1 off +6 dB). One warning: `nvme set-feature -f 0x0c -v 0` (APST off) on this drive hung the admin queue for ~10 minutes before applying, and did not help; don't do that on the root disk.

Not a distro issue, but if other Snapdragon laptops with the same Samsung PM9x-class module report whine, this is a cheap thing to check.

### Suspend

`systemctl suspend` (and the idle timer) → `PM: suspend entry (deep)` is the last journal line; the machine never resumes and the firmware resets it, which looks like a random reboot. No panic record. I mask `sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target` for now.

### BIOS 312

For this Snapdragon model there is no separate BIOS download: the firmware ships as a Windows firmware-class driver inside ASUS's "Qualcomm Board Support Package" (V1.312.4500.0, 2026-07-23). Running that installer only stages it; the flash happens on the next boot **of Windows**. Booting Linux afterwards does nothing and the ESRT keeps showing the old version. After the Windows boot: BIOS 312, Secure Boot still off, the firmware entry pointing at GRUB survived. No functional change observed on the Linux side (Wi-Fi, audio, cpufreq, fan control all as before).
