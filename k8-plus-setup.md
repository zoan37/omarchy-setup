# GMKtec NucBox K8 Plus: new-machine setup and SSH from the XPS 13

Set up **2026-10-24** on a fresh Omarchy 4.0.6 install, kernel `7.2.8-9-omarchy`,
BIOS `NucBox K8 Plus 1.01` (2024-10-12). Ryzen 7 8845HS with the Radeon 780M
(HawkPoint1, the same iGPU family as the SER8), 64 GB RAM, Intel AX200 Wi-Fi and
two Intel I226-V 2.5GbE ports. Dell 3440x1440 ultrawide over HDMI at scale 1,
the stock `auto`. USB keyboard and mouse, **no touchpad, no battery**.

It is the closest match to the [SER8](ser8-lan-ssh-hostname.md), so the
[new machine checklist](new-machine-checklist.md) was followed with the SER8 as
the model. All hardware-specific fixes for the other machines were skipped,
including the SER8 fan curve, which is scoped to the SER8's IT8613E controller
and BIOS.

## Applied

User config (each file has a `.bak.<timestamp>` next to it):

| What | Where | Doc |
|---|---|---|
| Left Super/Alt swap | `~/.config/hypr/input.lua` | [hyprland-shell-tweaks.md](hyprland-shell-tweaks.md) |
| Resize on border trio | `~/.config/hypr/looknfeel.lua` | same |
| Group tab reorder, SUPER+SHIFT+S screenshot (with `hl.unbind`), SUPER+A select all | `~/.config/hypr/bindings.lua` | same |
| Clock format `ddd d MMM HH:mm` | `~/.config/omarchy/shell.json` | same |
| Ghostty as default terminal, 11pt, `ctrl+enter=unbind` | `~/.config/xdg-terminals.list`, `~/.config/ghostty/local.conf` + trailing include | [terminal-font-size.md](terminal-font-size.md), [ghostty-ctrl-enter.md](ghostty-ctrl-enter.md) |
| Vulkan + VA-API Chrome flags | `~/.config/chrome-flags.conf` | [chrome-vulkan-white-video.md](chrome-vulkan-white-video.md) |
| `cleanupPeriodDays: 10950` | `~/.claude/settings.json` | [claude-code-notes.md](claude-code-notes.md) |
| git identity | `~/.gitconfig` | [new-machine-checklist.md](new-machine-checklist.md) |
| syncthing user service | enabled, running | [syncthing-and-ufw.md](syncthing-and-ufw.md) |

The global text size was already 12px, so `omarchy display text size 12` was
not needed.

SUPER+A is needed here because 4.0.6 predates Omarchy 4.5, which ships its own
"Select all" bind. **After upgrading to 4.5, delete the local SUPER+A block**,
or both fire on one press. The same upgrade brings the
[tray half-pixel](tray-icon-half-pixel.md) issue, which 4.0.6 doesn't have.

Root, run as one script:

```sh
sudo pacman -Sy
sudo pacman -S --needed ghostty syncthing cmake hyprpm
sudo systemctl enable --now sshd
sudo ufw allow from 192.168.0.0/24 to any port 22 proto tcp
sudo ufw allow syncthing
# Docker is installed: keep Avahi from advertising docker0 (see the SER8 notes)
sudo sed -i '/^\[server\]$/a deny-interfaces=docker0' /etc/avahi/avahi-daemon.conf
sudo systemctl restart avahi-daemon
sudo install -Dm755 assets/clock-refresh-on-resume/omarchy-clock-refresh \
  /usr/lib/systemd/system-sleep/omarchy-clock-refresh
```

## SSH from the XPS 13

Neither of the SER8's two problems applies here:

- **Hostname.** It is already `k8`, so there is no `omarchy` name
  clash on mDNS. The machine answers as `k8.local`.
- **One card on the LAN.** Only the AX200 is connected; both Ethernet ports
  have no cable. If a cable is plugged in while Wi-Fi stays up, the
  [ARP flux](ser8-lan-ssh-hostname.md#cause-1-two-wi-fi-interfaces-on-the-same-lan-arp-flux)
  from the SER8 can come back. Turn Wi-Fi off, or stop it autoconnecting, if
  that happens.

On the XPS 13:

```sh
ssh-copy-id <user>@k8.local      # one password login, then the key is in place
```

```sshconfig
# XPS 13 ~/.ssh/config
Host k8
    HostName k8.local
    User <user>
    AddressFamily inet          # ufw here only allows the LAN's IPv4 range
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

Verified: the sshd journal on the K8 shows `Accepted publickey ... ED25519`
from the XPS 13 (`192.168.0.29`) after the one `Accepted password` from
`ssh-copy-id`.

**Key-only SSH: not yet applied.** The checklist's lockdown still needs to run:

```sh
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' | sudo tee /etc/ssh/sshd_config.d/10-keys-only.conf
sudo sshd -t && sudo systemctl reload sshd
ssh -o PubkeyAuthentication=no localhost   # → Permission denied (publickey)
```

## Open / not done

- **Chrome flicker.** The SER8, on the same iGPU family, had toolbar flicker
  under these Vulkan flags ([trial notes](chrome-ser8-flicker-trial.md)). Not
  seen here yet. If it shows up, start from the SER8 trial, not from scratch.
- **hypr-tab-drag.** `cmake` and `hyprpm` are installed, but hyprpm needs an
  interactive terminal ([hyprpm-notes.md](hyprpm-notes.md)):
  `hyprpm update && hyprpm add https://github.com/zoan37/hypr-tab-drag && hyprpm enable tab-drag`,
  then `o.exec_on_start("hyprpm reload -n")` in `autostart.lua`. hypr-momentum
  is skipped (no touchpad).
- **Fan and power.** No fan, coil-whine or power-profile tuning has been looked
  at yet.

## Verify

```sh
systemctl is-active sshd                       # active
sudo ufw status | grep -E '22/tcp|syncthing'   # LAN-scoped 22, syncthing
avahi-resolve -4 -n k8.local                   # LAN address, not 172.17.0.1
hyprctl getoption input:kb_options             # ...,altwin:swap_lalt_lwin
omarchy menu keybindings --print | grep -i -E 'screenshot|select all'
omarchy-default-terminal                       # ghostty
ghostty +show-config | grep font-size          # 11
systemctl --user is-active syncthing           # active
```

## Undo

```sh
# config: restore the .bak.<timestamp> files in ~/.config/hypr and ~/.config/omarchy
sudo ufw delete allow from 192.168.0.0/24 to any port 22 proto tcp
sudo systemctl disable --now sshd
sudo sed -i '/^deny-interfaces=docker0$/d' /etc/avahi/avahi-daemon.conf && sudo systemctl restart avahi-daemon
sudo rm /usr/lib/systemd/system-sleep/omarchy-clock-refresh
```
