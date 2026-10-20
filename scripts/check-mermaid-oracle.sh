#!/usr/bin/env bash
# Differential test: MermaidKit's flowchart parser against mermaid.js's own.
# Builds the corpus (hand-written regression cases + seeded generated charts),
# parses it with mermaid.js (tools/mermaid-oracle) and with MermaidKit, and
# compares what a reader would see. Fails on any divergence not already in
# tools/mermaid-oracle/known-divergences.json, which may only shrink.
#   scripts/check-mermaid-oracle.sh            # check against the baseline
#   scripts/check-mermaid-oracle.sh --report   # print divergences, no baseline
#   scripts/check-mermaid-oracle.sh --update   # rewrite the baseline
set -euo pipefail
cd "$(dirname "$0")/.."
tool=tools/mermaid-oracle
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
( cd "$tool" && { [ -d node_modules ] || npm ci --silent --no-audit --no-fund 2>/dev/null || npm install --silent --no-audit --no-fund; } )
node "$tool/corpus.mjs" "${ORACLE_COUNT:-1500}" > "$tmp/corpus.json"
( cd "$tool" && node oracle.mjs "$tmp/corpus.json" ) > "$tmp/mermaid.jsonl"
ORACLE_CORPUS="$tmp/corpus.json" ORACLE_OUT="$tmp/kit.jsonl" \
  swift test --filter MermaidOracleDump/testDumpForTheMermaidOracle >/dev/null
case "${1:-}" in
  --report) node "$tool/compare.mjs" "$tmp/corpus.json" "$tmp/mermaid.jsonl" "$tmp/kit.jsonl" ;;
  --update) node "$tool/compare.mjs" "$tmp/corpus.json" "$tmp/mermaid.jsonl" "$tmp/kit.jsonl" \
              --baseline "$tool/known-divergences.json" --update ;;
  *)        node "$tool/compare.mjs" "$tmp/corpus.json" "$tmp/mermaid.jsonl" "$tmp/kit.jsonl" \
              --baseline "$tool/known-divergences.json" ;;
esac
