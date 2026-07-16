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

    static func draw(_ layout: GitGraphLayout, theme: DiagramTheme, in context: CGContext) {
        // Edges behind the dots: straight within a lane, a horizontal-tangent
        // curve when crossing lanes (branch point or merge).
        for edge in layout.edges {
            let color = theme.categoricalColor(edge.colorIndex)
            context.saveGState()
            context.setStrokeColor(resolvedCGColor(color.withAlphaComponent(0.8)))
            context.setLineWidth(2.5)
            context.setLineCap(.round)
            context.beginPath()
            context.move(to: edge.from)
            if abs(edge.from.y - edge.to.y) < 0.5 {
                context.addLine(to: edge.to)
            } else {
                let dx = (edge.to.x - edge.from.x) * 0.5
                context.addCurve(to: edge.to,
                                 control1: CGPoint(x: edge.from.x + dx, y: edge.from.y),
                                 control2: CGPoint(x: edge.to.x - dx, y: edge.to.y))
            }
            context.strokePath()
            context.restoreGState()
        }

        // Lane labels.
        for label in layout.laneLabels {
            drawTextLeft(label.name, at: label.point, size: 10.5, weight: .semibold,
                         color: theme.categoricalColor(label.colorIndex), in: context)
        }

        // Commit nodes: a filled dot (a ring for a merge), the tag above, the
        // id below.
        for commit in layout.commits {
            let color = theme.categoricalColor(commit.colorIndex)
            let r = commit.isMerge ? 5.5 : 6.5
            context.saveGState()
            context.setFillColor(resolvedCGColor(color))
            context.fillEllipse(in: CGRect(x: commit.center.x - r, y: commit.center.y - r, width: r * 2, height: r * 2))
            if commit.isMerge {
                context.setFillColor(resolvedCGColor(theme.canvas))
                context.fillEllipse(in: CGRect(x: commit.center.x - 2.5, y: commit.center.y - 2.5, width: 5, height: 5))
            }
            context.restoreGState()

            if let label = commit.label, let at = commit.labelCenter {
                drawText(label, center: at, size: 8.5,
                         color: theme.secondaryTextColor, in: context)
            }
            if let tag = commit.tag {
                let measured = measure(tag, size: 8.5)
                let chip = CGRect(x: commit.center.x - measured.width / 2 - 4,
                                  y: commit.center.y - 15 - 6, width: measured.width + 8, height: 13)
                context.saveGState()
                context.setFillColor(resolvedCGColor(theme.accent.withAlphaComponent(0.16)))
                context.addPath(CGPath(roundedRect: chip, cornerWidth: 3, cornerHeight: 3, transform: nil))
                context.fillPath()
                context.restoreGState()
                drawText(tag, center: CGPoint(x: chip.midX, y: chip.midY), size: 8.5,
                         weight: .medium, color: theme.ink, in: context)
            }
        }
    }
}
#endif
