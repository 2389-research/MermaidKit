import Foundation

/// A Mermaid `zenuml` diagram: an alternate sequence-diagram syntax. Participants
/// come from `@Actor`/`@Boundary`/`@Control`/`@Entity`/`@Database` declarations
/// and from message endpoints, in first-appearance order. Messages are the
/// interactions between participants (including self-calls).
public struct ZenUML: Hashable, Sendable {
    /// Declared participant stereotype (`@Actor`, `@Database`, …);
    /// `plain` when undeclared.
    public enum ParticipantKind: String, Hashable, Sendable {
        case actor, boundary, control, entity, database, plain
    }

    /// A lifeline; `id` and `name` both hold the participant's name.
    public struct Participant: Hashable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let kind: ParticipantKind
        /// Memberwise initializer.
        public init(id: String, name: String, kind: ParticipantKind) {
            self.id = id
            self.name = name
            self.kind = kind
        }
    }

    /// One interaction between participant ids in `participants`.
    public struct Message: Hashable, Sendable {
        public let from: String
        public let to: String
        /// Message text or called method; "" when the line names no call.
        public let text: String
        /// True for self-calls (`from == to`).
        public let isSelf: Bool
        /// Memberwise initializer.
        public init(from: String, to: String, text: String, isSelf: Bool) {
            self.from = from
            self.to = to
            self.text = text
            self.isSelf = isSelf
        }
    }

    public var title: String?
    /// Participants in first-appearance order (declared or first messaged).
    public var participants: [Participant]
    /// Messages in source order.
    public var messages: [Message]

    /// Memberwise initializer.
    public init(title: String?, participants: [Participant], messages: [Message]) {
        self.title = title
        self.participants = participants
        self.messages = messages
    }
}

extension MermaidParser {

    /// Parses `zenuml` body lines: `title`, `@Kind Name` participant
    /// declarations, `A->B: text` / `A->B.method()` messages, and
    /// `A.method()` self-calls. Nil without at least one participant and
    /// one message.
    static func parseZenUML(body: [String]) -> ZenUML? {
        var title: String?
        var order: [String] = []
        var declaredKind: [String: ZenUML.ParticipantKind] = [:]
        var messages: [ZenUML.Message] = []

        func register(_ name: String) {
            let key = name.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return }
            if !order.contains(key) { order.append(key) }
        }

        for raw in body {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // Comments and block punctuation are not messages; without these
            // guards `// comment` fabricated a "//" participant and brace
            // lines became phantom calls.
            if line.hasPrefix("//") { continue }
            if line == "{" || line == "}" || line.hasSuffix("{") && !line.contains("->") && !line.contains(".") { continue }
            // `x = A.method()` — the assignment target is syntax, not a
            // participant.
            if let equals = line.range(of: " = ") {
                line = String(line[equals.upperBound...]).trimmingCharacters(in: .whitespaces)
            }

            if line.hasPrefix("title ") {
                title = String(line.dropFirst("title ".count)).trimmingCharacters(in: .whitespaces)
                continue
            }

            // Participant declaration: `@Actor Client`, `@Database DB`, …
            if line.hasPrefix("@") {
                let rest = String(line.dropFirst())
                let parts = rest.split(separator: " ", maxSplits: 1).map { String($0) }
                guard parts.count == 2 else { continue }
                let name = parts[1].trimmingCharacters(in: .whitespaces)
                let kind = ZenUML.ParticipantKind(rawValue: parts[0].lowercased()) ?? .plain
                register(name)
                declaredKind[name] = kind
                continue
            }

            // Message: `A->B: text`, `A->B.method()`, or self-call `A.method()`.
            if let arrow = line.range(of: "->") {
                let from = String(line[..<arrow.lowerBound])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-> "))
                var rhs = String(line[arrow.upperBound...])
                while rhs.hasPrefix(">") { rhs.removeFirst() }
                rhs = rhs.trimmingCharacters(in: .whitespaces)

                let to: String
                let text: String
                if let colon = rhs.firstIndex(of: ":") {
                    to = String(rhs[..<colon]).trimmingCharacters(in: .whitespaces)
                    text = String(rhs[rhs.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                } else if let dot = rhs.firstIndex(of: ".") {
                    to = String(rhs[..<dot]).trimmingCharacters(in: .whitespaces)
                    text = String(rhs[rhs.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
                } else {
                    to = rhs.trimmingCharacters(in: .whitespaces)
                    text = ""
                }
                guard !from.isEmpty, !to.isEmpty else { continue }
                register(from)
                register(to)
                messages.append(ZenUML.Message(from: from, to: to, text: text, isSelf: from == to))
            } else if let dot = line.firstIndex(of: ".") {
                // Self-call: `OrderService.validate()`.
                let who = String(line[..<dot]).trimmingCharacters(in: .whitespaces)
                let text = String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
                guard !who.isEmpty else { continue }
                register(who)
                messages.append(ZenUML.Message(from: who, to: who, text: text, isSelf: true))
            }
        }

        let participants = order.map {
            ZenUML.Participant(id: $0, name: $0, kind: declaredKind[$0] ?? .plain)
        }
        guard !participants.isEmpty, !messages.isEmpty else { return nil }
        return ZenUML(title: title, participants: participants, messages: messages)
    }
}
