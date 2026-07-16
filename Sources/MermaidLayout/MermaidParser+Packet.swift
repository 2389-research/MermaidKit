import Foundation

extension MermaidParser {

    /// Parses `packet` body lines: an optional `title`, then bit-field rows —
    /// `0-15: "Source Port"` or single-bit `16: "Flag"`. Reversed ranges are
    /// normalised. Nil when no field parses.
    static func parsePacket(body: [String]) -> PacketDiagram? {
        var title: String?
        var fields: [PacketDiagram.Field] = []

        var cursor = 0   // next free bit, for the `+N` relative form
        for line in body {
            if line.hasPrefix("title ") {
                title = String(line.dropFirst("title ".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            // `<start>-<end>: "Label"` or `<bit>: "Label"`.
            guard let colon = line.firstIndex(of: ":") else { continue }
            let range = line[..<colon].trimmingCharacters(in: .whitespaces)
            let label = line[line.index(after: colon)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            let bounds = range.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            // Clamp bit indices: a bare Int at Int.max walks layout's
            // `segmentEnd + 1` into an overflow trap (a reproduced crash), and
            // a huge range explodes into tens of thousands of 32-bit rows that
            // take minutes to lay out and lint. 4096 bits comfortably covers
            // real protocol headers (an IPv6 header is 320).
            func clampedBit(_ text: String) -> Int? {
                Int(text).map { min(max($0, 0), 4096) }
            }
            let start: Int, end: Int
            if range.hasPrefix("+"), let width = clampedBit(String(range.dropFirst())), width >= 1 {
                // `+N: "Label"` (v11.7 relative form) is a WIDTH after the
                // previous field — Int("+16") == 16 once placed a single bit
                // at absolute position 16: a confidently wrong bit layout.
                start = cursor; end = min(cursor + width - 1, 4096)
            } else if bounds.count == 2, let a = clampedBit(bounds[0]), let b = clampedBit(bounds[1]) {
                start = min(a, b); end = max(a, b)
            } else if bounds.count == 1, let a = clampedBit(bounds[0]) {
                start = a; end = a
            } else {
                continue
            }
            guard start >= 0, !label.isEmpty else { continue }
            cursor = max(cursor, end + 1)
            fields.append(PacketDiagram.Field(startBit: start, endBit: end, label: label))
        }

        guard !fields.isEmpty else { return nil }
        return PacketDiagram(title: title, fields: fields)
    }
}
