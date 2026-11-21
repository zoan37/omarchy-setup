# Tower: MT7921U Wi-Fi drops every ~30 h (mt76 USB TX skb leak)

The [tower](tower-setup.md)'s USB Wi-Fi (MediaTek MT7921U, `0e8d:7961`, `mt7921u`) dropped off the network
every 30-31 hours on kernel `7.2.15-1-omarchy`. After each drop NetworkManager couldn't talk to
wpa_supplicant, and a software USB replug hung forever. It's a known mt76 bug: fixed upstream in **7.4-rc1 /
7.3.4**, never in 7.2.y (7.2 is EOL). Diagnosed 2026-11-21. Wired networking (X710, USB Ethernet) is not
affected.

## Symptom

- AP deauth with **reason 16 (GROUP_KEY_HANDSHAKE_TIMEOUT)**, about 4 s after a scheduled group rekey (the AP rekeys
  every ~61.5 min). Seen Nov 19 21:27 and Nov 21 05:12, each ~31 h after wpa_supplicant last started.
  (A reason-1 deauth on Nov 19 04:57 was an ordinary AP roam that self-healed in a minute. Unrelated.)
- wpa_supplicant logs **nothing** after the deauth, no `CTRL-EVENT-DISCONNECTED`. NM's D-Bus calls into it fail
  with `Timeout was reached` (`call-disconnect`, `Couldn't initialize supplicant interface`).
  `systemctl restart wpa_supplicant` prints `eloop: could not process SIGINT or SIGTERM in two seconds` before it exits.
- Data traffic is fine right up to the deauth: gateway pings pass every minute, and there are no MCU timeouts or USB errors.
  It looks like a hung chip, but the chip is fine.
- `echo 0 > /sys/bus/usb/devices/2-2/authorized` while in this state never returns, and the kernel logs
  `unregister_netdevice: waiting for wlp244s0f4u2i3 to become free. Usage count = 2` every 10 s. Writer stack:
  `msleep <- netdev_run_todo <- ieee80211_unregister_hw <- mt792xu_disconnect <- usb_unbind_interface <- ... authorized_store`.
  Only a reboot clears it, unless you use the live recovery below.

## Root cause

1. mt7921 does 802.3 TX encap offload. wpa_supplicant's **WNM BSS keep-alive** is a zero-length frame
   (`l2_packet_send(..., 0x0800, "", 0)`) sent once per BSS Max Idle Period (this AP: 480 × 1000 TU ≈ 491.5 s).
   It reaches the driver as a 14-byte Ethernet frame.
2. `mt7921_usb_sdio_tx_prepare_skb()` rejects `len <= ETH_HLEN` with `-EINVAL`. `mt76u_tx_queue_skb()` returns that
   error **without freeing the skb**, and the callers in `tx.c` drop it. The skb is lost while still charged to
   wpa_supplicant's AF_PACKET socket (960 bytes truesize each).
3. After 222 keep-alives (≈ 30.3 h) the socket's send buffer (212992, `net.core.wmem_default`) is full.
   wpa_supplicant blocks forever in `sendto()`: stack `sock_alloc_send_pskb <- packet_sendmsg <- __sys_sendto`,
   and `ss -f link -a -p -m` shows `t213120,tb212992` on its 0x888e socket.
4. With wpa_supplicant's main loop stuck, the next GTK rekey goes unanswered and the AP deauths with reason 16.
5. `packet_snd()` holds a **netdev reference** while it waits for buffer space. Unbinding the USB device therefore waits
   for that reference ("Usage count = 2"), which waits for buffer space, which only frees after the unbind. That's a
   circular wait, not a refcount leak. Restart wpa_supplicant *before* any USB unbind and the unbind works.

Upstream:

- **`82856da2d3b6`** "wifi: mt76: fix memory leak in USB TX path" (mainline v7.4-rc1). 7.3.y backport
  **`ad626a35bd78`**, first in **v7.3.4**. Also in 6.18.y (`001c88ed4a17`) and 6.12.y (`5bbfc1573665`).
- Prerequisite **`f5dd4833463e`** "wifi: mt76: mt792x: fix UAF in SDIO TX path when out of memory". 7.3.y
  **`ec6d03d8b21c`**. It switches `mt76_skb_adjust_pad()` to `__skb_pad()`; without it the leak fix opens a double free.
- Report: [morrownr/mt76#83](https://github.com/morrownr/mt76/issues/83).
- Firmware is not involved: 20260224 is still the newest MT7961 build. Not fixes: `disable_usb_sg=1` (withdrawn
  upstream), the wpa_supplicant `control_port=0` driver param.

## Live recovery without a reboot

Use this once wpa_supplicant is wedged, including when a USB deauthorize is already hung. It was done on the tower
2026-11-21 10:49 while a 4-GPU training job kept running.

```sh
# 0. Confirm: wpa_supplicant blocked in sendto, its socket full
sudo cat /proc/$(pgrep -xo wpa_supplicant)/stack          # sock_alloc_send_pskb / packet_sendmsg
sudo ss -f link -a -p -e -m | grep -A1 wpa_supplicant     # t>=tb on the [34958] (0x888e) socket
# 1. If a USB deauthorize is hung, kill its writer first. The kill is queued (task is in D) and takes effect when
#    the write returns, so the script doesn't run whatever comes next
ps -eo pid,stat,cmd | awk '$2 ~ /D/'                     # the shell stuck in authorized_store
sudo kill -KILL <that pid>
# 2. Kill wpa_supplicant: the wait is interruptible, the netdev ref drops, and the unbind finishes
sudo kill -KILL $(pgrep -xo wpa_supplicant)
journalctl -k -f                                          # "waiting for ... to become free" stops
# 3. Re-probe the adapter (USB reset + firmware load); wpa_supplicant comes back via D-Bus activation, NM reconnects
echo 1 | sudo tee /sys/bus/usb/devices/2-2/authorized
```

If nothing is hung yet (Wi-Fi just dropped with reason 16), `sudo systemctl restart wpa_supplicant` is enough.
**Never** deauthorize/unbind the USB device while wpa_supplicant is wedged.

## Kernel fix for 7.2.15 (out-of-tree mt76)

Scripts in [assets/tower/wifi/kernel-fix/](assets/tower/wifi/kernel-fix/): the two upstream 7.3.y patches
(they `git apply` cleanly on v7.2.15, offsets only), a build script, and install/rollback scripts.

```sh
cd assets/tower/wifi/kernel-fix
./build-patched-mt76.sh      # sparse clone of v7.2.15 mt76, apply 0001+0002, build 7 modules at nice 19 -j4
./install-patched-mt76.sh    # copy to /lib/modules/7.2.15-1-omarchy/updates/mt76-usb-txleak-fix + depmod
```

- Needs `linux-omarchy-headers` and gcc (the kernel is built with GCC 16 / BFD ld).
- Builds `mt76 mt76-usb mt76-connac-lib mt792x-lib mt792x-usb mt7921-common mt7921u`; only `mt76.ko` and `mt76-usb.ko`
  differ from a stock build.
- The modules are unsigned. `MODULE_SIG_FORCE` is off, so they load and taint the kernel.
- Nothing is loaded or unloaded. Stock modules in `kernel/` are untouched, and `updates/` wins at the next boot.

Installed on the tower 2026-11-21 11:01. It takes effect at the next reboot, which needs the LUKS passphrase at the console.

Verify after the reboot:

```sh
modinfo -F filename mt76 mt76-usb      # .../updates/mt76-usb-txleak-fix/...
cat /proc/sys/kernel/tainted           # non-zero (out-of-tree, unsigned): expected
sudo ss -f link -a -p -e -m | grep -A1 wpa_supplicant   # t stays ~0 over a day instead of +960 per keep-alive
```

Rollback (then reboot): `./rollback-patched-mt76.sh` removes the `updates/` dir and runs `depmod`.

## Userspace guard (installed 2026-11-21, until the patched driver is running)

The patched modules only take effect at a reboot, and the reboot date isn't known. Until then a timer restarts
wpa_supplicant before the leak can wedge it. A fresh wpa_supplicant gets a fresh socket, so the count starts over.
Files are in [assets/tower/wifi/guard/](assets/tower/wifi/guard/):

- `eapol-wmem.sh` prints `<wmem> <sndbuf> <pct>` for wpa_supplicant's l2 socket (the `[34958]`/0x888e line of
  `ss -f link -a -p -e -m`). It reads `960 212992 0` after one keep-alive on stock modules, and should stay near 0 once fixed.
- `wpa-eapol-guard.sh` + `.service` + `.timer` run 5 min after boot, then every 5 min.
  - At **≥ 70 %** of sndbuf (149 KB, ~156 keep-alives, **~21 h** after wpa_supplicant starts) it logs to tag
    `wpa-eapol-guard`, runs `systemctl restart wpa_supplicant` (SIGKILL fallback), then `nmcli con up`.
  - The hard wedge is at 100 % (222 keep-alives, ~30 h), so that leaves ~9 h of margin.
  - Expect one short Wi-Fi blip (**~10 s**, estimated, not yet measured) roughly once a day. Wired is unaffected.
  - It never touches USB or modules.
- `wpa-wedged.sh` exits 0 if wpa_supplicant is blocked in `sock_alloc_send_pskb` or its socket is ≥ 95 % full.
  The watchdog calls it.
- `install-userspace-guard.sh` installs these plus the watchdog and stats below. It keeps `.bak-<timestamp>` copies
  and installs by rename, and it needs `/etc/default/tower-wifi` (`CON="<connection name>"`).
- `remove-userspace-guard.sh` disables and removes the timer, service and `wpa-eapol-guard.sh`.

Check it:

```sh
systemctl is-active wpa-eapol-guard.timer          # active
sudo /usr/local/bin/eapol-wmem.sh                   # e.g. "3840 212992 1"
journalctl -t wpa-eapol-guard                       # one restart line pair per ~21 h on stock modules
journalctl -t wifi-stats -o cat | tail -1           # ends with eapol_wmem=...
```

## When to remove it

**Guard:** once the patched mt76 is running (`modinfo -F filename mt76` → `updates/mt76-usb-txleak-fix/`) or the
kernel is **≥ 7.3.4**:

1. Confirm the fix: `sudo /usr/local/bin/eapol-wmem.sh` stays near 0 for a day (unpatched it gains 960 B per keep-alive, every ~8 min).
2. `assets/tower/wifi/guard/remove-userspace-guard.sh` (disable --now the timer, delete the two units and
   `/usr/local/bin/wpa-eapol-guard.sh`, daemon-reload). Nothing is restarted.
3. Optional: leave `eapol-wmem.sh`, `wpa-wedged.sh` and the watchdog/stats as they are. With the fix the un-wedge check
   never fires. Or restore the pre-guard `/usr/local/bin/wifi-{watchdog,stats}.sh.bak-<timestamp>` by `mv`.

**Patched modules:** once the tower runs **kernel ≥ 7.3.4** (or 7.4), the fix is in-tree. The out-of-tree modules
are built for 7.2.15 only and won't be used by a new kernel, since their `updates/` dir lives under
`/lib/modules/7.2.15-1-omarchy`. Run `rollback-patched-mt76.sh` before or after the upgrade to clean up.

**Debug logging and watchdog:** drop the debug logging below once the fix is confirmed, and the watchdog once Wi-Fi
has stayed stable for a week.

## Watchdog and debug logging (installed on the tower)

[assets/tower/wifi/watchdog/](assets/tower/wifi/watchdog/):

- `wifi-watchdog.sh` + `.service` + `.timer` (every 60 s). It **never touches USB.**
  - First, if `wpa-wedged.sh` says wpa_supplicant is stuck, it SIGKILLs and restarts wpa_supplicant. SIGKILL ends
    the blocked `sendto()`, which releases the netdev ref.
  - Then it pings the gateway twice, 20 s apart. If the link is down: snapshot, `nmcli con up`, then wpa_supplicant
    restart + rescan + `con up`.
  - The connection name comes from `/etc/default/tower-wifi` (template `tower-wifi.default`). The tower's own copy
    has it inline.
  - Installed 2026-11-21 11:29, replacing an earlier version that only did `systemctl restart wpa_supplicant` after `nmcli` failed.
- `wifi-snapshot.sh`: on a detected drop, writes `/var/log/wifi-drops/<timestamp>.txt` (`iw link`/`station dump`,
  `ip`, mt76 debugfs, last 10 min of kernel, NM and wpa logs). Keeps 30.
- `wifi-stats.sh` + `.service` + `.timer` (every 30 s): one journal line (tag `wifi-stats`) with link, signal,
  retries, beacon loss, bitrates and `eapol_wmem=<wmem> <sndbuf> <pct>`.
- `50-mt7921u-no-autosuspend.rules`: USB autosuspend off for the adapter.

[assets/tower/wifi/debug-logging/](assets/tower/wifi/debug-logging/):

- `wpa_supplicant-debug.conf` → `/etc/systemd/system/wpa_supplicant.service.d/debug.conf`: `-dd -t`. It shows
  `WNM: BSS Max Idle Period` and `WNM: Send keep-alive`. That's about 230k journal lines a day (measured); journald is capped at 2G.
- `90-wifi-debug.conf` → `/etc/NetworkManager/conf.d/`: WIFI/SUPPLICANT/DEVICE at DEBUG.
- `mt76-debug.conf` → `/etc/modprobe.d/`: `dyndbg=+pt` for the mt76 modules (applies at module load).
- `20-wifi-powersave-off.conf` → `/etc/NetworkManager/conf.d/`: power save off (it didn't matter for this bug).

## Notes

- `hung_task` never reports the stuck unbind: `netdev_run_todo` sleeps in 250 ms `msleep`s, so the task keeps switching.
- Never rewrite a script in place while bash might be running it. Bash reads scripts incrementally, and a stuck
  watchdog was found reading an edited, deleted inode. Install by `install`/`mv` to a new inode.
- Raising `net.core.wmem_default` would only postpone the wedge and changes every socket on the box. Don't.
