#!/bin/bash
# a16-fan.sh: manual fan control for the ASUS Zenbook A16 through the EC mailbox (0x5b, device 0xC4),
# using the register map from the Zenbook A14 EC driver (omerfaruknehir/asus-zenbook-a14-ec):
#   bank 1: 0x82 = set fan mode (0 auto, 2 manual), 0x8c = select fan (0/1), 0x8a = set PWM (0..255; 0 = off,
#           25 = lowest reliable start, ~800 rpm at 30), 0x0a = read PWM, 0x09 = read tach (rpm ~= raw*250),
#           0x02 = read fan mode
# Mailbox transactions take the same lock as a16-fan-daemon so the two never interleave.
# usage: sudo a16-fan.sh auto | manual <pwm> | status
set -u
BUS=${BUS:-9}; exec 9>/run/lock/a16-fan.lock
ecrb(){ sudo i2ctransfer -y $BUS w3@0x5b 0x10 $1 $2 >/dev/null 2>&1 || return 1; v=$(sudo i2ctransfer -y $BUS w1@0x5b 0x11 r1@0x5b 2>/dev/null) || return 1; echo $((v)); }
ecwb(){ sudo i2ctransfer -y $BUS w3@0x5b 0x10 $1 $2 >/dev/null 2>&1 || return 1; sudo i2ctransfer -y $BUS w2@0x5b 0x11 $3 >/dev/null 2>&1; }
settle(){ for i in $(seq 1 75); do [ "$(ecrb 0xc4 0x30)" = 0 ] && return 0; sleep 0.02; done; return 1; }
eccw(){ local r; flock 9; settle && ecwb 0xc4 0x31 $2 && ecwb 0xc4 0x32 $3 && ecwb 0xc4 0x30 $1 && settle; r=$?; flock -u 9; return $r; }   # bank feature value
eccr(){ local r v; flock 9; settle && ecwb 0xc4 0x31 $2 && ecwb 0xc4 0x30 $1 && settle && v=$(ecrb 0xc4 0x32) && ecwb 0xc4 0x32 0 && echo $v; r=$?; flock -u 9; return $r; }  # bank feature
case "${1:-status}" in
  status) echo "mode=$(eccr 0x01 0x02) (0=auto,2=manual)"; for f in 0 1; do eccw 0x01 0x8c $f; echo "fan$f pwm=$(eccr 0x01 0x0a) tach_raw=$(eccr 0x01 0x09)"; done; echo "rpm(RAM)=$(glymur-ec-read.sh rpm 2>/dev/null)";;
  manual) p=${2:?pwm 0-255}; eccw 0x01 0x82 0x02 && for f in 0 1; do eccw 0x01 0x8c $f && eccw 0x01 0x8a $(printf 0x%02x $p); done && echo "manual pwm=$p";;
  auto) eccw 0x01 0x82 0x00 && echo "auto";;
  *) echo "usage: $0 status|manual <pwm>|auto"; exit 1;;
esac
