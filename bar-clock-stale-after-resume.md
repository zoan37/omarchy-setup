# Bar clock shows the old time after opening the lid

> **Status 2026-09-28: fixed locally with a sleep hook** (verified on a real
> wake). The bug itself is still open upstream in both Quickshell and Omarchy;
> see [Upstream](#upstream).

**Symptom:** open the lid and the bar clock still shows the time from when the
lid closed. It catches up after a delay, often 10 to 20 seconds and sometimes
more. The delay changes from one wake to the next.

**Observed 2026-09-27 on the XPS 13** (Omarchy 4.0.4, quickshell 0.3.1,
systemd 261). The bug is in the shell, not the hardware, so every machine has
it.

## Cause: the clock's timer stops counting during sleep

The bar clock (`/usr/share/omarchy/shell/plugins/panels/clock/BarWidget.qml`)
is a Quickshell `SystemClock` with `precision: SystemClock.Minutes`.
`SystemClock` (`src/core/clock.cpp` upstream) works out how many milliseconds
remain until the next minute and starts a `QTimer` for that long. `QTimer`
runs on the monotonic clock, which stops while the machine is suspended.

So the timer doesn't count the time spent asleep. Close the lid at `10:00:20`
and the timer has 40 s left. Open it at `14:30:05` and it still has 40 s left,
so the bar shows `10:00` until `14:30:45`. The lag equals the number of
seconds left in the minute when the lid closed. That's why it changes every
time and can be anywhere from 0 to 60 s.

When the timer fires, `setTime()` checks the real wall-clock time, so the bar
jumps straight to the correct time. Omarchy doesn't correct for the delay
either: nothing in the shell reacts to resume, and `omarchy-system-wake` only
restores brightness and the monitor layout.

## Fix: refresh the clock from a systemd sleep hook

The widget has an IPC command that sets the display to `new Date()`:

```sh
qs -p /usr/share/omarchy/shell ipc call omarchy.clock refresh
```

[`assets/clock-refresh-on-resume/omarchy-clock-refresh`](assets/clock-refresh-on-resume/omarchy-clock-refresh)
runs that command on every resume. Install it:

```sh
pkexec install -Dm755 assets/clock-refresh-on-resume/omarchy-clock-refresh \
  /usr/lib/systemd/system-sleep/omarchy-clock-refresh
```

`systemd-sleep` runs every executable in that directory with `pre`/`post`,
and no reload is needed. **It must go in `/usr/lib`:** on systemd 261,
`systemd-sleep` doesn't read `/etc/systemd/system-sleep/` (see `man
systemd-sleep`; the binary only contains the `/usr/lib` path). The first
install went to `/etc` and never ran. No package owns this file, so pacman
won't remove it, but a `systemd` package update is still worth a check.

Three things that are easy to get wrong in the hook:

- **Don't call the shell directly from the hook.** Since systemd 256,
  `systemd-sleep` keeps `user.slice` frozen while the `post` hooks run, so a
  plain `qs ipc call` waits on a quickshell that can't answer yet, and resume
  waits on the hook. The hook passes the call to
  `systemd-run --no-block` instead. That transient unit connects right away and
  gets its reply once the session unfreezes. `timeout 20` limits how long it
  can wait.
- **Install into `/usr/lib/systemd/system-sleep/`, not `/etc`**, as above.
- **Target the shell by PID, not `-p <path>`.** `qs ipc -p ...` only matches
  instances on the caller's Wayland display, and a root sleep hook has none.
  The first version failed with `No running instances ... present on the
  current display "unk"`. `qs ipc --pid <pid>` doesn't check the display.

## Verify

A dry run as root (it doesn't need a real suspend):

```sh
pkexec /usr/lib/systemd/system-sleep/omarchy-clock-refresh post suspend
journalctl -b --since -1min | grep omarchy-clock-refresh
# -> omarchy-clock-refresh-<pid>.service: Deactivated successfully.
```

After a real lid close and open, run the same `journalctl` grep. A unit that
succeeded means the hook ran, and the bar should show the current minute as
soon as the screen comes on.

## How it was debugged (2026-09-27, XPS 13)

1. The dry run above passed.
2. The first real wake still lagged: the lid closed 22:43:41 and opened 22:46:14,
   the clock was 3 min behind, and it took ~15 s to catch up. The journal had no
   `omarchy-clock-refresh` unit at all. The hook was sitting in
   `/etc/systemd/system-sleep/`, which `systemd-sleep` ignores.
3. After moving it to `/usr/lib/systemd/system-sleep/`, and after a reboot, the
   next wake refreshed immediately:

   ```
   23:04:26.858 systemd-logind: Lid opened.
   23:04:26.953 systemd-sleep: System returned from sleep operation 'suspend'.
   23:04:27.008 systemd-sleep: Successfully thawed unit 'user.slice'.
   23:04:27.129 systemd[1]: omarchy-clock-refresh-1173.service: Deactivated successfully.
   ```

   The refresh landed ~270 ms after the lid opened.

`user.slice` is thawed about 55 ms after the return from sleep, so the
session may already be unfrozen when `post` hooks run. Keep the
`systemd-run` handoff anyway: it's harmless and it protects against resume
hanging.

If it stops working, run the `journalctl` grep from [Verify](#verify):

- **No `omarchy-clock-refresh` line:** the hook isn't running. Check
  that it's still in `/usr/lib/systemd/system-sleep/` and is executable.
- **The unit failed:** read its output (`journalctl -u 'omarchy-clock-refresh-*'`).
  The shell's process line may have changed, so the `pgrep` pattern no longer matches.

## Revert

```sh
pkexec rm /usr/lib/systemd/system-sleep/omarchy-clock-refresh
```

## Upstream

The real fix belongs in Quickshell: `SystemClock` should re-check the time
after resume. It could arm a `timerfd` on `CLOCK_REALTIME` with
`TFD_TIMER_ABSTIME | TFD_TIMER_CANCEL_ON_SET` for the minute boundary, use
`CLOCK_BOOTTIME`, or re-run `update()` on logind `PrepareForSleep(false)`.
Quickshell master's `clock.cpp` is unchanged since v0.3.1.

- **Quickshell:** [quickshell-mirror/quickshell#1212](https://github.com/quickshell-mirror/quickshell/issues/1212)
  was filed by another Omarchy user on 2026-09-27. I added the source-level
  diagnosis there. The earlier
  [#559](https://github.com/quickshell-mirror/quickshell/issues/559) was
  closed as unreproducible. The lag is 0 to 60 s and depends on where in the
  minute the machine slept, so it's easy to miss.
- **Omarchy:** `omarchy-system-sleep-monitor` already watches
  `PrepareForSleep`, but only acts on `true` (lock before sleep). Also calling
  `omarchy.clock refresh` on `false` would fix it for everyone until
  Quickshell does. Filed as [omacom/omarchy#13504](https://github.com/omacom/omarchy/issues/13504).

Delete the hook once either fix ships.
