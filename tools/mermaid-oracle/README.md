# The mermaid.js oracle

A differential test for the flowchart parser: MermaidKit should read a chart
the way mermaid.js does. This parses a corpus with **mermaid.js's own parser**
(12.2.0, pinned) and with MermaidKit, and compares what a reader would see:
node ids, visible label text (entities decoded and HTML rendered, as the
browser shows them), shapes, each edge's endpoints, label, stroke, head,
arrows and length, and each subgraph's title, direction and members.

```sh
scripts/check-mermaid-oracle.sh            # CI: fail on a new divergence, or a known one getting worse
scripts/check-mermaid-oracle.sh --report   # list every divergence, with the charts
scripts/check-mermaid-oracle.sh --update   # record a fix (refuses while anything got worse)
scripts/check-mermaid-oracle.sh --accept   # record everything as it stands
```

**The corpus** is `cases.json`, every edge case a review has found (add new
ones there), plus about 1,500 charts that `corpus.mjs` generates from a fixed
seed. They combine every construct the parser reads with the characters that
have broken it (`; | # & < > " ( ) [ ] { } : @ % ~`), in node labels, edge
labels and inline link text, joined by newlines or `;`.

**Sentinels** (`sentinels.json`) open the corpus: charts both parsers must
read, and read alike. If one doesn't, the run stops (exit 2) and blames the
harness, so a mermaid that can't load can't pass as every chart "lenient".
Only mermaid's own parse is caught as a rejection; a throw in the harness
ends the run.

**Each chart is one of:**

- **agree:** both draw the same thing.
- **lenient:** mermaid errors and MermaidKit draws. This is allowed: degrade,
  never break.
- **rejects:** mermaid draws and MermaidKit returns nothing. A divergence.
- **differs:** both draw, but something a reader would see differs. A divergence.

**The baseline** (`known-divergences.json`) records each of today's
divergences by the hash of the chart, with what a reader sees differently,
counted by how bad it is:

- **missing:** mermaid draws it and MermaidKit has nothing there (a node, an
  edge between those endpoints, each parallel copy, the direction);
- **wrong:** it's there, but a property differs (a label, a shape, an edge's
  label, stroke, head, arrows or length, the direction);
- **extra:** MermaidKit draws something mermaid doesn't.

Divergences order by (kind, missing, wrong, extra). Drawing nothing is worse
than any drawing; then losing what mermaid draws is worst, then drawing it
wrong, then drawing extra. So no deletion can pass as progress: dropping
anything mermaid draws raises *missing*, whatever else it fixes, while
removing junk, or turning a rejection into a drawing, is progress. That order
is a policy (never drop): recovering something missing counts as progress
even if it draws extra, and the extra stays counted, so removing it later is
progress too.

CI fails when a chart diverges that the baseline doesn't list, or when a
listed chart orders after its record, or a listed chart has left the corpus
(lost coverage isn't a fix). So a parser change can't quietly break a chart
that read right, or make a wrong one wronger. After a fix, `--update` removes
the charts that now agree and records the ones that got better; it refuses to
write while anything got worse or went missing. The baseline only ever
shrinks: the same ratchet as the grid-alignment floors and the draw-vs-scene
conformance ceilings.

`--accept` writes every divergence as it stands. Use it only to start a
baseline, or when adding a case to `cases.json` that MermaidKit doesn't read
right yet, or when the corpus changes on purpose. The diff then shows what was
accepted, and the reviewer approves it.

**Comparison rules** live in `normalize.mjs` (mermaid's side) and
`Tests/MermaidLayoutTests/MermaidOracleDump.swift` (MermaidKit's side). Shapes
MermaidKit has no case for compare as its documented rectangle fallback.
Subgraphs compare by id (a title-only subgraph's synthesized id by its
title and named members, since the two sides number them differently),
with their title, direction and direct members (nodes and child subgraphs). Styling (`classDef`, `style`, `:::class`, `linkStyle`)
isn't compared: MermaidKit themes every node alike on purpose, and what it
must do with styling lines, keep reading the rest of the chart, is already
compared. Edge order isn't either: it only matters to `linkStyle N`, which
MermaidKit ignores.
A subgraph's direction compares as declared. mermaid's renderer ignores it
when a member links outside the subgraph, a limitation its docs list;
MermaidKit honors it on purpose.
