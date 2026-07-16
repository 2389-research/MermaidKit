#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import Foundation
import MermaidLayout

#if canImport(AppKit)
import CoreGraphics
import CoreText
import AppKit
#elseif canImport(UIKit)
import CoreGraphics
import CoreText
import UIKit
#endif

extension DiagramRenderer {

    static func draw(_ layout: PacketLayout, theme: DiagramTheme, in context: CGContext) {
        drawDiagramTitle(layout.title, width: layout.size.width, theme: theme, in: context)

        for segment in layout.segments {
            let tint = theme.categoricalColor(segment.colorIndex)
            context.saveGState()
            context.setFillColor(resolvedCGColor(tint.withAlphaComponent(0.16)))
            context.addPath(CGPath(roundedRect: segment.frame, cornerWidth: 3, cornerHeight: 3, transform: nil))
            context.fillPath()
            context.setStrokeColor(resolvedCGColor(tint.withAlphaComponent(0.55)))
            context.setLineWidth(1)
            context.addPath(CGPath(roundedRect: segment.frame.insetBy(dx: 0.5, dy: 0.5),
                                   cornerWidth: 3, cornerHeight: 3, transform: nil))
            context.strokePath()
            context.restoreGState()

            // Bit indices at the segment's top corners.
            drawText("\(segment.startBit)", center: CGPoint(x: segment.frame.minX + 9, y: segment.frame.minY + 7),
                     size: 7.5, color: theme.tertiaryTextColor, in: context)
            if segment.endBit != segment.startBit {
                drawText("\(segment.endBit)", center: CGPoint(x: segment.frame.maxX - 9, y: segment.frame.minY + 7),
                         size: 7.5, color: theme.tertiaryTextColor, in: context)
            }

            switch segment.labelMode {
            case .horizontal:
                drawText(segment.label, center: CGPoint(x: segment.frame.midX, y: segment.frame.midY + 3),
                         size: labelSize, color: theme.ink, in: context)
            case .vertical:
                // Rotated label for narrow fields (e.g. TCP flags), below the
                // bit-index strip.
                drawTextRotated(segment.label, center: CGPoint(x: segment.frame.midX, y: segment.frame.midY + 5),
                                size: labelSize, color: theme.ink, in: context)
            case .none:
                break
            }
        }
    }
}
#endif
