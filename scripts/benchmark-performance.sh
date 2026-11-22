#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/cache .build/config .build/security .build/clang
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang"
if test -n "$(git status --porcelain)"; then
  export KS_BENCHMARK_DIRTY=true
else
  export KS_BENCHMARK_DIRTY=false
fi
export KS_BENCHMARK_REVISION="$(git rev-parse HEAD)"
export KS_BENCHMARK_TOOLCHAIN="$(swift --version | head -1)"
swift run -c release --jobs 4 --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" \
  --security-path "$PWD/.build/security" PerformanceBenchmarks "$@"
