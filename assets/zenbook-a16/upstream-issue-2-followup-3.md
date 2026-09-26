## Correction/update on the coil whine: the NVMe link was the loudest *measurable* tone, not the only source

To be clear after the last comment: forcing the SSD link out of ASPM L1 removed the one tone the mic could pin down (8.9 kHz, −83 → −94 dBFS). It did not make the board silent. With an ear at the keyboard there is still a whine, and my webcam-mic setup bottoms out around −95 dBFS, so the rest is below what I can measure. The remaining part behaves like ordinary VRM noise: passive parts (inductors/MLCCs under the middle of the keyboard) excited by the SoC's power management, not the SoC itself, and present under Windows too.

What helped further, judged by ear only (room not quiet enough for the mic; treat as anecdotal), applied together and kept as a boot service (`a16-whine-tweaks`, values in `/etc/default/a16-whine`, all in [zoan37/omarchy-setup](https://github.com/zoan37/omarchy-setup/blob/master/zenbook-a16-omarchy-snapdragon.md) section 8):

- NVMe PCIe link retrained at Gen1 and the Wi-Fi link at Gen1 (`setpci` on the root port: LnkCtl2 target speed + LnkCtl retrain bit)
- the two 4.4 GHz clusters (cpu6-17) taken offline
- the remaining 3.6 GHz cluster run at a **fixed clock**, `scaling_min_freq` = `scaling_max_freq`. This was the most audible change: 1.5 GHz gave "more static", 2.5 GHz "oscillates", 3.6 GHz the steadiest. Consistent with the core rail's buck converter hovering at its light-load/burst-mode boundary at low voltages and being pushed into continuous mode at the top clock.
- `cpu-sleep-0` cpuidle state disabled (mic saw nothing, ear says it helps; re-enabled)
- runtime PM forced `on` for all USB/PCI/platform devices except the GPU
- the unused `cdsp` remoteproc stopped (`adsp` stays up for audio)

Net effect per the owner's ear: "less piercing pitch, more like a normal buzz" with the ear on the chassis; nothing audible at normal distance. Costs are real (roughly a third of the multi-thread performance, SSD ~0.9 GB/s, Wi-Fi ~2 Gbit/s, peripherals never sleep), so this is a trade for people who are sensitive to the tone, not a default. GPU devfreq pinned to max was tried and reverted (+6 °C, no benefit). A bisecting script (`whine-round8.sh`) is in the repo for when a quiet room is available.

Also worth noting: one published review of this model (ultrabookreview) reports no coil whine on their unit, so unit-to-unit variation exists and an exchange may be the real fix for a bad one.
