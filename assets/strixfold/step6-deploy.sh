#!/bin/bash
# StrixFold GETTING-STARTED step 5: Inputs (copy + verify rank 1), Deploy, verify rank 0. Inside the node1 container.
set -euo pipefail
cd ~/tfp/src/TensorFold
B=~/models/tf-port/inputs-tp2-c178a012
H=$(sha256sum $B/inputs_manifest.json | cut -d" " -f1); echo "bundle H=$H"; echo "$H" > ~/tfp/bundle.sha256
echo "== copy node0 part ($(date +%T))"
ssh node0 "mkdir -p models/tf-port"
rsync -a --exclude rank1/ $B node0:models/tf-port/
echo "== copied ($(date +%T))"
echo "== verify rank 1"
PATH=$HOME/venvs/tfp-inputs/bin:$PATH tools/dsv41-hip/verify_inputs.sh $B 1 ~/models/tf-port/libertai-2.9bpw ~/models/tf-port/ds1017-1bae0e10 $H 2>&1 | tail -6
echo "== deploy"
git status --porcelain | head -3; git rev-parse --abbrev-ref HEAD
C=$(git rev-parse HEAD)
tools/dsv41-hip/deploy_rank0.sh --native zig-out/native-hip --bin-commit $C --ds-kit $B/kit 2>&1 | tail -4
tools/dsv41-hip/deploy_rank0.sh --host local --native zig-out/native-hip --bin-commit $C --ds-kit $B/kit 2>&1 | tail -4
echo "== verify rank 0 on node0"
ssh node0 mkdir -p tfp/bin && scp -q zig-out/bin/tf-dsv41-check node0:tfp/bin/
ssh node0 "PATH=\$HOME/venvs/tfp-inputs/bin:\$PATH TFP_BIN=\$HOME/tfp/bin ~/tfp/deploy/current/tools/dsv41-hip/verify_inputs.sh ~/models/tf-port/inputs-tp2-c178a012 0 ~/models/tf-port/libertai-2.9bpw ~/models/tf-port/ds1017-1bae0e10 $H" 2>&1 | tail -6
echo STEP6 DONE
