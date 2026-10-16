# Adding a Diagram Type

The end-to-end walkthrough: every diagram type is a model, a parser, a layout,
two lowerings and a renderer, plus a handful of dispatch cases — and the pattern
repeats 30 times in this package. Copy the nearest neighbor.

## The files

We'll use `venn` as the worked example — it's a real, shipped type, so you can
read the finished files alongside this walkthrough. Newer types keep one file per
piece; older or grouped types share files (venn's scene lowering and renderer
live in the `+NewTypes` files), so find your neighbor with a quick search.

### 1. Model — beside the parser in `MermaidParser+Venn.swift`

(Newer types keep the model with their parser; the original types live in
`MermaidModels.swift`.)

A value type describing *what the user wrote*, not geometry:

```swift
public struct VennDiagram: Hashable, Sendable {
    public struct SetItem: Hashable, Sendable, Identifiable {
        public let id: String
        public let label: String?
        public let size: Double
    }
    public struct Overlap: Hashable, Sendable {
        public let ids: [String]
        public let label: String
    }
    public var sets: [SetItem]
    public var overlaps: [Overlap]
}
```

Give public types public initializers, so hosts can build a model without
writing Mermaid text.

### 2. Parser — `MermaidParser+Venn.swift`

```swift
extension MermaidParser {
    static func parseVenn(body: [String]) -> VennDiagram? { … }
}
```

Rules that keep the suite green:

- Never crash: unknown lines are skipped, not fatal.
- Numbers go through `MermaidParser.finiteDouble` (rejects `NaN`/`inf`,
  clamps magnitude) — `AdversarialInputTests` will find you otherwise.
- Return `nil` only when the body is not your dialect at all.

### 3. Layout — `DiagramLayoutVenn.swift`

Pure geometry. Text sizes come from the injected measurer — never guess
glyph widths:

```swift
extension DiagramLayoutEngine {
    public static func layout(_ venn: VennDiagram, measure: DiagramTextMeasurer) -> VennLayout { … }
}
```

The layout struct holds frames/polylines/label positions only — the
renderer must not re-derive geometry (that divergence class is why the
scene IR exists).

### 4. Lint lowering — `DiagramScene+<Type>.swift` (venn's is in `DiagramScene+NewTypes.swift`)

Hand your geometry to the linter:

```swift
extension DiagramScene {
    static func from(_ layout: VennLayout, measure: DiagramTextMeasurer) -> DiagramScene { … }
}
```

Containers (group boxes, plot areas) get `isContainer: true`; label frames
use `DiagramScene.estimatedLabelFrame`.

### 5. Render lowering — `RenderScene+Venn.swift`

The platform-free paint IR behind SVG export, `SceneWire`, and the Android,
Windows, WebAssembly and Flutter renderers:

```swift
extension RenderScene {
    public static func from(_ layout: VennLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene { … }
}
```

It must paint what the CoreGraphics renderer paints — the draw-vs-scene
conformance tests compare the two.

### 6. Renderer — `DiagramRenderer+<Type>.swift` (MermaidRender target; venn's is in `DiagramRenderer+NewTypes.swift`)

CoreGraphics drawing over the layout struct, all colors from
`DiagramTheme`, shared helpers (`drawText`, `fillStrokeBox`,
`strokeEdgeShafts`, `drawEdgeLabel`, `drawDiagramTitle`) from
`+Primitives`/`+GraphShared`.

## The dispatch cases

1. `MermaidDiagram` — add `case venn(VennDiagram)` (+ `typeName`).
2. `MermaidParser.parse` — route the `venn-beta` header, and add it to
   `knownHeaders` so `diagnose` can suggest it.
3. `DiagramScene.lower` and `DiagramRenderer`'s switch — one case each.
4. `RenderScene.from(_:theme:measure:spacing:)` and `MermaidAltText.describe` —
   one case each.

The compiler's exhaustive-switch errors walk you to every site.

## The verification loop

1. Add a **dense** fixture at `Fixtures/diagrams/venn.mmd` — worst-realistic,
   not minimal: long labels, many elements, edge cases.
2. Iterate against the linter:
   `MERMAIDKIT_LINT_TYPE=venn swift test --filter testLintSingleType`
   until zero errors, then add `venn` to `LayoutLintTests`' `errorFree` set.
3. **Render it and look at it** — the linter is necessary, not sufficient.
4. Add adversarial cases (`AdversarialInputTests`) for your syntax.
5. `RenderBenchmarks` renders and rasterizes your fixture automatically as a
   correctness smoke (it never asserts on wall-clock).
