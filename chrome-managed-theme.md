# Chrome: unlock the theme managed by an administrator

**Symptom:** Chrome says the theme is managed by an administrator and won't
let you choose a theme yourself.

**Cause on this machine (2026-09-18):** Omarchy installed a local, mandatory
browser policy at `/etc/opt/chrome/policies/managed/color.json`:

```json
{"BrowserThemeColor": "#1a1b26", "BrowserColorScheme": "device"}
```

`BrowserThemeColor` locks theme selection for every Chrome profile on the
machine. This local policy is enough to trigger Chrome's management message;
it does not by itself mean a work or school administrator manages the account.
[Google's policy documentation](https://chromeenterprise.google/policies/browser-theme-color/)
confirms that leaving the policy unset lets users choose their theme.

## Fix: opt Chrome out of Omarchy's browser theme policy

First inspect the directory and policy:

```sh
ls -la /etc/opt/chrome/policies/managed
cat /etc/opt/chrome/policies/managed/color.json
```

On this machine, `color.json` was the **only file**, and it contained only the
two appearance settings above. The directory move below is for that case.
If other policies are present, preserve them and investigate separately before
moving the directory.

Move the directory to a backup name outside Chrome's active `managed` path:

```sh
sudo mv -T --no-clobber \
  /etc/opt/chrome/policies/managed \
  /etc/opt/chrome/policies/managed.omarchy-theme-backup-20260918
google-chrome-stable --refresh-platform-policy --no-startup-window
```

The backup name above is the actual backup made on 2026-09-18. The same fix was applied on the Zenbook A16 on 2026-09-26, where `color.json` was again the only file (backup `managed.omarchy-theme-backup-20260926`). For a later
repair, use a new, unused backup name; `--no-clobber` deliberately prevents
overwriting an earlier backup. When an agent runs the move without an
interactive terminal, use `pkexec` in place of `sudo` so authentication can
happen through the desktop prompt.

Now choose a theme in **Chrome → Settings → Appearance**, or use **Customize
Chrome** on a new tab. If the restriction remains, quit and reopen Chrome.

### Why move the directory, rather than just delete `color.json`?

The installed `/usr/bin/omarchy-theme-set` runs
`omarchy-theme-set-browser` after each desktop theme change. That calls
`/usr/bin/omarchy-theme-set-browser-policy`, which writes `color.json` into
each existing browser policy directory. It skips directories that do not
exist. Deleting just the file would allow the next theme change to recreate it;
moving the directory makes that script skip Chrome entirely.

This leaves Chromium, Edge, and Brave's policy directories alone and requires
no changes to packaged Omarchy scripts. Chrome's theme and light/dark choice
can then be controlled in Chrome instead of following Omarchy's forced policy.

## Verification and update caveat

```sh
test ! -e /etc/opt/chrome/policies/managed && echo 'Chrome policy directory absent'
cat /etc/opt/chrome/policies/managed.omarchy-theme-backup-20260918/color.json
```

In Chrome, open `chrome://policy`, click **Reload policies**, and check that
`BrowserThemeColor` and `BrowserColorScheme` are no longer set by this local
file. Then confirm theme selection is available.

During the repair, the directory move and Chrome's policy-refresh command
completed successfully. Browser automation could not open `chrome://policy`,
so the in-browser verification is a manual check. Survival across ordinary
theme changes is based on inspection of the installed script, not a live
theme-switch test.

This is not guaranteed to survive browser reinstallation or future Omarchy
migrations. The installed `omarchy-install-browser` explicitly creates
`/etc/opt/chrome/policies/managed` when setting up Chrome. If the restriction
returns, inspect the directory and the current theme-policy script before
reapplying the fix.

## Undo

If `managed` is still absent, restore the backup and refresh Chrome's policies:

```sh
sudo mv -T --no-clobber \
  /etc/opt/chrome/policies/managed.omarchy-theme-backup-20260918 \
  /etc/opt/chrome/policies/managed
google-chrome-stable --refresh-platform-policy --no-startup-window
```

If an update has recreated `managed`, inspect both directories before
restoring; do not overwrite newer policies blindly. Restoring the backup
restores the original forced color, and subsequent Omarchy theme changes can
update it again.
