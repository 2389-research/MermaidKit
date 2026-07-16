# ``MermaidLayout``

Parse Mermaid source into typed models and pure geometry — no rendering, no
platform UI, machine-checkable layout.

## Overview

`MermaidLayout` is the platform-free half of MermaidKit: everything up to
(but not including) pixels.

```
source ──► MermaidParser.parse ──► MermaidDiagram (typed models)
       ──► DiagramLayoutEngine.layout(_:measure:) ──► per-type layout structs
       ──► DiagramScene.lower(_:measure:) ──► scene IR ──► DiagramLayoutLinter
```

Text metrics are injected through ``DiagramTextMeasurer``, so layout runs —
and is tested — without a display server. The scene IR
(``DiagramScene``) is `Codable`, which makes layout results diffable,
lintable, and consumable by backends other than CoreGraphics.

## Topics

### Parsing

- ``MermaidParser``
- ``MermaidDiagram``
- ``ParseDiagnostic``

### Layout

- <doc:HeadlessLayout>
- ``DiagramLayoutEngine``
- ``DiagramTextMeasurer``
- ``DiagramSpacing``

### Geometry verification

- <doc:SceneGeometryAndLinting>
- ``DiagramScene``
- ``DiagramLayoutLinter``
- ``LayoutViolation``

### Extending

- <doc:AddingADiagramType>
