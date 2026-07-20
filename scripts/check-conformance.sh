#!/usr/bin/env bash
# Cross-platform conformance gate.
#
# Runs the conformance harness (tools/conformance) and asserts its COMBINED
# signature equals the pinned reference — the same value the core must produce on
# EVERY platform it compiles to. Any divergence (a platform-math difference, a
# non-deterministic encoding) fails the build. See docs/notes/cross-platform-conformance.md.
#
#   scripts/check-conformance.sh [reference-hash] [swift-sdk-id]
#
# With a swift-sdk-id (e.g. the WASM SDK), the harness is built + run for that SDK
# (via WasmKit for wasm). Without, it runs for the host.
set -euo pipefail

# The reference: the byte-identical SceneWire+SVG signature across all platforms.
# Re-baseline deliberately (and note why) if a toolchain upgrade changes it.
REFERENCE="${1:-3f94e22042aa59eb}"
SDK_ARG="${2:-}"

cd "$(dirname "$0")/../tools/conformance"

if [ -n "$SDK_ARG" ]; then
  out=$(swift run --swift-sdk "$SDK_ARG" mmk-conform 2>/dev/null)
else
  out=$(swift run mmk-conform 2>/dev/null)
fi
echo "$out"

got=$(printf '%s\n' "$out" | awk '/^COMBINED/{print $2}')
if [ "$got" = "$REFERENCE" ]; then
  echo "✅ conformant: $got"
else
  echo "❌ cross-platform divergence: got '$got', expected '$REFERENCE'"
  exit 1
fi
