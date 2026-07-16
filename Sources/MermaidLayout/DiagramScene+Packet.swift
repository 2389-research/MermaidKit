import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension DiagramScene {
    /// Lowers a packet-diagram layout to the common IR. Each field row-slice
    /// (`Segment`) is a filled cell box on the 32-bit grid; a field that crosses
    /// a row boundary contributes several segments, so ids are disambiguated by
    /// bit range. Packet diagrams have no connectors, and every segment's label
    /// is centred inside its own box (implicit in the Node), so there are no
    /// free-standing edges or labels.
    static func from(_ layout: PacketLayout, measure: DiagramTextMeasurer) -> DiagramScene {
        DiagramScene(
            name: "packet",
            size: layout.size,
            nodes: layout.segments.map { seg in
                Node(
                    id: "\(seg.label) [\(seg.startBit)-\(seg.endBit)]",
                    frame: seg.frame,
                    isContainer: false
                )
            },
            edges: [],
            labels: []
        )
    }
}
