# Render performance: where the milliseconds go

Perf memo, 2026-07-15. Machine: Apple M1 Max, macOS 26.5, release build
(`-c release` for the function-level profile; the phase breakdown ran under
the normal test build). Every number here is machine-specific and best-of-N
cold — it is **not** a CI threshold. MermaidKit's test suite asserts
correctness only; timing gates flake under CI load, so nothing here gates a
merge. Numbers over adjectives: this memo is the receipts behind the README's
"under 25 ms" claim, and an honest read on whether any of it is worth touching.

## How to measure

The end-to-end harness is `RenderBenchmarks`
(`Tests/MermaidRenderTests/RenderBenchmarks.swift`). By default it is a
*correctness* smoke — every fixture in `Fixtures/diagrams/` must parse, render,
and rasterize (it forces `cgImage(forProposedRect:…)`, because a handler-backed
`NSImage` defers its drawing until first use and would otherwise flatter the
numbers). It makes **no wall-clock assertion**.

Timing is opt-in:

```
BENCH_TABLE=1 swift test --filter RenderBenchmarks 2>&1 | grep '^BENCH'
```

That measures parse-ms and total-ms (parse → layout → render → rasterize),
best-of-3, round-robin across types (sequential per-type sampling biased late
types with accumulated heat — a measured ~2x swing). The cache is busted each
pass with a run-unique comment, so every sample is a true cold render.

## Current numbers

Cold parse → layout → render → rasterize, best of 3, M1 Max. "Parse" is the
`MermaidParser.parse` slice of the same run. These are the dense per-type
fixtures in this repo; real-world diagrams are usually smaller.

| Diagram | Parse | Total | Diagram | Parse | Total |
|---|---:|---:|---|---:|---:|
| architecture | 0.36 | 14.6 | pie | 0.10 | 2.0 |
| block | 0.25 | 3.4 | quadrant | 0.16 | 4.0 |
| c4 | 0.29 | 7.4 | radar | 0.24 | 2.8 |
| class | 0.67 | 12.3 | requirement | 0.49 | 9.5 |
| cynefin | 0.15 | 2.3 | sankey | 0.17 | 26.5 |
| er | 0.30 | 8.7 | sequence | 0.43 | 9.6 |
| eventmodeling | 0.16 | 3.9 | state | 0.30 | 11.8 |
| flowchart | 2.07 | 13.3 | swimlane | 0.22 | 3.2 |
| gantt | 0.42 | 3.2 | timeline | 0.19 | 4.5 |
| gitgraph | 0.23 | 2.8 | treemap | 0.21 | 2.9 |
| ishikawa | 0.13 | 3.2 | treeview | 0.53 | 3.9 |
| journey | 0.22 | 4.4 | venn | 0.08 | 1.8 |
| kanban | 0.33 | 5.4 | wardley | 0.25 | 3.6 |
| mindmap | 0.32 | 8.5 | xychart | 0.18 | 2.4 |
| packet | 0.15 | 3.6 | zenuml | 0.26 | 9.3 |

All times in ms. Worst: sankey at ~26 ms. Most types land 2–12 ms, well inside
one 60 fps frame's worth of headroom for the common case and comfortably
interactive for the worst.

## Where the time goes

The harness only splits parse vs total, so a throwaway breakdown (deleted after
measurement) timed four phases separately per fixture, best of 5 with the first
round discarded as warmup:

- **parse** — `MermaidParser.parse(src)`
- **layout** — `DiagramScene.lower(diagram, measure:)`, which runs the real
  per-type `DiagramLayoutEngine.layout` (`DiagramSceneLower.swift:47`)
- **build** — `MermaidRenderer.image(...)`, which returns a handler-backed
  `NSImage` whose draw closure is **deferred** (it re-parses and re-lays-out
  internally, so this column double-counts parse+layout and is not additive)
- **rasterize** — forcing `cgImage(...)`, which finally runs the deferred draw
  closure: the actual `CGContext`/CoreText drawing

Summed across all 30 fixtures: **parse 9.9 ms, layout 36.1 ms, rasterize
152.6 ms**. The verdict is unambiguous: **drawing dominates**. Parse is noise
(sub-millisecond for all but flowchart). Layout matters for a handful of types.
Rasterization is where ~three-quarters of every cold render is spent.

Per-type, the standouts (parse / layout / rasterize, ms):

| type | parse | layout | rasterize |
|---|---:|---:|---:|
| sankey | 0.19 | 3.46 | **23.52** |
| state | 0.31 | 3.09 | 9.55 |
| sequence | 0.45 | 1.10 | 9.02 |
| requirement | 0.48 | 1.15 | 8.66 |
| class | 0.69 | 1.91 | 8.38 |
| zenuml | 0.27 | 0.62 | 7.83 |
| mindmap | 0.32 | 0.56 | 7.57 |
| flowchart | 1.93 | 3.09 | 7.22 |
| architecture | 0.37 | **9.15** | 5.52 |

Two things stand out:

1. **Rasterize is the tall pole for every non-trivial type.** These are the
   fixtures with many nodes, edges, and labels — more paths to fill/stroke and
   more text runs to lay out and draw. The cost scales with the count of drawn
   primitives, not with anything algorithmic.

2. **Architecture is the one layout-bound type** (9.15 ms layout vs 5.5 ms
   draw). Its placement is iterative (grid/edge-constraint solving in
   `DiagramLayoutArchitecture.swift`) rather than a single pass, so its cost
   lives in `lower`, not in drawing. Flowchart, sankey, and state are the next
   heaviest layouts (~3 ms) — flowchart's layered layout (network-simplex
   ranking + crossing reduction in `DiagramLayoutLayering.swift`) is the only
   one that is super-linear in edge count, which is exactly why `maxEdges`
   (500) caps it at parse.

Parse is only ever visible for flowchart (~2 ms), whose grammar does the most
per-line tokenising; every other type parses in well under half a millisecond.

## Hotspots (function level)

Built release and sampled the worst fixture (sankey) rendering in a tight loop
with `sample`. The call graph is overwhelmingly one path:

```
CGImageForProposedRect  (rasterize the deferred NSImage)
  DiagramRenderer.draw(_:theme:in:)   DiagramRenderer+Sankey.swift:36
    CGContextDrawPath → ripc_DrawPath → RIPLayerBltShape
      RGBAf16_mark_constmask → vImageCGCompositeConstMask_ARGB16F
```

~75% of sankey's render time is a single call: `context.fillPath()` at
`DiagramRenderer+Sankey.swift:36`, filling the translucent flow ribbons (large
closed Bézier quads at alpha ~0.28). Two compounding facts make it expensive:

- **The bands are big and semi-transparent.** Each fill composites a large
  alpha-masked region; sankey draws one per link and they overlap.
- **The backing store is `RGBAf16` (64-bit half-float, wide gamut).** The hot
  leaf is `vImageCGCompositeConstMask_ARGB16F` — CoreGraphics is compositing in
  16-bit-float-per-channel extended-range color, ~4x the memory bandwidth of
  8-bit sRGB. The handler-backed `NSImage` picks up the display's deep color
  space by default; nothing in the diagram actually needs wide gamut.

Text is *not* the sankey bottleneck (CoreText was ~1% of samples). But sampling
a label-dense type (sequence) shows the second cost driver clearly: there the
time splits between the same f16 path compositing (`ARGB16F`, `aa_render`) and
CoreText — `CTLineCreateWithAttributedString` (`DiagramRenderer+Primitives.swift:45`,
inside `measure`) and glyph drawing (`CTFontDraw`/`render_glyphs` under
`drawText`, `DiagramRenderer+Primitives.swift:106`). Note that `measure` builds
a fresh `CTLine` on **every** call and caches nothing, and layout calls it once
per label while draw effectively measures again — the same string is typeset two
or more times per render.

So the two hot paths, in order:

1. **CGContext fills/strokes composited into an `RGBAf16` surface** — dominant
   for fill-heavy types (sankey above all).
2. **CoreText line creation + glyph rasterization** — dominant for
   label-dense types (sequence, class, state, requirement), and paid partly
   twice because measurement is uncached.

## Caching

Repeat renders are essentially free. `DiagramRenderer` keeps an in-memory
`NSCache` keyed by `(source, theme fingerprint, spacing fingerprint)`
(`DiagramRenderer.swift:52`, ~64 MB cost-bounded, evicts under memory
pressure). A `MermaidView` re-evaluated on every SwiftUI `body` pass hits the
cache and pays a dictionary lookup plus an `NSImage.copy()`, not a re-render.
The benchmark and the phase breakdown both bust this cache deliberately (a
run-unique `%%` comment per pass) to measure the cold cost — the numbers above
are all first-render, worst case. The Linux/Silica backend renders directly and
uncached; a host batching many diagrams there should cache the returned image.

## What to optimize (if anything)

Honest answer: **probably nothing, yet.** Every type renders cold inside
interactive time; the worst is a dense sankey at ~26 ms, and it renders once and
then caches. This is not a perf problem in any current use. If a host ever does
have a reason to shave the cold path, the data points at exactly three
candidates, in descending payoff:

1. **Render into an 8-bit sRGB bitmap context instead of the default f16 wide-gamut
   backing.** This is the single biggest lever for sankey (and helps every
   fill/stroke-heavy type), because the hot leaf is literally f16 compositing.
   Diagrams use flat theme tints — no wide-gamut content is lost. Worth a
   measurement spike before committing to it (it changes the rasterization
   surface, so visual output must be diffed).
2. **Memoize text measurement.** `measure` typesets a fresh `CTLine` per call
   and the same label string is measured at layout time and again at draw time.
   A small `(string, size, weight) → CGSize` cache would remove the redundant
   typesetting for label-dense types. Cheap, low-risk, self-contained.
3. **Nothing for parse or layout** — parse is sub-millisecond everywhere and
   architecture's ~9 ms layout is the only algorithmically interesting cost, on
   a type nobody renders in a hot loop. Not worth touching.

Rendering stays synchronous by design: at these times a first render in a
SwiftUI `body` is cheaper than a state round-trip, and every repeat hits the
cache. `MermaidRenderer.renderImage(...)` exists for hosts that want to batch
many cold renders off the main thread.
