#!/bin/bash
# Keep the R9700 from going fully idle/empty: a tiny llama-server holds a Vulkan context,
# and a 1-token request every few seconds keeps work arriving. (Didn't prevent the hang.)
~/llama.cpp/build-vk/bin/llama-server -m ~/gguf/Qwen3-0.6B-Q8_0.gguf -dev Vulkan1 -ngl 99 -c 512 -np 1 --port 8098 >~/egpu-tests/keepalive-server.log 2>&1 &
for i in $(seq 1 60); do curl -sf localhost:8098/health >/dev/null && break; sleep 1; done
while :; do curl -s -m 20 localhost:8098/completion -d "{\"prompt\":\"hi\",\"n_predict\":1}" >/dev/null; sleep ${KEEPALIVE_SECS:-3}; done
