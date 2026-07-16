#if canImport(SwiftUI) && (canImport(AppKit) || canImport(UIKit))
import SwiftUI
import MermaidLayout

/// A drop-in SwiftUI view that renders Mermaid source natively.
///
/// ```swift
/// MermaidView("""
/// flowchart TD
///     A[Start] --> B{Choice}
/// """)
/// ```
///
/// With no explicit theme the view follows the environment's color scheme,
/// re-rendering on light/dark changes. The diagram displays at its natural
/// size and scales down (never up) when the container is narrower.
/// Unrecognized sources fall back to the raw text in monospaced type, so a
/// typo'd diagram degrades to something inspectable rather than a blank.
public struct MermaidView: View {
    private let source: String
    private let explicitTheme: DiagramTheme?
    private let spacing: DiagramSpacing

    @Environment(\.colorScheme) private var colorScheme

    /// - Parameters:
    ///   - source: Mermaid source, e.g. `"flowchart TD\n  A --> B"`.
    ///   - theme: Optional fixed theme. Omit to follow the environment's
    ///     light/dark color scheme.
    ///   - spacing: Layout density — `.compact`, `.regular`, `.comfortable`,
    ///     or custom gaps.
    public init(_ source: String, theme: DiagramTheme? = nil,
                spacing: DiagramSpacing = .regular) {
        self.source = source
        self.explicitTheme = theme
        self.spacing = spacing
    }

    /// The rendered diagram image (scaled down to fit, never up), or the
    /// monospaced raw-source fallback when the source can't be rendered.
    public var body: some View {
        let theme = explicitTheme ?? DiagramTheme(prefersDark: colorScheme == .dark)
        if let image = MermaidRenderer.image(source: source, theme: theme, spacing: spacing) {
            Image(platformImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                .accessibilityLabel(Text(accessibilityDescription))
        } else if MermaidParser.parse(source) != nil {
            // Parsed fine but couldn't be rasterized (the layout exceeded the
            // canvas guard): say THAT, not "unrecognized".
            fallbackSource(label: "Diagram too large to render")
        } else {
            fallbackSource(label: "Unrecognized diagram source")
        }
    }

    private func fallbackSource(label: String) -> some View {
        Text(source)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
            .accessibilityLabel(Text(label))
    }

    private var accessibilityDescription: String {
        // Full content description (type, scale, leading names) — the parse
        // hits MermaidParser's cache-free path but only runs when
        // accessibility actually resolves the label.
        MermaidAltText.describe(source: source) ?? "Diagram"
    }
}

extension MermaidView: Equatable {
    /// Lets SwiftUI skip re-evaluating unchanged diagrams in bulk containers:
    /// equal source + equal theme identity (fingerprint) means an identical
    /// render. Environment color-scheme changes invalidate separately.
    nonisolated public static func == (lhs: MermaidView, rhs: MermaidView) -> Bool {
        lhs.source == rhs.source
            && lhs.explicitTheme?.fingerprint == rhs.explicitTheme?.fingerprint
            && lhs.spacing == rhs.spacing
    }
}

private extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(AppKit)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}
#endif
