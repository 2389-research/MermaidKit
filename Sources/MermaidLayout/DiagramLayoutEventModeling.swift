import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Laid-out event model: a strict grid — one column per timeframe, one lane
/// band per frame kind — with elbow connectors between consecutive frames.
public struct EventModelingLayout: Sendable {
    public struct Frame: Sendable {
        public let entity: String
        public let kind: String
        public let frame: CGRect
        public let colorIndex: Int
    }
    public struct Lane: Sendable {
        public let name: String
        public let band: CGRect
    }
    public let size: CGSize
    public let lanes: [Lane]
    public let frames: [Frame]
    /// Elbow connectors between consecutive timeframes.
    public let connectors: [[CGPoint]]
}

extension DiagramLayoutEngine {
    /// Lays out event modeling: time flows left-to-right (one column per
    /// timeframe), the frame's kind picks its lane band (UI on top, then
    /// commands/read models, then events, per the method's convention), and
    /// consecutive frames connect with elbows.
    public static func layout(_ diagram: EventModelingDiagram, measure: DiagramTextMeasurer) -> EventModelingLayout {
        let margin: CGFloat = 14
        let gutter: CGFloat = 86
        let columnGap: CGFloat = 22
        let boxHeight: CGFloat = 34
        let lanePad: CGFloat = 14

        // Lane order per the method: UI, command/readmodel (interface row),
        // events (the timeline), processors below.
        let laneOrder: [(kinds: [EventModelingDiagram.Kind], name: String)] = [
            ([.ui], "UI / Automation"),
            ([.command, .readmodel], "Commands / Read Models"),
            ([.event], "Events"),
            ([.processor], "Processors"),
        ]
        let activeLanes = laneOrder.filter { lane in
            diagram.frames.contains { lane.kinds.contains($0.kind) }
        }
        func laneIndex(_ kind: EventModelingDiagram.Kind) -> Int {
            activeLanes.firstIndex { $0.kinds.contains(kind) } ?? 0
        }

        // Column widths: the widest entity in each timeframe column.
        let orderedTimeframes = Array(Set(diagram.frames.map(\.timeframe))).sorted()
        var columnWidth: [Int: CGFloat] = [:]
        for tf in orderedTimeframes {
            let widest = diagram.frames.filter { $0.timeframe == tf }
                .map { measure($0.entity, labelFontSize).width + 20 }
                .max() ?? 60
            columnWidth[tf] = max(64, widest)
        }
        var columnX: [Int: CGFloat] = [:]
        var x = margin + gutter
        for tf in orderedTimeframes {
            columnX[tf] = x
            x += (columnWidth[tf] ?? 64) + columnGap
        }
        let contentRight = x - columnGap

        let laneHeight = boxHeight + lanePad * 2
        let lanes: [EventModelingLayout.Lane] = activeLanes.enumerated().map { index, lane in
            .init(name: lane.name,
                  band: CGRect(x: margin, y: margin + CGFloat(index) * laneHeight,
                               width: contentRight - margin, height: laneHeight))
        }

        let kindColor: [EventModelingDiagram.Kind: Int] = [
            .ui: 0, .command: 5, .readmodel: 1, .event: 2, .processor: 3,
        ]
        let frames: [EventModelingLayout.Frame] = diagram.frames.map { frame in
            let lane = lanes[laneIndex(frame.kind)]
            return .init(
                entity: frame.entity, kind: frame.kind.rawValue,
                frame: CGRect(x: columnX[frame.timeframe] ?? margin,
                              y: lane.band.minY + lanePad,
                              width: columnWidth[frame.timeframe] ?? 64,
                              height: boxHeight),
                colorIndex: kindColor[frame.kind] ?? 0)
        }

        // Elbows between consecutive frames in source (timeframe) order:
        // out of the right edge, over, into the left edge (or straight down
        // a shared column when the step stays in one timeframe).
        var connectors: [[CGPoint]] = []
        for (a, b) in zip(frames, frames.dropFirst()) {
            if a.frame.midX == b.frame.midX {
                connectors.append([
                    CGPoint(x: a.frame.midX, y: a.frame.maxY),
                    CGPoint(x: b.frame.midX, y: b.frame.minY),
                ])
            } else {
                let start = CGPoint(x: a.frame.maxX, y: a.frame.midY)
                let end = CGPoint(x: b.frame.minX, y: b.frame.midY)
                let midX = (start.x + end.x) / 2
                connectors.append([
                    start,
                    CGPoint(x: midX, y: start.y),
                    CGPoint(x: midX, y: end.y),
                    end,
                ])
            }
        }

        return EventModelingLayout(
            size: CGSize(width: contentRight + margin,
                         height: margin * 2 + CGFloat(lanes.count) * laneHeight),
            lanes: lanes, frames: frames, connectors: connectors)
    }
}
