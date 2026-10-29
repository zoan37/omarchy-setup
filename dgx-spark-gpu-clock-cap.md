# DGX Spark: a 2000 MHz GPU clock cap (no power limit on the GB10)

**Not an Omarchy machine.** The NVIDIA DGX Spark (GB10) runs DGX OS and serves local models alongside the
Omarchy machines. It's here so the whole lab's power caps live in one place, next to the
[4090 PC](rtx4090-pc-power-caps.md), the [K8's B70](k8-plus-egpu.md) and the [R9700](r9700-egpu-thunderbolt.md).
Date: 2026-10-29.

**Reaching it:** from the XPS 13, `ssh spark-wifi` (the Spark's `spark-xxxx.local` over IPv4). The `ssh spark`
alias jumps through the K8 (`k8.local`) and fails when the K8 is off; see
[LAN/SSH notes](lan-ssh-self-healing.md).

## Why a clock cap, not a power cap

- **No user power limit or fan control on the GB10.** `nvidia-smi` shows `power.limit` and `fan.speed` as
  `[N/A]`: the firmware manages both, so the `nvidia-smi -pl` cap used on the 4090 doesn't exist here.
- **Clock locking is the only lever.** `nvidia-smi -lgc <min>,<max>` still works.
- **2000 MHz loses almost nothing.** An NVIDIA forum test
  ([Cooler GB10 temps, almost no performance lost](https://forums.developer.nvidia.com/t/cooler-gb10-temps-almost-no-performance-lost/372662))
  measured the GPU at **~43 W → ~25 W** under load with the **same tok/s** at a 2000 MHz cap.
- **Stock** is the equivalent of `-lgc 0,3000`; the hardware maximum (`clocks.max.gr`) is **3003 MHz**.

## Apply: `nvidia-smi -lgc 0,2000`

```sh
sudo nvidia-smi -lgc 0,2000
```

The lock resets on reboot, so a oneshot systemd unit reapplies it after `nvidia-persistenced` and resets it
on stop. Copy in [`assets/dgx-spark/gpu-clock-cap.service`](assets/dgx-spark/gpu-clock-cap.service):

```ini
[Unit]
Description=Cap NVIDIA GB10 GPU graphics clock to 2000 MHz (reduce heat)
After=nvidia-persistenced.service
Wants=nvidia-persistenced.service

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi -lgc 0,2000
ExecStop=/usr/bin/nvidia-smi -rgc
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Install it from the repo root (copy the file to the Spark first, for example with `scp`):

```sh
sudo install -Dm644 assets/dgx-spark/gpu-clock-cap.service /etc/systemd/system/gpu-clock-cap.service
sudo systemctl daemon-reload
sudo systemctl enable --now gpu-clock-cap
```

## Verify

```sh
systemctl status gpu-clock-cap        # active (exited), enabled
nvidia-smi --query-gpu=temperature.gpu,power.draw,clocks.gr --format=csv
```

| State (idle) | Temp | Power | Graphics clock |
|---|---|---|---|
| before the cap | 40 °C | ~7.4 W | 2158 MHz |
| after the cap | — | — | 1956 MHz |

At idle the difference is small; the cap matters under sustained load, where the clock would otherwise
boost toward 3 GHz.

## Undo

```sh
sudo systemctl disable --now gpu-clock-cap     # stop runs nvidia-smi -rgc, back to stock clocks
# remove it fully:
sudo rm /etc/systemd/system/gpu-clock-cap.service
sudo systemctl daemon-reload
```
