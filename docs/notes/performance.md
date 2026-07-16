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

These figures are **rough, machine-specific, ±variance, and not a CI gate** —
per-type millisecond totals drift run-to-run (measured swings of tens of
percent), so read them as a shape, not a spec. This one table is the single
source of truth the README and site quote in noise-robust ranges.

| Diagram | Parse | Total | Diagram | Parse | Total |
|---|---:|---:|---|---:|---:|
| architecture | 0.37 | 14.6 | pie | 0.10 | 2.6 |
| block | 0.25 | 3.2 | quadrant | 0.17 | 3.7 |
| c4 | 0.28 | 7.1 | radar | 0.25 | 3.0 |
| class | 0.68 | 9.7 | requirement | 0.52 | 9.3 |
| cynefin | 0.16 | 2.5 | sankey | 0.18 | 24.8 |
| er | 0.31 | 7.2 | sequence | 0.43 | 9.2 |
| eventmodeling | 0.14 | 3.9 | state | 0.30 | 11.4 |
| flowchart | 1.92 | 12.5 | swimlane | 0.23 | 3.7 |
| gantt | 0.41 | 3.5 | timeline | 0.20 | 4.5 |
| gitgraph | 0.22 | 2.4 | treemap | 0.22 | 3.1 |
| ishikawa | 0.12 | 2.7 | treeview | 0.54 | 4.1 |
| journey | 0.20 | 4.7 | venn | 0.08 | 1.6 |
| kanban | 0.32 | 6.0 | wardley | 0.25 | 3.6 |
| mindmap | 0.32 | 7.2 | xychart | 0.17 | 1.8 |
| packet | 0.14 | 4.2 | zenuml | 0.26 | 6.6 |

All times in ms. Worst: sankey at ~25 ms. Most types land under ~15 ms, well
inside interactive headroom for the common case and comfortable even for the
worst. (A prior run had sankey at ~26 ms and a few types a millisecond or two
higher — that spread is the run-to-run variance, not a regression.)

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

## Shared pipeline / fixed overhead

The tables above are per-type. This section asks a different question: what does
the *fixed plumbing* cost — the piping every render pays regardless of diagram
type, before any real drawing happens? The shared path is
`MermaidRenderer.image` → `DiagramRenderer.attachmentString` → `renderPlan`
(parse + per-type layout, folded into one call) → `captionedPlan` → `paddedCanvas`
→ backing-store `NSImage` build → `attributedString(for:)` → forced rasterize.
A trivial `flowchart TD / A[X]` isolates that floor with essentially nothing to
draw. (Numbers below: M-series, debug test build — the release test target can't
link because a `#if DEBUG` capture hook is referenced by another test; the phase
breakdown above ran the same way, so these are consistent with it. Debug inflates
absolutes; the *fractions* are what matter.)

### 1. The fixed-overhead floor

Trivial 1-node flowchart, cold (cache busted per iteration), best of 400:

| phase | ms | note |
|---|---:|---|
| parse | 0.067 | full `MermaidParser.parse` |
| plan (layout + closures) | 0.057 | `renderPlan`: real layout engine + closure boxes |
| paddedCanvas | ~0.000 | value-type bounds union, no heap |
| build `NSImage` | 0.001 | handler-backed, draw closure is **deferred** |
| rasterize (the tiny draw) | 0.070 | forcing `cgImage` finally runs the draw closure |
| cache-key build + hash | 0.003 | trivial source; O(source length) |
| **end-to-end** (`image` + force raster) | **0.210** | |

The floor is ~**0.2 ms**. Of that, the *actual drawing* (rasterize) is ~0.07 ms
— **one third**. The other **two thirds** is fixed setup: parse, layout, and the
attachment/cache/image plumbing (the e2e number is ~0.015 ms above the summed
phases because the public path also re-scans metadata, inserts into the cache,
copies the `NSImage`, and builds an `NSTextAttachment` — see §3). In absolute
terms this floor is negligible; the point is only that for a *trivial* diagram
the piping dominates the draw, and for any *real* diagram the draw dominates the
piping (the per-type tables show rasterize is ~75% of a dense render). The plumbing
does not scale badly — it is a near-constant tax, not a multiplier.

### 2. Allocations per render

No Instruments trace was captured (the release test target won't link); this is
read from the code. One cold Apple render allocates, in rough order of bytes:

- **The rasterization backing store** — the single largest allocation, and it is
  `RGBAf16` (8 bytes/px, wide gamut) not 8-bit sRGB (see the Hotspots section).
  For the trivial floor it's tiny; for a dense diagram it's the dominant buffer.
- **The parse AST** and **the layout IR** (nodes, edges, point arrays) — both
  scale with diagram size and are inherent, not churn.
- A **fixed handful of small heap allocations** every render pays no matter what:
  the `measure` closure box, the `draw` closure box (captures the layout), the
  `edgePolylines` array from `.map`, the cache-key `String`/`NSString`, the
  `metadata(in:)` line-split (§3), the cache `Entry`, the **`NSImage.copy()`** in
  `attributedString(for:)`, and the `NSTextAttachment` + `NSAttributedString`.

Verdict on churn: the pipeline is **not** allocation-heavy in the plumbing. There
is no per-primitive temporary-array thrash in the shared path; the arrays that
exist are proportional to node/edge/label counts, which is unavoidable. The fixed
small allocations are a short, bounded list.

### 3. Redundant work in the shared path

Three confirmed redundancies, all shared:

1. **Text is typeset two or more times per label.** Layout calls
   `DiagramRenderer.measure` once per label; at draw time `drawLine` builds its
   own `CTLine` again for the same string. `measure`
   (`DiagramRenderer+Primitives.swift:26`) **caches nothing** — every call is a
   fresh `NSAttributedString` + `CTLineCreateWithAttributedString` +
   `CTLineGetTypographicBounds`. Measured cost ~**6.3 µs/call** in debug (~2–3 µs
   release). For a label-dense type (sequence, class, state, requirement) with
   dozens of labels, the redundant typeset is on the order of 0.1–0.3 ms — small,
   but it is exactly the CoreText slice the Hotspots section sees paid twice.
   *(In DEBUG the capture hook adds a third `measure` call per drawn block, but
   that is test-only and not shipped.)*

2. **The source is scanned for metadata twice.** `MermaidParser.parse` already
   strips front-matter internally, yet `captionedPlan` calls
   `MermaidParser.metadata(in:)` again — a full `source.split("\n")` plus a
   per-line trim/keyword scan (`MermaidParser+Metadata.swift:50`) — on every
   render, just to recover the `title:`. Cost is O(source length): a rounding
   error for small sources, a real second full-string pass for a 50 KB source.
   The parse already had this metadata in hand; threading it through would delete
   the second scan.

3. **The cache key rebuilds and rehashes the whole source string every call.**
   The key is `"mermaid|\(theme.fingerprint)|\(spacing.fingerprint)|\(source)"`
   (`DiagramRenderer.swift:293`). The `theme.fingerprint` is precomputed once at
   theme init (cheap — not recomputed per render), and `spacing.fingerprint` is a
   tiny formatted string. But the key **interpolates the full source** and
   `NSCache` then hashes that whole `NSString` — an O(source length) build + hash
   paid on **every** call including cache *hits* (each SwiftUI `body` pass). Plus
   a cache hit also `NSImage.copy()`s the rendered image. For big sources these
   are the only non-trivial costs on the hot re-render path.

`DiagramScene.lower` is **not** on the render path — `renderPlan` calls
`DiagramLayoutEngine.layout` directly and draws from the layout; `lower` is the
IR/linter path (it does rebuild `DiagramScene` structs to append a title label,
but that copy never runs during a render). And there is **no** double parse or
double layout on the raster path: parse runs once, layout runs once (deferred
inside the draw closure), and the draw closure runs once at rasterize. (The
"build re-parses/re-lays-out" note earlier was a *measurement* artifact of a
throwaway harness that called `image()` as a separate phase after already doing
parse+layout — not something a single real render does.)

### 4. ARC / retain-release

No release-build time-profile was captured for the shared path specifically (the
prior function-level profile sampled the draw-dominated sankey path and did not
show `swift_retain`/`release` or ObjC bridging as material — the leaves were
`vImage…ARGB16F` compositing and CoreText). The shared plumbing does cross into
ObjC (`NSCache`, `NSString`, `NSImage`, `NSAttributedString`) and boxes two
closures per render, but at a ~0.2 ms floor none of this is a measurable fraction
of any real render. ARC is not a shared-path bottleneck.

### Verdict: is the shared pipeline as performant as possible?

**Essentially yes — the plumbing is lean, and the only real cost is the
unavoidable CoreGraphics drawing.** The fixed floor is ~0.2 ms; two-thirds of
*that* is setup, but 0.2 ms is nothing, and it is a near-constant tax rather than
something that scales with diagram size. Every non-trivial render is dominated by
rasterization (~75%), which is genuine drawing work, not piping.

There is a little slack, all small. In priority order (payoff / risk):

1. **Render into an 8-bit sRGB bitmap context instead of the default `RGBAf16`
   wide-gamut backing.** *Shared* (every render allocates this backing store) and
   the single biggest lever — the hot compositing leaf is literally f16. Payoff:
   up to ~2–4× on fill/stroke-bound types (sankey above all), a smaller win
   everywhere. Risk: it changes the rasterization surface, so visual output must
   be diffed; diagrams use flat theme tints, so no wide-gamut content is at stake.
   (This is the raster *surface*, arguably one layer below "piping," but it is
   shared by every type and is where the bytes and bandwidth go.)
2. **Memoize text measurement** with a shared `(string, size, weight) → CTLine`
   (or `→ CGSize`) cache serving both `measure` and `drawLine`. Removes the
   redundant typeset. Payoff: modest, meaningful for label-dense types (~5–15% of
   their total). Risk: low, self-contained.
3. **Thread parsed metadata through instead of re-scanning.** `captionedPlan`'s
   second `metadata(in:)` full-source pass is deletable by carrying the title the
   parser already extracted. Payoff: negligible for small sources, O(n) so real
   for large ones. Risk: low.
4. **Cheaper cache key / avoid the per-hit copy.** Hash the source once (or key on
   a digest) and reconsider the `NSImage.copy()` on hit. Payoff: low, only helps
   very large sources re-rendered every `body` pass. Risk: low but touches
   correctness-sensitive cache identity — least worth it.
5. **Allocation reduction** — not worth chasing. The plumbing's fixed allocations
   are a short bounded list; the rest is proportional to diagram size.

None of these is urgent. At current times nothing here is a perf problem in any
real use; this section is the receipts for saying so.
