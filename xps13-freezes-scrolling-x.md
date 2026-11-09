# XPS 13: screen and pointer freeze while scrolling x.com

**2026-11-08, XPS 13 (Wildcat Lake, 16 GB RAM), Omarchy 4.5.0, Hyprland 0.56.2, Chrome 157.**

**Symptom:** short freezes where the whole screen and the mouse pointer stop together, sometimes for over half a
second. They mostly happened while scrolling x.com past videos. Nothing showed up in `dmesg`, and there were no GPU
errors.

**Cause:** three problems on top of each other:

1. **Chrome was decoding every video on the CPU**, even though the VA-API driver was installed and
   `chrome-flags.conf` turned VA-API on. Someone had set *Hardware-accelerated video decode* to **Disabled** in
   `chrome://flags`, probably back during the [white-video](chrome-vulkan-white-video.md) debugging, and that
   setting wins over the flags file. x.com autoplays each video as it scrolls into view, so every one meant CPU
   decoding.
2. **Memory was full, and the desktop itself had been swapped out.** There were 21 Claude Code processes (~3.9 GB;
   16 were sessions restored at login 32 h earlier), Chrome (~4.3 GB) and grok-bot (~0.9 GB). About 5.9 GB sat in
   zram, with Omarchy's `vm.swappiness=150`. **Hyprland had more of itself in swap (72 MB) than in RAM (61 MB)**,
   and the Quickshell bar had 127 MB swapped with 53k major page faults. With the compositor's own pages in zram,
   the next frame or pointer move waits on swap-in, and that's when the screen and pointer freeze.
3. **Two dead SSH tunnels were spawning hundreds of processes every few seconds.** The
   [Strata tunnels](local-llm-open-webui.md) (`Restart=always`, `RestartSec=10`) had been failing since the 4090 PC
   and the K8 went off. Each failure ran [`lan-connect.sh`](lan-ssh-self-healing.md)'s MAC scan, which is 254
   parallel `ping`s. That added up to ~8,000 restarts and 4,000–10,000 sweeps a day for two weeks: constant bursts
   of new processes and ARP traffic on a machine that was already swapping.

Hyprland's own log showed the stalls. Libinput complains when the compositor gets to input late:

```sh
L=$(ls -t $XDG_RUNTIME_DIR/hypr/*/hyprland.log | head -1)
grep -c 'too slow' "$L"                                          # 32 since login
grep -o 'past (-[0-9]*ms)' "$L" | grep -o '[0-9]*' | sort -n | tail -3   # ... 317, 605
```

**Update, same evening: a fourth cause, the display.** With the three fixes below in place, the screen
froze again. The [stall logger](assets/xps13-freezes/freezewatch.sh) showed *no* system stall: the CPU,
Hyprland's input handling and memory/IO pressure were all normal. The machine was on the 2026-10-22 **PSR1-only**
boot setting, where the panel can hold its last frame while the GPU keeps producing new ones. Self-refresh is now
off entirely (`xe.enable_psr=0 xe.enable_panel_replay=0`), live via debugfs and as the boot default; details in
[xps13-panel-replay-scroll-judder.md](xps13-panel-replay-scroll-judder.md#psr1-froze-the-screen-2026-11-08-self-refresh-off).
Under test.

## Diagnosis (all read-only)

```sh
free -h; cat /proc/pressure/memory                    # "full" > 0 means tasks stalled on memory
for p in $(pgrep -x Hyprland) $(pgrep -x quickshell); do
  echo "$(cat /proc/$p/comm): $(grep -E 'VmRSS|VmSwap' /proc/$p/status | tr -s ' \n' ' ')"
done                                                  # VmSwap ≥ VmRSS for the compositor is bad
ps -eo rss,comm | awk '{a[$2]+=$1;n[$2]++} END{for(k in a) printf "%6d MB %3d %s\n",a[k]/1024,n[k],k}' | sort -rn | head

# Is Chrome actually using VA-API? The GPU process must have the iHD driver mapped.
G=$(pgrep -f '^/opt/google/chrome/chrome --type=gpu-process' | head -1)
grep -c iHD_drv_video /proc/$G/maps                   # 0 = software decode
ps -eo args | grep -- '--type=renderer' | grep -c -- '--disable-accelerated-video-decode'
python3 -I -c "import json,os;print(json.load(open(os.path.expanduser('~/.config/google-chrome/Local State')))['browser'].get('enabled_labs_experiments'))"
#   ['disable-accelerated-video-decode', 'enable-vulkan@1']   <- the culprit

# Restart loops
systemctl --user list-units --state=activating,failed
journalctl --user -u strata-tunnel --no-pager | grep -c 'Failed with'
```

**Trap:** `vainfo` working and the right `Vaapi*` features showing in the main process's command line both looked
like proof that decode worked. They weren't. A fresh Chrome profile with the same flags loaded iHD fine; only the
daily profile, because of its `chrome://flags` entry, didn't.

## Fix

1. **Close idle Claude Code sessions.** (Freed ~2.7 GB; RAM in use went 10 → 7.8 GB, available 4.5 → 7.4 GB, and
   pages stopped going out to swap.)
2. **Stop the tunnels while their machines are off:**
   ```sh
   systemctl --user disable --now strata-tunnel strata-tunnel-k8
   ```
   Turn them back on with `enable --now` when the 4090 PC / K8 are back.
3. **Set `chrome://flags` → *Hardware-accelerated video decode* back to Default.** To do it from a shell
   instead, quit Chrome first (it rewrites `Local State` on exit):
   ```sh
   cp ~/.config/google-chrome/'Local State' ~/'Local State.bak'
   pkill -TERM -o -x chrome; while pgrep -x chrome >/dev/null; do sleep 1; done
   python3 -I - <<'EOF'
   import json, os
   p = os.path.expanduser('~/.config/google-chrome/Local State')
   d = json.load(open(p))
   b = d.setdefault('browser', {})
   b['enabled_labs_experiments'] = [x for x in b.get('enabled_labs_experiments', [])
                                    if x != 'disable-accelerated-video-decode']
   json.dump(d, open(p, 'w'), separators=(',', ':'))
   EOF
   setsid -f uwsm app -- google-chrome-stable --restore-last-session
   ```
4. **GPU encode for video calls (optional):** add `AcceleratedVideoEncoder` to the `--enable-features=` line in
   `~/.config/chrome-flags.conf` (see [chrome-vulkan-white-video.md](chrome-vulkan-white-video.md)), then quit and
   relaunch fully.

## Verify

- `grep -c iHD_drv_video /proc/$G/maps` → non-zero (it was 5 after the fix).
- `chrome://gpu` → *Video Decode: Hardware accelerated*, *Video Encode: Hardware accelerated*.
- While an x.com or YouTube video plays, `chrome://media-internals` → `kVideoDecoderName` should be `VaapiVideoDecoder`
  or `VDAVideoDecoder`, not `FFmpegVideoDecoder` / `VpxVideoDecoder`.
- Renderers started in the first second after launch can still carry `--disable-accelerated-video-decode`. Reload a
  restored video tab once.
- Stall logger: [`assets/xps13-freezes/freezewatch.sh`](assets/xps13-freezes/freezewatch.sh) `<logfile>` runs for
  3 h and logs any 0.5 s sleep that overshoots by >150 ms, with memory/IO pressure, the Hyprland "too slow" count
  and the top CPU users. It caught nothing in the first period after the fix.

## Not done (options if it comes back)

- **Protect the compositor from reclaim**, e.g. a `MemoryLow=` drop-in on the Hyprland session unit, or lower
  `vm.swappiness` to 60–100.
- **Make the tunnels quiet instead of off:** `Environment=LAN_CONNECT_NO_SCAN=1` and `RestartSec=60` in both units, so
  a missing machine costs one port check per minute instead of a ping sweep every 10 s.
- **Hyprland debug logging** was on: its log in `$XDG_RUNTIME_DIR` (tmpfs, so RAM) was 47 MB after 32 h, mostly
  libinput gesture lines. That's minor.

## Revert

```sh
systemctl --user enable --now strata-tunnel strata-tunnel-k8
# Chrome: chrome://flags -> Hardware-accelerated video decode -> Disabled, or restore 'Local State.bak' with Chrome closed
# Remove AcceleratedVideoEncoder from ~/.config/chrome-flags.conf
```
