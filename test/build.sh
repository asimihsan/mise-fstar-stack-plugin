#!/bin/bash
# Build and test fstar-stack plugin in Docker
# Usage: ./build.sh [--no-cache]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/.."

cd "$PLUGIN_DIR"

CACHE_FLAG=""
if [[ "$1" == "--no-cache" ]]; then
    CACHE_FLAG="--no-cache"
fi

echo "=== Building fstar-stack-test Docker image for x86_64 ==="
docker build $CACHE_FLAG \
    --platform linux/amd64 \
    -f "$SCRIPT_DIR/Dockerfile" \
    --build-arg GH_TOKEN="${GH_TOKEN:-}" \
    -t fstar-stack-test:latest \
    --progress plain \
    .

echo ""
echo "=== x86_64 build successful! ==="

echo "=== Building fstar-stack-test Docker image for arm64 ==="
docker build $CACHE_FLAG \
    --platform linux/arm64 \
    -f "$SCRIPT_DIR/Dockerfile.arm64" \
    --build-arg GH_TOKEN="${GH_TOKEN:-}" \
    -t fstar-stack-test-arm64:latest \
    --progress plain \
    .

echo ""
echo "=== arm64 build successful! ==="

echo "All tests passed in the Docker container."
