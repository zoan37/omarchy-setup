# Ghostty: 10pt terminal with 12px global text size

**Goal:** terminals at 10pt, everything else (bar, GTK, Chrome) at 12px.

**Why it's not a knob:** `omarchy display text size <px>` drives the shell bar,
GTK `text-scaling-factor`, and the terminal font in lockstep with a hardcoded
ratio (`terminal_pt = round(px * 9/12)`), so 12px forces 9pt terminals. Raising
the global to 13px gives 10pt terminals but also enlarges Chrome/GTK — no good.
The ratio isn't configurable (constants live in the package-owned binary),
`~/.local/bin` is deliberately appended *after* `/usr/bin` so a wrapper can't
shadow the command, and there's no text-size hook to attach a fixup to.

**Fix: decouple with a ghostty include parsed after the stomped file.**

1. `~/.config/ghostty/local.conf`:
   ```
   font-size = 10
   ```
2. Last line of `~/.config/ghostty/config`:
   ```
   config-file = ?"~/.config/ghostty/local.conf"
   ```

Because the include is parsed last, it wins over line 7 of `config`, which
Omarchy rewrites to 9 on every slider touch — the stomp becomes harmless.

**Rules of the road:**

- Change terminal size only in `local.conf`, never in `config`.
- `omarchy display text size` will *misreport* "terminal font: 9 pt" (it greps
  line 7 of `config`). Cosmetic. Real value:
  `ghostty +show-config | grep font-size`.
