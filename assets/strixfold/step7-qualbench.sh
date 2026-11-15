#!/bin/bash
# StrixFold GETTING-STARTED "Benchmark": the published two-DGX-Spark prompt set, 5 reps, prefill 2,000 and 8,000. Inside the node1 container.
set -euo pipefail
[ -d ~/tfp/qual/recipe ] || git clone -q https://github.com/tonyd2wild/DeepSeek-V4.1-Flash-vLLM-DGX-Spark ~/tfp/qual/recipe
git -C ~/tfp/qual/recipe checkout -q 9fa230d3eb119f588e690bf9b87ce41ed902db60
mkdir -p ~/tfp/qual/bench/creator && cp ~/tfp/qual/recipe/bench/prompts-v1.json ~/tfp/qual/bench/creator/
cd ~/tfp/src/TensorFold/tools/dsv41-hip
qual/qual_bench.sh bench '$HOME/tfp/run/conf/my.conf' first --reps 5 --prefill 2000,8000
echo QUALBENCH DONE
