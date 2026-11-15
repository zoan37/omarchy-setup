#!/bin/bash
# StrixFold step 5 "Build and GPU tests" (BUILD_AND_RUN.md section 2), inside the node1 container.
set -uo pipefail
cd ~/tfp/src/TensorFold
git status --short | head -5
echo "== install"; tools/dsv41-hip/zig_build.sh install 2>&1 | tail -15
echo "== test"; tools/dsv41-hip/zig_build.sh test test-dsv41-hip-host native-hip dsv41-hip-gpu-test -Dhip-triton-kit=$HOME/tfp/tri/kit/gfx1151 2>&1 | tail -25
echo "== gpu tests"; tools/dsv41-hip/run_gpu_tests.sh 2>&1 | tail -30
echo BUILD DONE
