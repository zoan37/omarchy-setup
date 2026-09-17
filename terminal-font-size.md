# 11pt terminal with 12px global text size (ghostty and kitty)

**Goal:** terminals at 11pt, everything else (bar, GTK, Chrome) at 12px.

**Why it's not a knob:** `omarchy display text size <px>` drives the shell bar,
GTK `text-scaling-factor`, and the terminal font in lockstep with a hardcoded
ratio (`terminal_pt = round(px * 9/12)`), so 12px forces 9pt terminals. Raising
the global to 15px gives 11pt terminals but also enlarges Chrome/GTK — no good.
The ratio isn't configurable (constants live in the package-owned binary),
`~/.local/bin` is deliberately appended *after* `/usr/bin` so a wrapper can't
shadow the command, and there's no text-size hook to attach a fixup to.

**Fix: decouple with an include parsed after the stomped file.** Same idea in
both terminals, but kitty needs one extra step — see its section.

## Ghostty

1. `~/.config/ghostty/local.conf`:
   ```
   font-size = 11
   ```
2. Last line of `~/.config/ghostty/config`:
   ```
   config-file = ?"~/.config/ghostty/local.conf"
   ```

Because the include is parsed last, it wins over line 7 of `config`, which
Omarchy rewrites to 9 on every slider touch — the stomp becomes harmless.

## Kitty

Same shape, **plus you must seed an active `font_size` line first.** Omarchy's
kitty branch has two paths, and only one of them is harmless:

```bash
# omarchy-display-text-size
if grep -qE '^[[:space:]]*font_size[[:space:]]+' ~/.config/kitty/kitty.conf; then
  sed -i -E "s/^[[:space:]]*font_size[[:space:]]+.*/font_size $pt.0/" ...   # in place: fine
else
  printf '\nfont_size %s.0\n' "$pt" >>~/.config/kitty/kitty.conf            # APPENDS AT EOF
fi
```

Omarchy's shipped `kitty.conf` has `font_size` **commented out**, so a fresh
install takes the `else` branch and appends at EOF — *after* your include,
where last-wins means the stomp beats you. The trick silently dies on the first
slider touch, and nothing about the config looks wrong.

So:

1. `~/.config/kitty/local.conf`:
   ```
   font_size 11.0
   ```
2. An **active** `font_size 9.0` line in `~/.config/kitty/kitty.conf` (value
   irrelevant — it exists only to force the `sed`-in-place branch).
3. The **last** line of `~/.config/kitty/kitty.conf`:
   ```
   include local.conf
   ```

Kitty resolves a relative `include` against the including file's directory, and
takes the last value for `font_size`, so the include wins.

The pre-existing theme include at the top of `kitty.conf`
(`~/.local/state/omarchy/current/theme/kitty.conf`) is colors only — no font
lines — so it doesn't interact with any of this. `/etc/xdg/kitty/kitty.conf`
(package-owned) sets `font_size 9.0`, which the user file already overrides.

## Rules of the road

- Change terminal size only in `local.conf`, never in `config` / `kitty.conf`.
- `omarchy display text size` will *misreport* "terminal font: 9 pt" — it greps
  the stomped file. Cosmetic. Real value:
  - ghostty: `ghostty +show-config | grep font-size`
  - kitty: trust `local.conf`, or open the live config with `ctrl+shift+f2`
- Live-reload signals differ and Omarchy sends the right one for each:
  ghostty `SIGUSR2`, kitty `SIGUSR1`. Both reload in place.
- `omarchy refresh terminal` regenerates the stomped file **without** the
  include line. That's the one operation that actually breaks this — re-append
  it. See [post-update-checklist.md](post-update-checklist.md) §4.
