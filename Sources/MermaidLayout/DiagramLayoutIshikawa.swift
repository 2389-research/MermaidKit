import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Laid-out fishbone: the spine, the head box, alternating diagonal ribs
/// with their cause labels, and horizontal twigs with sub-cause labels.
public struct IshikawaLayout: Sendable {
    public struct Rib: Sendable {
        public let label: String
        /// Diagonal from the spine junction out to the rib tip.
        public let from: CGPoint
        public let to: CGPoint
        /// Cause label centre (just beyond the tip).
        public let labelCenter: CGPoint
        public let above: Bool
        public let colorIndex: Int
        /// Twigs: horizontal stubs off the rib with sub-cause labels.
        public let twigs: [Twig]
    }
    public struct Twig: Sendable {
        public let from: CGPoint
        public let to: CGPoint
        public let label: String
        public let labelCenter: CGPoint
    }
    public let size: CGSize
    public let spineStart: CGPoint
    public let spineEnd: CGPoint
    /// The problem box at the head (right end of the spine).
    public let headFrame: CGRect
    public let problem: String
    public let ribs: [Rib]
}

extension DiagramLayoutEngine {
    /// Lays out a fishbone: horizontal spine with the problem head at the
    /// right; major causes alternate above/below as 60-degree ribs spaced
    /// along the spine; sub-causes are horizontal twigs stepped along each
    /// rib, labels outboard.
    public static func layout(_ diagram: IshikawaDiagram, measure: DiagramTextMeasurer) -> IshikawaLayout {
        let margin: CGFloat = 16
        let maxTwigs = diagram.causes.map(\.subCauses.count).max() ?? 0
        let ribRise: CGFloat = max(88, 46 + CGFloat(maxTwigs) * 26)
        let ribRun: CGFloat = ribRise * 0.58   // ~60 degrees from horizontal
        // Longest twig label bounds the horizontal room each rib pair needs.
        let twigWidth: CGFloat = diagram.causes
            .flatMap(\.subCauses)
            .map { measure($0, labelFontSize).width }
            .max() ?? 60
        let ribSpacing: CGFloat = max(150, twigWidth + ribRun * 0.5 + 42)

        let above = diagram.causes.enumerated().filter { $0.offset % 2 == 0 }
        let below = diagram.causes.enumerated().filter { $0.offset % 2 == 1 }
        let pairs = max(above.count, below.count)

        let headSize = measure(diagram.problem, nodeFontSize)
        let headWidth = headSize.width + 22
        let spineY = margin + 18 + ribRise
        let spineStart = CGPoint(x: margin + 4, y: spineY)
        let spineLength = CGFloat(pairs) * ribSpacing + 40
        let spineEnd = CGPoint(x: spineStart.x + spineLength, y: spineY)
        let headFrame = CGRect(x: spineEnd.x + 2, y: spineY - 17,
                               width: headWidth, height: 34)

        func makeRib(_ pairIndex: Int, _ index: Int, _ cause: IshikawaDiagram.Cause,
                     isAbove: Bool) -> IshikawaLayout.Rib {
            let junction = CGPoint(
                x: spineStart.x + 40 + CGFloat(pairIndex) * ribSpacing + (isAbove ? 0 : ribSpacing / 2),
                y: spineY)
            let sign: CGFloat = isAbove ? -1 : 1
            let tip = CGPoint(x: junction.x + ribRun, y: junction.y + sign * ribRise)
            let labelCenter = CGPoint(x: tip.x, y: tip.y + sign * 12)
            // Twigs step along the rib from the tip inward, extending toward
            // the label side (right), horizontal.
            let twigs: [IshikawaLayout.Twig] = cause.subCauses.enumerated().map { i, sub in
                let t = CGFloat(i + 1) / CGFloat(cause.subCauses.count + 1)
                let start = CGPoint(x: tip.x + (junction.x - tip.x) * t,
                                    y: tip.y + (junction.y - tip.y) * t)
                let length: CGFloat = 16
                let end = CGPoint(x: start.x + length, y: start.y)
                let w = measure(sub, labelFontSize).width
                return .init(from: start, to: end, label: sub,
                             labelCenter: CGPoint(x: end.x + 4 + w / 2, y: end.y))
            }
            return .init(label: cause.label, from: junction, to: tip,
                         labelCenter: labelCenter, above: isAbove,
                         colorIndex: index, twigs: twigs)
        }

        var ribs: [IshikawaLayout.Rib] = []
        for (pairIndex, entry) in above.enumerated() {
            ribs.append(makeRib(pairIndex, entry.offset, entry.element, isAbove: true))
        }
        for (pairIndex, entry) in below.enumerated() {
            ribs.append(makeRib(pairIndex, entry.offset, entry.element, isAbove: false))
        }

        // Canvas: spine + head, twig labels included.
        var maxX = headFrame.maxX + margin
        for rib in ribs {
            let labelHalf = measure(rib.label, labelFontSize).width / 2
            maxX = max(maxX, rib.labelCenter.x + labelHalf + margin)
            for twig in rib.twigs {
                let w = measure(twig.label, labelFontSize).width
                maxX = max(maxX, twig.labelCenter.x + w / 2 + margin)
            }
        }
        return IshikawaLayout(
            size: CGSize(width: maxX, height: spineY + ribRise + 18 + margin),
            spineStart: spineStart, spineEnd: spineEnd,
            headFrame: headFrame, problem: diagram.problem, ribs: ribs)
    }
}
