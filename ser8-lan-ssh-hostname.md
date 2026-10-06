# SER8: SSH with the XPS 13 broke (two Wi-Fi cards, two "omarchy" hosts)

Fixed **2026-10-06** on the Beelink SER8, kernel `7.2.5-3-omarchy`.
SSH from the XPS 13 to the SER8 hung or failed intermittently, and
`ssh xps13` from the SER8 failed with "REMOTE HOST IDENTIFICATION HAS
CHANGED". There were two separate causes, and both had to be fixed.

## Cause 1: two Wi-Fi interfaces on the same LAN (ARP flux)

The SER8 had **both** the built-in Intel card (`wlp2s0`, `192.168.0.24`)
and the TP-Link RTL8821AU USB adapter (`wlp101s0f3u2`, `192.168.0.25`)
associated to the same router. Linux answers ARP for any local address on
any interface by default (`arp_ignore=0`), so the XPS cached **both** IPs
against the TP-Link's MAC:

```
# on the XPS
$ ip neigh | grep -E '192.168.0.2[45] '
192.168.0.25 dev wlp0s20f3 lladdr <tp-link-mac> REACHABLE
192.168.0.24 dev wlp0s20f3 lladdr <tp-link-mac> REACHABLE   # wrong card
```

Inbound traffic from the XPS therefore arrived on the TP-Link. Replies went
out through the Intel card, because the connected `192.168.0.0/24` route on
`wlp2s0` (metric 600) beats the TP-Link's (601):

```
$ ip route get 192.168.0.29 from 192.168.0.24
192.168.0.29 from 192.168.0.24 dev wlp2s0
```

With that asymmetric path, pings from the XPS to `.25` lost 100%, and TCP
22 to `.24` timed out. Internet access looked fine the whole time: the
default route uses the TP-Link (601 vs 20600), so internet traffic goes in
and out the same card. The Zenbook notes' earlier workaround
(`ssh -b 192.168.0.24 …`) was dealing with the same thing.

**Fix: use only one card on the LAN.** The TP-Link was kept: on
the router's 5 GHz SSID it links at 292.5 Mbit/s (VHT-MCS 7, 80 MHz), while both
cards on 2.4 GHz channel 1 had been getting 11–52 Mbit/s. The Intel
profiles were set not to autoconnect:

```sh
# every saved Wi-Fi profile bound to the Intel card (connection.interface-name wlp2s0)
nmcli con modify "<home-2.4GHz>" connection.autoconnect no
nmcli con modify "<home-5GHz>"   connection.autoconnect no
nmcli device disconnect wlp2s0
```

The TP-Link has its own duplicate profiles (NetworkManager appends ` 1`
to the names); check with `nmcli -f NAME,DEVICE,AUTOCONNECT con show`. A
phone-hotspot profile on `wlp2s0` was left alone. The SER8's LAN address is now
**`192.168.0.25`**, so anything that allowlists `192.168.0.24` needs
updating (see the [Zenbook notes](zenbook-a16-omarchy-snapdragon.md#2-remote-access-ssh-from-the-ser8)).

Keeping both cards up would need `arp_ignore=1`, `arp_announce=2` and
per-interface policy routing. That isn't worth it on a desktop.

## Cause 2: every Omarchy install is hostname `omarchy`

Both the SER8 and the XPS 13 were named `omarchy`. Avahi resolves the mDNS
name clash by renaming whichever host comes up second to `omarchy-2.local`.
After the SER8 rebooted, it took `omarchy-2.local`, the name the XPS
usually had:

- `ssh xps13` on the SER8 (`HostName omarchy-2.local`) resolved to
  `172.17.0.1`, the SER8's **own** `docker0` address, which Avahi was
  advertising. SSH reached the SER8 itself, hence the host-key warning
  (the fingerprint shown was the SER8's own host key).
- On the XPS, `omarchy.local` pointed back at itself, and
  `omarchy-2.local` tried the SER8's IPv6 address first. ufw here only
  allows port 22 from the XPS's IPv4 address, so that hung.

**Fix: rename the SER8 and stop advertising Docker's bridge.**

```sh
sudo hostnamectl set-hostname ser8
# /etc/avahi/avahi-daemon.conf, under [server]:
#   deny-interfaces=docker0
sudo systemctl restart avahi-daemon
```

The SER8 is now `ser8.local` (`avahi-daemon: running [ser8.local]`), and
the XPS keeps `omarchy.local` no matter which machine boots first.
`/etc/hosts` has no hostname entry (`myhostname` in nsswitch covers it),
so nothing else needed changing.

SSH aliases:

```sshconfig
# SER8 ~/.ssh/config
Host xps13 xps
    HostName omarchy.local      # was omarchy-2.local
    AddressFamily inet
    ...

# XPS 13 ~/.ssh/config
Host ser8 beelink
    HostName ser8.local
    User <user>
    AddressFamily inet          # ufw on the SER8 only allows the XPS's IPv4
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

On the SER8, the existing `omarchy-2.local` lines in `~/.ssh/known_hosts`
held the XPS's keys, so they were renamed to `omarchy.local` (backup at
`~/.ssh/known_hosts.bak-2026-10-06`). On the XPS, the SER8's key was pinned
under `ser8.local` and checked against
`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on the SER8;
the fingerprints matched.

## Verification

```sh
# SER8
hostnamectl --static                 # ser8
avahi-resolve -4 -n ser8.local       # 192.168.0.25
avahi-resolve -4 -n omarchy.local    # 192.168.0.29 (XPS)
ip -br addr | grep wl                # only wlp101s0f3u2 has an address
ssh xps13 hostname                   # omarchy

# XPS
ip neigh | grep 192.168.0.2          # .24 and .25 no longer share a MAC
ssh ser8 hostname                    # ser8, ~0.5 s
```

All of these were checked after the fix. A reboot of either machine was not
tested in this session. The XPS's hostname (`omarchy`) is now the only one
of its name on the LAN, so its mDNS name should stay stable.

## Undo

```sh
sudo hostnamectl set-hostname omarchy
sudo sed -i '/^deny-interfaces=docker0$/d' /etc/avahi/avahi-daemon.conf
sudo systemctl restart avahi-daemon
nmcli con modify "<home-2.4GHz>" connection.autoconnect yes
nmcli con up "<home-2.4GHz>"          # brings ARP flux back while the TP-Link is also up
```
