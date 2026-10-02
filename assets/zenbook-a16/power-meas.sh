#!/bin/bash
# meas.sh SETTLE WINDOW -> mean battery W over WINDOW s, plus CPU busy % and GPU share of time above 310 MHz
settle=${1:-30}; win=${2:-60}; sleep $settle
P=/sys/class/power_supply/qcom-battmgr-bat/power_now; G=/sys/class/devfreq/3d00000.gpu/trans_stat
cpu(){ awk '/^cpu /{print $2+$3+$4+$7+$8, $5+$6}' /proc/stat; }
gpu(){ awk '$1 ~ /^\*?[0-9]+:$/ || $2 ~ /^[0-9]+:$/ {print $NF}' $G | tr '\n' ' '; }
read b0 i0 < <(cpu); g0=($(gpu))
w=$(for i in $(seq $win); do cat $P; sleep 1; done | awk '{s+=-$1;n++} END{printf "%.2f", s/n/1e6}')
read b1 i1 < <(cpu); g1=($(gpu))
lo=$(( ${g1[0]} - ${g0[0]} )); tot=0; for k in ${!g1[@]}; do tot=$(( tot + ${g1[$k]} - ${g0[$k]} )); done
awk -v w=$w -v bb=$((b1-b0)) -v ii=$((i1-i0)) -v t=$tot -v l=$lo 'BEGIN{printf "%s W  cpu %.1f%%  gpu>310 %d%%\n", w, 100*bb/(bb+ii), (t>0 ? 100*(t-l)/t : 0)}'
