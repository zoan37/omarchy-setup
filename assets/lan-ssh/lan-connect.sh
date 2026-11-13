#!/usr/bin/env bash
# ProxyCommand that finds a home-LAN machine even if its DHCP address changes or mDNS (.local) is flaky.
# Copy to ~/.ssh/lan-connect.sh and fill in the case table with your machines (see ../../lan-ssh-self-healing.md).
# ssh config: ProxyCommand ~/.ssh/lan-connect.sh <name> %h %p
# Tries, in order: the last address that worked, the configured HostName, the machine's .local name,
# then its MAC addresses on every home subnet this laptop is on (after a ping sweep). The address that works is
# cached per machine. Two Wi-Fi routers at home (192.168.0.x and 192.168.1.x) are separate networks, so if the
# machine is on the other one, the X3 and Spark reach each other over their cable (10.77.0.x): hop through the partner.
set -u
name=$1 host=${2:-} port=${3:-22}
via= cable=
# Home subnets: every /24 this laptop has an IPv4 address on (Wi-Fi or Ethernet); 192.168.0 if none.
subnets=$( { ip -4 -o addr show scope global 2>/dev/null | awk '$2 !~ /^(docker|br-|veth|virbr|tailscale)/ {print $4}' \
             | cut -d/ -f1 | grep -E '^192\.168\.' | cut -d. -f1-3; } | awk '!seen[$0]++')
[ -n "$subnets" ] || subnets=192.168.0
on_subnet() { case " $subnets " in *" $(echo "$1" | cut -d. -f1-3) "*) return 0 ;; esac; return 1; }

# name -> mDNS name and MAC addresses (all interfaces that may be on the LAN)
case $name in
  k8)      mdns=k8.local;         macs='<k8-wifi-mac>|<k8-eth1-mac>|<k8-eth2-mac>' ;;
  spark)   mdns=spark-xxxx.local; macs='<spark-wifi-mac>'; via=x3; cable=10.77.0.1 ;;  # cable partner: X3
  x3)      mdns=x3.local;         macs='<x3-wifi-mac>';    via=spark; cable=10.77.0.2 ;;  # cable partner: Spark
  ser8)    mdns=ser8.local;       macs='<ser8-mac>' ;;
  mbp)     mdns=m5.local;         macs='<mac-wifi-mac>' ;;  # macOS private Wi-Fi address; may change
  skytech) mdns=;                 macs='<pc-mac>' ;;
  zenbook) mdns=zenbook.local;    macs='' ;;  # no MAC yet: cached address + mDNS only
  k6)      mdns=nucbox.local;     macs='' ;;  # no MAC yet: cached address + mDNS only
  *)       mdns=;                 macs='' ;;
esac

cache=~/.ssh/lan-cache/$name
mkdir -p ~/.ssh/lan-cache

is_open() { nc -4 -z -w 2 "$1" "$port" 2>/dev/null; }
connect() { echo "$1" > "$cache"; exec nc -4 "$1" "$port"; }

is_ip() { [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

# Only literal IPs here; .local names go through avahi below so the cache always holds an address.
for addr in "$(cat "$cache" 2>/dev/null)" "$host"; do
  is_ip "$addr" && on_subnet "$addr" && is_open "$addr" && connect "$addr"   # skip addresses on the other Wi-Fi
done

if [ -n "$mdns" ]; then
  addr=$(timeout 3 avahi-resolve -4 -n "$mdns" 2>/dev/null | awk '{print $2}')
  [ -n "$addr" ] && is_open "$addr" && connect "$addr"
fi

if [ -n "$macs" ]; then
  find_by_mac() { ip neigh | grep -iE "$macs" | awk '{print $1}' | grep -E "^($(echo $subnets | tr ' ' '|' | sed 's/\./\\./g'))\." | head -1; }
  addr=$(find_by_mac)
  # LAN_CONNECT_NO_SCAN=1 (e.g. a dashboard polling machines that may be off): skip the ping sweep
  if { [ -z "$addr" ] || ! is_open "$addr"; } && [ -z "${LAN_CONNECT_NO_SCAN:-}" ]; then
    for subnet in $subnets; do
      echo "lan-connect: scanning $subnet.0/24 for $name..." >&2
      for i in $(seq 1 254); do ping -c1 -W1 "$subnet.$i" >/dev/null 2>&1 & done
    done
    wait
    addr=$(find_by_mac)
  fi
  [ -n "$addr" ] && is_open "$addr" && connect "$addr"
fi

# Not on this laptop's network: hop through its cable partner (which may be on the other Wi-Fi or this one).
# LAN_CONNECT_NO_HOP stops the partner's own lookup from hopping back.
if [ -n "$via" ] && [ -z "${LAN_CONNECT_NO_HOP:-}" ]; then
  echo "lan-connect: $name not on this network; trying through $via's cable ($cable)..." >&2
  exec env LAN_CONNECT_NO_HOP=1 ssh -o BatchMode=yes -o ConnectTimeout=20 -W "$cable:$port" "$via"
fi

tried="the cached address, $host"
[ -n "$mdns" ] && [ "$mdns" != "$host" ] && tried+=", $mdns"
[ -n "$macs" ] && tried+=", a MAC scan of $(echo $subnets | sed 's/ /.0\/24, /g').0/24"
echo "lan-connect: $name not found (tried $tried); is it on?" >&2
exit 1
