# Bosgame M5: read the EC power mode (quiet / balanced / performance) from Linux

Installed **2026-11-15** on the Bosgame M5 (Sixunited board `AXB35-02`, ITE IT5570 EC,
AMI BIOS 3.11, Ryzen AI Max+ 395), Omarchy 4.5, kernel `7.2.15-1-omarchy`, Secure Boot off.

The front "performance" button (two crossing arrows) changes the EC's power mode. Bosgame only
ships a Windows tool for it. The community driver
[cmetz/ec-su_axb35-linux](https://github.com/cmetz/ec-su_axb35-linux) exposes the mode, the
three fans and the EC CPU temperature in sysfs. It is installed here through DKMS and loads at
boot. It was installed and checked read-only first. Later the same day the mode was switched from
quiet to **balanced** through sysfs (see [Switch modes](#switch-modes)). Since then the mode is pinned at boot, and a
fan-assist service writes the EC's fan-duty override (see [Fans](#fans-the-drivers-curve-does-nothing-on-bios-311-the-duty-override-works)).

## Result

```text
$ cat /sys/class/ec_su_axb35/apu/power_mode
quiet
fan1: rpm=1288 mode=auto level=0
fan2: rpm=1590 mode=auto level=0
fan3: rpm=570  mode=auto level=0
temp1: 38 C
```

The box is in **quiet** mode, which matches the symptom that led here: an all-core CPU load
plateaus at about 54 W / 2.7 GHz on the M5, against about 85 W / 3.7 GHz on the EVO X3 running
the same test. (A GPU-heavy load still reached about 88 W.)

## Board check first

The driver has **no DMI match** and loads on any machine. Check the board before loading it:

```sh
cat /sys/class/dmi/id/board_name    # must print AXB35-02
```

## Read the registers without the driver (optional pre-check)

The kernel's `ec_sys` module is read-only unless it is loaded with `write_support=1`. It shows
the raw EC RAM, which is useful before trusting the driver:

```sh
sudo modprobe ec_sys write_support=0
cat /sys/module/ec_sys/parameters/write_support     # N
sudo od -Ax -tx1 /sys/kernel/debug/ec/ec0/io        # 256 bytes
sudo modprobe -r ec_sys
```

The registers the driver uses, as read on this M5 at idle:

| Register | Meaning | Value read |
|---|---|---|
| `0x31` | power mode: `00` balanced, `01` performance, `02` quiet | `02` (quiet) |
| `0x21`/`0x23`/`0x25` | fan 1/2/3 mode (`x0` = EC auto, `x1` = manual) | `00 00 00` |
| `0x22`/`0x24`/`0x26` | fan 1/2/3 level when manual | `00 00 00` |
| `0x35:36`, `0x37:38`, `0x28:29` | fan 1, 2, 3 rpm (big-endian) | ~1800, ~2050, ~780 |
| `0x70` | CPU temperature, °C | `28` (40 °C, matches `Tctl`) |

StrixFold's [M5 cooling notes](https://github.com/Shoestring-dev/StrixFold/blob/main/docs/BOSGAME-M5.md#cooling)
use `0x33`/`0x34` for fan duty; both read `00` (firmware control) at idle here. PR #40 in the driver repo adds fan
duty control. That PR isn't used; `m5-fan-assist` writes these registers through `ec_sys` instead (see Fans below).

## Two write paths to know about, even for read-only use

Read from the driver source at commit `f62c2c2`:

1. **Loading** reads each fan's mode register. If it reads `0x11`/`0x21`/`0x31` (manual), the
   driver puts that fan in its own "curve" mode, and a 1-second worker starts **writing** fan
   levels. On this M5 those registers read `00`, so the worker never writes. If something else
   (the Windows tool, for example) leaves the fans in manual mode, loading the driver takes over
   fan control. The `ec_sys` dump above shows which case applies.
2. **Unloading** (`rmmod` / `modprobe -r`) writes `0x10`/`0x20`/`0x30` to the three fan-mode
   registers ("reset to AUTO"). On this M5 the idle value is `0x00`, not `0x10`, so an unload
   changes the registers. **Don't unload it** unless that write is OK. Shutdown does not unload
   modules, so a reboot is fine.

Reading the sysfs files only calls `ec_read`.

## Install (DKMS)

```sh
sudo pacman -S --needed dkms linux-omarchy-headers
git clone https://github.com/cmetz/ec-su_axb35-linux ~/src/ec-su_axb35-linux
cd ~/src/ec-su_axb35-linux          # commit f62c2c2 was used

V=1.0.f62c2c2; D=/usr/src/ec_su_axb35-$V
sudo install -d $D/src
sudo install -m644 Kbuild Makefile LICENSE README.md $D/
sudo install -m644 src/ec_su_axb35.c $D/src/
sudo install -m644 /path/to/omarchy-setup/assets/bosgame-m5-ec/dkms.conf $D/dkms.conf
sudo dkms add ec_su_axb35/$V
sudo dkms install ec_su_axb35/$V

# autoload at boot
sudo install -m644 /path/to/omarchy-setup/assets/bosgame-m5-ec/ec_su_axb35.conf /etc/modules-load.d/

sudo modprobe ec_su_axb35
```

Installed files are mirrored in [assets/bosgame-m5-ec/](assets/bosgame-m5-ec/).
The upstream repo has no `dkms.conf` of its own; its Ubuntu script writes one with MOK signing.
On Arch, `dkms` creates a self-signed key in `/var/lib/dkms/` on first use and signs the module
with it. With Secure Boot off that signature is not checked. The dmesg line
`module verification failed ... tainting kernel` is expected for any out-of-tree module.

### DKMS or a custom rebuild hook

DKMS was chosen. Arch's `dkms` package ships pacman hooks (`70-dkms-install.hook`) that rebuild
every registered module when a kernel's `build/` tree or `modules.order` changes. That happens
whenever `linux-omarchy` and `linux-omarchy-headers` update together. `dkms status` shows the
state, and the module is removed when an old kernel is removed. The costs: the headers package
must stay installed, every kernel update compiles the module (seconds), and a build failure on a
future kernel shows only in the pacman output. After the reboot `/sys/class/ec_su_axb35` is
missing. That failure is harmless, because the EC keeps running the fans and power mode itself.
A hand-written pacman hook calling `make` would do the same job with fewer packages, but it would
reimplement DKMS's per-kernel bookkeeping and cleanup.

## Read

```sh
B=/sys/class/ec_su_axb35
cat $B/apu/power_mode                                      # quiet | balanced | performance
for i in 1 2 3; do echo "fan$i $(cat $B/fan$i/rpm) rpm, $(cat $B/fan$i/mode)"; done
cat $B/temp1/temp $B/temp1/min $B/temp1/max                # °C; min/max since load
su_axb35_monitor                                           # repo's live monitor script (scripts/)
```

## Switch modes

The mode file is writable by root:

```sh
echo performance | sudo tee /sys/class/ec_su_axb35/apu/power_mode
echo balanced    | sudo tee /sys/class/ec_su_axb35/apu/power_mode
echo quiet       | sudo tee /sys/class/ec_su_axb35/apu/power_mode
```

Each line selects a different mode; run only the one you want. The write sets EC register
`0x31`. The front button probably changes the same register: it read quiet after the button
was pressed. Not yet checked: how the button cycles through the modes, how it interacts with a
sysfs write, and whether a written mode survives a power cycle. Re-read `power_mode` after a reboot and after a button
press, and re-run the all-core CPU load test to see the new plateau.

**2026-11-15: switched quiet → balanced** with the `tee` line above. The same all-core CPU load
now holds **84–85 W at ~3.6 GHz**, up from ~54 W / 2.7 GHz in quiet, and level with the EVO X3.
Performance mode has not been tried.

## Power mode at boot

The front button cycles the EC's power mode, so pin a known mode at every start:
[`m5-power-mode.service`](assets/bosgame-m5-ec/m5-power-mode.service) writes `balanced` (change `MODE=`) once the
driver's sysfs appears.

| Mode | Limit | Measured on this box (all-core CPU load) |
|---|---|---|
| quiet | ~54 W | 54 W, 2.7 GHz |
| **balanced** | ~85 W | **84-85 W, 3.6 GHz** (same as the EVO X3) |
| performance | ~120 W | not used: StrixFold measured it 9% slower and at 95-100 C with the stock fans |

## Fans: the driver's curve does nothing on BIOS 3.11; the duty override works

On this box (AXB35-02, AMI BIOS 3.11) the EC **ignores** the driver's `fanX/mode`, `level` and curve settings, as
StrixFold reports (docs/BOSGAME-M5.md, Cooling): `fixed` at level 2 and then 4 left fan 1 at 0 rpm. Factory `auto`
only reaches full speed at 95-97 C, which is where the Reddit reports of overnight overheat shutdowns come from.

What the EC does obey is its **duty override**, register `0x33` (fan 1) and `0x34` (fan 2): `0x80 + percent` sets
the fan, `0x00` hands it back to the firmware (registers found by
[nathanmarlor/strix-halo-fan-control](https://github.com/nathanmarlor/strix-halo-fan-control)). Writing `0xa8`
(40%) took fan 1 from 0 to 2,200 rpm within 9 s; `0x00` released it.

[`m5-fan-assist`](assets/bosgame-m5-ec/m5-fan-assist) +
[`m5-fan-assist.service`](assets/bosgame-m5-ec/m5-fan-assist.service) use it for an **"X3-like" quiet profile**: below
55 C the firmware keeps control (silent at idle); from 55 C the script owns both fans with a slower curve than the
factory one, letting the APU run warm the way the EVO X3 does (~80 C under load, inside its ~95-100 C limit):

| APU temp | Fans 1+2 |
|---|---|
| < 55 C | firmware |
| 55 C | 30% |
| 70 C | 40% |
| 78 C | 55% |
| 84 C | 75% |
| 88 C, or unreadable | 100% |

Stepping up is immediate; stepping down needs 5 C of hysteresis and 60 s at the current level. The temperature is the
hottest of the EC reading, CPU Tctl and the **APU's own** GPU (an eGPU on the box is ignored: it has its own cooling).
Stopping the service hands both fans back to the firmware. Needs `ec_sys` with `write_support=1`
(`/etc/modprobe.d/ec_sys-write.conf` + `/etc/modules-load.d/ec_sys.conf`); it refuses to run on anything but AXB35-02.

History: a first version helped from 65 C (50/70/85/100% at 65/72/80/86 C, no hold); under steady DeepSeek serving the
box sat at 64-72 C and the fans flipped 50% <-> 70% every 15-30 s, louder than the firmware alone. Paired with the
iGPU clock cap lowered 2000 -> 1800 MHz (`x3-gpu-clock-cap.service`), the quiet profile ran the same load at 74 C with
the fans at 40% (~2,600 rpm, down from ~3,000-3,700). The owner's verdict: lower, still audible. Next steps if needed:
a sustained power limit with RyzenAdj (the Strix Halo wiki's AXB35 power guide: quiet/balanced/performance = 54/85/120 W
sustained; an EC mode change resets custom limits), PTM7950 instead of the stock paste, or the 3D-printable 80 mm
"silent case".

```sh
sudo install -m 755 assets/bosgame-m5-ec/m5-fan-assist /usr/local/sbin/m5-fan-assist
sudo install -m 644 assets/bosgame-m5-ec/m5-fan-assist.service assets/bosgame-m5-ec/m5-power-mode.service /etc/systemd/system/
printf 'options ec_sys write_support=1\n' | sudo tee /etc/modprobe.d/ec_sys-write.conf
printf 'ec_sys\n' | sudo tee /etc/modules-load.d/ec_sys.conf
sudo systemctl daemon-reload && sudo systemctl enable --now m5-power-mode m5-fan-assist
journalctl -u m5-fan-assist -f      # "temp 74C: level 0 -> 2 (40%)" ...
```

The first version stepped at 65/72 C with no minimum hold; under steady DeepSeek serving the box sat at 64-72 C and
the fans flipped 50% <-> 70% every 15-30 s, which was louder than the firmware alone. Hence 75 C and the hold.

Measured with the first version (DeepSeek on the X3 + Bosgame pair, two rounds of 8 filings, 2000 MHz GPU cap, balanced): the hottest
reading reached 65 C, fans 50% (~3,000 rpm); a 73 C peak gave 70% (~3,700 rpm); the GPU peaked at 65 C; afterwards
the fans went back to the firmware. Speed unchanged.

## After a kernel update

```sh
uname -r
dkms status                     # ec_su_axb35/1.0.f62c2c2, <new kernel>, x86_64: installed
modinfo -n ec_su_axb35          # .../updates/dkms/ec_su_axb35.ko.zst
cat /sys/class/ec_su_axb35/apu/power_mode
```

If the build failed: `sudo dkms install ec_su_axb35/1.0.f62c2c2` shows the compiler error. Make
sure `linux-omarchy-headers` matches the running kernel.

## Revert

```sh
sudo rm /etc/modules-load.d/ec_su_axb35.conf
sudo dkms remove ec_su_axb35/1.0.f62c2c2 --all
sudo rm -r /usr/src/ec_su_axb35-1.0.f62c2c2
```

The module stays loaded until reboot. Read the unload warning above before running
`modprobe -r ec_su_axb35`.
