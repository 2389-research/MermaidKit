# ``MermaidRender``

Draw Mermaid diagrams natively — SwiftUI views, images, and text-view
attachments, themed by a single value.

## Overview

`MermaidRender` is the drawing half of MermaidKit. It consumes the geometry
produced by `MermaidLayout` and renders it with CoreGraphics/CoreText on
macOS, iOS, iPadOS, and visionOS, and with Silica (Cairo/FontConfig) on Linux —
the same layout and per-type draw code backs both. There is no JavaScript and
no WebView; on Apple the only dependency is `MermaidLayout`, and on Linux the
render backend additionally links Silica — behind the `LinuxRaster` package trait
(off by default), so no-trait consumers resolve a Silica-free graph everywhere.

Three ways in, from highest-level to lowest:

- ``MermaidView`` — a SwiftUI view: give it Mermaid source, it renders.
- ``MermaidRenderer/image(source:theme:)`` — one call, one native image.
- ``MermaidRenderer/attachmentString(source:theme:)`` — the diagram as a
  single-attachment `NSAttributedString` for embedding in a text view.

All rendering is synchronous (every built-in diagram type renders cold in
under 25 ms on Apple silicon; see the repository README for per-type
numbers) and cached per (source, appearance).

## Topics

### Getting started

- <doc:GettingStarted>
- ``MermaidView``
- ``MermaidRenderer``

### Styling

- <doc:Theming>
- ``DiagramTheme``
- ``MermaidLayout/DiagramSpacing``
- ``MermaidLayout/DiagramColor``

### Embedding in text views

- <doc:EmbeddingInTextViews>
