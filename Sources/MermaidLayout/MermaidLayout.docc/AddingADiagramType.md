# Adding a Diagram Type

The end-to-end walkthrough: every diagram type is five small files and
three dispatch lines, and the pattern repeats 30 times in this package —
copy the nearest neighbor.

## The five files

We'll use `venn` as the worked example — it's a real, shipped type, so you can read the finished five files alongside this walkthrough.

### 1. Model — `MermaidModels.swift`

A value type describing *what the user wrote*, not geometry:

```swift
public struct VennDiagram: Hashable, Sendable {
    public struct Set: Hashable, Sendable {
        public let label: String
        public let size: Double
    }
    public var sets: [Set]
    public var overlaps: [(a: Int, b: Int, size: Double)]
}
```

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
    public static func layout(_ d: VennDiagram, measure: DiagramTextMeasurer) -> VennLayout { … }
}
```

The layout struct holds frames/polylines/label positions only — the
renderer must not re-derive geometry (that divergence class is why the
scene IR exists).

### 4. Scene lowering — `DiagramScene+Venn.swift`

Hand your geometry to the linter:

```swift
extension DiagramScene {
    static func from(_ layout: VennLayout, measure: DiagramTextMeasurer) -> DiagramScene { … }
}
```

Containers (group boxes, plot areas) get `isContainer: true`; label frames
use `DiagramScene.estimatedLabelFrame`.

### 5. Renderer — `DiagramRenderer+Venn.swift` (MermaidRender target)

CoreGraphics drawing over the layout struct, all colors from
`DiagramTheme`, shared helpers (`drawText`, `fillStrokeBox`,
`strokeEdgeShafts`, `drawEdgeLabel`, `drawDiagramTitle`) from
`+Primitives`/`+GraphShared`.

## The three dispatch lines

1. `MermaidDiagram` — add `case venn(VennDiagram)` (+ `typeName`).
2. `MermaidParser.parse` — route the `venn-beta` header.
3. `DiagramScene.lower` and `DiagramRenderer`'s switch — one case each.

The compiler's exhaustive-switch errors walk you to every site.

## The verification loop

1. Add a **dense** fixture at `Fixtures/diagrams/venn.mmd` — worst-realistic,
   not minimal: long labels, many elements, edge cases.
2. Iterate against the linter:
   `MERMAIDKIT_LINT_TYPE=venn swift test --filter testLintSingleType`
   until zero errors, then add `venn` to `LayoutLintTests`' enforced set.
3. **Render it and look at it** — the linter is necessary, not sufficient.
4. Add adversarial cases (`AdversarialInputTests`) for your syntax.
5. `RenderBenchmarks` runs your fixture automatically; stay under the cap.
