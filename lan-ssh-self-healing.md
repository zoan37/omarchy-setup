# Home LAN: SSH that survives flaky mDNS and changed DHCP addresses

Set up **2026-10-25** on the XPS 13 (the laptop every other machine is reached from).
Script: [`assets/lan-ssh/lan-connect.sh`](assets/lan-ssh/lan-connect.sh).

## The problem

The SSH aliases used `.local` names (mDNS via Avahi) so a new DHCP lease wouldn't break them. Over Wi-Fi
that is unreliable:

- **mDNS timeouts.** Multicast is the weak spot of Wi-Fi (sent at the lowest rate, dropped by power save,
  worst on 2.4 GHz). On 2026-10-25 `k8.local` stopped resolving from the laptop
  (`avahi-resolve -4 -n k8.local` → `Timeout reached`) while the K8 itself was up and pingable, and its
  Avahi log showed no conflict. Restarting `avahi-daemon` on the K8 fixed it for a few minutes. Since the
  DGX Spark alias jumps through the K8 (`ProxyJump k8.local`), that took `ssh spark` down too.
- **Name conflicts after a reboot** rename a host to `<name>-2.local`
  ([SER8 recurrence](ser8-lan-ssh-hostname.md#recurrence-2026-10-22-ser8local-stopped-resolving-after-an-update-reboot)).
- **A hard-coded IP** fixes the lookup but breaks when DHCP hands out a different address.

## The method: a `ProxyCommand` that finds the machine

`lan-connect.sh <name> %h %p` runs before SSH connects and tries, in order:

1. **the last address that worked** for that machine (cached in `~/.ssh/lan-cache/<name>`);
2. **the configured `HostName`**, if it's a literal IP;
3. **the `.local` name**, via `avahi-resolve -4` with a 3 s timeout;
4. **the machine's MAC addresses**: look in the ARP table (`ip neigh`); if they're not there, ping-sweep the
   `/24` (~1–2 s, all 254 pings in parallel) and look again.

Each candidate must have the SSH port open (`nc -z -w 2`). The first one that does is cached and
connected with `exec nc <addr> <port>`. So the common case is as fast as a plain IP, and a moved machine is
found and remembered on the next connection.

**Host-key checking is unchanged.** `known_hosts` is still keyed on the alias's `HostName` (or
`HostKeyAlias`), so if the MAC scan ever found the wrong machine (MACs can be spoofed), SSH would refuse
the mismatched host key as usual.

## Setup

1. Collect each machine's MAC addresses, from every interface that may be on the LAN (Wi-Fi and
   Ethernet):

   ```sh
   # on the machine itself
   ip -o link | awk '/ether/ {print $2, $(NF-2)}'
   # or from the laptop, while the machine is on
   for i in $(seq 1 254); do ping -c1 -W1 192.168.0.$i >/dev/null 2>&1 & done; wait
   ip neigh | grep -v FAILED            # IP -> MAC
   avahi-resolve -4 -n <host>.local     # which IP is which machine
   ```

   A machine whose `.local` name doesn't resolve can be identified by its SSH host key:
   `ssh-keyscan -t ed25519 <ip>` against `ssh-keygen -F <host>.local`.

2. Copy the script to `~/.ssh/lan-connect.sh`, `chmod +x` it, and fill in the `case` table
   (`name) mdns=<host>.local; macs='<mac1>|<mac2>' ;;`). A machine with no MAC yet still gets the cache and
   mDNS steps.

3. Add one `ProxyCommand` line to each alias, keeping the existing `HostName`:

   ```sshconfig
   Host k8.local k8
       HostName 192.168.0.20
       ProxyCommand ~/.ssh/lan-connect.sh k8 %h %p
       HostKeyAlias k8.local
       User <user>

   Host ser8 beelink
       HostName ser8.local
       ProxyCommand ~/.ssh/lan-connect.sh ser8 %h %p
       User <user>
       AddressFamily inet

   # A machine reached through another one keeps its ProxyJump; the jump host's alias does the finding.
   Host spark
       HostName 10.77.0.1
       ProxyJump <user>@k8.local
       HostKeyAlias spark-xxxx.local
   ```

   Two aliases for the same machine (e.g. the Windows PC's OpenSSH on port 2222 and WSL on 22) share
   one `name`, so they share the cache; `%p` keeps the ports apart.

Requirements on the laptop: `nc` (OpenBSD netcat), `avahi-resolve` (avahi), `ping`, `ip` (all present on
Omarchy).

## Verification

All checked 2026-10-25 from the XPS 13:

```
k8          ok   (cached address, ~0.3 s)
spark       ok   (through the K8's alias)
spark-wifi  ok
ser8        ok
mbp         ok   (macOS)
skytech     ok   (Windows OpenSSH, port 2222)
skywsl      ok   (WSL, port 22, same cache)
```

- **Moved machine, simulated:** with the cache set to an unused address and `-o HostName=192.168.0.250`,
  `ssh k8 hostname` still answered `k8` in **~7 s** (two 2 s port checks, the mDNS timeout, then the ARP
  table had the K8's MAC) and re-cached the real address.
- **Stale `.local` cache:** for aliases with a `.local` `HostName` the cache always ends up holding an IP
  (the script resolves through Avahi rather than caching the name).
- **Machine off:** fails in ~3 s with
  `lan-connect: k6 not found (tried the cached address, nucbox.local); is it on?`.

## Caveats

- **macOS private Wi-Fi address.** Macs use a randomized ("private") MAC per network. It is usually
  stable on a given network, but macOS can rotate it; set the network's *Private Wi-Fi address* to
  **Fixed** in System Settings, or update the MAC in the table when it changes.
- **Same subnet only.** The MAC scan sweeps the laptop's own `/24`; it can't find a machine on another
  network (use the jump-host pattern above for those).
- **The ping sweep needs hosts that answer ping or ARP.** Every host answers ARP even with ICMP blocked,
  so it shows up in `ip neigh` anyway.

## Alternatives considered

| Option | Why not (yet) |
|---|---|
| DHCP reservation on the router | the right permanent fix; needs the router admin login. Complements this, doesn't replace it |
| Static IP on the machine | can collide with the router's DHCP pool unless the pool's range is known |
| Wired switch | mDNS is reliable on Ethernet; planned for the GPU hosts anyway |
| Tailscale / Headscale / NetBird | stable names everywhere, but another service on every machine (Tailscale's coordination server is third-party; Headscale self-hosts it) |
| Restarting Avahi | fixed `k8.local` for a few minutes only |

## Undo

Remove the `ProxyCommand` lines from `~/.ssh/config` (the aliases fall back to their `HostName`), then delete
`~/.ssh/lan-connect.sh` and `~/.ssh/lan-cache/`.
