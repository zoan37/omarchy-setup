# Ghostty: SIGSEGV in the `io` thread on herdr attach (unresolved)

**Symptom:** every Ghostty window vanishes at once, a few seconds after
`herdr` attaches (`herdr --remote mbp`, or a plain local attach). Whatever was
running in every other terminal dies with them. Omarchy then pops a "Process
crashed" notification and opens a new terminal to diagnose it.

**Observed 2026-08-14 → 2026-09-10 on the XPS 13 (DX13260).** Six crashes.
Still unresolved as of 2026-09-10 — this note exists so the investigation
doesn't get re-run from scratch.

## Recognising it

It is this bug if the faulting offset matches. Nothing else is needed to
identify it:

```sh
coredumpctl list /usr/bin/ghostty
coredumpctl info <pid> | grep -E 'TID:|Signal:|#0'
```

The signature, identical across all six:

```text
TID:    <n> (io)                     <- the io thread, never main
Signal: 11 (SEGV) si_code: SEGV_MAPERR
#0      ghostty + 0x151c90d
```

A null-pointer dereference: `r14 = 0x0`, faulting instruction
`mov 0x108(%r14),%rcx`, `si_addr = 0x108`. Structurally it's an intrusive
linked-list "pop head" — two code paths reach the same unlink block at
`+0x151c8ff`, and only one of them null-checks the node first. Ghostty is
built `ReleaseFast`, so Zig's safety checks are compiled out and the bad
unwrap segfaults instead of panicking.

Arch's package is stripped and Arch's debuginfod has no symbols for this
build, so the stack cannot be symbolized and gdb can't even walk it (frame 1
is `0x0`). **Don't burn time on gdb again** — the offset above is all a raw
core will give you.

## Trigger: herdr attaching

Every crash lands 1–3 s after a herdr client handshake. Cross-check the
coredump times against herdr's own log:

```sh
grep -E 'app.startup|handshake' ~/.config/herdr/herdr-client.log   # times are UTC
coredumpctl list /usr/bin/ghostty
```

| Ghostty crash (EDT) | herdr handshake | gap |
|---|---|---|
| 2026-08-14 10:55:32 | 10:55:29 (local attach, SemanticFrame) | 3 s |
| 2026-08-27 21:08:25 | 21:08:24 (mbp, TerminalAnsi) | 1 s |
| 2026-09-10 11:41:22 | 11:41:20 | 2 s |
| 2026-09-10 11:41:52 | 11:41:52 | <1 s |
| 2026-09-10 11:42:11 | 11:42:11 | <1 s |
| 2026-09-10 11:46:14 | 11:46:13 | <1 s |

**It is a race, not a certainty: 6 crashes in 50 attaches (~12%).** So "it
worked fine that time" proves nothing, and any test needs 25+ attaches to mean
anything (at 12%, a clean run of 15 is only ~85% confidence).

Not specific to `--remote` — the 2026-08-14 crash was a local attach on the
`SemanticFrame` encoding. It's the attach itself, which bulk-replays terminal
state into the pty in one burst.

The paired `herdr-stable` SIGABRT on 2026-08-27 is **collateral, not a cause**:
herdr aborted one second later while writing to stderr, because its tty had
just disappeared.

## Dead ends — don't re-chase these

- **`async-backend = epoll`.** Omarchy sets this at
  `/usr/share/omarchy/config/ghostty/config:41` (per ghostty discussion #3224),
  overriding ghostty's `auto`, and since the crash is on the `io` thread this
  looks extremely promising. It isn't: upstream #12459 reproduced the identical
  offset under `ghostty --config-file=/dev/null`, with Omarchy's config not
  loaded at all. Tried setting `io_uring` in `local.conf` on 2026-09-10 and
  reverted it — pointless.
- **Not an Omarchy bug at all.** The binary is stock Arch `extra`, which
  Omarchy neither builds nor patches. Even `--gtk-single-instance=true` (the
  reason one crash takes down *every* window) comes from ghostty's own
  `/usr/share/applications/com.mitchellh.ghostty.desktop`, not from Omarchy.
- **Not memory pressure.** No OOM kills, ~6 GiB available at crash time.
- **Not accumulated scrollback.** Three of the crashes were in Ghostty
  processes only seconds old.
- **Not a bad update.** The `archlinux-keyring` upgrade on 2026-09-10 landed at
  11:42:59, *after* the crashes began.

## Upstream status: reported to death, and stalled

Do **not** file anything. As of 2026-09-10 there are eight reports of this
exact offset, and every one was rejected by a Ghostty maintainer:

| Thread | Outcome |
|---|---|
| [#12459](https://github.com/ghostty-org/ghostty/issues/12459) | auto-closed; non-maintainers can't open issues |
| [#13807](https://github.com/ghostty-org/ghostty/discussions/13807) | "crash dumps are close to useless" → **locked** |
| [#13847](https://github.com/ghostty-org/ghostty/discussions/13847) | "Duplicate… do a better search" |
| [#13950](https://github.com/ghostty-org/ghostty/discussions/13950) | herdr trigger + rate table; "raw LLM output… slop noise" |
| [#13976](https://github.com/ghostty-org/ghostty/discussions/13976) | "Please do not interact in this discussion board again" |
| [#14091](https://github.com/ghostty-org/ghostty/discussions/14091) | near-identical Arch/Hyprland/herdr setup; rejected |
| [#14124](https://github.com/ghostty-org/ghostty/discussions/14124) | same disassembly annotated; "Do better" |
| [#14153](https://github.com/ghostty-org/ghostty/discussions/14153) | rejected, undisclosed AI use |

Everything above — the `+0x108` linked-list analysis, the epoll suspicion, the
herdr trigger, even a crash-rate table — is *already in those threads*. There
is no open tracking issue and no `crash`-labelled issue; mitchellh said in
#12459 he couldn't reproduce it. The bug is well-documented and completely
stuck.

Ghostty's [`AI_POLICY.md`](https://github.com/ghostty-org/ghostty/blob/main/AI_POLICY.md)
does allow AI-assisted reports, but requires disclosure, a real
human-in-the-loop, and hard trimming — and bad reports go on a **public
denouncement list** shared with other projects. A ninth redundant report is a
liability with no upside.

The only artifact anyone has actually asked for:

> "Please only report crashes on Linux that are reproducible in a debug
> environment. Packages are built without debug symbols and therefore crash
> dumps are close to useless." — pluiedev, #13807

## If it keeps happening

**Try a current Ghostty first.** The installed package reports `channel: tip`
but was built **2026-04-09** — five months stale — and a maintainer flagged
exactly that in #13807 ("this really seems like a packaging problem with the
Arch package"). There's a real chance it's already fixed upstream.

```sh
pacman -Qi ghostty | grep -E 'Version|Build Date'
ghostty +version
```

Then build current source (or `ghostty-git` from the AUR) and attach herdr
25+ times. If the crash is gone, it was the stale package — done, nothing to
report. If it still fires, build Debug or ReleaseSafe: the null unwrap becomes
a Zig panic with named frames, which is the one thing that would unstick eight
reports. Post that once, disclosed and trimmed, in Issue Triage.

Meanwhile, to stop one crash taking down every terminal, run the herdr window
as its own process:

```sh
ghostty --gtk-single-instance=false -e herdr --remote mbp
```

## Omarchy's only part in this

The crash notifier spawns a terminal to diagnose the crash — and that terminal
is Ghostty, which can crash, spawning another. On 2026-09-10 that produced
four crashes in five minutes; PID 2195250 *was* the diagnose session for crash
2512, dying mid-diagnosis. It self-limits (~12% per spawn) and settled on its
own, so it's worth knowing about but not worth filing.
