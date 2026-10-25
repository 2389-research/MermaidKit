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
/// re-rendering on light/dark changes. Its labels follow the environment's
/// Dynamic Type size (`DiagramSpacing.textScale`, times the spacing's own),
/// laid out at that size rather than scaled up; pin a size with
/// `.dynamicTypeSize(_:)`. The diagram displays at its natural size and
/// scales down (never up) when the container is narrower.
/// Unrecognized sources fall back to the raw text in monospaced type, so a
/// typo'd diagram degrades to something inspectable rather than a blank.
public struct MermaidView: View {
    private let source: String
    private let explicitTheme: DiagramTheme?
    private let spacing: DiagramSpacing

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The text scale for a Dynamic Type size: its body text size over the
    /// default's (17pt at `.large`), so `.xxxLarge` is 23/17 and
    /// `.accessibility5` 53/17.
    nonisolated static func textScale(for size: DynamicTypeSize) -> CGFloat {
        let body: CGFloat
        switch size {
        case .xSmall: body = 14
        case .small: body = 15
        case .medium: body = 16
        case .large: body = 17
        case .xLarge: body = 19
        case .xxLarge: body = 21
        case .xxxLarge: body = 23
        case .accessibility1: body = 28
        case .accessibility2: body = 33
        case .accessibility3: body = 40
        case .accessibility4: body = 47
        case .accessibility5: body = 53
        @unknown default: body = 17
        }
        return body / 17
    }

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

    /// The spacing at the environment's Dynamic Type size.
    private var dynamicSpacing: DiagramSpacing {
        var spacing = spacing
        spacing.textScale *= Self.textScale(for: dynamicTypeSize)
        return spacing
    }

    /// The rendered diagram image (scaled down to fit, never up), or the
    /// monospaced raw-source fallback when the source can't be rendered.
    public var body: some View {
        let theme = explicitTheme ?? DiagramTheme(prefersDark: colorScheme == .dark)
        if let image = MermaidRenderer.image(source: source, theme: theme, spacing: dynamicSpacing) {
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
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}
#endif
