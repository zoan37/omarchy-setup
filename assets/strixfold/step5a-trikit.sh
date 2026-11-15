#!/bin/bash
# StrixFold GETTING-STARTED step 5 "The Triton kit (once)", inside the node1 container (no systemd scope there).
set -euo pipefail
cd ~/tfp/src/TensorFold/tools/dsv41-hip/tri
taskset -c 8-15,24-31 nice -n 10 ~/venvs/triton/bin/python aot_build.py ../../../zig/src/families/dsv41/fixtures/launches.json ~/tfp/tri/kit/gfx1151 \
  --extra ../../../zig/src/families/dsv41/fixtures/derived_launches.json --jobs 8
echo TRIKIT DONE
