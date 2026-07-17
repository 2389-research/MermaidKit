#!/usr/bin/env bash
# Cross-process layout/render determinism check (issue #1).
#
# Swift randomizes the Set/Dictionary hash seed per process, so a layout that
# lets hashed-collection iteration order reach coordinates renders the same
# source differently across app launches. StabilityTests can't see this — it
# compares two layout calls inside ONE process (one fixed seed). This renders
# every fixture in TWO fresh processes (two random seeds) and diffs the raster
# signatures; any difference is a hash-order leak into geometry.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
filter='DeterminismSignatureTests/testEmitRasterSignatures'

echo "Rendering all fixtures in two fresh processes (randomized hashing)…"
DETERMINISM_OUT="$tmp/a.txt" swift test --filter "$filter" >/dev/null 2>&1
DETERMINISM_OUT="$tmp/b.txt" swift test --filter "$filter" >/dev/null 2>&1

if diff -u "$tmp/a.txt" "$tmp/b.txt" > "$tmp/delta.txt"; then
  echo "✓ deterministic: every fixture renders identically across process launches"
else
  echo "✗ NONDETERMINISTIC — these fixtures differ across processes (hash-order leak into geometry):"
  grep '^[-+][a-z]' "$tmp/delta.txt" | sed 's/\t.*//' | sort -u
  exit 1
fi
