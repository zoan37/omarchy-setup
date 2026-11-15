#!/bin/bash
# StrixFold GETTING-STARTED step 4, run INSIDE the node1 container (paths under $HOME are shared with the host).
set -euo pipefail
cd /tmp
if [ ! -x ~/opt/zig/zig ]; then
  curl -fsSLO https://ziglang.org/download/0.17.0/zig-x86_64-linux-0.17.0.tar.xz
  echo "1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026  zig-x86_64-linux-0.17.0.tar.xz" | sha256sum -c
  mkdir -p ~/opt && tar -xf zig-x86_64-linux-0.17.0.tar.xz -C ~/opt && ln -sfn zig-x86_64-linux-0.17.0 ~/opt/zig
fi
echo "zig $(~/opt/zig/zig version)"
cd ~/tfp/src/TensorFold
[ -x ~/venvs/tfp-inputs/bin/python ] || python3 -m venv ~/venvs/tfp-inputs
~/venvs/tfp-inputs/bin/pip install -q --no-deps --require-hashes -r tools/dsv41-hip/requirements-inputs.lock.txt --extra-index-url https://download.pytorch.org/whl/cpu
echo "inputs venv ok: $(~/venvs/tfp-inputs/bin/python -c "import torch,numpy,tokenizers; print(torch.__version__, numpy.__version__, tokenizers.__version__)")"
mkdir -p ~/tfp/tri/wheels && cd ~/tfp/tri/wheels
W=triton-3.8.0+git675c5987.rocm10.1.0a20260822-cp313-cp313-linux_x86_64.whl
[ -f "$W" ] || curl -fsSL -o "$W" "https://rocm.nightlies.amd.com/whl-multi-arch/${W/+/%2B}"
echo "1bab2eeb8f4beccad389a497a45b3018fa6291ab93c577f04b1376cf12422499  $W" | sha256sum -c
[ -x ~/venvs/triton/bin/python ] || python3 -m venv ~/venvs/triton
~/venvs/triton/bin/pip install -q --no-deps ./$W
echo "triton venv ok: $(~/venvs/triton/bin/python -c "import triton; print(triton.__version__)")"
echo STEP4 DONE
