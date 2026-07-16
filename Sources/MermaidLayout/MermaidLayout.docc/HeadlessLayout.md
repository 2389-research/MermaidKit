# Headless Layout

Use MermaidKit's geometry without drawing a pixel — for servers, tests,
tooling, and alternative rendering backends.

## Text measurement is injected

Layout needs to know how big text will be, but `MermaidLayout` refuses to
know about fonts. ``DiagramTextMeasurer`` is the seam:

```swift
public typealias DiagramTextMeasurer = (_ text: String, _ fontSize: Double) -> CGSize
```

Three measurers you might pass:

- **The renderer's own** — `MermaidRenderer.textMeasurer` (from the
  `MermaidRender` target): CoreText metrics, so geometry matches the drawn
  output exactly.
- **A deterministic estimate** — `{ text, size in CGSize(width: CGFloat(text.count) * size * 0.6, height: size + 4) }`:
  what MermaidKit's own layout tests use; runs anywhere, including Linux.
- **Your backend's metrics** — an SVG generator would pass its own
  font-measuring function here.

## Geometry without rendering

```swift
guard let diagram = MermaidParser.parse(source) else { … }

// Typed, per-type layout (frames, polylines, everything positioned).
// The main engines also take a density knob: `spacing: .compact`.
switch diagram {
case .flowchart(let chart):
    let layout = DiagramLayoutEngine.layout(chart, measure: measurer)
    // layout.nodes[i].frame, layout.edges[i].points, …
default: …
}

// Or the type-erased scene IR — one shape for all 30 types:
let scene = DiagramScene.lower(diagram, measure: measurer)
```

## Building another backend

``DiagramScene`` (or the richer per-type layout structs) is the contract a
non-CoreGraphics backend consumes: parse → layout → walk the geometry →
emit SVG/HTML canvas/PDF primitives. Parsing and layout stay shared, so a
new backend inherits all 30 types and the linter's guarantees for free.
This is the most-wanted contribution — see the repository's CONTRIBUTING.

## Programmatic diagrams

The models are plain public value types — you can skip Mermaid text
entirely and lay out a hand-built model:

```swift
let sankey = SankeyDiagram(nodes: […], links: […])
let layout = DiagramLayoutEngine.layout(sankey, measure: measurer)
```

Model inputs are treated as untrusted: malformed values (duplicate names,
non-finite numbers) degrade instead of trapping.
