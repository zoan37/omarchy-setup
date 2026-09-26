#!/bin/bash
# install-speaker-boost.sh: Zenbook A16 (UX3607OA) tweeter routing + boost, as the user (not root).
# Reuses Omarchy's speaker-tuning file names so the volume keys resolve to the physical sink and
# `omarchy audio tuning off` removes it. Needs the UCM fix (section 4) so the 4ch speaker sink exists.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd); C=${XDG_CONFIG_HOME:-$HOME/.config}
pacman -Q lsp-plugins-lv2 >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm lsp-plugins-lv2
install -Dm644 /usr/share/omarchy/default/audio/filter-chain-host.conf "$C/pipewire/omarchy-speaker-tuning.conf"
install -Dm644 "$D/90-tuning.conf" "$C/pipewire/omarchy-speaker-tuning.conf.d/90-tuning.conf"
install -Dm644 /usr/share/omarchy/default/systemd/user/omarchy-speaker-tuning.service "$C/systemd/user/omarchy-speaker-tuning.service"
systemctl --user daemon-reload
systemctl --user enable omarchy-speaker-tuning.service
systemctl --user restart omarchy-speaker-tuning.service
for _ in {1..20}; do pactl list sinks short | grep -q omarchy_speaker_tuning && break; sleep 0.25; done
pactl set-default-sink omarchy_speaker_tuning
for id in $(pactl list sink-inputs | awk '/^Sink Input #/{id=substr($3,2)} /application\.name = /{print id}'); do
  pactl move-sink-input "$id" omarchy_speaker_tuning 2>/dev/null || true
done
omarchy-audio-tuning status
