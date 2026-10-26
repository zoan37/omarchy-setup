#!/usr/bin/env bash
# ProxyCommand that finds a home-LAN machine even if its DHCP address changes or mDNS (.local) is flaky.
# Copy to ~/.ssh/lan-connect.sh and fill in the case table with your machines (see ../../lan-ssh-self-healing.md).
# ssh config: ProxyCommand ~/.ssh/lan-connect.sh <name> %h %p
# Tries, in order: the last address that worked, the configured HostName, the machine's .local name,
# then its MAC addresses on the LAN (after a ping sweep). The address that works is cached per machine.
set -u
name=$1 host=${2:-} port=${3:-22}
subnet=192.168.0

# name -> mDNS name and MAC addresses (all interfaces that may be on the LAN)
case $name in
  k8)      mdns=k8.local;         macs='<k8-wifi-mac>|<k8-eth1-mac>|<k8-eth2-mac>' ;;
  spark)   mdns=spark-xxxx.local; macs='<spark-wifi-mac>' ;;
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
  is_ip "$addr" && is_open "$addr" && connect "$addr"
done

if [ -n "$mdns" ]; then
  addr=$(timeout 3 avahi-resolve -4 -n "$mdns" 2>/dev/null | awk '{print $2}')
  [ -n "$addr" ] && is_open "$addr" && connect "$addr"
fi

if [ -n "$macs" ]; then
  find_by_mac() { ip neigh | grep -iE "$macs" | awk '{print $1}' | grep "^$subnet\." | head -1; }
  addr=$(find_by_mac)
  # LAN_CONNECT_NO_SCAN=1 (e.g. a dashboard polling machines that may be off): skip the ping sweep
  if { [ -z "$addr" ] || ! is_open "$addr"; } && [ -z "${LAN_CONNECT_NO_SCAN:-}" ]; then
    echo "lan-connect: scanning $subnet.0/24 for $name..." >&2
    for i in $(seq 1 254); do ping -c1 -W1 "$subnet.$i" >/dev/null 2>&1 & done
    wait
    addr=$(find_by_mac)
  fi
  [ -n "$addr" ] && is_open "$addr" && connect "$addr"
fi

tried="the cached address, $host"
[ -n "$mdns" ] && [ "$mdns" != "$host" ] && tried+=", $mdns"
[ -n "$macs" ] && tried+=", a MAC scan of $subnet.0/24"
echo "lan-connect: $name not found (tried $tried); is it on?" >&2
exit 1
