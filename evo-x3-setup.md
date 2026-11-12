# GMKtec EVO X3: new-machine setup

Set up **2026-11-12** on a fresh Omarchy 4.5.0 install, kernel `7.2.15-1-omarchy`,
BIOS `EVO-X3_V1.01` (2026-06-17). AMD Ryzen AI Max+ 395 (Strix Halo) with the
Radeon 8060S iGPU, 128 GB unified memory (BIOS default split: 64 GB VRAM carve-out,
~62 GB visible to Linux), Realtek RTL8125 2.5GbE (`eno1`), MediaTek MT7925 Wi-Fi 7
(`wlp99s0`). Dell 3440x1440 ultrawide over HDMI at scale 1 (stock `auto`). USB
keyboard and mouse, **no touchpad, no battery**. Hostname `x3`.

It shipped with Windows 11. Before wiping it, Windows was used once to run Intel's
Arc Pro driver installer with the B70 attached, which updates that card's firmware
(see the B70 idle-power notes in [k8-plus-egpu.md](k8-plus-egpu.md)). Omarchy then
replaced Windows entirely (no dual boot).

The [new machine checklist](new-machine-checklist.md) was followed with the
[K8 Plus](k8-plus-setup.md) as the model (same monitor, same kind of input, no
touchpad). Hardware-specific fixes for the other machines were skipped.

## Applied

User config (each changed file has a `.bak.<timestamp>` next to it):

| What | Where | Doc |
|---|---|---|
| Left Super/Alt swap: `omarchy:shift_caps_compose,altwin:swap_lalt_lwin` | `~/.config/hypr/input.lua` | [hyprland-shell-tweaks.md](hyprland-shell-tweaks.md) |
| Resize on border trio | `~/.config/hypr/looknfeel.lua` | same |
| Group tab reorder and SUPER+SHIFT+S screenshot, both with `o.rebind` | `~/.config/hypr/bindings.lua` | same |
| `hyprpm reload -n` at startup (hypr-tab-drag) | `~/.config/hypr/autostart.lua` | [hyprpm-notes.md](hyprpm-notes.md) |
| Clock format `ddd d MMM h:mm AP` | `~/.config/omarchy/shell.json` | same |
| Ghostty as default terminal, 11pt, Ctrl+Enter as CSI-u | `~/.config/xdg-terminals.list`, `~/.config/ghostty/local.conf` + trailing include | [terminal-font-size.md](terminal-font-size.md), [ghostty-ctrl-enter.md](ghostty-ctrl-enter.md) |
| Vulkan + VA-API Chrome flags, merged into the stock `--enable-features=` line | `~/.config/chrome-flags.conf` | [chrome-vulkan-white-video.md](chrome-vulkan-white-video.md) |
| `cleanupPeriodDays: 99999` | `~/.claude/settings.json` | [claude-code-notes.md](claude-code-notes.md) |
| git identity | `~/.gitconfig` | [new-machine-checklist.md](new-machine-checklist.md) |
| syncthing user service | enabled, running | [syncthing-and-ufw.md](syncthing-and-ufw.md) |

Differences from the K8 (4.0.6) because this is 4.5:

- **`kb_options` stock default changed.** 4.5 ships `omarchy:shift_caps_compose`
  instead of `compose:caps,shift:both_capslock_cancel`, so the swap string is
  built from the new default. Check with `hyprctl getoption input:kb_options`
  before copying an older machine's line.
- **No local SUPER+A.** 4.5 ships "Select all".
- **`o.rebind` instead of `hl.unbind` + `o.bind`.** The tab-reorder keys are
  written as `SUPER + SHIFT + CTRL + LEFT/RIGHT` (Omarchy's modifier order), so
  they replace stock "Move window to left/right monitor" instead of being listed
  next to it.
- **Default terminal is foot** until `omarchy-default-terminal ghostty`. Over SSH
  that command prints `OMARCHY_PATH: unbound variable` from `omarchy-i18n` but
  still writes `xdg-terminals.list` correctly.

Root steps, as one script: [assets/evo-x3/root-setup.sh](assets/evo-x3/root-setup.sh).
It installs ghostty, syncthing, cmake and hyprpm, enables sshd with LAN-scoped and
cable-scoped ufw rules, opens syncthing, makes SSH key-only, keeps Avahi off
`docker0` (Docker is preinstalled), installs the
[clock refresh hook](bar-clock-stale-after-resume.md), and configures the Spark
cable below.

## Direct cable to the DGX Spark

The X3's `eno1` is cabled straight to the Spark's 2.5GbE port, the same link the
K8 used before (Spark side: NetworkManager profile on `enP7s7`, `10.77.0.1/30`).

**Symptom:** a few minutes after boot `eno1` had no address at all, not even IPv6
link-local, so the X3 vanished from the cable. **Cause:** NetworkManager's stock
"Wired connection 1" profile uses DHCP; nothing on a direct cable answers, the
attempt times out and NM deactivates the profile, taking link-local with it.
**Fix:** a static profile:

```sh
sudo nmcli c modify 'Wired connection 1' connection.id spark-direct
sudo nmcli c modify spark-direct ipv4.method manual ipv4.addresses 10.77.0.2/30 \
  ipv4.never-default yes ipv6.method link-local connection.autoconnect yes
sudo nmcli c up spark-direct
```

`never-default` keeps the default route on Wi-Fi. ufw allows SSH on this link
only: `sudo ufw allow in on eno1 from 10.77.0.0/30 to any port 22 proto tcp`.

**Half-up link.** Once, the Spark's port went to NO-CARRIER while the X3 kept
reporting carrier at 2.5 Gb/s, so neither side could reach the other. Bouncing the
X3's port renegotiated it and the link came straight back:

```sh
sudo ip link set eno1 down; sleep 3; sudo ip link set eno1 up
sudo nmcli c up spark-direct && ping -c3 10.77.0.1
```

Verified: `ping 10.77.0.1` from the X3, and `ssh x3-cable` from the XPS 13.

## Second Wi-Fi network

The X3, the Spark and the XPS 13 were later moved to a second router on
`192.168.1.0/24`. The LAN-scoped SSH rule doesn't cover it, so the X3 refused
SSH there until it had its own rule:

```sh
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp
```

`lan-connect.sh` still found both machines, through their `.local` names (its
MAC sweep only covers `192.168.0.0/24`). On the Spark the second network has
`autoconnect-priority 20`, above the first network's 10, so it stays preferred
after a reboot.

## SSH from the XPS 13

The X3 is on Wi-Fi at `192.168.0.21` and answers as `x3.local` (with Avahi off
`docker0`, it resolves to the LAN address, not `172.17.0.1`). It uses the
[self-healing ProxyCommand](lan-ssh-self-healing.md), with the X3's Wi-Fi MAC in
the script's machine table:

```sshconfig
Host evo x3 x3.local
    HostName 192.168.0.21
    ProxyCommand ~/.ssh/lan-connect.sh x3 %h %p
    HostKeyAlias x3.local
    User <user>
    ConnectTimeout 15

# backup path over the Spark cable
Host x3-cable
    HostName 10.77.0.2
    ProxyJump spark-wifi
    HostKeyAlias x3.local
    User <user>
```

Key-only SSH is on; verified with
`ssh -o PubkeyAuthentication=no localhost` → `Permission denied (publickey)`.

## Not done

- **gh auth and hypr-tab-drag** need a terminal on the X3 itself:
  `gh auth login -h github.com -p https -w && gh auth setup-git`, then
  `hyprpm update && hyprpm add https://github.com/zoan37/hypr-tab-drag && hyprpm enable tab-drag`.
  hypr-momentum is skipped (no touchpad).
- **Power and fans.** The power profile is `performance` (stock without a
  battery). No fan, power-limit or UMA-split tuning yet; for eGPU use over
  OcuLink see the R9700/B70 notes before changing it.

## Verify

```sh
systemctl is-active sshd                          # active
sudo ufw status | grep -E '22/tcp|syncthing'      # both LANs 22, eno1 22 from 10.77.0.0/30, syncthing
avahi-resolve -4 -n x3.local                      # LAN address, not 172.17.0.1
hyprctl getoption input:kb_options                # omarchy:shift_caps_compose,altwin:swap_lalt_lwin
omarchy menu keybindings --print | grep -E 'SHIFT \+ S |grouped window'
omarchy-default-terminal                          # ghostty
ghostty +show-config | grep font-size             # 11
systemctl --user is-active syncthing              # active
ip -br addr show eno1                             # 10.77.0.2/30
```

## Undo

```sh
# config: restore the .bak.<timestamp> files in ~/.config/hypr, ~/.config/omarchy,
# ~/.config/ghostty and ~/.config/chrome-flags.conf
sudo rm /etc/ssh/sshd_config.d/10-keys-only.conf && sudo systemctl reload sshd
sudo ufw delete allow in on eno1 from 10.77.0.0/30 to any port 22 proto tcp
sudo sed -i '/^deny-interfaces=docker0$/d' /etc/avahi/avahi-daemon.conf && sudo systemctl restart avahi-daemon
sudo rm /usr/lib/systemd/system-sleep/omarchy-clock-refresh
sudo nmcli c modify spark-direct ipv4.method auto ipv4.addresses '' ipv6.method auto
```
