# StrixFold on two Omarchy Strix Halo boxes, in a Debian 13 / ROCm 10 container

[StrixFold](https://github.com/Shoestring-dev/StrixFold) runs DeepSeek-V4.1-Flash split across two Strix Halo boxes
(Ryzen AI Max+ 395, gfx1151, 128 GB) over USB4. Its tested stack is Debian 13 with AMD/Collabora's "rex" repository:
kernel 7.2.7 and ROCm 10.0.0-4. These notes run it **without reinstalling** two Omarchy boxes (an
[EVO X3](evo-x3-setup.md) and a Bosgame M5, set up 2026-11-15): the Omarchy kernel (`7.2.15-1-omarchy`) and amdgpu
stay on the host, and a Debian 13 container per box carries ROCm 10 and StrixFold's toolchain.

Result: it builds, passes StrixFold's GPU tests and input checks, and serves. The probe answers "Paris", and the speeds
(below) are close to StrixFold's own one-cable Bosgame pair.

Files: [assets/strixfold/](assets/strixfold/).

## Host setup (both boxes)

| What | How |
|---|---|
| BIOS | UMA frame buffer at the minimum (1 GB); see [evo-x3-setup.md](evo-x3-setup.md#local-llm-memory-bios-carve-out-and-gtt) |
| GPU memory, **124 GiB GTT** | in `/etc/default/limine`: `amdgpu.gttsize=126976 ttm.pages_limit=32505856 ttm.page_pool_size=32505856`, then `sudo limine-update` and reboot. Check: `mem_info_gtt_total` = 133143986176 |
| USB4 link | `thunderbolt_net` loaded at boot (`/etc/modules-load.d/thunderbolt-net.conf`); an NM profile on `thunderbolt0`: node0 `10.40.0.1/24`, node1 `10.40.0.2/24` (the addresses StrixFold's `serve.conf` expects), **MTU 1500** (StrixFold: 65520 drops packets under bulk load), IPv6 off; ufw allows `thunderbolt0` from `10.40.0.0/24` |
| USB4 kept awake | `usb4-keep-awake.service` writes `on` to the thunderbolt `power/control` files at boot, so the link comes back after the partner reboots (StrixFold BOSGAME-M5.md) |
| SSH | each box's key in the other's `authorized_keys` |
| podman + crun | `sudo pacman -S podman crun`. `crun` is needed for `--group-add keep-groups` (GPU device groups) in a rootless container |

Roles: **node1** builds and runs every script (the Bosgame here, it had the disk space: about 620 GB), **node0**
serves the API (the X3, which already held the 400 GB of model files).

One USB4 cable only (the X3 has one port): StrixFold measured one cable at 6-7% slower decode and 14-16% slower prompt
reading than two. A fresh cable trained Gen 3 x2 (40 Gb/s); after a reboot it came back at Gen 2, as StrixFold
describes for the M5. `iperf3` over `thunderbolt_net`: about 9.2 Gb/s per direction, ping about 0.7 ms.

## The container

[`Containerfile`](assets/strixfold/Containerfile): `debian:trixie`, the ryai keyring checked against StrixFold's sha256
and the key fingerprint, then `amdrocm-core-sdk10.0-gfx1151=10.0.0-4`, `amdrocm-core10.0-gfx1151=10.0.0-4`,
`therock-gfx1151`, and the build tools. About 1 GB to download, 9.3 GB as an image. Build it once (on node1) and copy it
over the USB4 link:

```sh
cd ~/tfp/container && podman build -t localhost/strixfold-env:rocm10.0.0-4 .
podman save localhost/strixfold-env:rocm10.0.0-4 | ssh 10.40.0.1 podman load      # 36 s for 9 GB
```

[`sf-up`](assets/strixfold/sf-up) starts a long-lived container named `strixfold`: host network (it sees
`thunderbolt0`), `/dev/kfd` and `/dev/dri`, `--userns keep-id`, **`$HOME` mounted at the same path** (so
`~/models/tf-port`, `~/tfp` and the venvs are the same paths inside and out), and **`--init`**. On node0,
`sf-up node0` also starts an sshd inside the container on `10.40.0.1:2222` with SFTP, so that StrixFold's
`ssh node0 ...` and `scp ... node0:` land in the container, where ROCm 10 is. On node1:

```sshconfig
Host node0
    HostName 10.40.0.1
    Port 2222
```

[`sf`](assets/strixfold/sf) runs a command inside (`sf` alone opens a shell).

Check: `sf /opt/rocm/core-10.0/bin/hipconfig --version` gives `7.15...`, `rocminfo` lists `gfx1151`, and Python is 3.13.

### What the container needed beyond StrixFold's docs

- **`systemd-run`**: `zig_build.sh` always re-runs itself under `systemd-run --user --scope`, and
  `prepare_inputs.sh` / `verify_inputs.sh` do unless `TFP_SCOPED=1`. There is no user manager in the container, so
  [`systemd-run-shim`](assets/strixfold/systemd-run-shim) is installed as `/usr/local/bin/systemd-run`: it runs the
  command in the foreground and keeps `AllowedCPUs=` as `taskset`. Only `--scope` is supported. `serve.conf`'s
  `SPAWN_UNIT=0` (the default) needs no systemd.
- **`bc`**: `run_gpu_tests.sh` uses it (exit 127 without it).
- **`--init`**: without an init, exited ranks stay as zombies (`<defunct>`) under the container's PID 1, and the next
  `first_light.sh up` refuses: `bosgame is not idle: engine process(es) 3416`.
- **`--ulimit host`**: a rootless container can't raise `nofile` past the host's hard limit (`error setting rlimit
  type 7`).
- **sshd's `Subsystem sftp`**: StrixFold copies to node0 with `scp`.

## The StrixFold steps, in the container

The scripts in [assets/strixfold/](assets/strixfold/) are StrixFold's GETTING-STARTED steps as run here, each inside
node1's container (`podman exec -d strixfold bash -lc "<script> > log 2>&1"`):

| Step | Script | Time | Result |
|---|---|---|---|
| Toolchain: Zig 0.17.0, the pinned input venv (torch 2.9.0+cpu), AMD's Triton 3.8.0 wheel, all hash-checked | `step4-toolchain.sh` (node0 needs the input venv too) | few min | ok |
| Triton kit | `step5a-trikit.sh` | ~1 min | 280 variants built, 0 failed |
| Build and GPU tests | `step5b-build.sh` | ~10 min | `install` ok (186 kernel objects); smoke and ABI pass; glue 10 of 11 |
| Inputs | `prepare_inputs.sh` (from the repo) | ~19 min | 198 GB bundle, `status: pass` |
| Copy node0's part, verify both, deploy | `step6-deploy.sh` | copy 3 min (~100 GB over USB4), verify ~15 min per box | both ranks `pass`; deploy `fc1399ca92eb` on both |
| Serve | `first_light.sh up` | weights ~40 s | probe: "The capital of France is Paris." |

Notes from the build:

- **`zig_build.sh test` reports "failed command" for four `hipcc` kernel compiles** whose only output is a warning
  (`argument unused during compilation: '--hip-link'`); Zig counts output on stderr as a failure. The `install` step
  produces everything (`zig-out/native-hip`, the kit and its manifest), and the GPU tests run.
- **The glue test's one failure is `clock`**: the GPU timer runs about 0.26% faster than the rate ROCm reports. StrixFold
  documents the same on the M5; it only affects timings.

## Serving

```sh
sf   # on node1, then:
cd ~/tfp/deploy/current/tools/dsv41-hip
TF_SERVE_CONF=$HOME/tfp/run/conf/my.conf ./first_light.sh up      # or: status, down
```

`my.conf` is the shipped `serve.conf` with `BUNDLE_SHA256` set to the bundle's hash and the second cable removed:
`TP_STRIPE=` (empty) and `COLL_PROXY_STRIPE_KIB=0`, the settings StrixFold used for its one-cable measurement. The
server listens on node0 at `127.0.0.1:18080` (OpenAI chat API, model `dsv41`).

## Speed

`first_light.sh`'s built-in bench, one run each, both boxes at their balanced power mode:

| | iGPU clock capped at 2000 MHz | Stock clock (2900 MHz) | StrixFold, 2 x Bosgame M5, one cable |
|---|---:|---:|---:|
| Code, 400 tokens | 59.8 tok/s | 66.4 tok/s | 76.4 tok/s |
| Prose, 400 tokens | 35.7 tok/s | 37.8 tok/s | 39.3 tok/s |
| Prompt, 1,818 tokens | 1,113 tok/s | 1,021 tok/s | 1,085 tok/s |

StrixFold's own benchmark (`qual/qual_bench.sh bench ... --reps 5 --prefill 2000,8000`, the two-DGX-Spark prompt set,
every prompt cold, stock clocks, one cable), median of 5 per category:

| coding | format | math | reasoning | json | prose | summary | narrative | **headline** (mean of the 8) |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 70.4 | 70.2 | 59.8 | 52.9 | 51.0 | 38.6 | 37.6 | 35.3 | **52.0 tok/s** |

StrixFold publishes **52.8 tok/s** for this headline on two Ryzen AI Halo boxes with two cables, so generation is on par.
Prompt reading at 2,952 tokens: 1,004 tok/s (theirs: 1,414 with two cables). Time to first token 0.45 s on average.
The 8,000-token prompt case sends ~11,600 tokens and needs `CONTEXT` above the shipped 8192; with 8192 it fails
("This server's maximum context..."), which is the one `fail` in the run's status.

The [2000 MHz clock cap](evo-x3-setup.md#gpu-clock-cap-less-heat) costs about 11% on code (drafting verifies several
tokens per step, so decode leans on compute) and 6% on prose.

Bosgame M5 power mode: its front button cycles the EC's power modes, and ours had been switched to quiet (about
54 W all-core instead of 85). See [bosgame-m5-ec-driver.md](bosgame-m5-ec-driver.md) to read and set it from Linux.

## Not done

- A two-cable test (the X3 has one USB4 port).
- TPM unlock: both boxes still ask for the LUKS passphrase at boot, so the pair is not yet hands-off after a power cut.
