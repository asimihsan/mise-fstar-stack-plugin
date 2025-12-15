#!/bin/bash
# Verify built artifacts match expected architecture
# Usage: ./verify-arch.sh [expected_arch]
# Default: auto-detect from uname -m

set -e

EXPECTED_ARCH="${1:-$(uname -m)}"
FSTAR_STACK_DIR=$(mise where fstar-stack)

echo "=== Verifying architecture: $EXPECTED_ARCH ==="

# Check krmllib
KRMLLIB="$FSTAR_STACK_DIR/karamel/krmllib/dist/generic/libkrmllib.a"
if [[ -f "$KRMLLIB" ]]; then
    # lipo works on macOS, file works on both
    ACTUAL=$(lipo -info "$KRMLLIB" 2>/dev/null | grep -oE '(arm64|x86_64)$' || file "$KRMLLIB" | grep -oE '(arm64|x86_64|x86-64)' | head -1)
    # Normalize x86-64 to x86_64
    ACTUAL="${ACTUAL/x86-64/x86_64}"
    echo "libkrmllib.a: $ACTUAL"
    if [[ "$ACTUAL" != "$EXPECTED_ARCH" ]]; then
        echo "ERROR: Expected $EXPECTED_ARCH, got $ACTUAL"
        exit 1
    fi
else
    echo "WARNING: libkrmllib.a not found at $KRMLLIB"
fi

# Check KaRaMeL executable
KRML_EXE="$FSTAR_STACK_DIR/karamel/_build/default/src/Karamel.exe"
if [[ -f "$KRML_EXE" ]]; then
    ACTUAL=$(file "$KRML_EXE" | grep -oE '(arm64|x86_64|x86-64)' | head -1)
    # Normalize x86-64 to x86_64
    ACTUAL="${ACTUAL/x86-64/x86_64}"
    echo "Karamel.exe: $ACTUAL"
    if [[ "$ACTUAL" != "$EXPECTED_ARCH" ]]; then
        echo "ERROR: Expected $EXPECTED_ARCH, got $ACTUAL"
        exit 1
    fi
else
    echo "WARNING: Karamel.exe not found at $KRML_EXE"
fi

echo "=== Architecture verification PASSED ==="
