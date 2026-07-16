import Foundation

/// An event modeling diagram (`eventmodeling`): a left-to-right timeline of
/// frames, each typed (ui / command / readmodel / event / processor), with
/// the type determining its swimlane and consecutive same-timeline frames
/// connected by elbows.
public struct EventModelingDiagram: Hashable, Sendable {
    /// The frame types, which determine the lane.
    public enum Kind: String, Hashable, Sendable {
        case ui, command, readmodel, event, processor
        /// Accepts the documented aliases (`cmd`, `rmo`, `evt`, `pcr`).
        public init?(token: String) {
            switch token.lowercased() {
            case "ui": self = .ui
            case "command", "cmd": self = .command
            case "readmodel", "rmo": self = .readmodel
            case "event", "evt": self = .event
            case "processor", "pcr": self = .processor
            default: return nil
            }
        }
    }
    /// One `tf <nn> <type> <Entity>` frame.
    public struct Frame: Hashable, Sendable {
        /// The author's timeframe number (ordering key; gaps allowed).
        public let timeframe: Int
        public let kind: Kind
        public let entity: String
        public init(timeframe: Int, kind: Kind, entity: String) {
            self.timeframe = timeframe; self.kind = kind; self.entity = entity
        }
    }
    public var frames: [Frame]
    public init(frames: [Frame]) { self.frames = frames }
}

extension MermaidParser {
    /// Parses `eventmodeling` bodies: `tf|timeframe <nn> <type> <Entity>`
    /// statements (inline `{…}` data and `[[…]]` data-block references are
    /// stripped — chips are not drawn in this version), and `rf|resetframe`
    /// lines are ordering directives that need no geometry.
    static func parseEventModeling(body: [String]) -> EventModelingDiagram? {
        var frames: [EventModelingDiagram.Frame] = []
        for line in body {
            var text = line
            // Strip inline data payloads and data-block references.
            if let brace = text.firstIndex(of: "{") { text = String(text[..<brace]) }
            text = text.replacingOccurrences(of: #"\[\[[^\]]*\]\]"#, with: "",
                                             options: .regularExpression)
            let tokens = text.split(separator: " ").map(String.init)
            guard tokens.count >= 4,
                  tokens[0] == "tf" || tokens[0] == "timeframe",
                  let number = Int(tokens[1]),
                  let kind = EventModelingDiagram.Kind(token: tokens[2]) else { continue }
            let entity = tokens[3...].joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !entity.isEmpty else { continue }
            frames.append(.init(timeframe: number, kind: kind, entity: entity))
        }
        guard !frames.isEmpty else { return nil }
        return EventModelingDiagram(frames: frames.sorted { $0.timeframe < $1.timeframe })
    }
}
