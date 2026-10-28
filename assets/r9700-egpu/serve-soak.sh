#!/bin/bash
# Load the model once in llama-server, then back-to-back 512-token requests for SOAK_SECS (default 900).
# Extra llama.cpp env (e.g. GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1) is inherited from the caller.
L=~/egpu-tests/serve-soak.log
D=$(for d in /sys/bus/pci/devices/*; do grep -q 0x7551 $d/device 2>/dev/null && echo $d; done | head -1)
echo "start $(date +%T) env: $(env | grep ^GGML_ | tr "\n" " ")" > $L
~/llama.cpp/build-vk/bin/llama-server -m ~/gguf/Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf -dev Vulkan1 -ngl 99 -fa on -c 8192 --port 8099 >~/egpu-tests/llama-server.log 2>&1 &
for i in $(seq 1 180); do curl -sf localhost:8099/health >/dev/null && break; sleep 1; done
curl -sf localhost:8099/health >/dev/null || { echo "LOAD FAILED $(date +%T)" >> $L; exit 1; }
echo "loaded $(date +%T) after ${i}s" >> $L
end=$(( $(date +%s) + ${SOAK_SECS:-900} )); n=0
while [ $(date +%s) -lt $end ]; do
  n=$((n+1))
  r=$(curl -s -m 120 localhost:8099/completion -d "{\"prompt\":\"Write a long story about a robot learning to paint, part $n.\",\"n_predict\":512,\"cache_prompt\":false}" | grep -oE "\"predicted_per_second\":[0-9.]+|\"prompt_per_second\":[0-9.]+" | cut -d: -f2 | tr "\n" " ")
  echo "$(date +%T) req=$n junction=$(( $(cat $D/hwmon/hwmon*/temp2_input 2>/dev/null)/1000 ))C pp/tg=${r:-FAILED} gpu_errs=$(sudo -n dmesg | grep "$(basename $D)" | grep -iE "timeout|reset" | wc -l)" >> $L
  [ -z "$r" ] && { echo "request failed, stopping" >> $L; break; }
done
echo "done $(date +%T)" >> $L
