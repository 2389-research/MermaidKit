# Embedding in Text Views

Put diagrams inside attributed strings — how a markdown editor inlines a
rendered ```` ```mermaid ```` block.

## The attachment API

``MermaidRenderer/attachmentString(source:theme:spacing:)`` returns the rendered
diagram as a **single-attachment** `NSAttributedString`: one U+FFFC
character carrying an `NSTextAttachment` whose image is the diagram.

```swift
if let diagram = MermaidRenderer.attachmentString(source: fenced, theme: theme) {
    let block = NSMutableAttributedString(attributedString: diagram)
    block.addAttributes([.paragraphStyle: centered], range: NSRange(location: 0, length: block.length))
    output.append(block)
} else {
    output.append(styledSourceFallback(fenced))   // not Mermaid → show the code
}
```

Because it's a plain attachment, everything TextKit knows how to do —
selection, copy, layout reflow around the paragraph — works unmodified.

## Patterns from a production host

MermaidKit was extracted from a production markdown editor that uses
exactly this API. Conventions that proved out:

- **Tag the source onto the range.** Store the original Mermaid text in a
  custom attribute on the attachment's range, so click-to-edit and
  copy-as-source can recover it.
- **Fall back to the fenced source, never to nothing.** `nil` means "not
  Mermaid I understand" — render the code block you would have rendered
  anyway.
- **Match `canvas` to your page color** (see <doc:Theming>) and re-render on
  appearance flips; the cache keys on (source, appearance) so this is cheap.

## Sizing

The attachment's bounds are the diagram's natural size in points. If your
column is narrower, scale the attachment bounds down proportionally rather
than letting TextKit crop.
