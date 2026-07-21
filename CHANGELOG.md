# Changelog

## 2.2.0 — Any source format, inline and narrated

Format-aware entry points, so a rich-text host (a live editor, a document view)
gets the same sized, themed `NSAttributedString` attachment **and** accessibility
narration for *every* supported source format — not just Mermaid — without ever
touching the parsers.

- **Format-aware `MermaidRenderer` API.** A new `DiagramSourceFormat`
  (`.mermaid`, `.dot`, `.dippin`, `.sqlDDL`, `.gitLog`) drives format-aware
  `image` / `pngData` / `attachmentString` / `altText(source:format:)`, plus
  diagram-based twins.
  DOT, Dippin, SQL DDL and git-log sources now render inline and narrate exactly
  like Mermaid. (#46, #47)
- Non-Mermaid formats ride the **same NSCache path** as Mermaid — keyed by
  format tag + source so same-text DOT and Mermaid can't collide — so a live
  editor doesn't re-parse and re-render on every keystroke.

### Fixed

- **Arrowheads over tinted group boxes** (C4, architecture, block) no longer show
  a pale canvas-colored **wedge**. The head is now a single opaque triangle
  rather than a translucent head painted over a canvas-colored shaft-eraser —
  which removes both the seam the eraser prevented and the wedge it caused. Both
  render paths (CoreGraphics + the platform-free `RenderScene`) change in lockstep
  so the draw-vs-scene conformance ratchet still holds. (#23)

### Docs

- The architecture/pipeline diagrams in the platform notes and package READMEs
  are now **Mermaid** (` ```mermaid ` — rendered natively by GitHub, and by
  MermaidKit itself), replacing the ASCII-art code fences. MermaidKit now
  dogfoods its own renderer in its docs. (#49)

## 2.1.0 — Flutter, and any bare surface

A sixth native platform (**Flutter**) and the raw-raster primitive that drives
**any bare surface** — a Raspberry Pi framebuffer, an SDL2 window, a GPU texture.
Additive; existing platforms and output are unchanged.

- **Flutter** (`flutter/mermaidkit`) renders all 30 types with a Dart
  `CustomPainter` on Flutter's Skia/Impeller canvas — a fidelity match for the
  Android backend, and one plugin reaches iOS, Android, web, and desktop:
  - A `SceneWire` Dart model (sealed classes + a `type` discriminator) and
    `MermaidPainter` / `MermaidDiagram`.
  - A **`dart:ffi` bridge** (`MermaidNative`) over `mmk_scene_json` in the Swift
    core built as a shared library, so an app passes a Mermaid *source string*:
    `MermaidNative.scene("flowchart LR\n A --> B")`. The Flutter analogue of
    Android's JNI and .NET's P/Invoke — `dart:ffi` calls the `@_cdecl` C ABI
    directly.
  - Optional `fontFamily` for bundled/custom label fonts.
- **Raw raster on Linux.** `MermaidRenderer.rgbaRaster` — previously Apple-only —
  now returns raw RGBA pixels on Linux too, reading the Cairo (Silica) image
  surface directly. This is the primitive every display-server-free surface needs
  (a PNG isn't enough): framebuffers, SDL, GPU upload.
- **`tools/pi-canvas`** — a demo/proof: an infinite, pannable canvas of diagrams
  composited into a 640×480 framebuffer, over the raw raster with no display
  server. A single `Framebuffer` seam with three backends — a PNG stand-in,
  `/dev/fb0` (RGB565), and **SDL2** (streaming texture) — verified on the Pi's
  aarch64 architecture with the Silica/Cairo raster.
- A `MermaidKitCShared` dynamic product already existed (the Windows DLL); it now
  also backs the Flutter `dart:ffi` bridge and any P/Invoke-style consumer.

## 2.0.0 — Native everywhere

MermaidKit renders natively on **five platforms** — macOS/iOS, Linux, **Android**,
**Windows/.NET**, and **WebAssembly** — from one Swift layout core. The Swift
package's public API is **additive** (no breaking changes); the major bump marks
the platform expansion. Android, Windows, and .NET ship as their own `0.1.0`
artifacts.

- **Native Android rendering.** The [`android/`](android/) Gradle module renders
  all 30 diagram types with a Kotlin `Canvas`:
  - A `SceneWire` Kotlin model (plain `@Serializable`) + a `SceneRenderer` (Skia
    `Canvas`) that draws the platform-free scene the core emits.
  - A **JNI bridge** — `MermaidNative` over a per-ABI `libmermaidkit.so` (the
    Swift core + a C shim, built by `android/native/build-jni.sh`) — so an app
    passes a Mermaid *source string*: `MermaidDiagram("…", Modifier.fillMaxWidth())`.
  - The **device measure seam** (`Paint.measureText` threaded through JNI, so
    layout measures with the face that draws), **Material theming**
    (`MermaidTheme.fromMaterial(MaterialTheme.colorScheme)`, default), a Compose
    `MermaidDiagram` + classic `MermaidView`, and `contentDescription` from the
    narration.
  - A release **AAR** bundling stripped `.so` for arm64-v8a, armeabi-v7a, and
    x86_64; verified end-to-end on an android-34 emulator in CI.
- **Native Windows / .NET rendering.** The [`windows/`](windows/) .NET library
  renders with **SkiaSharp** (real Skia — the same engine as Android, a fidelity
  match; no SVG fallback): a `SceneWire` model, a `SceneRenderer` over `SKCanvas`,
  and a **P/Invoke bridge** (`MermaidNative` over a Swift-built
  `MermaidKitCShared.dll`) so a .NET app goes from a source string to a Skia
  diagram. Gated on `windows-latest` in CI.
- **WebAssembly.** The platform-free core compiles to `wasm32-unknown-wasi` and
  emits SVG (or a Canvas2D scene) in the browser.
- **Cross-platform conformance — proven byte-identical.** A new conformance
  harness (`tools/conformance`) + CI gate (`conformance.yml`) run the same
  fixtures through the core on macOS, Linux, Android, WASM, and Windows and assert
  one signature. Reaching byte-identity caught and fixed two real determinism bugs:
  - `JSONEncoder` serializes `Double`s differently across Foundation
    implementations (Darwin's shortest round-trip vs swift-corelibs' full
    precision) — `SceneWire` now **quantizes coordinates to an exact 1/256 grid**
    (sub-pixel; SVG unaffected) so the wire JSON is identical everywhere.
  - Pie arc tessellation used `ceil(sweep / (π/8))`, which flipped the segment
    count on a 1-ULP `sin`/`cos` difference (WASM's math lib vs glibc/Darwin) —
    fixed with an epsilon before the `ceil`.
- **C ABI additions** (`MermaidKitC`, still `MermaidLayout`-only):
  - `mmk_scene_json_themed(source, theme_json, measure, userdata)` — theme a scene
    with explicit caller colors via the new **`ThemeWire`** JSON, instead of a
    built-in preset.
  - A dynamic **`MermaidKitCShared`** product (the C ABI as a shared library — the
    Windows DLL the .NET bridge P/Invokes).
  - WASI portability: `TerminalCapabilities` guards its termios/tty paths for
    WebAssembly; libc imports guard for Bionic/Android.

## 1.4.0

A platform-free render IR with SVG output, and a fifth input front-end. Additive;
the rendered output of existing diagrams is unchanged.

- **SVG export.** `MermaidRenderer.svg(source:theme:)` renders **any of the 30
  diagram types** to a standalone SVG document — with **no CoreGraphics**. It goes
  through a new public, platform-free render IR:
  - **`RenderScene`** (`MermaidLayout`) — a `Codable` display list that fully
    determines the picture (shaped nodes, arrowed/dashed edges, text, containers,
    canvas), lowered from every diagram type. `MermaidRenderer.renderScene(source:theme:)`
    builds it; `SVGRenderer.svg(_:)` paints it. This is the foundation for the
    planned native Android renderer and a plugin/interchange contract (see
    `docs/notes/android.md`).
  - Cross-process determinism is CI-gated for the RenderScene/SVG pipeline as well
    as the raster path — the same source serializes byte-identically across
    process launches (the wire-format guarantee those consumers need).
- **New front-end: `git log` → gitgraph.** `GitLogParser.parse(_:)` turns
  `git log` output into the `GitGraph` IR — a fifth input front-end after Mermaid,
  DOT, Dippin, and SQL. Two-pass topological ordering, branch-lane derivation from
  ref decorations, and `--format gitlog` in `mermaidkit-term`.
- **Docs.** An Android support plan (`docs/notes/android.md`) and a development
  approach memo (`docs/notes/development-approach.md`).

## 1.3.0

Three new capabilities on the front/back-end seam — all additive; the rendered
output of existing diagrams is unchanged.

- **DOT export.** `DOTExporter.export(_:)` emits a `Flowchart` as Graphviz DOT —
  the inverse of the DOT front-end, so MermaidKit is now a **Mermaid ⇄ DOT
  converter**. Flat charts round-trip exactly (`parse(export(chart)) == chart`);
  clustered charts round-trip structurally. Also `export(_ diagram:) -> String?`
  for the diagram union.
- **SQL DDL → ER front-end.** `SQLDDLParser.parse(_:)` turns a `CREATE TABLE`
  schema dump into the `ERDiagram` IR: typed columns, `PRIMARY`/`FOREIGN`/`UNIQUE`
  keys (inline and table-level), and `REFERENCES` mapped to one-to-many crow's-foot
  relationships. Handles dialect quoting (`"x"`, `` `x` ``, `[x]`) and comments;
  ignores unknown clauses; degrades to `nil` on malformed/huge input.
  - **New:** `ERDiagram.Attribute.keys: [Key]` (`.primary`/`.foreign`/`.unique`),
    rendered as a compact `PK`/`FK`/`UK` badge in the entity box. The field has a
    defaulted initializer and the badge is a no-op when empty, so existing
    `erDiagram` rendering and all `Attribute(type:name:)` call sites are unchanged.
- **Diagram narration.** `MermaidAltText.narrate(_:)` gives a step-by-step
  accessibility *walkthrough* (a richer companion to `describe`'s one-line
  summary): it follows a flowchart's edges through its decisions, reads a state
  machine from its initial state, spells out an ER schema's cardinalities, and
  replays a sequence message by message; every other type falls back to
  `describe`. Deterministic and length-bounded. Mirrors `describe`'s API
  (`narrate(_:)`, `narrate(_:metadata:)`, `narrate(source:)`).
- **Docs.** Design memos on how the project is built (`development-approach.md`)
  and a runtime-plugin extensibility sketch (`plugin-extensibility.md`).

## 1.2.0

Two new front-ends, a terminal renderer, and a layout-quality pass. Additive to
the public API; the rendered output of the layered/graph families changes (for
the better), so gallery images are regenerated to match.

- **New front-ends: Graphviz DOT and Dippin.** `DOTParser.parse(_:)` and
  `DippinParser.parse(_:)` turn a `.dot` or `.dip` source into MermaidKit's
  `Flowchart` IR, so any DOT/Dippin file renders through the same layout and
  every backend (CoreGraphics/CoreText on Apple, Silica/Cairo on Linux, and the
  terminal). The DOT parser handles subgraphs/clusters, attribute defaults,
  `dir=back`, and shape mapping; the Dippin parser maps its eight node kinds
  (agent, tool, human, conditional, parallel, fan_in, subgraph, manager_loop)
  to shapes and collapses simple `when` equalities to concise edge labels.
- **New: render an already-parsed diagram.** `MermaidRenderer.pngData(diagram:)`,
  `image(diagram:)`, and `rgbaRaster(diagram:)` render a `MermaidDiagram` without
  re-serializing to Mermaid text — the path the front-ends use. `rgbaRaster`
  bounds `targetWidth` (and the derived height) to `maxRasterDimension` and
  rejects non-finite/oversized requests before allocating.
- **New shapes:** `NodeShape.hexagon` and `.subroutine`.
- **Terminal rendering (experimental).** A new `mermaidkit-term` CLI renders any
  Mermaid/DOT/Dippin source in the terminal, picking the best tier the terminal
  answers to: Kitty graphics (real image) → half-block truecolor (1×2 color
  pixels) → colored box-drawing → plain ASCII, with OSC 11 background detection
  and capability probing. Platform-free (lives in `MermaidLayout`), so it runs
  headless on Linux/CI.
- **Layout: edge labels and back-edges.** Flowchart (and the shared state /
  swimlane / ER / class families) now center edge labels on the arrow-free run
  midpoint and reserve enough connector length to clear a minimum visible stub,
  stagger crowded parallel captions, route back-edges up a gutter, and
  straighten needless jogs; fan-out edges sharing a source spread onto distinct
  tracks. New geometry-linter rules ratchet all of this: `label-on-fixture`,
  `label-crowds-edge`, and `edges-doubled`. Gallery/website images for the
  affected families are regenerated; all others render pixel-identical.

## 1.1.0

Performance and metadata refinements — additive and output-identical. The public
API and layout are unchanged except for one new convenience method.

- **New: `MermaidParser.parseWithMetadata(_:)`** — parse a source and get the
  extracted YAML front-matter (`title`, `accTitle`, `accDescr`) back in one call
  as `(diagram, DiagramMetadata)`, avoiding a second scan over the source.
- **Perf: shared-pipeline fixes** — rendered output is byte-identical (verified
  against the draw-vs-scene conformance ratchet): text measurement is now
  memoized, so each label is typeset once instead of at both layout and draw;
  the render cache key hashes the source once and keys by reference rather than
  rebuilding an interpolated string on every call.
- The one profiled optimization that *didn't* pan out — an 8-bit sRGB render
  backing store — was measured ~2× slower than the f16 default on Apple silicon
  and rejected; kept as a documented negative result.
- **Docs**: a full performance memo (`docs/notes/performance.md`) with
  methodology, per-type numbers, and where the time goes; a
  terminal-rendering-capabilities note; and the coverage audit reconciled
  against 1.0. Project site: https://2389-research.github.io/MermaidKit/

## 1.0.0

Stable release. The public API is frozen: the entry points (`MermaidParser`,
`DiagramLayoutEngine`, `DiagramScene`, `DiagramLayoutLinter`, `MermaidRenderer`,
`MermaidView`, `DiagramTheme`) are stable, and from here model/layout field
changes are semver-major.

What 1.0 is: **30 diagram types** parsed, laid out, and rendered natively —
CoreGraphics/CoreText on Apple, Silica/Cairo on Linux (behind the `LinuxRaster`
trait) — with no JavaScript and no WebView. Layout quality is machine-checked
by a geometry linter and a draw-vs-scene conformance ratchet in CI; the package
is cleanly `from:`-consumable on every platform (Silica-free by default).

- **Line breaks in labels.** `<br>` in every form (`<br>`, `<br/>`, `<br />`,
  case-insensitive, with attributes) plus a literal `\n` and any real newline
  break box/node labels and sequence notes onto multiple lines (the box grows);
  fixed chrome (legends, chart axes) collapses them to a space.

Known issue: a cross-process layout-ordering nondeterminism in a few non-layered
types (the layered/flowchart family is deterministic); tracked as an open issue.

## 0.12.0

MermaidKit is stably consumable again. **Problem: v0.11.0 pinned the Silica
Linux backend to `branch: master`, an unstable-version dependency. SwiftPM
forbids a package consumed via a stable version tag (`from: "0.x.0"`) from
transitively depending on a branch/revision, so every tagged 0.11.0 release
was UNRESOLVABLE by a normal `from:`-pinned host** (this is what stranded
Quoin on 0.10.0). Worse, even platform-conditioned, SwiftPM still fetched
Silica and its entire transitive graph (Cairo, FontConfig, PureSwift/Android,
Kotlin, JavaScriptKit, swift-java, swift-syntax — 16 packages) on macOS/iOS
consumers that never link a Silica symbol.

- The Silica/Cairo dependency and the `SilicaCairo`/`Cairo` product links are
  now gated behind a **package trait, `LinuxRaster` (SwiftPM 6.1+), default
  OFF**. A consumer that doesn't opt in resolves a graph with ZERO
  Silica/Cairo/branch dependencies — so a stable `from:` resolve is clean on
  every platform, and Apple hosts never fetch the Linux raster stack. Verified:
  a default `swift package resolve` produces an empty external graph (0
  checkouts); `--traits LinuxRaster` brings Silica + its 16-package graph back.
- Linux users who want the native raster backend opt in:
  `.package(url: "…/MermaidKit", from: "0.12.0", traits: ["LinuxRaster"])`,
  or `swift build --traits LinuxRaster`.
- CI's Linux job builds and tests with `--traits LinuxRaster` (exercising the
  Silica backend) AND builds `MermaidLayout` with default traits (proving the
  headless, Silica-free graph a `from:` consumer gets). `Package.resolved` is
  no longer committed (a trait-on lockfile would re-fetch the whole graph for
  MermaidKit's own default build); it is git-ignored.
- MermaidLayout + MermaidRender build on macOS, iOS, and Linux; the 183-test
  macOS suite and the Linux suite stay green.

Flowchart cycle back-edges (issue #1): the layered engine already routes a
back-edge through a real, node-attached polyline (confirmed across LR/TD,
tight two-node cycles, and multi-rank cycles), but nothing *guaranteed* it.

- `routeChains` can no longer emit a degenerate edge: the old
  "< 2 points" fallback shipped a `[.zero, .zero]` stub (a dangling wire at the
  origin — the reported "stray vertical line / no connector"). It now falls
  back to a straight border-to-border segment between the two nodes' anchors,
  so every flowchart edge is a non-degenerate, attached polyline.
- New scoped linter rule `edge-endpoint-detached` (node-graph families only —
  flowchart/state, whose every edge connects two boxes): flags any edge whose
  first/last polyline point is a degenerate/zero stub or lands off every node
  or container border. Sequence/ishikawa/gitgraph/wardley/treeview, whose edges
  attach to lifelines/spines/plot geometry, are exempt by construction.
- BackEdgeReproTests now asserts NON-degeneracy (distinct endpoints, real
  extent, label on the path) in addition to endpoint attachment.
- Node re-declaration (`B{Decision}` then `B[Figga]`) is deliberate and
  matches mermaid.js `addVertex`: a later explicit shape+label overrides the
  earlier; a bare back-reference (`D -->|who| B`) preserves the earlier shape.

## 0.11.0

Native rendering on **Linux**. `MermaidRender` now draws with Silica
(Cairo/FontConfig) as well as CoreGraphics/CoreText, sharing the exact layout
and per-type draw code — all 30 diagram types render to PNG and PDF headless on
swift-corelibs-foundation. See `docs/notes/linux-rendering-via-silica.md`.
(0.12.0 puts this backend behind the `LinuxRaster` trait — see above — so the
"Silica's transitive graph forces the toolchain floor / is fetched everywhere"
notes below now apply only when the trait is enabled.)

- **Toolchain floor is now Swift 6.2 / Xcode 26.** The manifest moved to
  `swift-tools-version: 6.2` (also required by package traits). All consumers
  must build with Swift 6.2+.
- `SilicaCairo` + `Cairo` are **Linux-only** target dependencies; on Apple they
  are never linked (CoreGraphics/CoreText are used, output unchanged).
- On Linux, `MermaidRenderer.image(...)` returns a `PlatformImage` with
  `pngData()` / `writePNG(to:)`; `pdfData(...)` works via Cairo's PDF surface.
  `attachmentString` (NSTextAttachment) stays Apple-only.
- **Fix Linux build** (#2): a public `CGVector` shim for swift-corelibs-foundation
  (which lacks it); a Linux CI job (`swift:6.2` + Cairo/FontConfig) that builds
  and tests the whole package, compiler-enforcing the platform-free contract.
- Flowchart cycle back-edge (#1): regression tests pinning that every edge
  attaches to its nodes and that node re-declaration matches mermaid.js.

## 0.10.0

Front-matter and accessibility metadata are first-class. Previously the
YAML front-matter block was stripped wholesale (its `title:` discarded) and
`accTitle:`/`accDescr:` lines were only tolerated by a couple of dialects.

- `MermaidParser.metadata(in:)` returns the new `DiagramMetadata`
  (`title`, `accessibilityTitle`, `accessibilityDescription`); one linear
  scan, no diagram parse. Front-matter keys other than a top-level `title:`
  (`config:`, `layout:`, `look:`, `theme:`, …) stay a graceful no-op.
- `accTitle:` / `accDescr:` statements (single-line and `accDescr { … }`
  block form, keyword case-insensitive) are stripped before any dialect
  parses the body, so they can never mint stray nodes — in ANY type.
- The front-matter `title:` renders as mermaid.js's centred caption above
  the diagram (standard title ink via the `DiagramTheme` seam), in both the
  raster and PDF paths. Dialects that draw their own title (pie, gantt, …)
  are untouched — no doubling.
- `DiagramScene` gains optional `title` / `accessibilityTitle` /
  `accessibilityDescription` fields; `DiagramScene.lower(_:metadata:measure:)`
  stamps them (geometry unchanged — metadata is data, not layout).
- `MermaidAltText` leads with the author's own accTitle/accDescr (or the
  front-matter title) before the generated structural summary;
  `attachmentString`/`MermaidView` pick that up automatically.

## 0.9.0

Flowchart subgraphs render as group boxes — the first of the audit's
"big-four structural gaps." Previously `subgraph id[Label] … end` flattened:
members drew, but the labeled group box was lost and any edge targeting a
subgraph id minted a phantom node.

- `subgraph id[Label] … end` now draws a labeled rounded box around its
  members. Nesting is arbitrary (a box inside a box), and an inner
  `direction LR/TB` reorients that group's interior independently.
- Membership follows mermaid: the first subgraph block a node textually
  appears in claims it (an inside reference wins over an earlier outside
  one; an inner block wins over its outer).
- An edge whose endpoint names a subgraph id (`Z --> GroupID`) now resolves
  to that group's box border instead of fabricating a phantom node.
- Layout is recursive: each group's interior is laid out as its own
  flowchart and placed as one sized rectangle by the parent's layered pass,
  so group boxes never overlap non-members (the geometry linter stays
  clean). Inter-group edges terminate on the box border. A group's box
  lowers to the scene as a container; its header lowers as a checked label.

Clustering also tightened member placement: the self-referential flowchart
fixture's total edge length fell from 3335 to 2808.

## 0.8.0

Sequence lifecycle and typography — the remaining Tier-1 items, validated
against websequencediagrams.com's classic feature set (all in mermaid
syntax; no extensions):

- `create participant/actor X` places the head at its creation row;
  `destroy X` ends the lifeline with the classic cross (open activation
  bars die with it).
- `<br/>` (and `<br>`) line breaks in messages and notes: rows grow,
  note boxes size to their widest line, message labels stack above the
  arrow, and column sizing measures lines rather than raw strings.
- Typed participants — `participant DB@{ "type": "database" }` — render
  head glyphs for database, queue, collections, boundary, control, and
  entity (websequencediagrams' participant types, absorbed by mermaid
  v11).

## 0.7.0

Sequence diagrams reach structural mermaid-parity for everyday syntax —
the sequence-primitives research memo's Tier 1, shipped:

- `box [color] Label ... end` participant groupings render as full-height
  background bands (color tokens recognized and dropped; our theme
  palette supplies the tint), heads dropping to give the band label
  headroom; `end` disambiguates correctly between boxes and fragments.

- Sequence diagrams: combined fragments render — `loop`/`alt`+`else`/
  `opt`/`par`+`and`/`critical`+`option`/`break` frames with kind tabs,
  guard labels, and dividers, arbitrarily nested (tolerant stack machine;
  a missing `end` closes at end-of-diagram), plus `rect` background
  bands. The layout's flat row list became a typed row stream (the
  sequence-primitives research memo's design), which variable-height rows
  and future activation bars build on. Frames lower to the scene as
  containers.
- Sequence activation bars render: `->>+`/`->>-` shorthand and explicit
  `activate`/`deactivate` statements produce execution bars on lifelines,
  nested activations stacking with rightward depth offsets; unclosed bars
  run to the lifeline bottom. Bars lower into the scene as slim nodes.
- Sequence arrows carry their identity: all mermaid arrow tokens map to
  true head styles (none/filled/cross/open/both, including v11's
  `<<->>`); `autonumber start step off` variants render as badge chips.
- Sequence `Note right of / left of / over` boxes render (author content
  that previously vanished); `actor` participants draw as stick figures.
- README/fixture: the sequence self-portrait now exercises an actor, a
  note, and an alt/else fragment.

## 0.6.0

The parser honesty sprint: syntax that used to be silently dropped — or
worse, corrupted into confident phantom content — now parses to what the
author wrote. Every fix is pinned by a regression test using the exact
previously-broken form (ParserHonestyTests).

Fabrication/corruption fixes:
- sequence: `->>+`/`->>-` activation shorthand no longer mints phantom
  `+Name`/`-Name` lifelines (the docs' first example was affected); the
  `participant P as an actor guy` alias no longer loses text to a global
  "actor " strip.
- gantt: directive lines containing colons (`axisFormat %H:%M`,
  `todayMarker`, `click ... href`) no longer become phantom task bars;
  `until` no longer becomes a task id; `y/M/s/ms` duration units parse.
- radar: positional `{1, 2, 3}` values (the docs' primary form) no longer
  render every curve flat at the minimum; multiple `axis` lines append;
  the ceiling grows to the data when `max` is unset.
- packet: `+N` is a field WIDTH after the previous field, not an absolute
  single bit — relative layouts were confidently wrong before.
- treemap: `:::styleClass` no longer destroys leaf values; `classDef`
  lines are no longer literal tree nodes.
- zenuml: comments and assignment targets no longer fabricate
  participants.
- C4: `RelIndex(i, from, to, ...)` no longer shifts the index into `from`.
- gitGraph: `cherry-pick` appears on the timeline instead of vanishing.

New flowchart syntax (was silently erased whole-line before):
- chained edges `A --> B --> C`; `&` fan-out (`A & B --> C & D`, label-safe);
  inline `-- text -->` labels; min-length links (`---->`); bidirectional
  `<-->` (new `backArrow` on Edge, drawn at both ends); `--o`/`--x` heads
  (drawn as plain arrows — honest degradation); edge IDs (`e1@-->`);
  `:::class` suffixes.

Cross-cutting: YAML front-matter (`---title/config---`) is stripped, so
every config-bearing doc example now native-renders. Fixtures exercise the
new syntax with graph-identical rewrites, so the lint corpus proves it.

## 0.5.0

Full mermaid.js type parity: **all 30 documented diagram types render.**

Seven new types, each full-stack (parser + layout + renderer + scene
lowering + linter coverage + alt-text + PDF + gallery self-portrait):

- `treeView-beta` — indentation hierarchy with folder/file glyphs; accepts
  pasted `tree` output (box-drawing normalizes to indents).
- `venn-beta` — 1-3 sets, area-proportional radii, overlap labels pushed
  into their region's private lens.
- `cynefin-beta` — the fixed 2x2 + confusion disk; transitions run in the
  outer corridor past the item stacks.
- `wardley-beta` — author-coordinate scatter with evolution bands, links,
  dashed evolve arrows, inertia bars, collision-staggered labels.
- `ishikawa-beta` — classic fishbone: spine, alternating 60-degree ribs,
  horizontal twigs (upstream's minimal documented grammar).
- `eventmodeling` — strict time-by-lane grid with typed color-coded
  frames and elbow connectors.
- `swimlane-beta` — flowchart semantics under lane constraints: global
  columns from network-simplex layering, authored lane bands, cross-lane
  orthogonal edges.

Linter refinements the new types forced: T-junctions no longer count as
edge crossings (strict-orientation test), and `mark-escapes-plot` applies
only to a sole bounding container (lanes/composites are not plots).

Benchmarks re-measured across all 30 (worst: sankey 35.8 ms rasterized —
its fixture grew and its labels gained chips; still 7x under the CI cap).

## 0.4.1

- Fix the iOS build under Swift 6.1: `UIImage.accessibilityLabel` is
  `@MainActor` in the iOS SDK, so the attachment path now sets it only
  when already on the main thread (the real text-view embedding case);
  `MermaidView`'s own accessibility label covers the view path regardless.
  Local Swift 6.2 accepted the unguarded mutation — CI's 6.1 correctly
  rejected it, and the CI step now preserves compiler diagnostics on
  failure instead of swallowing them with `tail`.

## 0.4.0

Three capabilities from the IR-compilation design review (docs/website has
the memo's conclusions; SVG/ASCII backends are deliberately deferred until
there's a concrete consumer):

- **Vector PDF export** — `MermaidRenderer.pdfData(source:theme:spacing:)`:
  the same layout and draw code as the raster path, into a `CGPDFContext`.
  Crisp at any zoom; the export/print path. All 23 fixture types verified.
- **Accessibility alt-text** — every diagram describes itself.
  `MermaidView` exposes a full content description to VoiceOver
  ("Flowchart with 12 nodes and 14 connections: ..."), `attachmentString`
  sets it on the embedded image, `MermaidRenderer.altText(source:)` and
  the platform-free `MermaidAltText.describe(_:)` expose it directly.
- **`DiagramColor`** — platform-free sRGB color values in MermaidLayout,
  and `DiagramTheme.resolved`: every theme color as `DiagramColor`,
  resolved once under the theme's pinned appearance (the fingerprint now
  derives from the same pass). The color groundwork for future
  non-CoreGraphics backends, fully additive.
- Internals: the per-type render dispatch is factored into `renderPlan` +
  `paddedCanvas`, shared by raster and PDF — new types reach every output
  format at once.

## 0.3.1

- Chain straightening after Brandes-Koepf placement, in both the flowchart
  pipeline and the class/ER/state layeredRoutes: BK's balancing step leaves
  single-parent chains a few points off their neighbour's centre (a visible
  jog, with the edge label on the kink). A gap-clamped priority pass
  (Gansner et al. section 4.2, degree-1 case) snaps them straight; where
  parent and child alignment genuinely conflict, one clean alignment wins
  over two half-jogs. Pinned by ChainAlignmentTests at 0.5pt.

## 0.3.0

The gallery becomes the documentation, and the linter learns to read.

- **Self-referential fixtures**: every example diagram is now about
  MermaidKit itself — the class diagram is the real public API, the sankey
  hero is the render pipeline, the gantt/timeline/gitgraph are the actual
  project history, the xychart plots the published benchmark numbers. The
  same 23 files are the gallery, the lint corpus, and the benchmark suite.
- **New linter invariant, `edge-cuts-label` (error)**: an edge traveling
  through bare label text fails CI. `DiagramScene.Label` gained
  `anchorEdge` (an edge label sits on its own route by design) and `backed`
  (an opaque chip interrupts a crossing line; the text stays readable) so
  the check flags only genuine defects. Found and fixed a real one on
  arrival: sankey's outboard labels now draw on canvas chips.
- **gitgraph engine upgrades** (all exposed by real-word fixture labels):
  commit columns space adaptively by measured label width; auto-generated
  ids (`c1`, `merge2`) no longer render as labels; a label whose dot has a
  branch/merge leg below it flips above the rail (or slides aside when a
  tag occupies the top).
- Docs: benchmark table re-measured on the 0.2.0 engine (worst 24.7 ms,
  most types under 12 ms); every claim audited against the code.

Model additions (pre-1.0 reshape per the stability policy):
`GitGraph.Commit.hasExplicitID`, `GitGraphLayout.Commit.label/labelCenter`,
`DiagramScene.Label.anchorEdge/backed` — all defaulted where possible.

## 0.2.0

ELK-inspired layout upgrades ("what can we learn from the Eclipse Layout
Kernel" — the answer, implemented):

- Network-simplex layering (ELK/dot's default) replaces longest-path for
  the layered family: class fixture total edge length -36%, state -32%.
- Edge labels are layout citizens: multi-layer edges reserve a real channel
  (widened median dummy) and draw their label exactly there; adjacent-layer
  labeled edges grow their inter-layer gap. Previously merged label pairs
  render separated.
- Fixed-side ports: architecture honors author-declared edge sides
  (`waf:R --> L:gateway`); Edge.fromSide/toSide are now optional (nil =
  engine picks the facing side).
- Edit stability (ELK's "consider model order"): explicit declaration-order
  tie-breaking in crossing minimization, fully deterministic optimization
  (no Set-iteration order dependence), verified by SceneDelta-based tests —
  re-runs are bit-identical, a same-width label rename moves nothing, and
  appending a leaf node has a bounded blast radius.
- `DiagramSpacing` — the density knob (`.compact`/`.regular`/
  `.comfortable`, or custom gaps), threaded through flowchart/class/ER/
  state/architecture and surfaced on MermaidView/MermaidRenderer; render
  cache keys include it. Preset safety is tested (compact stays
  occlusion-free; presets order canvas area).

## 0.1.1

- Fix iOS build: v0.1.0's trait pinning used a nonexistent
  `UIGraphicsImageRendererFormat.traitCollection` property (the UIKit branch
  had never been compiled). The format is now resolved via `.preferred()`
  under the pinned traits.
- CI now compiles MermaidRender for the iOS Simulator on every push, so the
  UIKit branch can't silently break again.

## Unreleased (pre-0.1)

Initial public release — extracted from the markdown editor it grew inside.

- 23 Mermaid diagram types parsed, laid out, and rendered natively
  (Swift + CoreGraphics, zero dependencies).
- `MermaidView` (SwiftUI), `MermaidRenderer.image`/`.attachmentString`,
  `DiagramTheme`.
- `DiagramScene` geometry IR + `DiagramLayoutLinter` — layout quality
  enforced in CI as geometric invariants.
- Adversarial-input hardening: numeric sanitation at the parser boundary,
  mermaid.js-style input caps (`maxTextSize` 50k, `maxEdges` 500), fuzz-style
  pipeline tests.
- Render benchmarks: every fixture type renders cold in <25 ms on Apple
  silicon (CI-enforced <250 ms).
- Themeable categorical palette: `DiagramTheme(palette:)` re-skins node
  tints/pie slices/sankey bands across all types; render cache now keys on
  the full theme fingerprint (a same-appearance theme change previously
  could serve a stale cached render).
- Second external audit round: fixed two reproduced process crashes
  (gantt `inf`/`nan` duration skipping the sanitizer; packet bit index at
  Int.max overflowing in layout) and two hostile-input hangs (packet
  0..1M-bit ranges, unbounded radar tick loops) — all now clamped at parse
  with adversarial regression tests. Render-layer correctness: iOS trait
  resolution pinned to the theme's appearance (dynamic colors no longer
  bake at ambient traits), theme fingerprint resolved under the same
  pinned appearance and memoized (was ambient-dependent, with a crash
  path on unconvertible colors), cache cost accounts for backing-scale
  bytes, cache hits skip re-parsing, and returned NSImages are copies so
  host mutations can't poison the cache. Async API renamed to
  `renderImage` (a same-name overload made the sync path unreachable in
  async contexts) and now propagates cancellation. Benchmarks force
  rasterization — published numbers were flattered by NSImage's deferred
  drawing; honest worst is ~19 ms (was reported 13.1).
- Swift 6 language mode (swift-tools-version 6.0), zero warnings; async
  `MermaidRenderer.image(source:theme:)` twin renders off the calling
  thread via `sending`.
- `MermaidParser.diagnose(_:)`: human-readable parse failures with 1-based
  line numbers, cap explanations, and did-you-mean header suggestions.
- Performance/robustness audit: A* router's open set is a binary heap
  (architecture fixture 22.4 -> 13.1 ms cold); render cache is bounded
  (64 MB cost limit, NSCache pressure eviction) and wrapped Sendable; both
  targets compile with ZERO warnings under -strict-concurrency=complete.
- DocC documentation catalogs for both targets (Getting Started, Theming,
  Embedding in Text Views, Headless Layout, Scene Geometry and Linting,
  Adding a Diagram Type) + `.spi.yml` for Swift Package Index hosting.
