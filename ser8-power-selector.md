# SER8: power-mode selector on the desktop bar

Installed **2026-09-20** on the Beelink SER8 (Ryzen 7 8745HS, kernel
`7.2.5-3-omarchy`). Click the icon at the far top right to choose **Power Saver**,
**Balanced**, or **Performance**. The icon follows the active mode; Power Saver
shows a leaf. Hovering names the current mode. The selected mode is highlighted
in the popup, and changes are saved for the next boot.

## Why the stock control was missing

The installed `omarchy.power` widget is also the battery widget. Its
`Panel.qml` gates visibility, size, refresh, and opening on `batteryPresent`.
It was already in the SER8's bar layout but hidden because this desktop has
no battery. The XPS 13 has a battery, so the stock selector is visible there.
All three power profiles are supported on the SER8 independently of that UI.

The fix is a local clone, **`zoan.power`**, replacing `omarchy.power` in the
right-hand bar layout. No package-owned files under `/usr/share/omarchy/`
were changed. This clone is for an AC-powered desktop; keep the stock battery
widget on laptops.

## Installed files and behavior

[assets/ser8-power-selector/](assets/ser8-power-selector/) contains exact copies
of the installed `Panel.qml`, `Model.js`, and `manifest.json`.

- Live plugin: `~/.config/omarchy/plugins/zoan.power/`.
- Bar placement: `{"id": "zoan.power"}` at the end of
  `bar.layout.right` in `~/.config/omarchy/shell.json`.
- The manifest retains `omarchy.clonedFrom: "omarchy.power"`, so the existing
  `omarchy.power` IPC target continues to work.
- Quickshell's `PowerProfiles` service updates the icon over D-Bus. There is
  no polling timer or repeated background shell command.
- Selecting a mode runs `omarchy-powerprofiles-set ac <profile>`, the same
  persistence helper used by the stock widget. The buttons are disabled while
  the command runs, and a failed command shows an error in the popup.
- Arrow keys move between modes, Enter selects, and Escape closes the popup.

## Persistence: use Omarchy's setter

The SER8 was back in Performance mode when inspected on September 20, despite
the earlier Power Saver setup. The installed Omarchy startup helper restores
its own saved AC profile, defaulting to Performance if no valid selection is
saved. The daemon's state file alone therefore does not establish what profile
Omarchy will use after login.

Use these commands for persistent changes:

```sh
omarchy powerprofiles set ac power-saver
omarchy powerprofiles set ac balanced
omarchy powerprofiles set ac performance
```

Each line selects a different mode; run only the one wanted. The current
choice is **Power Saver**, saved in
`~/.local/state/omarchy/powerprofiles/ac` (or under `$XDG_STATE_HOME` if set).
`omarchy powerprofiles init` restores this choice at startup.

On this machine, Power Saver sets all 16 CPU policies to energy preference
`power`, per-policy boost `0`, and maximum frequency `3801000` kHz. The global
boost file still says `1`; inspect the per-policy files. Balanced was verified
with `balance_performance` on all policies. See
[the fan notes](ser8-quiet-fan.md) for the separate automatic fan curve.
No new fan-curve, firmware, or wattage-limit changes were made for this widget.

## Restore on a fresh SER8 install

Run from this repository's root inside the desktop session. These steps use
Omarchy's clone command to generate the correct manifest for the current user;
the archived manifest records this machine's `zoan.power` identity.

```sh
cp ~/.config/omarchy/shell.json ~/.config/omarchy/shell.json.bak.power-selector-$(date +%s)
omarchy plugin clone omarchy.power
power_plugin_id="$(id -un).power"
power_plugin_dir="$HOME/.config/omarchy/plugins/$power_plugin_id"
install -m 0644 assets/ser8-power-selector/Panel.qml \
  assets/ser8-power-selector/Model.js "$power_plugin_dir/"
omarchy bar move "$power_plugin_id" --section right
omarchy powerprofiles set ac power-saver
omarchy restart shell
```

If the clone already exists, back up that directory and skip the clone command
before copying the two files. If it is disabled, re-enable it with
`omarchy plugin enable "$power_plugin_id" --section right`.

The first installation emitted hot-reload messages but still behaved like the
old battery-only widget. Restarting the shell loaded the new code and made the
selector visible. A plugin rescan alone did not resolve that instance.

## Verify and check after updates

```sh
powerprofilesctl get
cat "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/powerprofiles/ac"
omarchy-shell omarchy.power open
```

Expect `power-saver` from both reads unless another mode was deliberately
selected. Confirm the popup displays all three modes and highlights the active
one. After selecting a different mode, repeat both reads, then return to the
preferred mode. After the next real reboot, repeat the checks again.

During setup, the popup and leaf icon were visually checked, Power Saver was
confirmed active and saved, and the shell logs showed no errors from this
widget after restart. A full reboot and clicks through every mode were not
tested during installation. No controlled before/after power or noise
measurement was made for this change.

The clone lives in user config and should survive ordinary package updates,
but it does not automatically receive upstream widget changes. After shell
updates, check that the popup still opens and switches profiles. A shell config
reset can remove its bar entry; re-enable the local plugin if needed.

## Undo

```sh
omarchy plugin disable zoan.power
omarchy plugin enable omarchy.power --section right
omarchy restart shell
```

Substitute the current user's clone ID if different. This restores the stock
widget, which will again be hidden on the SER8. It leaves the active/saved power
profile alone; use the commands above if that should change too. The local
clone remains on disk for re-enabling later.
