#!/usr/bin/env bash
# Re-run build_hot_reload.sh whenever any source/**/*.odin file changes.
# Requires: fswatch (brew install fswatch)
#
# Workflow:
#   1. Terminal A: ./build_hot_reload.sh run     (launches game)
#   2. Terminal B: ./watch.sh                    (auto-rebuilds on save)
set -eu

if ! command -v fswatch >/dev/null 2>&1; then
    echo "fswatch not found. Install with: brew install fswatch" >&2
    exit 1
fi

cd "$(dirname "$0")"

./build_hot_reload.sh
echo "[watch] ready - waiting for changes in source/"

fswatch -o -l 0.2 source | while read -r _; do
    echo "[watch] change detected, rebuilding..."
    ./build_hot_reload.sh || echo "[watch] build failed, waiting for next change"
done
