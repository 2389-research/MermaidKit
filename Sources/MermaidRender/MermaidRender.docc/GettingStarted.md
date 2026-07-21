# Getting Started

Render your first diagram in one line, then choose the right API for your
app's shape.

## Add the package

```swift
.package(url: "https://github.com/2389-research/MermaidKit.git", from: "2.2.0")
```

Depend on the `MermaidRender` product (it brings `MermaidLayout` with it).

## SwiftUI: MermaidView

```swift
import MermaidRender

struct Docs: View {
    var body: some View {
        ScrollView {
            MermaidView("""
            sequenceDiagram
                App->>API: POST /session
                API-->>App: 201 token
            """)
            .padding()
        }
    }
}
```

``MermaidView`` follows the environment's color scheme and re-renders when
it flips. It displays at the diagram's natural size and scales *down* to fit
a narrower container — never up. If the source isn't recognized Mermaid, it
degrades to the raw text in monospaced type, so a typo'd diagram stays
inspectable instead of vanishing.

Need a vector export? `MermaidRenderer.pdfData(source:theme:)` renders the
same layout as single-page PDF data. Need a description for assistive
technology? `MermaidRenderer.altText(source:)` — `MermaidView` already
exposes it to VoiceOver automatically.

Pass an explicit theme to opt out of appearance-following, and a spacing
preset to control density:

```swift
MermaidView(source, theme: DiagramTheme(prefersDark: true), spacing: .compact)
```

## AppKit/UIKit: images

```swift
let image = MermaidRenderer.image(
    source: source,
    theme: DiagramTheme(prefersDark:
        view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
)
imageView.image = image   // NSImage on macOS, UIImage elsewhere
```

`image(source:theme:)` returns `nil` for unrecognized sources — branch to
your own fallback (most apps show the fenced source). To tell the user *why*
it failed, ask for diagnostics:

```swift
if MermaidRenderer.image(source: source, theme: theme) == nil {
    for d in MermaidParser.diagnose(source) {
        print(d.line.map { "line \($0): " } ?? "", d.message)
        // line 1: unknown diagram type 'flowchar' — did you mean 'flowchart'?
    }
}
```

## What parses, what doesn't

30 diagram types parse their core syntax. Styling and interaction
directives from mermaid.js (`%%{init:}%%`, `classDef`, `style`, `click`…)
are **ignored, not fatal** — the diagram renders with your
``DiagramTheme`` instead. Unknown dialects return `nil`. Input is bounded
(`MermaidParser.maxTextSize`, `MermaidParser.maxEdges`); past the caps,
parsing returns `nil` fast.

## Performance model

Rendering is synchronous and cached per (source, appearance). Cold renders
are under 12 ms for most types (worst measured: ~25 ms for a dense
sankey, rasterization included), so calling from a SwiftUI `body` or a
main-thread layout pass is by design. If you're rendering hundreds of
diagrams in one pass, do it off-main and hand images back.
