import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension RenderScene {

    /// Lowers a `PacketLayout` into a fully-resolved `RenderScene` — the
    /// platform-free twin of `DiagramRenderer.draw(_ layout: PacketLayout, …)`
    /// (MermaidRender/DiagramRenderer+Packet.swift). It emits, in the same
    /// painter's order: an optional title, then per bit-field segment a tinted
    /// rounded rect with a firm border, the start/end bit indices at its top
    /// corners, and the field label (horizontal, or rotated for narrow fields).
    /// All colors are flat; nothing is approximated.
    public static func from(_ layout: PacketLayout, theme: RenderTheme,
                            measure: DiagramTextMeasurer) -> RenderScene {
        _ = measure
        var elements: [Element] = []

        if let title = layout.title, !title.isEmpty {
            elements.append(.text(Text(
                string: title, center: CGPoint(x: layout.size.width / 2, y: 14),
                fontSize: 12.5, weight: .semibold, color: theme.ink)))
        }

        for segment in layout.segments {
            let tint = theme.categoricalColor(segment.colorIndex)
            elements.append(.shape(Shape(
                path: .roundedRect(segment.frame, radius: 3),
                fill: tint.withAlpha(0.16), stroke: nil)))
            elements.append(.shape(Shape(
                path: .roundedRect(segment.frame.insetBy(dx: 0.5, dy: 0.5), radius: 3),
                fill: nil, stroke: Stroke(color: tint.withAlpha(0.55), width: 1))))

            // Bit indices at the segment's top corners.
            elements.append(.text(Text(
                string: "\(segment.startBit)",
                center: CGPoint(x: segment.frame.minX + 9, y: segment.frame.minY + 7),
                fontSize: 7.5, color: theme.tertiaryText)))
            if segment.endBit != segment.startBit {
                elements.append(.text(Text(
                    string: "\(segment.endBit)",
                    center: CGPoint(x: segment.frame.maxX - 9, y: segment.frame.minY + 7),
                    fontSize: 7.5, color: theme.tertiaryText)))
            }

            switch segment.labelMode {
            case .horizontal:
                if !segment.label.isEmpty {
                    elements.append(.text(Text(
                        string: segment.label,
                        center: CGPoint(x: segment.frame.midX, y: segment.frame.midY + 3),
                        fontSize: labelSize, color: theme.ink)))
                }
            case .vertical:
                if !segment.label.isEmpty {
                    elements.append(.text(Text(
                        string: segment.label,
                        center: CGPoint(x: segment.frame.midX, y: segment.frame.midY + 5),
                        fontSize: labelSize, color: theme.ink, rotation: -.pi / 2)))
                }
            case .none:
                break
            }
        }

        return RenderScene(size: layout.size, background: theme.canvas, elements: elements)
    }

    private static let labelSize: CGFloat = 10.5
}
