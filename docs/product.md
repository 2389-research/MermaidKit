# MermaidKit — Product Data

This is a data specification for downstream consumption (marketing, design,
documentation). It records what MermaidKit is and what it does, with claims
backed by tests, docs, or CI-generated images. It deliberately contains no
taglines and makes no visual or format decisions for those surfaces.

Feature groups are labeled **G1–G9** and referenced by shorthand throughout.

---

## Identity

| Key | Value |
| :--- | :--- |
| Name | MermaidKit |
| Definition | A native Swift library that parses, lays out, and renders [Mermaid](https://mermaid.js.org) diagrams. The diagram source is the input; the library produces typed models, pure geometry (a scene IR), and drawn images and PDF — on Apple platforms via CoreGraphics/CoreText, on Linux via Silica (Cairo/FontConfig). No JavaScript, no WebView, no Mermaid.js. |
| Status | **1.0** — stable public API (the entry points are frozen; model/layout field changes are now semver-major). Latest tag `v1.0.0`. Rendering ships on Apple platforms and on Linux (behind the `LinuxRaster` package trait, so no-trait consumers keep a Silica-free graph); `MermaidLayout` is platform-free. |
| Repository | github.com/2389-research/MermaidKit |
| Platforms | Rendering: macOS 14+, iOS 17+, visionOS 1+ (CoreGraphics/CoreText); Linux (Silica/Cairo). Geometry (`MermaidLayout`): platform-free — builds and tests on any swift-corelibs-foundation target. |
| Language / runtime | Swift 6 (`swift-tools-version: 6.2`, strict concurrency; the Silica backend's transitive graph sets a Swift 6.2 / Xcode 26 floor). Drawing via CoreGraphics/CoreText on Apple, Silica/Cairo on Linux. Zero JavaScript at runtime; local-only. |
| Rendering | Native geometry pipeline: parse → layout → common scene IR → draw. Both backends share the layout and per-type draw code; only the platform surface (CoreGraphics vs Silica) differs. No web view, no headless browser, no Mermaid.js. |
| Dependencies | Zero third-party packages on Apple. On Linux the render backend adds Silica (Cairo/FontConfig); `MermaidLayout` depends on nothing. |
| Coverage | **30 distinct diagram types** (`MermaidDiagram` enum, 30-branch parser dispatch, 30-row README matrix, 30 fixtures). |
| Verification | 179 package tests on macOS, 0 failures (2 intentionally env-gated skips). On Linux, 163 tests run in a `swift:6.2` container — the `MermaidLayout` suite plus Silica render smoke tests (all 30 fixtures render). |
| Origin | Built so that a diagram's source of truth stays the Mermaid text — parsed, laid out, and drawn natively in a Swift app — with layout judged by machine-checkable geometry rather than pixels, and with no runtime dependency on a JavaScript engine or web view. Consumed by the Quoin markdown editor as a first-party engine. |

---

## Target Audiences

| Audience | Job to be done | Features that matter most |
| :--- | :--- | :--- |
| App developers (Apple platforms) | Render Mermaid diagrams natively in a SwiftUI/AppKit/UIKit app without bundling a web view or JS engine | G1, G5, G6 |
| Markdown / document tools | Embed diagrams as native attributed-string attachments or PDF, matching the host's light/dark theme | G5, G7 |
| Technical & docs authors | Cover a broad diagram vocabulary (flowcharts, sequence, class, ER, state, charts, and more) from plain text | G1, G2, G3 |
| Layout / graph-drawing engineers | Reuse a platform-free, deterministic layout engine with a geometry linter, without any UI | G2, G4, G7 |
| Accessibility-minded teams | Ship diagrams with deterministic, content-bearing alt text and honest degradation | G3, G6 |
| CI / quality engineers | Judge diagram-layout changes by a semantic scene diff and lint deltas, not brittle pixel comparisons | G4, G8, G9 |
| AI / agent workflows | Generate Mermaid text and get a faithful native render, or reason over the scene IR + lint report programmatically | G3, G4, G7 |

---

## Feature Groups

### G1 — Diagram coverage

Thirty distinct diagram types, one dense fixture and one DocC-referenced render
per type. Support matrix in `README.md`; gallery in `docs/GALLERY.md`.

| Feature | Specific |
| :--- | :--- |
| Type count | **30 types** — the `MermaidDiagram` enum has 30 cases (`MermaidParser.swift`), matched by a 30-branch `parse` dispatch, a 31-keyword header vocabulary (`flowchart`+`graph` alias one type), and 30 `.mmd` fixtures. |
| Graph diagrams | flowchart (`flowchart`/`graph`), sequence, class, entity-relationship (`erDiagram`), state (v2), gitGraph, C4 (`C4Context`/`C4Container`/…), requirement, zenuml, block (`block-beta`), architecture, swimlane, eventmodeling. |
| Charts & data | pie, xychart, quadrant, radar, sankey, packet, treemap, venn. |
| Trees & hierarchies | mindmap, kanban, treeView, ishikawa (fishbone), cynefin, wardley. |
| Timeline & process | gantt, timeline, journey. |
| Per-type depth | Each type parses its real syntax, not a stub — e.g. sequence supports typed participants, `box` groups, 8 arrow-head tokens, nested combined fragments (loop/alt/opt/par/critical/break) + activation bars + create/destroy + autonumber; class supports 7 relation kinds and generics; ER supports four cardinalities and identifying/non-identifying relations. |
| Header nuances | `stateDiagram` matches both bare and `-v2`; `C4*` matches on the `C4` stem; `-beta` types match on their stem; `block-beta` requires its full header. |

### G2 — Flowchart layout engine (layered / Sugiyama)

The flagship. A pure-geometry, industry-standard layered pipeline. Documented in
`DiagramLayoutFlowchart.swift` and `README.md`; the `flowchart.mmd` fixture
literally diagrams the pipeline.

| Feature | Specific |
| :--- | :--- |
| Pipeline | Cycle-safe layer assignment → dummy-node channels for long edges → barycenter crossing-minimization → Brandes–Köpf cross coordinates → orthogonal edge routing → edge-label space reservation. |
| Layer assignment | **Network simplex** (Gansner et al. — minimum total edge length), the ELK Layered / Graphviz-dot default, with longest-path as both the initial feasible seed and the fallback at the iteration cap (`DiagramLayoutLayering.swift`). |
| Cycle / back-edges | Back-edges are detected and stripped before layering (which requires an acyclic graph), then routed on the opposite side; long edges (forward or back) get dummy-node chains so they route between nodes, not through them. Regression-pinned by `BackEdgeReproTests`. |
| Subgraph clusters | Recursive: each subgraph's interior is laid out as its own flowchart, wrapped in box chrome, with inner `direction` honored and LCA-based edge re-parenting; an edge may name a subgraph id and attach to the group border (no phantom node). |
| Node shapes | 6 — rectangle `[ ]`, rounded `( )`, stadium `([ ])`, diamond `{ }`, circle `(( ))`, cylinder `[( )]`. |
| Directions | TD / LR / BT / RL. |
| Edge model | optional `\|label\|`, dashed (`-.->`), arrow/no-arrow (`---`), bidirectional (`<-->`); `--o`/`--x` heads and edge IDs parse without minting phantom nodes. |
| Determinism | Model-order tie-breaks throughout, so the same source yields byte-identical geometry across runs (`StabilityTests`). |

### G3 — Parsing fidelity & robustness

Faithful parsing with a "degrade, never break" contract. Parser in
`MermaidParser*.swift`; enforced by `ParserHonestyTests`, `AdversarialInputTests`,
`ParseDiagnosticsTests`.

| Feature | Specific |
| :--- | :--- |
| Front matter | A leading `---`…`---` YAML block is stripped before any dialect parses; top-level `title:` captured, other keys (`config:`, `theme:`, …) tolerated and ignored. |
| Accessibility directives | `accTitle`/`accDescr` (single-line and block `accDescr { … }`) captured into `DiagramMetadata`, removed from the body so they never become nodes; readable without a full parse via `MermaidParser.metadata(in:)`. |
| Node re-declaration | Mermaid-faithful: a later *explicit* shape/label wins; a later *bare* reference does not clobber an earlier shape (pinned in `ParserHonestyTests`). |
| Degrade, never break | An unknown dialect returns `nil` (hosts show the fenced source; `diagnose` explains why). Styling/interaction directives (`%%{init}%%`, `classDef`/`style`/`click`, `:::class`, `%%` comments) are ignored, never fatal. |
| Diagnostics | `MermaidParser.diagnose` reports empty/oversized/comment-only source, recognized-header-but-empty-body, and Levenshtein "did-you-mean" header suggestions, with correct line numbers. |
| Adversarial safety | The full parse→layout→scene→lint pipeline is run on empty input, every header with no body, garbage bodies, RTL/Arabic/unicode, 100k-char labels, 120-level nesting, and hostile numbers (`inf`/`nan`/`1e308`/`Int.max`) — asserting it returns without crashing, hanging, or trapping. |
| Input caps | mermaid.js-parity guards: `maxTextSize` 50,000 chars (whole source), `maxEdges` 500 (flowcharts); oversized input is rejected fast. |

### G4 — Geometry-not-pixels linting & scene diff

The distinctive quality thesis: judge layout by a common scene IR's invariants,
not by pixels. `DiagramScene.swift` (linter), `DiagramSceneDiff.swift` (diff);
design in `SceneGeometryAndLinting.md`.

| Feature | Specific |
| :--- | :--- |
| Common scene IR | Every laid-out diagram lowers to one `DiagramScene` (nodes, edges as polylines, labels, containers) via `DiagramScene.lower(_:measure:)` — the level at which invariants are checked. |
| Linter — errors | `edge-occludes-node` (a wire crossing a box interior), `nodes-overlap`, `off-canvas`, `edge-cuts-label` (a foreign edge slicing label text), `mark-escapes-plot` (a series leaving a dominant chart plot). Measured with real (Liang–Barsky) geometry and injected text metrics, not bounding-box guesses. |
| Linter — warnings | `labels-overlap`, `label-over-node`, `edge-under-label`, `edge-crossings` (beyond a `max(2, edges/3)` budget). |
| Scene delta | `SceneDelta` reports moved/added/removed nodes (with displacement vectors), rerouted edges, and canvas resize, with a one-line human summary (e.g. `+2 nodes · 3 nodes moved (max 14pt)`). |
| Lint delta / verdict | `LintDelta` reports which violations a change cleared vs introduced and returns a verdict — `✓ fixed`, `✗ regressed (+N errors)`, `↓ improved`, or `= no error change` — the machine-readable "did this change help?" signal, above a pixel pdiff. |

### G5 — Native rendering

Drawing of the scene with one theme value re-skinning every type — CoreGraphics/
CoreText on Apple (macOS 14+, iOS 17+, visionOS 1+), Silica (Cairo/FontConfig)
on Linux. The `MermaidRender` target; both backends share the layout and
per-type draw code, so a diagram type reaches every platform at once.

| Feature | Specific |
| :--- | :--- |
| Image output | `MermaidRenderer.image(source:theme:spacing:)` returns a platform image (NSImage/UIImage); an async, cancellable `renderImage(...)` renders off the main thread. NSCache-backed render cache (~64 MB). |
| Text-view embedding | `attachmentString(source:theme:)` returns a single-attachment `NSAttributedString` for markdown editors and text views. |
| PDF export | `pdfData(source:theme:spacing:)` renders resolution-independent single-page vector PDF, reusing the exact same draw plan as the raster path. |
| SwiftUI view | `MermaidView` follows the environment color scheme, scales down (never up), degrades unparsable source to a monospaced source card, and exposes an accessibility label. |
| Theming | One `DiagramTheme` value (ink, secondary/tertiary text, canvas, accent, hairline, a six-hue categorical palette, `prefersDark`) re-skins all 30 types; `init(prefersDark:)` presets light/dark. |
| Spacing presets | `DiagramSpacing` density knob — `.regular`, `.compact` (0.75×), `.comfortable` (1.35×) — proven collision-free at every preset (`DiagramSpacingTests`). |

### G6 — Accessibility

Deterministic, content-bearing alt text from the typed model, wired into every
render path. `MermaidAltText`; `AltTextTests`, `DiagramMetadataTests`.

| Feature | Specific |
| :--- | :--- |
| Alt text | `MermaidAltText.describe(_:)` produces one deterministic sentence per type from the models (not geometry): leads with the type, states honest counts, then names leading content (long lists truncate to 6 + "and N more"). All 30 types handled. |
| Author words first | `describe(_:metadata:)` prepends the author's `accTitle`/front-matter `title` and `accDescr`, then the generated structural summary — author intent first, always backed by honest counts. |
| Wired everywhere | `MermaidView`'s accessibility label, the embedded image's description, and `MermaidRenderer.altText(source:)` all use it; it survives the render-cache round-trip. |

### G7 — Platform-free engine & interop

`MermaidLayout` is a UI-free, dependency-free engine: parse, layout, scene IR,
and linting, with text measurement injected. DocC: `HeadlessLayout.md`.

| Feature | Specific |
| :--- | :--- |
| MermaidLayout | Parse → typed models → per-type layout → scene IR → geometric linter, with zero AppKit/CoreGraphics-drawing imports. Builds and tests on Linux (swift-corelibs-foundation). |
| Injected measurement | Layout refuses to know about fonts: a `DiagramTextMeasurer` closure is the sole text-metrics seam, so the same measurer feeds layout, lowering, linting, and drawing — geometry sees exactly what the renderer paints. |
| Public seams | `MermaidParser.parse`, `DiagramLayoutEngine.layout(_:measure:spacing:)`, `DiagramScene.lower`, `DiagramLayoutLinter.lint`/`.delta`, `MermaidAltText.describe` — each usable without any renderer. |
| Interop by construction | Because the input is Mermaid text and the output is a typed model + inspectable scene IR + lint report, any tool that emits Mermaid drives MermaidKit, and any tool can reason over the geometry programmatically. |
| Compilation-target research | `docs/notes/ir-compilation-targets.md` explores lowering the same IR to targets beyond NSImage/UIImage. The Linux/Silica backend (`docs/notes/linux-rendering-via-silica.md`) is the first realized instance of that seam; a future SVG backend would reuse it. |

### G8 — Fidelity & determinism guarantees

Named properties with dedicated tests, run on every CI build.

| Feature | Specific |
| :--- | :--- |
| Draw-vs-scene conformance ratchet | Every text rect the renderer paints must be covered by a scene node/label; per-type uncovered-chrome ceilings can only ratchet *down*, so new uncovered text fails the build (`DrawSceneConformanceTests`, over all 30 fixtures). |
| Deterministic layout | The same source yields identical geometry across repeated layouts in a process; the layered family (flowchart etc.) is order-stable via model-order tie-breaks. A same-width rename moves nothing; appending a leaf has bounded blast radius (`StabilityTests`). (A cross-process ordering gap in a few non-layered types is tracked as an open issue.) |
| Straight spines | Brandes–Köpf balancing plus model-order tie-breaks keep single-parent chains straight (`ChainAlignmentTests`). |
| Geometry linting in CI | Every fixture lints clean over exact geometry on every run (`LayoutLintTests`); the `edge-cuts-label` invariant has its own suite. |
| Platform-free contract | The Linux CI job proves `MermaidLayout` builds and tests without CoreGraphics (the guard that caught a `CGVector` portability break) — and now also builds + renders `MermaidRender` via Silica. |

### G9 — Engineering & verification

| Feature | Specific |
| :--- | :--- |
| Test suite | 183 package tests, 0 failures (2 intentionally env-gated skips: doc-image generation and single-type lint). 164 layout tests, 19 render tests. |
| Cross-platform | 163 tests green on Linux (`swift:6.2` container, `--traits LinuxRaster`): the `MermaidLayout` suite plus the Silica render smoke tests (all 30 fixtures render). `MermaidLayout` still builds on bare swift-corelibs-foundation with the default (Silica-free) graph, so the platform-free contract stays compiler-enforced. |
| Dependency policy | The Silica/Cairo Linux render backend is behind the `LinuxRaster` package trait (default OFF). A `from:`-pinned consumer resolves a Silica-free graph on every platform — no unstable branch dependency, no Cairo/PureSwift stack fetched on Apple. Linux users opt in with `traits: ["LinuxRaster"]`. |
| CI | `test` (macOS): `swift build` + `swift test` on Xcode 26, plus a compile-only iOS-Simulator guard (a UIKit branch with no test host that must always compile). `linux`: installs Cairo/FontConfig, then `swift build --traits LinuxRaster` + `swift test --traits LinuxRaster`, and a `swift build --target MermaidLayout` proving the default Silica-free graph builds. |
| Parser honesty | `ParserHonestyTests` (41 tests) pins that syntax once silently dropped or mangled now parses faithfully; `AdversarialInputTests` (11) that hostile input never crashes. |
| Benchmarks | `RenderBenchmarks` guards end-to-end parse→layout→render timing (the "interactive time" claim). |
| Documentation | DocC catalogs for both targets (8 articles) plus `README.md`, `docs/GALLERY.md`, and three preserved design memos in `docs/notes/`. |

---

## Approach

Positioned in design space, not against named products.

| Concern | Mermaid.js in a WebView | Prerendered images / SVG export | MermaidKit |
| :--- | :--- | :--- | :--- |
| Runtime | JavaScript engine + web view | External tool / build step | Native Swift; CoreGraphics/CoreText; zero JS at runtime |
| Dependencies | Mermaid.js + browser stack | A headless browser or CLI | Zero third-party packages |
| Theming | CSS / JS config, per-diagram | Baked into the asset | One `DiagramTheme` value re-skins all 30 types; follows app light/dark |
| Live rendering | DOM reflow in a web view | Not live (static asset) | Direct draw; async off-main-thread render; ~interactive time |
| Layout quality signal | Pixel diffs or manual review | Pixel diffs | Semantic scene IR + geometry linter + lint-delta verdict |
| Unsupported input | Error or broken DOM | Build failure or blank | Returns `nil` / a labeled source card + a diagnostic; never crashes |
| Accessibility | Depends on generated DOM/ARIA | Usually none | Deterministic, model-derived alt text on every render path |
| Reuse without UI | Coupled to the web stack | Coupled to the tool | Platform-free `MermaidLayout` engine (Linux-buildable) |
| Offline / privacy | Depends on bundled assets | Varies | Local-only; no network, no browser |

---

## Image Asset Inventory

Repository images live under `docs/images/`; the type renders and hero are
regenerated by a gated test (`DocImageGeneration`, `GEN_DOC_IMAGES=1`).

| Asset | Shows | Suited for |
| :--- | :--- | :--- |
| `docs/images/hero-light.png` / `hero-dark.png` | A representative diagram (sankey), rendered by MermaidKit | Hero |
| `docs/images/types/<name>.png` (+ `-dark`) | One render per diagram type, light & dark — 30 types × 2 = 60 images | Feature (G1), gallery |
| `docs/GALLERY.md` | All 30 type renders in light/dark `<picture>` blocks | Proof, docs |
| `Fixtures/diagrams/*.mmd` | The 30 dense source fixtures behind every render, lint, and benchmark | Reference, examples |

---

## Documentation Index

| Module | Content |
| :--- | :--- |
| `README.md` | Public overview + the 30-type support matrix (the coverage source of truth) |
| `docs/GALLERY.md` | Every diagram type rendered, light/dark |
| `Sources/MermaidLayout/MermaidLayout.docc/` | `MermaidLayout.md` (parse → typed models + geometry), `SceneGeometryAndLinting.md` (judge layout by geometry, machine-checked in CI), `HeadlessLayout.md` (the `DiagramTextMeasurer` seam), `AddingADiagramType.md` (each type is "five small files and three dispatch lines") |
| `Sources/MermaidRender/MermaidRender.docc/` | `MermaidRender.md` (draw with CoreGraphics/CoreText), `GettingStarted.md`, `EmbeddingInTextViews.md` (`attachmentString`), `Theming.md` (one `DiagramTheme` re-skins all types) |
| `docs/notes/` | Preserved design memos: `ir-compilation-targets.md` (IR beyond NSImage/UIImage), `mermaid-coverage-audit.md` (historical gap audit vs mermaid.js — roadmap, not current state), `sequence-primitives-research.md` |
| `docs/website/BRIEF.md` | Design-context pack for a brochure site |

---

## Note on Modularization

Feature groups G1–G9 are self-indexing by shorthand; a marketing or docs surface
can lift any single group as a standalone section, and the Approach table and
Asset Inventory are each usable independently. Numeric claims (type count, test
counts, input caps, image counts) should be re-pulled from the cited sources at
publish time, as they move with the codebase. One caveat: the authoritative
diagram-type count is **30** (enum, dispatch, README matrix, fixtures) — if any
older doc still says "23", use 30. Linux rendering shipped in **v0.11.0**
(MermaidRender via Silica/Cairo); the still-outstanding portability item is an
SVG backend, not Linux.
