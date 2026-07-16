import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Geometry for a ZenUML (sequence) diagram: participant boxes across the top,
/// dashed lifelines dropping from each, and horizontal message arrows between
/// lifelines stacked top-to-bottom. Self-calls draw a small return loop to the
/// right of their lifeline. Pure geometry — the renderer only draws.
public struct ZenUMLLayout: Sendable {
    /// A participant box and the extent of its lifeline.
    public struct Participant: Sendable {
        public let frame: CGRect
        public let name: String
        /// A `«Actor»`-style stereotype, or nil for a plain participant.
        public let stereotype: String?
        /// X of the box center and the lifeline.
        public let centerX: CGFloat
        /// Y where the lifeline starts (bottom of the box).
        public let lifelineTop: CGFloat
        /// Y where the lifeline ends (shared by all participants).
        public let lifelineBottom: CGFloat
        /// Cycled palette slot (participant order), not a color.
        public let colorIndex: Int
    }

    /// A message arrow drawn at `y` between two lifelines.
    public struct Arrow: Sendable {
        /// Sender's lifeline x.
        public let fromX: CGFloat
        /// Recipient's lifeline x; for a self-call, the loop's right extent.
        public let toX: CGFloat
        /// Y the arrow is drawn at.
        public let y: CGFloat
        public let label: String
        public let isSelf: Bool
        /// Height of the return loop for a self-call (0 for a normal arrow).
        public let selfHeight: CGFloat
    }

    public let size: CGSize
    public let title: String?
    public let participants: [Participant]
    public let arrows: [Arrow]
}

extension DiagramLayoutEngine {

    /// Lays out a ZenUML sequence diagram: participant boxes left to right
    /// (gaps widened for adjacent message labels and self-call loops), one
    /// message per row below. Pure geometry — the renderer only draws.
    public static func layout(_ d: ZenUML, measure: DiagramTextMeasurer) -> ZenUMLLayout {
        let margin: CGFloat = 14
        let titleHeight: CGFloat = d.title == nil ? 0 : 26
        let boxHeight: CGFloat = 38
        let minBoxWidth: CGFloat = 66
        let maxBoxWidth: CGFloat = 220
        let boxPadX: CGFloat = 14
        let minGap: CGFloat = 42
        let labelPad: CGFloat = 20
        let selfLoopWidth: CGFloat = 26
        let selfLoopHeight: CGFloat = 18
        let rowHeight: CGFloat = 34
        let selfRowHeight: CGFloat = 42
        let topPad: CGFloat = 26          // box bottom → first arrow

        let n = d.participants.count
        var indexOf: [String: Int] = [:]
        for (i, p) in d.participants.enumerated() { indexOf[p.id] = i }

        // Stereotype text + box widths (name width, but wide enough for the
        // stereotype line too).
        let stereos: [String?] = d.participants.map {
            $0.kind == .plain ? nil : "«\($0.kind.rawValue.capitalized)»"
        }
        var widths: [CGFloat] = []
        for (i, p) in d.participants.enumerated() {
            var w = measure(p.name, nodeFontSize).width
            if let s = stereos[i] { w = max(w, measure(s, labelFontSize).width) }
            widths.append(min(maxBoxWidth, max(minBoxWidth, w + boxPadX * 2)))
        }

        // Edge-to-edge gap per adjacent pair, widened for adjacent message
        // labels and self-call loops so nothing overlaps a box.
        var gap = [CGFloat](repeating: minGap, count: max(0, n - 1))
        var extraRight: CGFloat = 0
        for m in d.messages {
            if m.isSelf {
                guard let a = indexOf[m.from] else { continue }
                let need = selfLoopWidth + measure(m.text, labelFontSize).width + 18
                if a < n - 1 { gap[a] = max(gap[a], need) } else { extraRight = max(extraRight, need) }
            } else {
                guard let a = indexOf[m.from], let b = indexOf[m.to] else { continue }
                let lo = min(a, b), hi = max(a, b)
                if hi - lo == 1 {
                    gap[lo] = max(gap[lo], measure(m.text, labelFontSize).width + labelPad)
                }
            }
        }

        // Participant centers left to right.
        var centers = [CGFloat](repeating: 0, count: n)
        var cursor = margin
        for i in 0..<n {
            centers[i] = cursor + widths[i] / 2
            cursor += widths[i]
            if i < n - 1 { cursor += gap[i] }
        }
        let contentRight = cursor + extraRight + margin

        let boxTop = margin + titleHeight
        var y = boxTop + boxHeight + topPad

        var arrows: [ZenUMLLayout.Arrow] = []
        for m in d.messages {
            if m.isSelf {
                guard let a = indexOf[m.from] else { continue }
                arrows.append(.init(fromX: centers[a], toX: centers[a] + selfLoopWidth,
                                    y: y, label: m.text, isSelf: true, selfHeight: selfLoopHeight))
                y += selfRowHeight
            } else {
                guard let a = indexOf[m.from], let b = indexOf[m.to] else { continue }
                arrows.append(.init(fromX: centers[a], toX: centers[b],
                                    y: y, label: m.text, isSelf: false, selfHeight: 0))
                y += rowHeight
            }
        }
        let lifelineBottom = y + 8

        var participants: [ZenUMLLayout.Participant] = []
        for (i, p) in d.participants.enumerated() {
            let frame = CGRect(x: centers[i] - widths[i] / 2, y: boxTop,
                               width: widths[i], height: boxHeight)
            participants.append(.init(
                frame: frame, name: p.name, stereotype: stereos[i],
                centerX: centers[i], lifelineTop: frame.maxY,
                lifelineBottom: lifelineBottom, colorIndex: i
            ))
        }

        let width = min(max(contentRight, margin * 2 + 80), 3999)
        let height = min(max(lifelineBottom + margin, margin * 2 + 40), 3999)
        return ZenUMLLayout(size: CGSize(width: width, height: height),
                            title: d.title, participants: participants, arrows: arrows)
    }
}
