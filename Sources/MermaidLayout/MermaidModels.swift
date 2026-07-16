import Foundation

// Parsed Mermaid diagram models (the data types). Parsing lives in
// MermaidParser; per-type layout in DiagramLayout*.swift; drawing in
// the render layer's DiagramRenderer. Split out of MermaidParser.swift so the
// parser file holds logic, not declarations.

/// A Mermaid `flowchart` / `graph`: shaped nodes joined by edges, laid out
/// along a header-declared direction.
public struct Flowchart: Hashable, Sendable {
    /// Layout flow from the header: `TD` top-down, `LR` left-right,
    /// `BT` bottom-top, `RL` right-left.
    public enum Direction: String, Sendable {
        case topDown = "TD"
        case leftRight = "LR"
        case bottomTop = "BT"
        case rightLeft = "RL"
    }

    /// Node outline, from the bracket style wrapping the label.
    public enum NodeShape: Hashable, Sendable {
        case rectangle      // A[Label]
        case rounded        // A(Label)
        case stadium        // A([Label])
        case diamond        // A{Label}
        case circle         // A((Label))
        case cylinder       // A[(Label)] — database
        case stateStart     // state diagram [*] as a source: filled dot
        case stateEnd       // state diagram [*] as a target: ringed dot
    }

    /// One node; `id` is the Mermaid identifier.
    public struct Node: Hashable, Sendable, Identifiable {
        public let id: String
        /// Display text; falls back to `id` when none is declared.
        public var label: String
        public var shape: NodeShape
    }

    /// A connection between two nodes.
    public struct Edge: Hashable, Sendable {
        /// Source node id (an id in `nodes`, or a subgraph id in `subgraphs`).
        public let from: String
        /// Target node id (an id in `nodes`, or a subgraph id in `subgraphs`).
        public let to: String
        /// Optional `|label|` text.
        public var label: String?
        /// Dotted connectors (`-.->`, `-.-`) draw dashed.
        public var dashed: Bool
        /// False for open links (`---`, `-.-`).
        public var hasArrow: Bool
        /// True for bidirectional links (`<-->`): an arrowhead at BOTH ends.
        public var backArrow: Bool = false
    }

    /// A `subgraph id[Label] … end` grouping box. Membership is by id: a node
    /// or nested subgraph belongs to the innermost subgraph that lists it.
    /// Nesting is arbitrary; an edge endpoint may name a subgraph id (the
    /// group as a whole), which the layout connects to the group's box border.
    public struct Subgraph: Hashable, Sendable, Identifiable {
        /// The subgraph's identifier (synthesized `sub0`, `sub1`, … when the
        /// source gives only a title).
        public let id: String
        /// Header text drawn at the top of the box.
        public var label: String
        /// Direct member node ids, in first-appearance order (excludes members
        /// of nested child subgraphs).
        public var nodeIDs: [String]
        /// Directly-nested child subgraph ids, in declaration order.
        public var childIDs: [String]
        /// Inner `direction` override; nil inherits the parent chart's flow.
        public var direction: Direction?
        public init(id: String, label: String, nodeIDs: [String] = [],
                    childIDs: [String] = [], direction: Direction? = nil) {
            self.id = id; self.label = label; self.nodeIDs = nodeIDs
            self.childIDs = childIDs; self.direction = direction
        }
    }

    public var direction: Direction
    /// Nodes in first-appearance order (declared or first referenced).
    public var nodes: [Node]
    public var edges: [Edge]
    /// Subgraph grouping boxes, in declaration order; empty for a flat chart
    /// (the common case — the layout takes a zero-overhead fast path).
    public var subgraphs: [Subgraph]

    public init(direction: Direction, nodes: [Node], edges: [Edge],
                subgraphs: [Subgraph] = []) {
        self.direction = direction
        self.nodes = nodes
        self.edges = edges
        self.subgraphs = subgraphs
    }
}

/// A state machine with nested composite states. Distinct from Flowchart so
/// composites can carry their own sub-diagram (with their own `[*]` entry /
/// exit), and so choice / fork / join get first-class shapes.
public struct StateDiagram: Hashable, Sendable {
    /// What a state node is; drives its drawn shape.
    public indirect enum Kind: Hashable, Sendable {
        case simple                 // rounded state box
        case start                  // `[*]` used as a transition source
        case end                    // `[*]` used as a transition target
        case choice                 // <<choice>>: small diamond
        case fork                   // <<fork>>: bar
        case join                   // <<join>>: bar
        case composite(StateDiagram) // `state X { … }`
    }

    /// One state; `id` is the Mermaid identifier.
    public struct Node: Hashable, Sendable, Identifiable {
        public let id: String
        /// Display text; falls back to `id` when no description is given.
        public var label: String
        public var kind: Kind
    }

    /// A transition between two node ids in `nodes` (within one scope).
    public struct Edge: Hashable, Sendable {
        public let from: String
        public let to: String
        /// Trailing `: text` annotation; nil when unlabelled.
        public var label: String?
    }

    public var direction: Flowchart.Direction
    public var nodes: [Node]
    public var edges: [Edge]
}

/// A Mermaid `sequenceDiagram`: participants (lifelines) exchanging an
/// ordered list of messages.
public struct SequenceDiagram: Hashable, Sendable {
    /// A lifeline; `id` is the Mermaid identifier.
    public struct Participant: Hashable, Sendable, Identifiable {
        /// Head glyph kinds (mermaid v11 `@{ "type": "..." }`, matching
        /// websequencediagrams' classic participant types).
        public enum Kind: String, Hashable, Sendable {
            case participant, actor, database, queue, collections
            case boundary, control, entity
        }
        public let id: String
        /// Display text; the `as` alias when declared, else the id.
        public var label: String
        /// Declared with `actor` — drawn as a stick figure, not a box.
        public var isActor: Bool = false
        /// Head glyph; `.actor` mirrors `isActor` (kept for compatibility).
        public var kind: Kind = .participant
    }

    /// A `Note right of A: ...` / `Note over A,B: ...` annotation, anchored
    /// between messages.
    public struct Note: Hashable, Sendable {
        public enum Position: String, Hashable, Sendable { case leftOf, rightOf, over }
        public let position: Position
        /// One participant id (left/right) or one-or-two (over).
        public let ids: [String]
        public let text: String
        /// Number of messages that precede this note (its row anchor).
        public let afterMessage: Int
        public init(position: Position, ids: [String], text: String, afterMessage: Int) {
            self.position = position; self.ids = ids
            self.text = text; self.afterMessage = afterMessage
        }
    }

    /// One message arrow.
    public struct Message: Hashable, Sendable {
        /// Arrowhead identity — mermaid's eight arrow tokens differ by head
        /// as well as line style, and the head carries meaning (sync call vs
        /// async signal vs lost message).
        public enum ArrowHead: String, Hashable, Sendable {
            /// `->` / `-->`: a bare line, no head.
            case none
            /// `->>` / `-->>`: filled arrowhead (synchronous call).
            case filled
            /// `-x` / `--x`: cross head (lost/terminated message).
            case cross
            /// `-)` / `--)`: open half-arrow (asynchronous signal).
            case open
            /// `<<->>` / `<<-->>`: filled heads at BOTH ends.
            case both
        }
        /// Sender participant id (an id in `participants`).
        public let from: String
        /// Receiver participant id (an id in `participants`).
        public let to: String
        public var text: String
        /// Reply arrows (`-->`, `-->>`) draw dashed.
        public var dashed: Bool
        /// Head style; `.filled` matches the most common token (`->>`).
        public var head: ArrowHead = .filled
        /// Autonumber badge value, when `autonumber` is active.
        public var number: Int?
        /// `A->>+B:` — the receiver activates when this message lands.
        public var activatesTarget: Bool = false
        /// `B->>-A:` — the sender deactivates as this message leaves.
        public var deactivatesSender: Bool = false
    }

    /// A combined fragment (`loop`/`alt`/`opt`/`par`/`critical`/`break`) or
    /// background `rect`, spanning a range of the event stream.
    public struct Fragment: Hashable, Sendable {
        public enum Kind: String, Hashable, Sendable {
            case loop, alt, opt, par, critical, `break`, rect
        }
        public let kind: Kind
        /// The guard/label after the keyword (`alt is sick` → "is sick");
        /// for `rect`, the color spec (unused by our theme-driven fill).
        public let label: String?
        public init(kind: Kind, label: String?) { self.kind = kind; self.label = label }
    }

    /// One entry in the diagram's row stream, in exact source order. Indices
    /// point into `messages`, `notes`, and `fragments`.
    public enum Event: Hashable, Sendable {
        case message(Int)
        case note(Int)
        /// A fragment opens (its label tab row).
        case open(Int)
        /// An `else`/`and`/`option` divider inside fragment `fragment`.
        case divider(fragment: Int, label: String?)
        /// A fragment closes.
        case close(Int)
        /// Explicit `activate X` / `deactivate X` statements.
        case activate(String)
        case deactivate(String)
        /// `create participant X` — the head appears at this row.
        case create(String)
        /// `destroy X` — the lifeline ends with a cross at this row.
        case destroy(String)
    }

    /// A `box [color] Label ... end` grouping of participants.
    public struct Box: Hashable, Sendable {
        public let label: String?
        public let memberIDs: [String]
        public init(label: String?, memberIDs: [String]) {
            self.label = label; self.memberIDs = memberIDs
        }
    }

    /// Participants in first-appearance order (declared or first messaged).
    public var participants: [Participant]
    /// Participant groupings drawn as background bands.
    public var boxes: [Box] = []
    /// Notes, anchored between messages by `afterMessage`.
    public var notes: [Note] = []
    /// Combined fragments / rects, indexed by `Event.open/close/divider`.
    public var fragments: [Fragment] = []
    /// The full row stream in source order. Empty for diagrams built before
    /// fragments existed (layout falls back to messages + anchored notes).
    public var events: [Event] = []
    /// Messages in source order.
    public var messages: [Message]
}

/// A Mermaid `classDiagram`: class boxes with attribute/method compartments,
/// joined by typed relations.
public struct ClassDiagram: Hashable, Sendable {
    /// One class box. Identity is the class `name`.
    public struct Class: Hashable, Sendable, Identifiable {
        /// Same as `name`.
        public var id: String { name }
        public let name: String
        /// Attribute compartment lines, as written (members without `()`).
        public var attributes: [String]
        /// Method compartment lines, as written (members containing `()`).
        public var methods: [String]
    }

    /// The marker draws at the `to` end of the relation; parse-time
    /// normalization flips reversed arrows so this always holds.
    public enum RelationKind: Hashable, Sendable {
        case inheritance    // hollow triangle
        case realization    // hollow triangle, dashed line
        case composition    // filled diamond
        case aggregation    // hollow diamond
        case association    // open arrowhead
        case dependency     // open arrowhead, dashed line
        case link           // plain line

        /// Kinds whose line draws dashed (realization, dependency).
        public var dashed: Bool { self == .realization || self == .dependency }
    }

    /// A typed connection between two class names in `classes`.
    /// The kind's marker sits at the `to` end.
    public struct Relation: Hashable, Sendable {
        public let from: String
        public let to: String
        public var kind: RelationKind
        /// Trailing `: text` annotation; nil when unlabelled.
        public var label: String?
    }

    /// Classes in first-appearance order (declared or first related).
    public var classes: [Class]
    public var relations: [Relation]
}

/// A Mermaid `erDiagram`: entities with typed attributes, joined by
/// cardinality-marked relationships.
public struct ERDiagram: Hashable, Sendable {
    /// Crow's-foot cardinality at one end of a relationship.
    public enum Cardinality: Hashable, Sendable {
        case one            // ||
        case zeroOrOne      // |o / o|
        case oneOrMore      // |{ / }|
        case zeroOrMore     // o{ / }o
    }

    /// One attribute row inside an entity box: a type and a name.
    public struct Attribute: Hashable, Sendable {
        public let type: String
        public let name: String
    }

    /// An entity box. Identity is the entity `name`.
    public struct Entity: Hashable, Sendable, Identifiable {
        /// Same as `name`.
        public var id: String { name }
        public let name: String
        public var attributes: [Attribute]
    }

    /// A relationship between two entity names in `entities`.
    public struct Relation: Hashable, Sendable {
        public let from: String
        public let to: String
        /// Cardinality marker at the `from` end.
        public var fromCard: Cardinality
        /// Cardinality marker at the `to` end.
        public var toCard: Cardinality
        /// Relationship verb drawn on the line.
        public var label: String
        /// Non-identifying relationships (`..`) draw dashed.
        public var identifying: Bool
    }

    public var entities: [Entity]
    public var relations: [Relation]
}

/// A Mermaid `pie` chart: labelled slices drawn proportionally to value.
public struct PieChart: Hashable, Sendable {
    /// One wedge; `value` is a non-negative share (not a percentage).
    public struct Slice: Hashable, Sendable {
        public let label: String
        public let value: Double
    }

    public var title: String?
    /// Slices in declaration order.
    public var slices: [Slice]
}

/// A Gantt chart: sections of time-boxed tasks. Each task's start and length
/// are resolved to a numeric **day timeline** at parse time — from an explicit
/// `dateFormat` date, an `after <id>` dependency, or an implicit "starts when
/// the previous task ends" — so the layout engine only maps days to pixels.
/// The earliest task sits at day 0. Directives that don't affect bar geometry
/// (`axisFormat`, `excludes`, `todayMarker`) are accepted and ignored; only
/// the ISO `YYYY-MM-DD` date format is understood.
public struct GanttChart: Hashable, Sendable {
    /// Highlight tag from the task spec (`active`, `done`, `crit`).
    public enum Status: String, Hashable, Sendable {
        case normal, active, done, critical
    }

    /// One bar (or milestone diamond); `id` is the explicit task id when
    /// given, else a generated `task<n>`.
    public struct Task: Hashable, Sendable, Identifiable {
        public let id: String
        public var label: String
        /// Owning section name, or "" when the task precedes any `section`.
        public var section: String
        /// Offset from the project start, in days (earliest task = 0).
        public var start: Double
        /// Duration in days; 0 for a milestone.
        public var length: Double
        public var isMilestone: Bool
        public var status: Status

        /// Memberwise initializer.
        public init(id: String, label: String, section: String, start: Double,
                    length: Double, isMilestone: Bool, status: Status) {
            self.id = id
            self.label = label
            self.section = section
            self.start = start
            self.length = length
            self.isMilestone = isMilestone
            self.status = status
        }

        /// Day offset of the task's end (start + length).
        public var end: Double { start + length }
    }

    public var title: String?
    /// Tasks in declaration order.
    public var tasks: [Task]
    /// Section names in first-appearance order.
    public var sections: [String]
}

/// A Mermaid `timeline`: an ordered list of time periods, each carrying a
/// handful of events, optionally grouped into named sections. Rendered as a
/// vertical spine (fits a document's column better than the horizontal
/// original).
public struct Timeline: Hashable, Sendable {
    /// One time period on the spine, with its events in source order.
    public struct Period: Hashable, Sendable {
        public let label: String
        /// Owning section, or "" when the period precedes any `section`.
        public let section: String
        public let events: [String]

        /// Memberwise initializer.
        public init(label: String, section: String, events: [String]) {
            self.label = label
            self.section = section
            self.events = events
        }
    }

    public var title: String?
    /// Periods in declaration order.
    public var periods: [Period]
    /// Section names in first-appearance order (for stable tinting).
    public var sections: [String]

    /// Memberwise initializer.
    public init(title: String?, periods: [Period], sections: [String]) {
        self.title = title
        self.periods = periods
        self.sections = sections
    }
}

/// A Mermaid `mindmap`: a single-rooted tree whose hierarchy comes from
/// indentation. Node shape decorations (`((circle))`, `[square]`, …) are
/// stripped to their label text. `[MindmapNode]` provides the recursion.
public struct Mindmap: Hashable, Sendable {
    public var root: MindmapNode
    /// Wraps the root of the parsed tree.
    public init(root: MindmapNode) { self.root = root }
}

/// One mindmap node: a label and its children (empty for a leaf).
public struct MindmapNode: Hashable, Sendable {
    public let label: String
    public let children: [MindmapNode]
    /// Creates a node; `children` defaults to empty (a leaf).
    public init(label: String, children: [MindmapNode] = []) {
        self.label = label
        self.children = children
    }
}

/// A Mermaid `journey` (user journey): titled sections of tasks, each task
/// carrying a 1–5 satisfaction score and the actors involved.
public struct UserJourney: Hashable, Sendable {
    /// One journey step.
    public struct Task: Hashable, Sendable {
        public let label: String
        /// Satisfaction, clamped to 1…5.
        public let score: Int
        /// Actor names involved in this step; may be empty.
        public let actors: [String]
        /// Owning section, or "" when the task precedes any `section`.
        public let section: String

        /// Memberwise initializer.
        public init(label: String, score: Int, actors: [String], section: String) {
            self.label = label
            self.score = score
            self.actors = actors
            self.section = section
        }
    }

    public var title: String?
    /// Tasks in declaration order.
    public var tasks: [Task]
    /// Section names in first-appearance order.
    public var sections: [String]

    /// Memberwise initializer.
    public init(title: String?, tasks: [Task], sections: [String]) {
        self.title = title
        self.tasks = tasks
        self.sections = sections
    }
}

/// A Mermaid `quadrantChart`: labelled points plotted in a 2×2 matrix with
/// axis-end labels and per-quadrant names. Coordinates are 0…1 (x: left→right,
/// y: bottom→top). Quadrant order matches Mermaid: 1 top-right, 2 top-left,
/// 3 bottom-left, 4 bottom-right.
public struct QuadrantChart: Hashable, Sendable {
    /// A plotted point; `x`/`y` are 0…1 (x left→right, y bottom→top).
    public struct Point: Hashable, Sendable {
        public let label: String
        public let x: Double
        public let y: Double
        /// Memberwise initializer.
        public init(label: String, x: Double, y: Double) {
            self.label = label
            self.x = x
            self.y = y
        }
    }

    public var title: String?
    public var xAxisLeft: String?
    public var xAxisRight: String?
    public var yAxisBottom: String?
    public var yAxisTop: String?
    /// Quadrant names [q1, q2, q3, q4]; any may be nil.
    public var quadrants: [String?]
    public var points: [Point]

    /// Memberwise initializer.
    public init(title: String?, xAxisLeft: String?, xAxisRight: String?,
                yAxisBottom: String?, yAxisTop: String?, quadrants: [String?], points: [Point]) {
        self.title = title
        self.xAxisLeft = xAxisLeft
        self.xAxisRight = xAxisRight
        self.yAxisBottom = yAxisBottom
        self.yAxisTop = yAxisTop
        self.quadrants = quadrants
        self.points = points
    }
}

/// A Mermaid `packet` diagram: named bit-field ranges laid out on a 32-bit
/// grid (a protocol-header picture).
public struct PacketDiagram: Hashable, Sendable {
    /// One bit field spanning `startBit`…`endBit` inclusive (bit 0 first;
    /// startBit <= endBit — a single-bit field has them equal).
    public struct Field: Hashable, Sendable {
        public let startBit: Int
        public let endBit: Int
        public let label: String
        /// Memberwise initializer.
        public init(startBit: Int, endBit: Int, label: String) {
            self.startBit = startBit
            self.endBit = endBit
            self.label = label
        }
    }

    public var title: String?
    /// Fields in declaration order.
    public var fields: [Field]
    /// Memberwise initializer.
    public init(title: String?, fields: [Field]) {
        self.title = title
        self.fields = fields
    }
}

/// A Mermaid `xychart`: bar and/or line series over shared x-axis categories,
/// with an optional y-axis range and titles.
public struct XYChart: Hashable, Sendable {
    /// How a series draws: bars or a connected line.
    public enum SeriesKind: Hashable, Sendable { case bar, line }

    /// One data series; `values` align with `categories` by index.
    public struct Series: Hashable, Sendable {
        public let kind: SeriesKind
        public let values: [Double]
        /// Memberwise initializer.
        public init(kind: SeriesKind, values: [Double]) {
            self.kind = kind
            self.values = values
        }
    }

    public var title: String?
    public var xAxisTitle: String?
    /// Category labels along the x-axis.
    public var categories: [String]
    public var yAxisTitle: String?
    /// Explicit y-axis lower bound; nil when the source gives no range.
    public var yMin: Double?
    /// Explicit y-axis upper bound; nil when the source gives no range.
    public var yMax: Double?
    public var series: [Series]

    /// Memberwise initializer.
    public init(title: String?, xAxisTitle: String?, categories: [String],
                yAxisTitle: String?, yMin: Double?, yMax: Double?, series: [Series]) {
        self.title = title
        self.xAxisTitle = xAxisTitle
        self.categories = categories
        self.yAxisTitle = yAxisTitle
        self.yMin = yMin
        self.yMax = yMax
        self.series = series
    }
}

/// A Mermaid `kanban` board: named columns, each holding cards with optional
/// ticket and priority metadata. Hierarchy comes from indentation.
public struct KanbanBoard: Hashable, Sendable {
    /// One card; `ticket` and `priority` come from trailing `@{…}` metadata
    /// and are nil when absent.
    public struct Card: Hashable, Sendable {
        public let text: String
        public let ticket: String?
        public let priority: String?
        /// Creates a card; metadata defaults to nil.
        public init(text: String, ticket: String? = nil, priority: String? = nil) {
            self.text = text
            self.ticket = ticket
            self.priority = priority
        }
    }

    /// A named column with its cards in declaration order.
    public struct Column: Hashable, Sendable {
        public let title: String
        public let cards: [Card]
        /// Memberwise initializer.
        public init(title: String, cards: [Card]) {
            self.title = title
            self.cards = cards
        }
    }

    /// Columns in declaration order.
    public var columns: [Column]
    /// Memberwise initializer.
    public init(columns: [Column]) { self.columns = columns }
}

/// A Mermaid `radar` chart: named axes and one or more curves scoring each
/// axis, drawn as overlaid polygons on a spoked graticule.
public struct RadarChart: Hashable, Sendable {
    /// One spoke; `key` is the identifier curves score against, `label`
    /// the display text (falls back to the key).
    public struct Axis: Hashable, Sendable {
        public let key: String
        public let label: String
        /// Memberwise initializer.
        public init(key: String, label: String) {
            self.key = key
            self.label = label
        }
    }

    /// One polygon overlaid on the graticule.
    public struct Curve: Hashable, Sendable {
        public let label: String
        /// Values aligned to `axes` order (missing axes default to min).
        public let values: [Double]
        /// Memberwise initializer.
        public init(label: String, values: [Double]) {
            self.label = label
            self.values = values
        }
    }

    public var title: String?
    public var axes: [Axis]
    public var curves: [Curve]
    /// Value at the graticule's outer ring (default 100).
    public var maxValue: Double
    /// Value at the centre (default 0).
    public var minValue: Double
    /// Number of graticule rings; always >= 1.
    public var ticks: Int

    /// Memberwise initializer.
    public init(title: String?, axes: [Axis], curves: [Curve],
                maxValue: Double, minValue: Double, ticks: Int) {
        self.title = title
        self.axes = axes
        self.curves = curves
        self.maxValue = maxValue
        self.minValue = minValue
        self.ticks = ticks
    }
}

/// A Mermaid `treemap`: a weighted hierarchy drawn as nested rectangles.
/// Leaf nodes carry an explicit value; an internal node's value is the sum of
/// its children. Hierarchy comes from indentation.
public struct TreemapNode: Hashable, Sendable {
    public let label: String
    /// The node's weight; for an internal node, the sum of its children.
    public let value: Double
    public let children: [TreemapNode]
    /// Creates a node; `children` defaults to empty (a leaf).
    public init(label: String, value: Double, children: [TreemapNode] = []) {
        self.label = label
        self.value = value
        self.children = children
    }
}

/// A parsed `treemap` diagram: a wrapper around its root `TreemapNode`.
public struct Treemap: Hashable, Sendable {
    public var root: TreemapNode
    /// Wraps the root of the parsed tree.
    public init(root: TreemapNode) { self.root = root }
}

/// A Mermaid `gitGraph`: an ordered commit history across branches, with
/// branch/checkout/merge operations. Each commit records its branch, parents
/// (indices into `commits`), and optional id/tag.
public struct GitGraph: Hashable, Sendable {
    /// One commit, in sequence order.
    public struct Commit: Hashable, Sendable {
        /// Explicit `id:` value, or an auto-generated `c<n>` / `merge<n>`.
        public let id: String
        /// Owning branch name (an entry in `branches`).
        public let branch: String
        /// `tag:` value; nil when untagged.
        public let tag: String?
        public let isMerge: Bool
        /// Indices into `commits` of this commit's parents (0–2).
        public let parents: [Int]
        /// True when the author wrote an explicit `id:`; auto-generated ids
        /// (`c<n>`, `merge<n>`) exist for identity but are not drawn.
        public let hasExplicitID: Bool
        /// Memberwise initializer.
        public init(id: String, branch: String, tag: String?, isMerge: Bool,
                    parents: [Int], hasExplicitID: Bool = true) {
            self.id = id
            self.branch = branch
            self.tag = tag
            self.isMerge = isMerge
            self.parents = parents
            self.hasExplicitID = hasExplicitID
        }
    }

    /// Commits in source order (topologically valid: parents precede children).
    public var commits: [Commit]
    /// Branch names in creation order (their lane order).
    public var branches: [String]
    /// Memberwise initializer.
    public init(commits: [Commit], branches: [String]) {
        self.commits = commits
        self.branches = branches
    }
}
