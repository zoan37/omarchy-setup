# Notes for coding agents

This repo is public. Everything committed here is published.

## Privacy: never identify the owner

Don't write anything that identifies the person or their machines into any file, commit message, script,
log excerpt or image. In particular:

- **No real names, login names or usernames**: not in prose, not in paths, not in command output. Copy
  terminal output in with the username already replaced.
- **No home paths with a username.** Use `~`, `$HOME`, `$USER`, or a placeholder variable as the
  whine-mic scripts do (`/home/$ZUSER`).
- **No email addresses.** Commits use the GitHub handle and its `users.noreply.github.com` address only.
- **No device identifiers**: serial numbers, MAC addresses, disk/LUKS/partition UUIDs, Wi-Fi network names,
  public IP addresses, or personal hostnames. Private LAN addresses (`192.168.x.x`) are fine.
- **Photos and screenshots**: blur serial and product labels (the SSD label in the teardown photos is
  blurred), strip EXIF/GPS metadata, and check for names in window titles, prompts and notifications.

Before committing, scan the staged changes. The pattern list is yours to fill in locally (the login name, real
name, email); never commit it:

```sh
git diff --cached -U0 | grep -n -i -E '<login>|<name>|<email>|/home/[a-z]'
```

If something identifying is already in history, say so and ask before rewriting history and force-pushing.
