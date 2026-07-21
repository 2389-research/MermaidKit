# Scene Geometry and Linting

Judge diagram layout by geometry, not by eyeballing pixels — the design
idea that shaped MermaidKit.

## The problem it solves

"Does this diagram look right?" is normally answered by staring at a PNG —
unreliable for humans at scale and useless in CI. But a layout engine
already *knows* the exact geometry it produced. MermaidKit lowers every
diagram to a common IR and checks invariants of good layout on it directly.

## DiagramScene: the IR

``DiagramScene`` describes what a laid-out diagram *is*, independent of how
it's painted:

- `nodes` — boxes with frames (`isContainer` marks groups/plots that
  legitimately contain others)
- `edges` — routed polylines, with optional labels
- `labels` — free-standing text with estimated frames
- `size` — the canvas

```swift
let diagram = MermaidParser.parse(source)!
let scene = DiagramScene.lower(diagram, measure: measurer)
let json = try JSONEncoder().encode(scene)   // Codable: diff it, store it, ship it
```

Use the renderer's own measurer (`MermaidRenderer.textMeasurer` from the
`MermaidRender` target) when you want scene geometry to match the drawn
output exactly; any deterministic ``DiagramTextMeasurer`` works for pure
geometry tests.

## The linter

``DiagramLayoutLinter/lint(_:)`` checks the scene against invariants:

| Check | Severity | Meaning |
|---|---|---|
| `edge-occludes-node` | error | A wire travels through a box's interior (measured by clipped length — endpoint boxes are *not* exempt) |
| `nodes-overlap` | error | Two non-container boxes intersect |
| `off-canvas` | error | A node or label extends outside the canvas |
| `mark-escapes-plot` | error | A data series leaves its plot container |
| `edge-cuts-label` | error | A foreign edge slices through a bare label |
| `label-on-fixture` | error | An edge label sits on a bend, a crossing, another label, a box, or an arrowhead tip (flowchart/state) |
| `label-crowds-edge` | error | An edge label's run leaves under 10pt of connector on a side (flowchart/state) |
| `edge-endpoint-detached` | error | An edge has no polyline, is a zero-length stub, or an endpoint sits detached from every node |
| `edges-doubled` | error | Two edges run doubled along a shared line (overlapping connectors) |
| `labels-overlap` / `label-over-node` | warning | Colliding text |
| `edge-under-label` | warning | An edge passes under a backed (chip) label |
| `edge-crossings` | warning | Crossing count beyond a budget |

```swift
let violations = DiagramLayoutLinter.lint(scene)
let errors = violations.filter { $0.severity == .error }
```

MermaidKit's own test suite lints a dense fixture for **every** diagram type
and asserts zero errors — so a layout regression fails CI as a named
geometric fact ("edge #3 passes through node "DiagramScene" (165pt inside)"),
not as a pixel diff.

## Diffing layouts

``DiagramScene`` supports structural diffing: what moved, what rerouted,
which violations appeared or cleared between two versions of the engine —
a machine-readable "perceptual diff" for layout changes.

## Honest limits

A clean lint is a *floor*, not a ceiling: the invariants catch objective
defects, not aesthetics. Tangle, rhythm, and balance still need human eyes —
render your change and look at it. (The linter itself was twice found to
have blind spots by a human reviewer; the current invariants encode what
those reviews caught.)
