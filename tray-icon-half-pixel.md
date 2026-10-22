# Tray app icons sit off-center after Omarchy 4.5

> **Status 2026-10-22: patched locally in a package-owned file**, so every
> `omarchy update` undoes it. Upstream bug: omacom/omarchy#16116 (open).
> Remove the local patch once a release rounds the position.

**Symptom:** after updating 4.0.4 → 4.5.0rc1, app icons in the bar tray
(Slack here) sit visibly higher than the Bluetooth, Wi-Fi, display, volume and
battery icons next to them. On a scale-1 screen the same bug shows as blurry
tray icons instead (that's how #16116 describes it).

**Observed on the XPS 13** (2560×1600 at scale 1.6, bar `base-size = 12`).
The bug is in the shell, not the hardware, so every machine on 4.5 has it.
How visible it is depends on the display scale.

## Cause: the icon is centered on a half pixel

Upstream commit `201de1c0` ("Normalize bar icon size and alignment", PR
#15065, 2026-10-11) changed `TrayItem` in
`/usr/share/omarchy/shell/plugins/bar/widgets/Tray.qml` from

```qml
TrayIcon {
  anchors.centerIn: parent
  width: Style.space(12)
  height: Style.space(12)
```

to a centering done by hand:

```qml
TrayIcon {
  x: (parent.width - width) / 2
  y: (parent.height - height) / 2
  width: Style.bar.iconSize
  height: Style.bar.iconSize
```

With the default tokens the slot is `icon-slot = 27` and the icon is
`icon-size = 12`, so the offset is `(27 - 12) / 2 = 7.5` logical px.
`anchors.centerIn` never produced a half pixel, because `anchors.alignWhenCentered`
(on by default) snaps a centered item to a whole pixel. At scale 1.6 the
half pixel is enough to put the icon a pixel high. The commit was meant to
align the bar icons, so the half pixel is a side effect and not intended.

Only tray app icons move. The status icons are glyphs drawn by
`BarIconButton` / `WidgetButton`, which have their own centering code.

Measured with `grim -s 1.6` on the top bar (42 physical px tall), top edge of
the drawn icon:

| | Slack | Status icons |
|---|---|---|
| 4.5.0rc1 stock | y 12 | y 13 |
| With the rounding patch | y 13 | y 13 |

Slack's center still reads half a pixel higher afterwards because its image is
16 px tall where the glyphs are 17 px. That is the icon itself, not its
position.

## Fix: round the position

```sh
F=/usr/share/omarchy/shell/plugins/bar/widgets/Tray.qml
pkexec sh -c "cp $F $F.orig && sed -i \
  -e 's|^      x: (parent.width - width) / 2$|      x: Math.round((parent.width - width) / 2)|' \
  -e 's|^      y: (parent.height - height) / 2$|      y: Math.round((parent.height - height) / 2)|' $F"
grep -n 'Math.round((parent' $F    # expect lines 881 and 882
omarchy restart shell
```

The sed patterns are anchored on the six-space indent of `TrayItem`'s
`TrayIcon` block, so they don't touch anything else in the file. If the grep
returns nothing after an update, either upstream changed the lines (check
whether #16116 was fixed) or the indent moved.

Why not a config override: the only knobs are global `[bar]` tokens in
`~/.config/omarchy/shell.toml`. `icon-size = 13` or `icon-slot = 28` would make
the difference even, but `icon-slot` resizes every bar button and `icon-size`
resizes every bar icon, which is a bigger change than the bug.

## Undo

```sh
F=/usr/share/omarchy/shell/plugins/bar/widgets/Tray.qml
pkexec mv $F.orig $F && omarchy restart shell
```

Or reinstall the package: `sudo pacman -S omarchy`. An update does the same
thing and leaves the `.orig` behind; delete it then.

## Upstream

- Issue: [omacom/omarchy#16116](https://github.com/omacom/omarchy/issues/16116),
  "Tray icons are blurry since 4.5.0rc1: centered on a half pixel". It has the
  same diagnosis and the same two-line fix. Open, with no replies, as of 2026-10-22.
- The issue notes that #15065 added the same hand-written centering in other
  widgets (`BarIconButton.qml` lines 39–40 and 52). Those can hit the same
  half pixel when the slot and the icon differ by an odd number of pixels.
  None of them were visibly off on this machine.
