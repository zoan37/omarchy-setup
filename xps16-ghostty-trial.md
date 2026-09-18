# XPS 16: trying Ghostty as the default terminal

**2026-09-18:** switched the Dell XPS 16 from Kitty to Ghostty for a daily-use
trial. Ghostty is the current default; this is not a confirmed fix for the
reported missing or out-of-order characters.

One earlier keyboard comparison captured the same missing `n` in the raw
kernel key-down events and in Kitty's received text. That sample places the
missing event before the terminal application; it does not distinguish a
missed physical press from a keyboard/firmware/driver problem. No reordered
events were captured in that trial.

## Installed and configured

- `ghostty`, `ghostty-shell-integration`, and `ghostty-terminfo`: `1.3.1-2`.
- Default selected with `omarchy default terminal ghostty`.
- `~/.config/xdg-terminals.list` selects `com.mitchellh.ghostty.desktop`.
- JetBrainsMono Nerd Font at **11pt**, using the trailing `local.conf` include
  described in [terminal-font-size.md](terminal-font-size.md).
- Existing Omarchy theme integration and other Ghostty settings retained.
- Kitty remains installed; existing terminal sessions were left running.

Backups made before changing the default/config:

```text
~/.config/xdg-terminals.list.bak.20260918-153745
~/.config/ghostty/config.bak.20260918-153745
```

Ghostty opened successfully. Herdr trackpad scrolling initially appeared not
to work, but the user then confirmed it worked; no scroll settings were changed.
Monitor scaling remains **1.6** at native **3200×2000@120Hz**.

## Verify or repeat the setup

If Ghostty is absent, install it with `omarchy pkg add ghostty`. Then:

```sh
omarchy default terminal ghostty
omarchy default terminal                 # ghostty
xdg-terminal-exec --print-id              # com.mitchellh.ghostty.desktop
ghostty +validate-config                  # succeeds with no errors
ghostty +show-config | rg '^font-size'    # font-size = 11
```

These checks passed on September 18. Open a new terminal with the usual
terminal shortcut to use Ghostty. A future `omarchy refresh terminal` can
remove the trailing font override include; see the
[post-update checklist](post-update-checklist.md).

## Switch back

```sh
omarchy default terminal kitty
```

This changes future default-terminal launches; it does not close Ghostty or
its running sessions.
