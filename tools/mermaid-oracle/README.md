# The mermaid.js oracle

A differential test for the flowchart parser: MermaidKit should read a chart
the way mermaid.js does. This parses a corpus with **mermaid.js's own parser**
(12.2.0, pinned) and with MermaidKit, and compares what a reader would see:
node ids, visible label text (entities decoded and HTML rendered, as the
browser shows them), shapes, and each edge's endpoints, label, stroke, head,
arrows and length.

```sh
scripts/check-mermaid-oracle.sh            # CI: fail on a divergence not in the baseline
scripts/check-mermaid-oracle.sh --report   # list divergences, with the charts
scripts/check-mermaid-oracle.sh --update   # rewrite the baseline after a fix
```

**The corpus** is `cases.json`, every edge case a review has found (add new
ones there), plus about 1,500 charts that `corpus.mjs` generates from a fixed
seed. They combine every construct the parser reads with the characters that
have broken it (`; | # & < > " ( ) [ ] { } : @ % ~`), in node labels, edge
labels and inline link text, joined by newlines or `;`.

**Each chart is one of:**

- **agree:** both draw the same thing.
- **lenient:** mermaid errors and MermaidKit draws. This is allowed: degrade,
  never break.
- **rejects:** mermaid draws and MermaidKit returns nothing. A divergence.
- **differs:** both draw, but something a reader would see differs. A divergence.

**The baseline** (`known-divergences.json`) records today's divergences by
the hash of the chart. CI fails on any divergence that isn't in it, so a
parser change can't quietly break a chart that used to read right. When a fix
makes known divergences agree, run `--update` and the baseline shrinks. It
only ever shrinks: the same ratchet as the grid-alignment floors and the
draw-vs-scene conformance ceilings.

**Comparison rules** live in `normalize.mjs` (mermaid's side) and
`Tests/MermaidLayoutTests/MermaidOracleDump.swift` (MermaidKit's side). Shapes
MermaidKit has no case for compare as its documented rectangle fallback.
Subgraph membership isn't compared yet.
