#!/bin/bash
# Repeated model loads (the step that hangs), stop at the first failure.
# LOADS (default 10) and GAP_SECS (pause between loads, default 0) are optional.
L=~/egpu-tests/load-loop.log; echo "start $(date +%T) env: $(env | grep ^GGML_ | tr "\n" " ")" > $L
for n in $(seq 1 ${LOADS:-10}); do
  [ $n -gt 1 ] && sleep ${GAP_SECS:-0}; t0=$(date +%s)
  out=$(timeout 300 ~/llama.cpp/build-vk/bin/llama-bench -m ~/gguf/Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf -dev Vulkan1 -ngl 99 -fa 1 -p 64 -n 16 -r 1 2>&1)
  rc=$?; tg=$(echo "$out" | grep tg16 | grep -oE "[0-9]+\.[0-9]+ ±" | cut -d" " -f1)
  echo "$(date +%T) load=$n rc=$rc secs=$(( $(date +%s)-t0 )) tg16=${tg:-none} gpu_errs=$(sudo -n dmesg | grep -ciE "ring .*timeout")" >> $L
  [ $rc -ne 0 -o -z "$tg" ] && { echo "FAILED at load $n" >> $L; break; }
done
echo "done $(date +%T)" >> $L
