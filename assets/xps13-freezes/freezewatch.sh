#!/usr/bin/env bash
# Logs a line whenever a 0.5 s sleep takes much longer (whole-system stall), plus a heartbeat every 30 s.
out=$1; L=$(ls -t $XDG_RUNTIME_DIR/hypr/*/hyprland.log | head -1)
end=$(( $(date +%s) + 3*3600 )); i=0
while [ $(date +%s) -lt $end ]; do
  t0=$(date +%s%N); sleep 0.5; t1=$(date +%s%N); d=$(( (t1-t0)/1000000 - 500 ))
  i=$((i+1))
  if [ $d -gt 150 ] || [ $((i % 60)) -eq 0 ]; then
    tag=beat; [ $d -gt 150 ] && tag="STALL ${d}ms"
    printf '%s %s | mem:%s io:%s | hypr-slow:%s | top:%s\n' "$(date +%T)" "$tag" \
      "$(awk '/full/{print $2}' /proc/pressure/memory)" "$(awk '/full/{print $2}' /proc/pressure/io)" \
      "$(grep -c 'too slow' $L)" "$(ps -eo pcpu,comm --sort=-pcpu --no-headers | head -3 | tr -s ' \n' ' ')" >> "$out"
  fi
done
