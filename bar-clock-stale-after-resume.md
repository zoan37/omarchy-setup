# Bar clock shows the old time after opening the lid

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
  /etc/systemd/system-sleep/omarchy-clock-refresh
```

It lives in `/etc`, which Omarchy updates don't touch, and needs no reload:
`systemd-sleep` runs everything in that directory with `pre`/`post`.

Two things that are easy to get wrong in the hook:

- **Don't call the shell directly from the hook.** Since systemd 256,
  `systemd-sleep` keeps `user.slice` frozen while the `post` hooks run, so a
  plain `qs ipc call` waits on a quickshell that can't answer yet, and resume
  waits on the hook. The hook passes the call to
  `systemd-run --no-block` instead. That transient unit connects right away and
  gets its reply once the session unfreezes. `timeout 20` limits how long it
  can wait.
- **Target the shell by PID, not `-p <path>`.** `qs ipc -p ...` only matches
  instances on the caller's Wayland display, and a root sleep hook has none.
  The first version failed with `No running instances ... present on the
  current display "unk"`. `qs ipc --pid <pid>` doesn't check the display.

## Verify

A dry run as root (it doesn't need a real suspend):

```sh
pkexec /etc/systemd/system-sleep/omarchy-clock-refresh post suspend
journalctl -b --since -1min | grep omarchy-clock-refresh
# -> omarchy-clock-refresh-<pid>.service: Deactivated successfully.
```

After a real lid close and open, run the same `journalctl` grep. A unit that
succeeded means the hook ran, and the bar should show the current minute as
soon as the screen comes on.

**Status 2026-09-27:** the dry run passes on the XPS 13. A real
suspend/resume, with `user.slice` frozen, hasn't been observed yet.

## Revert

```sh
pkexec rm /etc/systemd/system-sleep/omarchy-clock-refresh
```

## Fix it upstream

The proper fix belongs in Quickshell: `SystemClock` should re-check the time
after resume, either by listening for logind's `PrepareForSleep(false)` or by
using a timer that follows wall-clock time (`timerfd` on `CLOCK_REALTIME` with
`TFD_TIMER_CANCEL_ON_SET`). Omarchy could also call `omarchy.clock refresh`
itself on wake. Once either change ships, delete the hook.
