# Bar weather icon missing after boot (Wi-Fi race)

**Symptom:** the weather icon is absent from the bar, right of the clock. The
rest of the bar is fine, and the config looks correct.

**Observed 2026-08-15 on the Beelink SER8** (Wi-Fi). The XPS 13 has not shown
it.

## It is not a config problem

Check both halves before touching anything:

```sh
omarchy weather status          # -> "Fort Wayne  ·  Temp 76°F  ·  Wind ←6mph"
python3 -c "import json;print([w['id'] for w in json.load(open('$HOME/.config/omarchy/shell.json'))['bar']['layout']['center']])"
```

If the CLI reports weather and `omarchy.weather` is in the layout, the widget
is simply hiding itself. It has no fallback and no error state:

```qml
// /usr/share/omarchy/shell/plugins/panels/weather/BarWidget.qml:49
visible: panelLoader.item && panelLoader.item.label !== ""
```

`label` is only ever set from a **successful** wttr.in fetch
(`Panel.qml:346,405`), so an empty label means every fetch so far has failed.

## Cause: the shell starts before the network associates

```sh
uptime -s
journalctl --user -b _COMM=quickshell | grep "Launching config"
journalctl -b | grep -E "NetworkManager.*(state change|connected)" | head
```

On the SER8: boot `14:03:25`, quickshell up at `14:03:53`, and `wlp2s0` was
still `disconnected` at `14:03:51`. The panel's initial fetch plus its few
2.5s retries all fired into a dead network, exhausted the retry budget, and
handed off to the 15-minute `refreshTimer` — so the icon stays gone for up to
a quarter hour after every slow-associating boot.

Note the CLI and the widget use **different endpoints**, so the CLI working
proves less than it looks: `omarchy-weather-status` fetches
`wttr.in/<place>?format=%t|%w`, while the panel fetches the much heavier
`?format=j1`. Test the one that matters:

```sh
curl -fsS --max-time 12 -w '\nHTTP:%{http_code} %{time_total}s\n' -o /dev/null "https://wttr.in/<place>?format=j1"
```

## Fix

```sh
omarchy restart shell
```

That is the whole fix once the network is up. It recurs on any boot where
Wi-Fi is slow to associate; it is upstream retry behaviour, not local
breakage.

Setting an explicit location with coordinates also removes the IP-detection
round-trip from startup and switches the current-conditions source to
open-meteo, which is faster than wttr's `j1`:

```sh
omarchy weather location --set "<city>" <lat>,<lon>
omarchy weather location --clear     # back to IP auto-detect
```

State lives in `~/.local/state/omarchy/settings/weather.json`; a missing file
means auto-detect. The panel watches that file, so writing it triggers a
refetch without restarting the shell.
