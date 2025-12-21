#!/bin/bash
# Test plugin on native macOS (run locally, not in Docker)
# Verifies ARM64 architecture on Apple Silicon

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="2025.12.15-stack.1"

echo "=== Testing mise-fstar-stack-plugin on macOS ==="

# Must be run on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "ERROR: This script must be run on macOS"
    exit 1
fi

ARCH=$(uname -m)
echo "Native architecture: $ARCH"

# Clean install
echo ""
echo "=== Uninstalling existing fstar-stack ==="
mise uninstall fstar-stack 2>/dev/null || true

echo ""
echo "=== Installing fstar-stack ==="
mise plugin link --force fstar-stack "$SCRIPT_DIR/.."
mise install fstar-stack@"$VERSION" --force

# Verify tools work
echo ""
echo "=== Verifying tools ==="
mise exec fstar-stack@"$VERSION" -- fstar.exe --version
mise exec fstar-stack@"$VERSION" -- Karamel.exe -version

# Verify architecture
echo ""
echo "=== Verifying architecture ==="
"$SCRIPT_DIR/verify-arch.sh" "$ARCH"

echo ""
echo "=== macOS native test PASSED ==="
