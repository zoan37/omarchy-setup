# MacBook Neo: joining WPA/WPA2 mixed-mode routers (TKIP group key)

**2026-11-06**, Omarchy 4.5 for Apple Silicon, `linux-aurora` kernel
`7.2.11-14-1-ARCH`, `iwd` 3.12, NetworkManager 1.58. Back to the
[Neo setup notes](macbook-neo-setup.md).

**Symptom:** the home Netgear's 2.4 GHz and 5 GHz networks both show up, the
password dialog appears, and the connection fails at once. The same laptop joins
them fine from macOS, and an iPhone hotspot works from Linux.

**Cause:** the router runs in WPA/WPA2 mixed mode, and the `mt7932-fullmac` driver
accepts only CCMP (AES). A two-part driver patch fixes it. Changing the router to
`WPA2-PSK [AES]` also works in principle, but it does nothing for the routers at
hotels, cafes and other people's homes.

**Status:** working. The patched driver joined both the 5 GHz and 2.4 GHz
networks, tested from a separate boot entry: internet and DNS fine, mDNS discovery
of other devices on the LAN fine, Bluetooth up, no driver errors. Installed into
the normal boot afterwards and confirmed with a reboot: both networks passed again.
Only one router has been tried.

## Diagnosis

The password is not the problem, and the failure never reaches the router:

```sh
journalctl -u NetworkManager -b | grep -E 'Network.Connect failed'
# Activation: (wifi) Network.Connect failed: GDBus.Error:net.connman.iwd.NotSupported
```

Compare what the radio supports with what the router advertises. `nmcli`'s
security flags are not real here, because the `iwd` backend fills them in, so use
`iw`:

```sh
iw phy phy0 info | sed -n '/Supported Ciphers/,/Available/p'
#   * CCMP-128 (00-0f-ac:4)

iwctl station wlan0 scan; sleep 5
iw dev wlan0 scan dump | grep -E '^BSS|SSID:|Group cipher|Pairwise'
#   Group cipher: TKIP
#   Pairwise ciphers: CCMP TKIP
```

So unicast traffic could use AES, but the router's broadcast (group) key is TKIP,
and `iwd` refuses a network whose group cipher the driver doesn't list. Nothing in
the logs says "TKIP", so it looks like a generic failure.

## Why macOS works and Linux doesn't

The limit is the Linux driver, not the chip. macOS uses Apple's driver. This one
is a young firmware-owned driver: the firmware runs the WPA2 handshake itself and
the host installs no keys. Two things blocked TKIP:

| Gate | File | Effect |
|---|---|---|
| `ciphers[]` lists only CCMP | `startup.c` | `iwd` and cfg80211 see no TKIP support |
| `cipher_group != CCMP` returns `-EOPNOTSUPP` | `association.h`, `mt7932_connect_auth()` | The driver refuses the request |

The firmware blob has a `wpa_supplicant`-style cipher name table including `TKIP`
and `CCMP+TKIP`, which was the hint that it could cope. That turned out to be
true: nothing else needed changing. The association path, the firmware request
and the receive filter all worked as they were.

The driver's refusal was deliberate, or at least conservative: `association-test.c`
has a "TKIP group" reject case, though that one goes through SAE, which the patch
still refuses.

## The patch

[`assets/macbook-neo/mt7932-tkip-group.patch`](assets/macbook-neo/mt7932-tkip-group.patch)
adds TKIP to the cipher list and allows a TKIP group key with CCMP pairwise for
WPA2-PSK only.

**Still refused, on purpose:** pairwise TKIP, WPA1, and a TKIP group with SAE or
OWE. A pure TKIP or WPA1-only router will not connect. Those are old and rare
enough, and a much bigger job, since the firmware request would have to change.

TKIP's known weaknesses apply to the broadcast key on these networks. That's the
router's choice, and macOS accepts the same thing. Your unicast traffic stays AES.

## Build

The kernel is built with clang, so the module needs `LLVM=1`. There are no
per-kernel tags on the repo. The driver source used here was commit
`747e84f29e1f` on `integration/aurora`, and the patch also applies to the tip of
that branch as of 2026-11-06.

```sh
sudo pacman -S --needed clang lld llvm linux-aurora-headers

git clone --depth 1 --filter=blob:none --sparse --branch integration/aurora \
  https://github.com/omacom/linux-aurora
cd linux-aurora
P=drivers/net/wireless/mediatek/mt7932
git sparse-checkout set $P
git apply /path/to/omarchy-setup/assets/macbook-neo/mt7932-tkip-group.patch

make -C /lib/modules/$(uname -r)/build M=$PWD/$P LLVM=1 CONFIG_MT7932_FULLMAC=m modules
```

The clone is about 20 MB. A warning that the compiler differs from the kernel's
(clang 23 against 18 here) was harmless in this test.

## Why it can't be swapped live

Two things that look like they should work and don't:

- **`rmmod` fails with "Module is in use".** The driver takes a reference on itself
  on purpose: with Bluetooth live on the same chip, a function reset can't happen,
  so unloading could hang the machine. Note that `rmmod mt7932_bt_pcie` succeeds
  first, which leaves Bluetooth off until the next boot.
- **Dropping the file in `updates/` isn't enough.** The driver loads from the
  initramfs, early in boot, via the `aurora-vendor-order` hook. It's inside the
  unified image on the ESP, so that image has to be rebuilt.

## Test first with a separate boot entry

There was no fallback on this machine: one menu entry, no snapshots. So the safe
first boot was a second image, leaving the normal one alone. `mkinitcpio -U` can
build one with the patched module, after which the module comes back out of
`updates/` so the normal rebuilds aren't affected:

```sh
KVER=$(uname -r); ESP=/boot/efi; UP=/lib/modules/$KVER/updates
CMD=$(sudo grep -m1 -E '^\s*cmdline:' $ESP/limine.conf | sed -E 's/^\s*cmdline:\s*//')
echo "$CMD" > /tmp/cmdline     # must contain rd.luks.name=

sudo mkdir -p $UP
sudo install -m644 $P/mt7932-fullmac.ko $UP/ && sudo depmod $KVER
sudo mkinitcpio -k $KVER --nopost --cmdline /tmp/cmdline \
  -U $ESP/EFI/Linux/omarchy_tkip-test.efi
sudo rm $UP/mt7932-fullmac.ko && sudo rmdir $UP && sudo depmod $KVER
```

Then append an entry to `/boot/efi/limine.conf`, keeping the two-space indent, so
it sits under the `/+Omarchy` group, and raise `timeout: 1` to `10` so there's time
to pick it:

```
  //TKIP Wi-Fi test
  protocol: efi
  path: boot():/EFI/Linux/omarchy_tkip-test.efi
  cmdline: <the same cmdline>
```

**Take the command line from `limine.conf`, not `/proc/cmdline`.** Here
`/proc/cmdline` didn't show `rd.luks.name=`, and an image built from it might not
unlock the disk. Also confirm the config isn't hash-enrolled before editing it: the
bootloader binary's `++CONFIG_B2SUM_SIGNATURE++` marker should be followed by 128
zeros. Enrolled configs refuse to boot after an edit. It was not enrolled here.

`default_entry` stays on the normal kernel, so a boot where you miss the menu is a
normal stock boot.

## Install permanently

```sh
sudo assets/macbook-neo/mt7932-tkip-install.sh /path/to/mt7932-fullmac.ko
# reboot, then:
assets/macbook-neo/mt7932-tkip-check.sh "Network 1" "Network 2"
```

The script copies the current image to a **Stock Wi-Fi driver (fallback)** menu
entry, installs the module in `/lib/modules/<kver>/updates/`, rebuilds with
`limine-mkinitcpio`, and verifies the image contents and hash. Any failed check
restores the previous image and menu. It sets the menu timeout to 3 seconds, as 1
is too short to reach the fallback.

This repo's script is a cleaned-up, general version of the one that ran on the
Neo. It passes `bash -n`, but this exact version hasn't been run.

`updates/` wins over the stock module in `depmod`, and custom menu entries survive
`limine-mkinitcpio`, so firmware and systemd updates that rebuild the image keep
the patch.

## After a kernel update

A new kernel has a new `/lib/modules/<kver>`, with no `updates/` in it, so **the
stock driver comes back.** Nothing fails, but mixed-mode routers stop connecting
while hotspots and AES-only networks keep working. Have a hotspot ready.

Redo the [build](#build) against the new kernel's headers, then run the install
script. If the patch no longer applies, the driver has changed: check whether
upstream has added TKIP, and read `mt7932_connect_auth()`.

The fallback entry only suits the kernel it was built with. The install script
refreshes it on each new kernel.

Tracked in the [post-update checklist](post-update-checklist.md).

## Verify

```sh
iw phy phy0 info | grep -A2 'Supported Ciphers'     # lists TKIP
modinfo -n mt7932_fullmac                           # .../updates/mt7932-fullmac.ko
iwctl station wlan0 show | grep -E 'network|Security'
avahi-browse -art -t | head                         # other LAN devices: broadcast works
journalctl -k -b | grep mt7932 | grep -iE 'fail|mismatch|recover'   # nothing
```

Broadcast is the part to check, since that's what the TKIP key carries. A ping to
the router proves only unicast. mDNS discovery or ARP from other machines on the
LAN proves the group key is really decrypting.

## If it goes wrong

- **Won't boot:** hold the power button, start again, press the down arrow at the
  boot menu, and pick **Stock Wi-Fi driver (fallback)**.
- **Boots but no Wi-Fi:** same fallback, or undo below.

## Undo

```sh
sudo rm /lib/modules/$(uname -r)/updates/mt7932-fullmac.ko
sudo rmdir /lib/modules/$(uname -r)/updates
sudo depmod $(uname -r)
sudo limine-mkinitcpio
# optional: remove the fallback entry from /boot/efi/limine.conf and
# sudo rm /boot/efi/EFI/Linux/omarchy_stock-fallback.efi
```

## Open

- **Upstream:** reported with the patch as
  [omacom/linux-aurora#398](https://github.com/omacom/linux-aurora/issues/398),
  PR open from the `zoan37/linux-aurora` fork with added test cases. Once it's in,
  none of this is needed.
- **A post-update warning** for when the stock driver comes back.
- **Other routers:** only one has been tried. Roaming between access points on a
  mixed-mode network is untested.
- **`wpa_supplicant`** as a way around it was not tried. It likely wouldn't help,
  since cfg80211 checks ciphers against the driver's list.
