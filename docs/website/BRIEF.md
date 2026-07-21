# MermaidKit — design context pack

You are designing a brochure site (GitHub Pages) for MermaidKit. Everything
in this pack was verified against the code at v0.8.0 on 2026-07-08. Cite
facts as written; do not embellish, round up, or invent. Where a claim
feels thin, use fewer claims — the diagrams do the impressing.

## What MermaidKit is

MermaidKit renders [Mermaid](https://mermaid.js.org) diagrams natively on
Apple platforms — pure Swift and CoreGraphics. No JavaScript, no WebView,
zero dependencies. All **30 mermaid diagram types**, a one-line SwiftUI
view, image / attributed-string / vector-PDF output, VoiceOver
descriptions for every diagram, themed with a single value. MIT license.

- Repo: https://github.com/2389-research/MermaidKit
- Latest release: v0.8.0
- Site target: https://2389-research.github.io/MermaidKit/ — a static
  `index.html` placed in the repo's `docs/` folder (GitHub Pages serves
  `docs/` from `main`; reference images relatively as `images/...`)

## The three story pillars

### 1. The diagrams check themselves

Every diagram lowers to a machine-readable geometry scene — boxes, edge
routes, labels — and a **geometry linter** checks invariants of good
layout on every CI run: no edge through a box, no line slicing through
label text, no overlapping nodes, nothing off-canvas, no chart series
escaping its plot, no T-junction miscounted as a crossing. Layout
regressions fail CI as named geometric facts ("edge #3 passes through
node 'DiagramScene' (165pt inside)"), not as pixel diffs or human
eyeballing.

And the site can make the companion claim with a straight face because
the images prove it: **every example is the project documenting itself.**
The class diagram is the real public API. The sankey hero is the render
pipeline. The gitgraph is the actual release history. The xychart plots
the real benchmark numbers. The same 30 files are simultaneously the
gallery, the lint corpus, and the benchmark suite — the examples cannot
drift from what the engine does, because CI runs them as tests.

Layout quality is engineered: network-simplex layer assignment (the
strategy Graphviz dot defaults to), label-space reservation during
layout, chain straightening after coordinate assignment, and edit
stability verified by scene-diff tests — rename a label to same-width
text and *nothing else moves*. Diagrams don't teleport while you edit.

### 2. One line to a diagram

```swift
import MermaidRender

MermaidView("""
flowchart TD
    A[Start] --> B{Choice}
    B -->|yes| C[Do it]
    B -->|no| D[Skip]
""")
```

That's the whole integration: follows light/dark automatically, sizes to
the diagram, caches renders, describes itself to VoiceOver. The full API
surface (all verified names):

- `MermaidView(source, theme:spacing:)` — the SwiftUI drop-in.
- `MermaidRenderer.image(source:theme:spacing:)` — one call, one image;
  sync and fast enough for a SwiftUI `body`. `renderImage(...)` is the
  async sibling with cancellation.
- `MermaidRenderer.attachmentString(...)` — the diagram as an
  `NSAttributedString` attachment for text views, VoiceOver description
  included.
- `MermaidRenderer.pdfData(source:theme:spacing:)` — single-page vector
  PDF from the same layout and draw code; crisp export and print.
- `MermaidRenderer.altText(source:)` / `MermaidAltText.describe(_:)` —
  a deterministic content description ("Flowchart with 12 nodes and 14
  connections: ...") for assistive technology, generated for all 30 types.
- `DiagramTheme` — six colors + a categorical palette re-skins all 30
  types at once; `theme.resolved` exposes every color as a platform-free
  sRGB value. `DiagramSpacing` — `.compact` / `.regular` / `.comfortable`
  density presets or exact gaps.
- `MermaidParser.parse(_:)` / `diagnose(_:)` — diagnose explains parse
  failures with line numbers and did-you-mean suggestions for typo'd
  headers.
- Headless: the parse → layout → scene pipeline is platform-free (no
  AppKit/UIKit imports), so tools can get pure geometry — frames,
  polylines, label boxes — without rendering a pixel.

Install:
```swift
.package(url: "https://github.com/2389-research/MermaidKit.git", from: "0.8.0")
```

### 3. Built to meet people where they are

- **Nothing breaks the host app.** Unknown dialects degrade to readable
  monospaced source. Styling directives (`%%{init:}%%`, `classDef`,
  `style`, `click`) are ignored, not fatal. Hostile input — garbage,
  100k-character labels, NaN/Infinity — is contained by an adversarial
  test suite in CI, with numeric sanitation at the parser boundary.
- **What the author wrote is what parses.** A dedicated "parser honesty"
  effort eliminated silent content loss and phantom-content fabrication
  across ten parsers, each fix pinned by a regression test using the
  exact previously-broken syntax.
- **Author intent is honored.** Declare an architecture edge's side
  (`waf:R --> L:gateway`) and the router obeys. Pick a density preset and
  every layout adapts. Override one palette and every chart re-skins.
- **Accessibility is built in, not bolted on**: every diagram type ships
  a VoiceOver description from day one.
- **Honest support matrix.** The README states plainly what parses, what
  is ignored, and what's a known gap worth filing. The site should keep
  that plainness — it's part of the identity.
- Platforms: renders natively on Apple (macOS 14+, iOS 17+, visionOS 1+),
  Linux, Android, Windows/.NET, WebAssembly, and Flutter, from one Swift
  layout core (Swift 6 language mode, Xcode 16+ to build). Lower Apple OS
  floors are the top of the public roadmap.

## Feature space (complete, verified)

**All 30 mermaid diagram types render natively**: flowchart, sequence,
class, state, entity-relationship, user journey, gantt, pie, quadrant,
requirement, gitGraph, C4, mindmap, timeline, zenuml, sankey, xychart,
block, packet, kanban, architecture, radar, treemap, treeview, venn,
cynefin, wardley, ishikawa, eventmodeling, swimlane.

Beyond core syntax, the notable structural support (all mermaid syntax,
no extensions):

- **Cross-cutting**: YAML front-matter (`--- title/config ---`) on every
  type.
- **Sequence** (full everyday parity): combined fragments —
  `loop`/`alt`+`else`/`opt`/`par`+`and`/`critical`+`option`/`break`,
  arbitrarily nested, tolerant of a missing `end` — plus `rect`
  background bands; activation bars from `->>+`/`->>-` and
  `activate`/`deactivate`; `box` participant groupings; notes
  (`Note right of / left of / over`) with `<br/>` line breaks; `actor`
  stick figures and typed participants (`@{ "type": "database" }` —
  database, queue, collections, boundary, control, entity glyphs);
  `create`/`destroy` lifecycles with the classic destruction cross; true
  arrow heads for every token (`->`, `-->`, `->>`, `-->>`, `-x`, `--x`,
  `-)`, `--)`, `<<->>`, `<<-->>`); autonumber badges with
  start/step/off.
- **Flowchart**: chained edges (`A --> B --> C`), `&` fan-out, inline
  `-- text -->` labels, bidirectional `<-->`, min-length links, `--o`/
  `--x` heads, edge IDs, `:::class` tolerance, six node shapes.
- **Gantt**: sections, `done/active/crit/milestone`, `after`
  dependencies, `d/w/h/m/y/M/s/ms` durations; directive lines can never
  become phantom bars.
- **Radar** positional and key:value data; **packet** `+N` relative
  widths; **treemap** `:::class`; **gitGraph** merges, tags,
  cherry-pick; **class** generics `~T~`; **ER** attribute keys and
  self-relations; **state** composites, forks, choices; **architecture**
  author-declared edge sides with A* routing.

Known gaps (say them plainly if the site mentions coverage): flowchart
subgraph boxes and `@{ shape }` shape library; HTML in labels beyond
`<br/>`; FontAwesome icons; click/animation interactivity; mermaid.js
theming directives (theming is `DiagramTheme`'s job).

## Numbers the site may cite (all verified 2026-07-08)

- **30** diagram types. **Zero** dependencies. Zero JavaScript, no
  WebView.
- Cold render **including rasterization**, Apple silicon, dense fixtures,
  fair round-robin sampling: worst **25.0 ms** (sankey); most types
  **2–12 ms**; repeat renders hit an in-memory cache keyed by
  (source, theme, spacing). CI fails any type over 250 ms.
- Parse alone: 0.05–1.9 ms per fixture.
- Input caps mirror mermaid.js: 50,000-character sources, 500 flowchart
  edges; oversized input returns nil fast.
- 149 tests in CI, including: the geometry linter over all 30 fixtures,
  per-fixture edge-length budgets, scene-diff edit-stability tests,
  adversarial input suite, rasterized render benchmarks, PDF export
  validation for all 30 types, alt-text determinism for all 30 types,
  and 30+ parser-honesty regressions.
- Swift 6 language mode, zero concurrency warnings. MIT.

## Asset inventory

All images are rendered by MermaidKit itself and regenerate from source.
Each exists in light and dark; serve both via `<picture>` with
`prefers-color-scheme`. In the deployed site, reference them relatively
(`images/hero-light.png`, `images/types/<name>.png`, `-dark` suffix for
dark variants).

**Hero** — MermaidKit's own render pipeline as a sankey (~2200px wide):
- https://raw.githubusercontent.com/2389-research/MermaidKit/v0.8.0/docs/images/hero-light.png
- https://raw.githubusercontent.com/2389-research/MermaidKit/v0.8.0/docs/images/hero-dark.png

**Per-type gallery** (30 × 2, max 2000px wide). Pattern:
`https://raw.githubusercontent.com/2389-research/MermaidKit/v0.8.0/docs/images/types/<name>.png`

| name | the self-portrait shows |
|---|---|
| architecture | the module map with author-declared edge sides |
| block | the render pipeline as blocks |
| c4 | a host app embedding MermaidKit |
| class | **the real public API** — strong gallery opener |
| cynefin | layout strategies sorted by problem class |
| er | the scene IR's data model |
| eventmodeling | the render pipeline as an event model |
| flowchart | the render decision flow, fallbacks included |
| gantt | the actual 1.0 release program |
| gitgraph | the real branch/tag release history |
| ishikawa | "diagram renders wrong" root-cause fishbone |
| journey | a developer's first week adopting the library |
| kanban | the live roadmap board |
| mindmap | the feature map |
| packet | TCP header (the canonical example for this type) |
| pie | source lines by component |
| quadrant | roadmap candidates, effort vs impact |
| radar | quality dimensions by release |
| requirement | real quality requirements traced to their verifying tests |
| sankey | sources flowing through the pipeline (hero's family) |
| sequence | **the showpiece**: actor figure, typed database head, box band, activation bar, note, alt/else fragment — the whole sequence feature set in one diagram |
| state | a source's lifecycle with the light/dark raster fork |
| swimlane | parse-to-display flow across module lanes |
| timeline | project history |
| treemap | the source tree by lines |
| treeview | this repo's own source tree with inline notes |
| venn | gallery = lint corpus = benchmarks ("the 30 fixtures") |
| wardley | the component landscape with evolve arrows toward SVG |
| xychart | published benchmark numbers with the budget line |
| zenuml | the diagnose-and-fix flow |

No logo exists; the diagrams are the visual identity. If a wordmark is
designed, keep it quiet — the gallery carries the page.

## Code snippets (copy exactly; these compile)

SwiftUI:
```swift
import MermaidRender

MermaidView("""
sequenceDiagram
    actor Dev
    participant Cache@{ "type": "database" }
    Dev->>+Cache: lookup
    Cache-->>-Dev: hit
""")
```

Image:
```swift
let image = MermaidRenderer.image(
    source: "flowchart LR\n  A[Parse] --> B[Layout] --> C[Render]",
    theme: DiagramTheme(prefersDark: false)
)
```

Vector PDF:
```swift
let pdf = MermaidRenderer.pdfData(source: source, theme: theme)
```

Install:
```swift
.package(url: "https://github.com/2389-research/MermaidKit.git", from: "0.8.0")
```

## Voice (non-negotiable)

- Anti-hype. No superlatives, no emoji section headers, no
  "production-ready". Numbers over adjectives.
- Focus entirely on what MermaidKit is and does. No comparisons with
  other tools or renderers, no benchmark claims against anything else —
  the table is MermaidKit-only cold-render times.
- State limitations plainly, near the claims they qualify: core syntax
  per type (not a syntax-complete port), output is native-looking rather
  than a pixel-clone. (Rendering is native on Apple, Linux, Android,
  Windows/.NET, WebAssembly, and Flutter — no longer Apple-only.)
- Any performance claim must match the numbers section exactly.

## Suggested shape (starting point, not a mandate)

1. **Hero** — pitch line, the sankey hero (theme-aware), the SwiftUI
   snippet, install line. "No JavaScript. No WebView. No dependencies."
   is the honest hook.
2. **Gallery** — the 30 self-portraits; lead with class (the API drawing
   itself) and sequence (the feature showpiece).
3. **It checks its own work** — the geometry-linter story, told simply:
   a lint report line beside the diagram it protects.
4. **One line to a diagram** — the DX pillar: snippet, theme, spacing,
   PDF, alt-text, diagnose.
5. **Built to adapt** — graceful degradation, parser honesty,
   accessibility, the roadmap invitations (lower Apple OS floors).
6. **Footer** — GitHub, latest release, MIT.

Single page, static HTML/CSS, fast on a phone, light/dark aware. The
diagrams are colorful; keep the chrome quiet around them. **No analytics
or trackers** — the library's privacy story is "no network" and the site
must live up to it. Don't claim full mermaid.js syntax parity.
(Linux rendering *is* real as of v0.11.0 — MermaidRender draws via Silica/Cairo
there; this brief otherwise reflects the v0.8.0 snapshot noted above.)
