#!/bin/bash
# Build and test fstar-stack plugin in Docker
# Usage: ./build.sh [--no-cache]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVEN_POOL_DIR="$SCRIPT_DIR/../../proven-pool"

cd "$PROVEN_POOL_DIR"

CACHE_FLAG=""
if [[ "$1" == "--no-cache" ]]; then
    CACHE_FLAG="--no-cache"
fi

echo "=== Building fstar-stack-test Docker image ==="
# Use linux/amd64 platform because F* only provides x86_64 Linux builds
docker build $CACHE_FLAG \
    --platform linux/amd64 \
    -f "$SCRIPT_DIR/Dockerfile" \
    --build-arg GH_TOKEN="${GH_TOKEN:-}" \
    -t fstar-stack-test:latest \
    .

echo ""
echo "=== Build successful! ==="
echo "All tests passed in the Docker container."
