# Render performance: where the milliseconds go

Perf memo, last revised 2026-07-15. Machine: **Apple M1 Max**, macOS 26.5.
Every number here is machine-specific and best-of-N cold — it is **not** a CI
threshold. MermaidKit's test suite asserts correctness only; timing gates flake
under CI load, so nothing here gates a merge. Numbers over adjectives: this memo
is the receipts behind the README's "under 25 ms" claim, an honest read on
whether any of it is worth touching, and — as of this revision — the record of
three shared-pipeline redundancies removed and one backing-store lever
**evaluated and rejected on measurement** (see *Fixable vs irreducible*).

## Methodology

**Harness.** The end-to-end harness is `RenderBenchmarks`
(`Tests/MermaidRenderTests/RenderBenchmarks.swift`). By default it is a
*correctness* smoke — every fixture in `Fixtures/diagrams/` must parse, render,
and rasterize. It forces `cgImage(forProposedRect:…)`, because a handler-backed
`NSImage` defers its drawing until first use and would otherwise flatter the
numbers. It makes **no wall-clock assertion**. Timing is opt-in:

```
BENCH_TABLE=1 swift test --filter RenderBenchmarks 2>&1 | grep '^BENCH'
```

That measures parse-ms and total-ms (parse → layout → render → rasterize).

**Build.** Debug vs release matters. The per-type table and phase breakdown run
under the normal (debug) test build; the function-level profile was taken from a
`-c release` build. Debug inflates absolute times (roughly 2–3× on the
CoreText-bound slices); the *fractions* and the *shape* carry over, which is what
the memo trades on. One tooling wart worth recording: the release **test target**
won't link, because a `#if DEBUG` capture hook (the draw-vs-scene conformance
hook, `DiagramRenderer.textCaptureHook`) is referenced by another test — so an
Instruments **Allocations** trace of the release test path was never captured,
and the allocation notes below are read from the code, not from a trace.

**Best-of-N.** Reported figures are best-of-3 (per-type table) or best-of-5/7
(phase and backing-store spikes) with the first round discarded as warmup. Cold
cost is what we want, so **the cache is busted every pass** with a run-unique
`%%` comment appended to the source — every sample is a true parse + layout +
render, never a cache hit.

**Round-robin sampling.** The harness samples every type once per round, then
takes the best across rounds — it does **not** run one type N times back to
back. Consecutive per-type sampling biased later types with accumulated heat: a
measured ~2× swing on the same fixture (23 ms isolated vs 45 ms mid-suite).
Round-robin spreads the heat evenly so the between-type comparison is fair.

**Phase breakdown.** To split a render into parse / layout / build / rasterize,
a throwaway harness (deleted after measuring) timed the four calls separately per
fixture. Note that `build` (`MermaidRenderer.image`) returns a handler-backed
`NSImage` whose draw closure is *deferred*; timing it as a separate phase
re-runs parse+layout internally, so that column double-counts and is not
additive — the honest phases are parse, layout, and rasterize (the forced
`cgImage`).

**Profiling.** Hotspots came from a release build sampled with `sample` while
rendering the worst fixture (sankey) in a tight loop, reading the call graph down
to the leaf. Caveats: `sample` is a statistical profiler (leaves under ~1% are
noise), and the release **test** target's link failure above blocked the
Instruments Allocations trace, so allocation claims are static reads.

**Why ranges, not fixed figures.** Per-type totals drift run-to-run by tens of
percent — thermal state, other processes, allocator warmth. The tables below are
a **shape**, not a spec. Where two runs of the same build disagree by a
millisecond or two, that is variance, not signal; treat every number as ±.

## Current numbers

Cold parse → layout → render → rasterize, best of 3, M1 Max, post-fix (the three
shared-pipeline fixes below are output-identical, so they don't move this table
beyond noise). "Parse" is the `MermaidParser.parse` slice of the same run.

These figures are **rough, machine-specific, ±variance, and not a CI gate** —
read them as a shape. This one table is the single source of truth the README and
site quote in noise-robust ranges.

| Diagram | Parse | Total | Diagram | Parse | Total |
|---|---:|---:|---|---:|---:|
| architecture | 0.34 | 14.5 | pie | 0.10 | 1.9 |
| block | 0.24 | 3.1 | quadrant | 0.19 | 3.1 |
| c4 | 0.27 | 6.0 | radar | 0.23 | 2.5 |
| class | 0.67 | 8.8 | requirement | 0.47 | 7.3 |
| cynefin | 0.14 | 2.5 | sankey | 0.17 | 23.1 |
| er | 0.30 | 6.4 | sequence | 0.43 | 8.2 |
| eventmodeling | 0.18 | 3.7 | state | 0.31 | 11.1 |
| flowchart | 2.01 | 10.8 | swimlane | 0.23 | 3.0 |
| gantt | 0.40 | 2.6 | timeline | 0.17 | 3.7 |
| gitgraph | 0.22 | 2.0 | treemap | 0.21 | 2.6 |
| ishikawa | 0.13 | 2.3 | treeview | 0.54 | 3.4 |
| journey | 0.21 | 3.4 | venn | 0.09 | 1.7 |
| kanban | 0.31 | 4.5 | wardley | 0.27 | 3.2 |
| mindmap | 0.32 | 7.4 | xychart | 0.17 | 1.8 |
| packet | 0.14 | 3.1 | zenuml | 0.26 | 5.4 |

All times in ms. Worst: **sankey at ~25 ms** (23–25 across runs). **Most types
land under ~15 ms**, well inside interactive headroom for the common case and
comfortable even for the worst. **Parse is sub-millisecond** for every type
except flowchart (~2 ms, the densest grammar). These are the dense per-type
fixtures in this repo; real-world diagrams are usually smaller and faster.

## Where the time goes

Summing the per-fixture phase breakdown across all 30 fixtures: **parse 9.9 ms,
layout 36.1 ms, rasterize 152.6 ms**. The verdict is unambiguous: **drawing
dominates**. Rasterization is ~three-quarters of every cold render; parse is
noise; layout matters for a handful of types.

Per-type standouts (parse / layout / rasterize, ms):

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
   `DiagramLayoutArchitecture.swift`) rather than a single pass. Flowchart,
   sankey, and state are the next heaviest layouts (~3 ms) — flowchart's layered
   layout (network-simplex ranking + crossing reduction) is the only one that is
   **super-linear in edge count**, which is why `maxEdges` (500) caps it at parse.

### The fixed-overhead floor

The tables above are per-type. A different question: what does the *fixed
plumbing* cost — the piping every render pays before any real drawing? A trivial
`flowchart TD / A[X]` isolates that floor. (M-series, debug build, cold, cache
busted per iteration, best of 400.)

| phase | ms | note |
|---|---:|---|
| parse | 0.067 | full `MermaidParser.parse` |
| plan (layout + closures) | 0.057 | real layout engine + closure boxes |
| paddedCanvas | ~0.000 | value-type bounds union, no heap |
| build `NSImage` | 0.001 | handler-backed, draw closure is **deferred** |
| rasterize (the tiny draw) | 0.070 | forcing `cgImage` runs the draw closure |
| cache-key build + hash | 0.003 | O(source length) |
| **end-to-end** | **0.210** | |

The floor is ~**0.21 ms**, and it is **near-constant** — a fixed tax, not a
multiplier. For a *trivial* diagram the piping dominates the draw (rasterize is
one third of 0.21 ms); for any *real* diagram the draw dominates the piping
(rasterize is ~75% of a dense render). The plumbing does not scale badly.

### Allocations

No Instruments trace (the release test target won't link — see Methodology);
this is read from the code. In rough order of bytes:

- **The rasterization backing store** — the single largest allocation. It is
  `RGBAf16` (8 bytes/px, wide gamut), not 8-bit sRGB — the display's deep color
  space, picked up by the handler-backed `NSImage`. Tiny for the trivial floor,
  the dominant buffer for a dense diagram. (This is the buffer the rejected sRGB
  lever below would have shrunk — see *Fixable vs irreducible*.)
- **The parse AST** and **the layout IR** — both scale with diagram size and are
  inherent, not churn.
- A **short, bounded handful of small heap allocations** every render pays: two
  closure boxes (`measure`, `draw`), the `edgePolylines` array, the cache
  `Entry`, the `NSTextAttachment` + `NSAttributedString`, and the per-hit
  `NSImage.copy()`.

Verdict on churn: the pipeline is **not** allocation-heavy in the plumbing.
There's no per-primitive temporary-array thrash; the arrays that exist are
proportional to node/edge/label counts, which is unavoidable.

## Hotspots (function level)

Built release and sampled sankey (the worst fixture) in a tight loop. The call
graph is overwhelmingly one path:

```
CGImageForProposedRect  (rasterize the deferred NSImage)
  DiagramRenderer.draw(_:theme:in:)   DiagramRenderer+Sankey.swift:36
    CGContextDrawPath → ripc_DrawPath → RIPLayerBltShape
      RGBAf16_mark_constmask → vImageCGCompositeConstMask_ARGB16F
```

~75% of sankey's render is a single call: `context.fillPath()`, filling the
translucent flow ribbons (large closed Bézier quads at alpha ~0.28). The bands
are big and semi-transparent, and sankey draws one per link with overlap — each
fill composites a large alpha-masked region. The hot leaf is
`vImageCGCompositeConstMask_ARGB16F`: CoreGraphics compositing in 16-bit-float
extended-range color.

Text is *not* the sankey bottleneck (CoreText was ~1% of samples). But sampling
a label-dense type (sequence) shows the second driver: time splits between the
same f16 path compositing and CoreText — `CTLineCreateWithAttributedString`
(inside `measure`) and glyph drawing (`CTFontDraw`/`render_glyphs` under
`drawText`).

So the two hot paths, in order:

1. **CGContext fills/strokes composited into the `RGBAf16` surface** — dominant
   for fill-heavy types (sankey above all).
2. **CoreText line creation + glyph rasterization** — dominant for label-dense
   types (sequence, class, state, requirement).

## Caching

Repeat renders are essentially free. `DiagramRenderer` keeps an in-memory
`NSCache` keyed by **(source, theme fingerprint, spacing fingerprint)** (~64 MB
cost-bounded, evicts under memory pressure). A `MermaidView` re-evaluated on
every SwiftUI `body` pass hits the cache and pays a dictionary lookup plus an
`NSImage.copy()`, not a re-render. The benchmark and the phase breakdown both
bust this cache deliberately (a run-unique `%%` comment) to measure the cold cost
— the numbers above are all first-render, worst case. The Linux/Silica backend
renders directly and uncached; a host batching many diagrams there should cache
the returned image itself.

## Fixable vs irreducible

The honest framing. Two columns: what can't be cheaper, and what was slack.

### Irreducible — this is the real work

- **Rasterization is genuine drawing.** ~75% of every non-trivial render is
  CoreGraphics filling/stroking paths and CoreText drawing glyphs. There is no
  algorithm to remove; the cost is the primitive count, and the primitive count
  is the diagram.
- **Parse and layout scale with diagram size.** The AST and the layout IR are
  proportional to nodes/edges/labels. Inherent.
- **The first typeset of each unique label** must build a `CTLine`. The memo
  below removes the *redundant* typesets, not the first one.
- **Flowchart's layered layout is super-linear in edge count** (network-simplex
  ranking + crossing reduction). Capped at parse by `maxEdges` = 500, not
  optimized away.
- **Measurement variance** — tens of percent run-to-run. Not a cost, but a floor
  on how precisely any of this can be quoted.

### Slack that was removed (three output-identical fixes — **done, on `main`**)

All three keep rendering **byte-identical**. Verified same-process (per issue
#1, cross-process f16 rasterization is nondeterministic, so the check must run in
one process): the dense fixtures were rendered with each fix bypassed vs applied
and the rasterized pixels diffed to zero; the full suite, the draw-vs-scene
conformance ratchet, and LayoutLint stay green. They don't show up as a headline
speedup — rasterization dominates, so trimming these sub-slices lands inside
run-to-run variance — but they delete real redundant work, worst for large
sources.

1. **Memoized text measurement.** `measureLine` built a fresh `CTLine` on every
   call; layout measures each label and the multi-line draw path measures again
   for line heights, so the same string was typeset for measurement two-plus
   times per render. An `NSCache` keyed by `(string, size, weight)` turns the
   repeats into a dictionary hit. The system font is deterministic, so a cached
   `CGSize` is bit-identical to a fresh `CTLineGetTypographicBounds`.
2. **Deduped the metadata double-scan.** `parse` already stripped/parsed
   front-matter, yet `captionedPlan` re-ran `metadata(in:)` (a full
   `source.split` + per-line scan) on every render just to recover `title:` —
   O(source length), a second full pass for a large source. Added
   `parseWithMetadata`, which returns the metadata the same pass extracted, and
   threaded the title into `captionedPlan`. One scan, not two.
3. **Cheaper cache key.** The key interpolated the whole source into a fresh
   `"mermaid|…|<source>"` `NSString` every call — an O(source length) allocation
   + hash paid even on cache *hits* (each `body` pass). Replaced with a
   `RenderKey` that keeps the source by reference (copy-on-write, no copy),
   precomputes the hash once, and compares fields in `isEqual:` — identical
   hit/miss semantics, no per-call concatenation. The per-hit `NSImage.copy()` is
   left as-is: it's a cheap, correctness-critical guard (NSImage is mutable;
   handing out the cache's own instance lets a caller's `image.size = …` poison
   every future hit).

### The one lever under evaluation — **rejected on measurement**

The prior revision of this memo ranked **rendering into an 8-bit sRGB bitmap
context instead of the f16 wide-gamut backing** as the single biggest lever,
reasoning that the hot leaf is literally f16 compositing (~4× the bandwidth of
8-bit sRGB) so a narrower surface should be ~2–4× faster on sankey. That was a
hypothesis from reading the sampled leaf. It was implemented and measured on
branch `perf/srgb-backing` (draft PR:
<https://github.com/2389-research/MermaidKit/pull/3>), and **the hypothesis does
not survive measurement.**

Direct raster into each surface (M1 Max, same process, best-of-7, cache-busted).
`sRGB8 / P3-f16` > 1.0 means 8-bit sRGB is **slower**:

| fixture | P3-f16 ms | ext-f16 ms | sRGB8 ms | sRGB8 / P3-f16 |
|---|---:|---:|---:|---:|
| sankey | 19.40 | 18.53 | 42.55 | **2.19× slower** |
| sequence | 5.93 | 6.28 | 12.05 | **2.03× slower** |
| timeline | 3.49 | 3.57 | 5.01 | 1.44× |
| architecture | 4.84 | 4.39 | 5.97 | 1.23× |
| requirement | 5.98 | 5.99 | 7.04 | 1.18× |
| flowchart | 6.15 | 6.06 | 6.51 | 1.06× |
| class | 5.68 | 6.03 | 5.88 | 1.03× |
| er | 4.86 | 4.79 | 4.28 | 0.88× |
| mindmap | 5.68 | 6.00 | 4.88 | 0.86× |
| pie | 1.25 | 1.40 | 0.88 | 0.71× |

The types the change was meant to help most — sankey and sequence, the big
translucent alpha composites — are **~2× slower** under 8-bit sRGB. CoreGraphics'
f16 `ARGB16F` path is evidently the *optimized* one for large alpha-masked
composites on Apple silicon; "fewer bytes ⇒ faster" simply did not hold. The
full `image()` path shows the same regression (BENCH sankey ~46 ms sRGB vs ~23 ms
f16).

And it isn't free on fidelity. All-30-fixture pixel diff, same process, both
surfaces normalized to an 8-bit sRGB display raster:

| reference | worst maxΔ (0–255) | avg meanΔ |
|---|---:|---:|
| vs Display-P3 f16 (gamut + P3-space compositing) | 33 (journey) | 0.090 |
| vs extended-sRGB f16 (pure bit-depth) | 5 (requirement) | 0.064 |

No flat fill region changes; the delta lives on antialiased/alpha edges. Pure
bit-depth (f16→8) costs ≤5/255 — imperceptible; the larger P3 numbers come from
compositing in P3 space vs sRGB space. So the swap is **not** byte-identical: it
loses wide gamut (fine for today's flat sRGB tints, a real loss if a host themes
with P3) for a small edge delta — **and buys no speed.**

**Verdict on the lever: reject.** No speedup (a net slowdown where it counts), a
fidelity/gamut trade, zero upside. The branch and PR stand as the receipts; `main`
keeps the f16 default. This is exactly why the memo insists on measurement over
inference: the most-promising-on-paper optimization was net-negative in practice.

### Not worth chasing

- **Parse / layout micro-opt** — parse is sub-millisecond everywhere;
  architecture's ~9 ms layout is the only algorithmically interesting cost, on a
  type nobody renders in a hot loop.
- **Allocation reduction** — the plumbing's fixed allocations are a short bounded
  list; the rest is proportional to diagram size.
- **ARC / retain-release** — the release profile showed no `swift_retain`/
  `release` or ObjC bridging as material; the leaves were f16 compositing and
  CoreText. At a ~0.21 ms floor none of the plumbing's ObjC crossings register.

## Verdict

**Performance is not a problem.** Every type renders cold inside interactive
time; the worst is a dense sankey at ~25 ms, and it renders once and then caches.
The plumbing is lean — a ~0.21 ms near-constant floor, no allocation thrash, no
double parse or double layout on the raster path — and the only real cost is the
unavoidable CoreGraphics drawing, which is genuine work, not piping.

Three output-identical redundancies were removed (done, on `main`); one
backing-store lever was evaluated and **rejected on measurement** (draft PR #3).
The remaining levers, if a host ever truly needs the cold path faster, are the
irreducible ones — and those you pay because they are the drawing. Rendering
stays synchronous by design: at these times a first render in a SwiftUI `body` is
cheaper than a state round-trip, and every repeat hits the cache.
`MermaidRenderer.renderImage(...)` exists for hosts that want to batch many cold
renders off the main thread.
