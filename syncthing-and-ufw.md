# Syncthing on a fresh Omarchy machine — and the ufw wall nothing tells you about

**Observed 2026-09-17** pairing a new XPS 16 with the XPS 13. Cost an hour,
because every symptom pointed at the network and none of them were the network.

## The headline: Omarchy enables `ufw` and ships no helper for it

`ufw` is **active out of the box** (`systemctl is-active ufw` → `active`), the
default inbound policy drops everything, and there is no `omarchy firewall`
command — the subcommand doesn't exist. So on a fresh machine **nothing you
run is reachable from your own LAN**, including syncthing and sshd.

Nothing surfaces this. Syncthing's UI shows the device as simply not connected,
which reads as a discovery or pairing problem.

## The symptom that misleads you

Two Omarchy laptops on the same subnet, each scanning the other:

- Both machines **ping fine** (2.7 ms) — layer 3 is healthy.
- Every TCP port **times out** in both directions.
- So each one's port scan reports the other as a live host with no services,
  and both conclude "the other machine isn't running syncthing."

A scan run from the XPS 13 classified the XPS 16 as *"Apple/IoT device, no
SSH/Syncthing"* while that machine was listening on `*:22000`. ufw was eating
the SYN.

The mutual blindness is what makes this convincing: a firewall on *one* side
would look like an asymmetric problem, but symmetric silence looks like the
router.

**Diagnostic rule: ping works + every TCP port times out = a host firewall, not
the network.** Client isolation on an AP kills ICMP too, so a successful ping
rules it out in one step.

```sh
ping -c2 <other-machine>          # works
timeout 3 bash -c 'exec 3<>/dev/tcp/<other-machine>/22000'   # times out
systemctl is-active ufw           # -> active. There it is.
```

### It also silently breaks local discovery

Syncthing announces itself by **broadcast on UDP 21027**. ufw drops that
inbound, so neither machine ever hears the other and both fall back to global
discovery + the public relay pool — slower, and dependent on the internet for
two laptops sitting on the same desk.

Chasing this from the wrong end is a dead end worth not repeating: a listener
bound to UDP 21027 heard **zero announcements in 75 seconds** on a LAN with two
live syncthing instances. (Binding it at all means stopping the local
syncthing, which holds the port exclusively with no `SO_REUSEPORT`.)

## The fix, on every machine

Arch's ufw already ships the profile — `/etc/ufw/applications.d/ufw-syncthing`
covers `22000` (tcp+udp) and `21027/udp`:

```sh
sudo ufw allow syncthing
sudo ufw status verbose        # verify
```

For sshd (off by default on Omarchy: `inactive`, `disabled`), prefer scoping to
the LAN over a blanket allow, so port 22 isn't also open on coffee-shop Wi-Fi:

```sh
sudo systemctl enable --now sshd
sudo ufw allow from 192.168.0.0/24 to any port 22 proto tcp
```

`sudo ufw allow ssh` works too and is one token shorter; it is also open
everywhere you ever associate. `ufw limit ssh` rate-limits but still exposes
the port on every network.

Add `sudo ufw allow syncthing-gui` **only** if you want the web UI reachable
from another machine. It binds `127.0.0.1:8384` by default, which is the right
default — see the auth note below before changing it.

## Syncthing v2 changed two things that break old notes

Running v2.1.3 (`syncthing@archlinux`):

- **The config moved.** It's `~/.local/state/syncthing/`, not
  `~/.config/syncthing/`. Anything that greps the old path silently finds
  nothing.
- **There is no default `~/Sync` folder any more.** A fresh install has
  **zero** folders configured and `~/Sync` does not exist. The `<folder id="">`
  block in `config.xml` is the defaults *template*, not a real folder — don't
  read it as one.

Also: the GUI starts with **no username or password**. It's bound to localhost,
so it isn't network-exposed, but anything running locally can reconfigure your
sync. Set credentials under Actions → Settings → GUI.

## Pair the direction that matters: share *outward* from the machine with the data

A folder is identified by its **folder ID**, and both sides must agree on it.
If you add `~/Sync` as a new folder on the new machine, it gets a fresh random
ID that will never match the existing one, and the two sides sync nothing while
each looks perfectly healthy.

So: create the folder on the new machine as an **empty directory only**, don't
register it in syncthing, and share the existing folder *to* the new device
from the machine that already has the data. Accept the incoming share and pick
the path.

## Adding a peer without the web UI

The local REST API takes the device ID straight from the config, no sudo and no
browser:

```sh
KEY=$(python3 -c "import re;print(re.search(r'<apikey>(.*?)</apikey>',open('$HOME/.local/state/syncthing/config.xml').read()).group(1))")

# this machine's own ID
syncthing device-id

# add a peer
curl -s -X POST -H "X-API-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{"deviceID":"XXXXXXX-...","name":"xps13","addresses":["dynamic"],
       "compression":"metadata","introducer":false,"paused":false}' \
  http://127.0.0.1:8384/rest/config/devices

# list what is configured
curl -s -H "X-API-Key: $KEY" http://127.0.0.1:8384/rest/config/devices | jq -r '.[] | "\(.name) \(.deviceID)"'
```

`/rest/system/discovery` returns `{}` when nothing is paired yet — that is not
an error, and it is not evidence that discovery is broken.

Device IDs are deliberately **not** recorded in this repo. They aren't secrets
(they're key fingerprints, meant to be exchanged), but publishing them invites
connection attempts you'd then have to decline. Read them off each machine with
`syncthing device-id`.

## Name your devices

A fresh install names itself after the **hostname**, which on Omarchy is
`omarchy` for every machine. Two or three devices all called "omarchy" is
useless in the UI — rename each one (`xps13`, `xps16`, `ser8`) in Settings
right after pairing.

## The service does not start at boot — it starts at login

```sh
systemctl --user enable --now syncthing.service
```

`--user` ties it to your **user session**, so it starts when you log in, not
when the machine boots. On a laptop you log into anyway that's effectively the
same thing. If you want it running before/without login (headless, or syncing
while sitting at the greeter):

```sh
sudo loginctl enable-linger $USER      # check with: loginctl show-user $USER -p Linger
```

That also keeps it running after you log out, which may or may not be what you
want.
