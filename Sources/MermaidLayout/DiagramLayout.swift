import Foundation
#if canImport(CoreGraphics)
// On Apple platforms the CGRect/CGPoint conveniences (midX, init(x:y:…))
// live in CoreGraphics; on Linux swift-corelibs-foundation provides them.
import CoreGraphics
#endif

/// Measures a text label at a font size — injected by the renderer so the
/// layout engines stay platform-free and unit-testable.
public typealias DiagramTextMeasurer = (_ text: String, _ fontSize: Double) -> CGSize

/// Placed flowchart geometry — produced by the layout engine; the renderer
/// only draws. As for every `*Layout` struct in this module: coordinates are
/// points in a top-left-origin space (y increases downward), and `size` is
/// the canvas the whole layout fits in.
public struct FlowchartLayout: Sendable {
    /// A node with its final bounding box; the shape outline is inscribed in
    /// `frame`.
    public struct PlacedNode: Sendable {
        /// Node identifier from the Mermaid source.
        public let id: String
        public let label: String
        public let shape: Flowchart.NodeShape
        public let frame: CGRect
    }

    /// An edge with its resolved orthogonal route.
    public struct PlacedEdge: Sendable {
        /// Route start, on the source node's outline.
        public let start: CGPoint
        /// Route end, on the target node's outline (arrowhead here when
        /// `hasArrow`).
        public let end: CGPoint
        /// Full polyline route (orthogonal between offset nodes); always
        /// begins at `start` and ends at `end`.
        public let points: [CGPoint]
        public let label: String?
        public let dashed: Bool
        public let hasArrow: Bool
        /// Arrowhead at the START too (`<-->`).
        public let backArrow: Bool
        /// Where to center the label — chosen by the layout to avoid boxes and
        /// other labels. nil for an unlabeled edge; the renderer falls back to
        /// the route midpoint if it is somehow absent.
        public let labelPoint: CGPoint?

        /// Creates a placed edge; omitting `points` yields the straight
        /// two-point route `[start, end]`.
        public init(start: CGPoint, end: CGPoint, points: [CGPoint]? = nil,
                    label: String?, dashed: Bool, hasArrow: Bool, backArrow: Bool = false,
                    labelPoint: CGPoint? = nil) {
            self.start = start
            self.end = end
            self.points = points ?? [start, end]
            self.label = label
            self.dashed = dashed
            self.hasArrow = hasArrow
            self.backArrow = backArrow
            self.labelPoint = labelPoint
        }
    }

    /// A laid-out subgraph grouping box: a labeled rectangle enclosing its
    /// members (and any nested containers). Drawn behind the nodes; `depth` is
    /// the nesting level (0 = outermost) so the renderer can tint by depth.
    public struct Container: Sendable {
        public let id: String
        public let label: String
        public let frame: CGRect
        public let depth: Int
        public init(id: String, label: String, frame: CGRect, depth: Int) {
            self.id = id; self.label = label; self.frame = frame; self.depth = depth
        }
    }

    /// Canvas the whole layout fits in.
    public let size: CGSize
    public let nodes: [PlacedNode]
    public let edges: [PlacedEdge]
    /// Subgraph boxes, outermost first; empty for a flat chart.
    public let containers: [Container]

    public init(size: CGSize, nodes: [PlacedNode], edges: [PlacedEdge],
                containers: [Container] = []) {
        self.size = size
        self.nodes = nodes
        self.edges = edges
        self.containers = containers
    }
}

/// Placed sequence diagram: participant head boxes across the top, lifelines
/// dropping to `lifelineBottom`, and message arrows stacked top to bottom.
/// Top-left-origin points; `size` is the canvas.
public struct SequenceLayout: Sendable {
    /// A participant's header box; its lifeline drops from `lifelineX`.
    public struct Head: Sendable {
        public let label: String
        public var frame: CGRect
        /// Drawn as a stick figure (declared with `actor`) instead of a box.
        public let isActor: Bool
        /// Head glyph kind (raw value of `SequenceDiagram.Participant.Kind`).
        public var kind: String = "participant"
        /// Where this lifeline stops (a `destroy` row); nil = the shared bottom.
        public var lifelineEndY: CGFloat?
        /// Draw the destruction cross at `lifelineEndY`.
        public var showsDestroyCross: Bool = false
        /// X of the participant's vertical lifeline (the head's center).
        public var lifelineX: CGFloat { frame.midX }
        public init(label: String, frame: CGRect, isActor: Bool = false,
                    kind: String = "participant") {
            self.label = label; self.frame = frame; self.isActor = isActor
            self.kind = kind
        }
    }

    /// A combined-fragment frame (loop/alt/opt/par/critical/break) or a
    /// background rect, already positioned around its rows.
    public struct Frame: Sendable {
        /// Divider line (`else`/`and`/`option`) inside the frame.
        public struct Divider: Sendable {
            public let y: CGFloat
            public let label: String?
            public init(y: CGFloat, label: String?) { self.y = y; self.label = label }
        }
        /// Raw value of `SequenceDiagram.Fragment.Kind`.
        public let kind: String
        public let label: String?
        public let rect: CGRect
        public let dividers: [Divider]
        public init(kind: String, label: String?, rect: CGRect, dividers: [Divider]) {
            self.kind = kind; self.label = label; self.rect = rect; self.dividers = dividers
        }
    }

    /// An activation bar: an execution interval on a lifeline. Nested
    /// activations stack with increasing `depth` (drawn offset rightward).
    public struct Bar: Sendable {
        public let x: CGFloat
        public let depth: Int
        public let top: CGFloat
        public let bottom: CGFloat
        public init(x: CGFloat, depth: Int, top: CGFloat, bottom: CGFloat) {
            self.x = x; self.depth = depth; self.top = top; self.bottom = bottom
        }
    }

    /// A note box anchored between message rows.
    public struct NoteBox: Sendable {
        public let text: String
        public let frame: CGRect
        public init(text: String, frame: CGRect) { self.text = text; self.frame = frame }
    }

    /// A message arrow drawn at `y` between two lifelines.
    public struct Arrow: Sendable {
        /// Sender's lifeline x.
        public let fromX: CGFloat
        /// Recipient's lifeline x; for a self-message, the loop's right extent.
        public let toX: CGFloat
        /// Y the arrow is drawn at.
        public let y: CGFloat
        public let text: String
        public let dashed: Bool
        /// Message to the same participant: drawn as a small loop.
        public let isSelfMessage: Bool
        /// Arrowhead style (raw value of `SequenceDiagram.Message.ArrowHead`).
        public let head: SequenceDiagram.Message.ArrowHead
        /// Autonumber badge, when active.
        public let number: Int?

        /// Creates an arrow; defaults to a normal (non-self) message.
        public init(fromX: CGFloat, toX: CGFloat, y: CGFloat, text: String, dashed: Bool,
                    isSelfMessage: Bool = false,
                    head: SequenceDiagram.Message.ArrowHead = .filled, number: Int? = nil) {
            self.fromX = fromX
            self.toX = toX
            self.y = y
            self.text = text
            self.dashed = dashed
            self.isSelfMessage = isSelfMessage
            self.head = head
            self.number = number
        }
    }

    public let size: CGSize
    /// Participant heads in declaration order.
    public let heads: [Head]
    /// Y where every lifeline ends.
    public let lifelineBottom: CGFloat
    /// Message arrows in source order, top to bottom.
    public let arrows: [Arrow]
    /// Note boxes, already positioned in their interleaved rows.
    public var notes: [NoteBox] = []
    /// Fragment frames, outermost first (draw order: behind rows).
    public var frames: [Frame] = []
    /// Activation bars on lifelines.
    public var bars: [Bar] = []
    /// Participant-group background bands (`box ... end`).
    public struct BoxBand: Sendable {
        public let label: String?
        public let rect: CGRect
        public let colorIndex: Int
        public init(label: String?, rect: CGRect, colorIndex: Int) {
            self.label = label; self.rect = rect; self.colorIndex = colorIndex
        }
    }
    public var boxBands: [BoxBand] = []
}

/// Placed pie chart: a disk of slices with a legend column to its right.
/// Top-left-origin points; `size` is the canvas.
public struct PieLayout: Sendable {
    /// One wedge; consecutive slices share boundary angles.
    public struct Slice: Sendable {
        public let label: String
        public let value: Double
        /// Share of the total, 0…1.
        public let fraction: Double
        public let startAngle: Double // radians, 12 o'clock = -π/2, clockwise
        public let endAngle: Double
        /// Cycled palette slot (slice order), not a color.
        public let colorIndex: Int
    }

    public let size: CGSize
    /// Center of the disk.
    public let center: CGPoint
    public let radius: CGFloat
    public let title: String?
    public let slices: [Slice]
    /// Top-left anchor of the legend; one row per slice stacks downward.
    public let legendOrigin: CGPoint
}

/// Placed Gantt chart: a task-label gutter on the left, section tint bands,
/// day-tick gridlines, and one bar (or milestone diamond) per task row.
/// Top-left-origin points; `size` is the canvas.
public struct GanttLayout: Sendable {
    /// One task's bar row.
    public struct Bar: Sendable {
        public let label: String
        /// The bar rectangle, or the milestone diamond's bounding box.
        public let frame: CGRect
        /// Right edge of the label gutter at the row's vertical center; the
        /// renderer right-aligns the task label to this point.
        public let labelPoint: CGPoint
        public let isMilestone: Bool
        public let status: GanttChart.Status
    }

    /// Tint band behind one section's rows.
    public struct SectionBand: Sendable {
        public let name: String
        /// Full-width tint band spanning the section's consecutive rows.
        public let frame: CGRect
        /// Cycled palette slot (section order), not a color.
        public let colorIndex: Int
    }

    /// A vertical day gridline spanning `top`…`bottom` at `x`.
    public struct Tick: Sendable {
        public let x: CGFloat
        public let label: String   // day index
        public let top: CGFloat
        public let bottom: CGFloat
    }

    public let size: CGSize
    public let title: String?
    /// X where the bar area begins (right of the task-label gutter).
    public let labelGutter: CGFloat
    public let bars: [Bar]
    public let sections: [SectionBand]
    public let ticks: [Tick]
}

/// Placed timeline: a vertical spine with one dot per period, period labels
/// in a left gutter, and event cards stacked right of each dot.
/// Top-left-origin points; `size` is the canvas.
public struct TimelineLayout: Sendable {
    /// One event card.
    public struct Event: Sendable {
        public let text: String
        public let frame: CGRect
        /// Categorical tint index (by section, else by period).
        public let colorIndex: Int
    }

    /// A period: its dot on the spine, gutter label anchor, and event cards.
    public struct Period: Sendable {
        public let label: String
        /// Right-aligned anchor for the period label: right edge at vertical
        /// center of the period's first row.
        public let labelPoint: CGPoint
        /// The node dot sitting on the spine.
        public let dot: CGPoint
        public let events: [Event]
    }

    /// Tint band behind one section's periods.
    public struct SectionBand: Sendable {
        public let name: String
        /// Full-width tint band spanning the section's consecutive periods.
        public let frame: CGRect
        public let colorIndex: Int
    }

    public let size: CGSize
    public let title: String?
    /// X of the vertical spine the period dots sit on.
    public let spineX: CGFloat
    /// Y of the first period's dot.
    public let spineTop: CGFloat
    /// Y of the last period's dot.
    public let spineBottom: CGFloat
    public let periods: [Period]
    public let sections: [SectionBand]
}

/// Placed mindmap: a left-to-right tree — root at the left, one column per
/// depth, siblings stacked vertically. Top-left-origin points; `size` is the
/// canvas.
public struct MindmapLayout: Sendable {
    public struct Node: Sendable {
        public let label: String
        public let frame: CGRect
        /// Tree depth; 0 = root, increasing rightward (one column per depth).
        public let depth: Int
        /// Categorical tint index: which top-level branch this node belongs to.
        public let colorIndex: Int
    }

    /// Parent→child connector.
    public struct Edge: Sendable {
        /// Right-center of the parent node.
        public let from: CGPoint
        /// Left-center of the child node.
        public let to: CGPoint
        /// Tint index of the child's branch.
        public let colorIndex: Int
    }

    public let size: CGSize
    public let nodes: [Node]
    public let edges: [Edge]
}

/// Placed user journey: one row per task (score badge, label, actor list),
/// grouped into section tint bands. Top-left-origin points; `size` is the
/// canvas.
public struct JourneyLayout: Sendable {
    /// One task row.
    public struct Task: Sendable {
        public let label: String
        /// Left-aligned anchor at the row's vertical center.
        public let labelPoint: CGPoint
        /// Satisfaction score, 1…5 (drives the score badge colour).
        public let score: Int
        public let scoreCenter: CGPoint
        /// Actors joined for display, and their left-aligned anchor.
        public let actors: String
        public let actorsPoint: CGPoint
    }

    /// Full-width tint band behind one section's consecutive rows.
    public struct SectionBand: Sendable {
        public let name: String
        public let frame: CGRect
        /// Cycled palette slot (section order), not a color.
        public let colorIndex: Int
    }

    public let size: CGSize
    public let title: String?
    /// Diameter of every score badge (`Task.scoreCenter` is its center).
    public let scoreDiameter: CGFloat
    public let tasks: [Task]
    public let sections: [SectionBand]
}

/// Placed quadrant chart: a square 2×2 plot with tinted quarters, plotted
/// points, and axis-end labels. Top-left-origin points; `size` is the canvas.
public struct QuadrantLayout: Sendable {
    /// A plotted data point.
    public struct Point: Sendable {
        public let label: String
        /// Dot center, inside `plotRect`.
        public let position: CGPoint
        /// Left-aligned anchor for the point's label (right of the dot).
        public let labelPoint: CGPoint
    }

    /// A text label anchored at its center point.
    public struct Label: Sendable {
        public let text: String
        public let center: CGPoint
    }

    public let size: CGSize
    public let title: String?
    /// The square plot area the four quadrant quarters tile.
    public let plotRect: CGRect
    /// Radius of every point dot.
    public let dotRadius: CGFloat
    public let points: [Point]
    /// One tint quarter per quadrant [q1 TR, q2 TL, q3 BL, q4 BR].
    public let quadrantRects: [CGRect]
    /// Quadrant name labels, centered horizontally in their quarter and pushed
    /// toward its outer edge (clear of points near the center lines); unnamed
    /// quadrants are omitted.
    public let quadrantLabels: [Label]
    /// x-axis end labels (below the plot), horizontal.
    public let xAxisLabels: [Label]
    /// y-axis end labels (left gutter), drawn rotated 90°.
    public let yAxisLabels: [Label]
}

/// Placed packet diagram: field boxes on a `bitsPerRow`-bit grid; a field
/// crossing a row boundary is split into multiple `segments`.
/// Top-left-origin points; `size` is the canvas.
public struct PacketLayout: Sendable {
    /// How a segment's label fits: horizontally, rotated vertically (for narrow
    /// single-/few-bit fields like TCP flags), or not at all.
    public enum LabelMode: Sendable { case horizontal, vertical, none }

    /// One row-slice of a field (a field wraps into multiple segments when it
    /// crosses the 32-bit row boundary).
    public struct Segment: Sendable {
        public let label: String
        public let labelMode: LabelMode
        public let frame: CGRect
        public let startBit: Int
        public let endBit: Int
        /// Cycled palette slot per source field (a wrapped field's segments
        /// share one slot), not a color.
        public let colorIndex: Int
    }

    public let size: CGSize
    public let title: String?
    /// Bits per grid row (32).
    public let bitsPerRow: Int
    public let segments: [Segment]
}

/// Placed xy chart: grouped bar and/or line series over shared x categories,
/// with a value axis on the left. Top-left-origin points; `size` is the
/// canvas.
public struct XYChartLayout: Sendable {
    /// One bar of a bar series.
    public struct Bar: Sendable {
        public let frame: CGRect
        /// The owning series' index in the chart's series list (palette slot).
        public let colorIndex: Int
    }

    /// A line series' polyline through the category centers.
    public struct Line: Sendable {
        public let points: [CGPoint]
        /// The owning series' index in the chart's series list (palette slot).
        public let colorIndex: Int
    }

    /// A text label anchored at its center point.
    public struct Label: Sendable {
        public let text: String
        public let center: CGPoint
    }

    public let size: CGSize
    public let title: String?
    /// The data plot area.
    public let plotRect: CGRect
    public let bars: [Bar]
    public let lines: [Line]
    /// Category labels below the plot.
    public let xLabels: [Label]
    /// Value ticks left of the plot (with gridline y positions).
    public let yLabels: [Label]
    /// Rotated y-axis title in the left gutter, if any.
    public let yAxisTitle: Label?
    /// x-axis title centered below, if any.
    public let xAxisTitle: Label?
}

/// Placed kanban board: tinted column headers over vertical stacks of cards.
/// Top-left-origin points; `size` is the canvas.
public struct KanbanLayout: Sendable {
    /// One card; its frame reserves a row for the ticket line when present.
    public struct Card: Sendable {
        /// Pre-wrapped text lines.
        public let lines: [String]
        public let ticket: String?
        public let frame: CGRect
        /// The owning column's index into `columns` (palette slot).
        public let colorIndex: Int
    }

    /// A column header; the column's cards carry the same `colorIndex`.
    public struct Column: Sendable {
        public let title: String
        public let headerFrame: CGRect
        /// Cycled palette slot (column order), not a color.
        public let colorIndex: Int
    }

    public let size: CGSize
    public let columns: [Column]
    public let cards: [Card]
}

/// Placed radar chart: spokes from `center`, a concentric graticule of rings,
/// one polygon per data curve, and a legend below. Top-left-origin points;
/// `size` is the canvas.
public struct RadarLayout: Sendable {
    /// A data curve's polygon: one vertex per axis, in axis order.
    public struct Curve: Sendable {
        public let points: [CGPoint]
        /// Cycled palette slot (curve order); matches its legend entry.
        public let colorIndex: Int
    }

    /// One concentric graticule polygon (a vertex per axis).
    public struct Ring: Sendable {
        public let points: [CGPoint]
    }

    /// An axis line from `center` to `end`, labelled just beyond the rim.
    public struct Spoke: Sendable {
        public let end: CGPoint
        public let label: String
        /// Label anchor, outward of `end` along the spoke.
        public let labelPoint: CGPoint
    }

    /// One legend row: a color swatch and the curve's label.
    public struct LegendEntry: Sendable {
        public let label: String
        public let swatchCenter: CGPoint
        /// Left-aligned anchor for the label text.
        public let labelPoint: CGPoint
        /// Cycled palette slot; index into `curves`.
        public let colorIndex: Int
    }

    public let size: CGSize
    public let title: String?
    public let center: CGPoint
    public let rings: [Ring]
    public let spokes: [Spoke]
    public let curves: [Curve]
    public let legend: [LegendEntry]
}

/// Placed treemap (squarified). Top-left-origin points; `size` is the canvas.
public struct TreemapLayout: Sendable {
    /// One rectangle: a leaf value cell, or an internal group drawn as an
    /// outline + header behind its children.
    public struct Cell: Sendable {
        public let label: String
        public let value: Double
        public let frame: CGRect
        /// Categorical tint by top-level branch.
        public let colorIndex: Int
        public let isLeaf: Bool
        /// Nesting depth (top-level branches are 1).
        public let depth: Int
    }

    public let size: CGSize
    /// Internal group rects first, then leaves — so the renderer draws groups
    /// behind their children.
    public let cells: [Cell]
}

/// Placed git graph, left to right: commits advance along x in history order
/// and each branch occupies a horizontal lane. Top-left-origin points; `size`
/// is the canvas.
public struct GitGraphLayout: Sendable {
    /// A commit dot.
    public struct Commit: Sendable {
        public let center: CGPoint
        /// The commit's lane: index into `laneLabels`, and its palette slot.
        public let colorIndex: Int
        public let id: String
        /// Text drawn under the dot — the author's explicit `id:` only;
        /// auto-generated ids are identity, not content.
        public let label: String?
        /// Where the label's centre sits. Below the dot by default; layout
        /// flips it above the rail when a branch/merge leg occupies the space
        /// underneath (nil when `label` is nil).
        public let labelCenter: CGPoint?
        public let tag: String?
        public let isMerge: Bool
    }

    /// One straight, axis-aligned leg. A same-lane connection is a single
    /// horizontal leg; a cross-lane connection (branch point or merge) is
    /// emitted as two legs sharing a right-angle corner.
    public struct Edge: Sendable {
        public let from: CGPoint
        public let to: CGPoint
        /// The child commit's lane palette slot.
        public let colorIndex: Int
    }

    /// A branch name anchored at the left edge of its lane.
    public struct LaneLabel: Sendable {
        public let name: String
        /// Left-aligned anchor on the lane's y.
        public let point: CGPoint
        public let colorIndex: Int
    }

    public let size: CGSize
    public let commits: [Commit]
    public let edges: [Edge]
    public let laneLabels: [LaneLabel]
}

/// Placed class diagram: compartmented class boxes and orthogonally routed
/// relation edges. Top-left-origin points; `size` is the canvas.
public struct ClassLayout: Sendable {
    /// A class box: name compartment on top, then attribute and method rows.
    public struct Box: Sendable {
        public let name: String
        public let attributes: [String]
        public let methods: [String]
        public let frame: CGRect
        /// Height of the name compartment; member rows follow below.
        public let nameHeight: CGFloat
        /// Height of each attribute/method row.
        public let rowHeight: CGFloat
    }

    /// A relation routed between two boxes; the kind's marker sits at `end`.
    public struct Edge: Sendable {
        public let start: CGPoint      // at the `from` box border
        public let end: CGPoint        // at the `to` box border, marker here
        /// Orthogonal route from `start` to `end`; first is `start`, last is
        /// `end`. The marker orients along the final segment.
        public let points: [CGPoint]
        public let kind: ClassDiagram.RelationKind
        public let label: String?
        /// Where layout RESERVED space for the label (a widened median dummy
        /// or the grown inter-layer gap); renderers should draw it here.
        public let labelAnchor: CGPoint?
    }

    public let size: CGSize
    public let boxes: [Box]
    public let edges: [Edge]
}

/// Placed entity-relationship diagram: entity boxes with attribute rows and
/// crow's-foot relationship edges. Top-left-origin points; `size` is the
/// canvas.
public struct ERLayout: Sendable {
    /// An entity box: name compartment on top, one row per attribute below.
    public struct Box: Sendable {
        public let name: String
        public let attributes: [ERDiagram.Attribute]
        public let frame: CGRect
        /// Height of the name compartment; attribute rows follow below.
        public let nameHeight: CGFloat
        /// Height of each attribute row.
        public let rowHeight: CGFloat
    }

    /// A relationship; cardinality markers sit at both ends.
    public struct Edge: Sendable {
        public let start: CGPoint
        public let end: CGPoint
        /// Orthogonal route from `start` to `end`; crow's-foot markers orient
        /// along the first and last segments.
        public let points: [CGPoint]
        /// Cardinality marker drawn at the `start` end.
        public let fromCard: ERDiagram.Cardinality
        /// Cardinality marker drawn at the `end` end.
        public let toCard: ERDiagram.Cardinality
        public let label: String
        /// Identifying relationship (Mermaid `--`) vs non-identifying (`..`).
        public let identifying: Bool
        /// Where layout reserved space for the label, when it did.
        public let labelAnchor: CGPoint?
    }

    public let size: CGSize
    public let boxes: [Box]
    public let edges: [Edge]
}

/// Placed state diagram in absolute (flattened) coordinates: leaf state
/// nodes, composite-state container boxes, and transition edges.
/// Top-left-origin points; `size` is the canvas.
public struct StateLayout: Sendable {
    /// Node glyph: plain state box, initial/final dot, choice diamond, or
    /// fork/join bar.
    public enum NodeKind: Sendable { case simple, start, end, choice, fork, join }

    /// A leaf (non-composite) state; composites appear as `Container`s.
    public struct Node: Sendable {
        public let id: String
        public let label: String
        public let kind: NodeKind
        public let frame: CGRect
    }

    /// A composite state's container box. `titleHeight` is the label strip at
    /// the top; children live below it. `depth` (0 = outermost) tints nesting.
    public struct Container: Sendable {
        public let label: String
        public let frame: CGRect
        public let titleHeight: CGFloat
        public let depth: Int
    }

    /// A transition; `points` is the orthogonal route from `start` to `end`.
    public struct Edge: Sendable {
        public let start: CGPoint
        public let end: CGPoint
        public let points: [CGPoint]
        public let label: String?
        /// Where layout reserved space for the label, when it did.
        public let labelAnchor: CGPoint?
    }

    public let size: CGSize
    public let nodes: [Node]
    /// Composite boxes; a parent always precedes its nested children, so
    /// drawing in order paints outer boxes behind inner ones.
    public let containers: [Container]
    public let edges: [Edge]
}

// MARK: - Engine

/// The pure layout engines: one `layout(_:measure:)` overload per diagram
/// type (spread across the DiagramLayout*.swift files). Geometry only —
/// platform-free and deterministic, with all text measurement injected via
/// `DiagramTextMeasurer`.
public enum DiagramLayoutEngine {

    /// Font size the engines measure primary node/box labels at; renderers
    /// must draw them at the same size for the measured geometry to fit.
    public static let nodeFontSize: Double = 12
    /// Font size for secondary text: edge labels, detail rows, axis ticks.
    public static let labelFontSize: Double = 10.5
    /// Minimum separation between a pair of antiparallel box-diagram edges, and
    /// the floor `separateRuns` enforces between any two coincident box runs.
    static let boxAntiparallelSep: CGFloat = 20

    // MARK: Shared box placement

    /// Back edges (cycle-closing) found by DFS, as indices into `edges`.
    /// Layering must ignore them or a cycle drifts nodes down without bound.
    static func backEdgeIndices(ids: [String], edges: [(String, String)]) -> Set<Int> {
        var adjacency: [String: [Int]] = [:]
        for (index, edge) in edges.enumerated() { adjacency[edge.0, default: []].append(index) }
        var color: [String: Int] = [:]   // 0 = white, 1 = grey (on stack), 2 = black
        var back = Set<Int>()
        func visit(_ id: String) {
            color[id] = 1
            for index in adjacency[id] ?? [] {
                let target = edges[index].1
                switch color[target] ?? 0 {
                case 1: back.insert(index)          // edge into an ancestor → back edge
                case 0: visit(target)
                default: break
                }
            }
            color[id] = 2
        }
        for id in ids where (color[id] ?? 0) == 0 { visit(id) }
        return back
    }


    /// Barycenter crossing-minimization: repeatedly reorder each layer by the
    /// mean position of each node's predecessors. Empty layers are dropped.
    static func barycenterOrder(
        layers: [[String]], edges: [(String, String)], sweeps: Int = 2
    ) -> [[String]] {
        var layers = layers
        layers.removeAll(where: \.isEmpty)

        // Predecessors precomputed once so the sort comparator is O(1), not
        // an O(E) filter per comparison.
        var predecessors: [String: [String]] = [:]
        for (from, to) in edges { predecessors[to, default: []].append(from) }
        var position: [String: Int] = [:]
        func recordPositions() {
            for layer in layers {
                for (i, id) in layer.enumerated() { position[id] = i }
            }
        }
        func barycenter(_ id: String) -> Double {
            let ps = (predecessors[id] ?? []).compactMap { position[$0] }
            return ps.isEmpty ? Double(position[id] ?? 0)
                              : Double(ps.reduce(0, +)) / Double(ps.count)
        }
        recordPositions()
        for _ in 0..<sweeps {
            for index in 1..<max(layers.count, 1) {
                layers[index].sort {
                    let a = barycenter($0), b = barycenter($1)
                    // Explicit model-order tie-break (ELK's "consider model
                    // order"): equal barycenters keep their existing relative
                    // order — descending from declaration order — instead of
                    // leaning on the sort algorithm's undocumented stability.
                    if a != b { return a < b }
                    return (position[$0] ?? 0) < (position[$1] ?? 0)
                }
                recordPositions()
            }
        }
        return layers
    }

    /// Layered top-down layout with **dummy-node edge routing**, shared by the
    /// class, ER, and state diagrams (the Sugiyama approach the flowchart uses).
    /// Layers come from `layeringEdges` (already oriented by the caller — e.g.
    /// class inheritance flipped so parents sit above children); every routing
    /// edge that spans more than one layer gets dummy nodes in the intervening
    /// layers, so it reserves a channel and runs *between* boxes instead of
    /// elbowing around them. Returns the real-box frames, the canvas size, and
    /// one orthogonal polyline per `routingEdges` entry, in order.
    static func layeredRoutes(
        ids: [String],
        sizes: [String: CGSize],
        layeringEdges: [(String, String)],
        routingEdges: [(from: String, to: String)],
        layerGap: CGFloat,
        nodeGap: CGFloat,
        margin: CGFloat,
        edgeLabelSizes: [CGSize?]? = nil
    ) -> (frames: [String: CGRect], size: CGSize, routes: [[CGPoint]], labelAnchors: [CGPoint?]) {
        let layerBack = backEdgeIndices(ids: ids, edges: layeringEdges)
        let forward = layeringEdges.enumerated().filter { !layerBack.contains($0.offset) }.map(\.element)
        let layerOf = assignLayers(ids: ids, edges: forward)
        let layerCount = (layerOf.values.max() ?? 0) + 1

        // Dummy nodes for every routing edge spanning more than one layer.
        var layers: [[String]] = Array(repeating: [], count: layerCount)
        for id in ids where layerOf[id] != nil { layers[layerOf[id]!].append(id) }
        var allSizes = sizes
        var chains: [[String]] = []
        var segmentEdges: [(String, String)] = []
        var dummies: Set<String> = []
        // Labeled edges between ADJACENT layers carry their text in the
        // inter-layer gap; grow each gap to fit the tallest such label so the
        // chip never crowds the boxes above or below it.
        var gapExtra = [CGFloat](repeating: 0, count: max(layerCount, 1))
        if let edgeLabelSizes {
            for (index, edge) in routingEdges.enumerated() {
                guard let labelSize = edgeLabelSizes[index],
                      let lu = layerOf[edge.from], let lv = layerOf[edge.to],
                      abs(lu - lv) == 1 else { continue }
                let gap = min(lu, lv)
                gapExtra[gap] = max(gapExtra[gap], labelSize.height + 6)
            }
        }
        for (index, edge) in routingEdges.enumerated() {
            guard let lu = layerOf[edge.from], let lv = layerOf[edge.to] else { chains.append([]); continue }
            let lo = min(lu, lv), hi = max(lu, lv)
            if hi - lo <= 1 {
                chains.append([edge.from, edge.to])
                segmentEdges.append((edge.from, edge.to))
                continue
            }
            var midByLayer: [(layer: Int, id: String)] = []
            // ELK-style label reservation: the MEDIAN dummy of a labeled edge
            // is widened to the label's size, so ordering and Brandes-Köpf
            // reserve real horizontal space for the text instead of the label
            // being squeezed in afterwards. `placeRunLabels` (below) then anchors
            // the caption on the resulting straight channel.
            let labelSize = edgeLabelSizes?[index] ?? nil
            let medianLayer = (lo + 1 + hi - 1) / 2
            for layer in (lo + 1)...(hi - 1) {
                let dummy = "\u{a7}b\(index).\(layer)"
                layers[layer].append(dummy)
                if let labelSize, layer == medianLayer {
                    allSizes[dummy] = CGSize(width: max(16, labelSize.width + 8), height: 1)
                } else {
                    allSizes[dummy] = CGSize(width: 16, height: 1)
                }
                dummies.insert(dummy)
                midByLayer.append((layer, dummy))
            }
            let mids = (lu < lv ? midByLayer : midByLayer.reversed()).map(\.id)
            let chain = [edge.from] + mids + [edge.to]
            chains.append(chain)
            for k in 0..<(chain.count - 1) { segmentEdges.append((chain[k], chain[k + 1])) }
        }

        // Order, then assign x with Brandes–Köpf (top-down; cross axis is x) so
        // dummy channels and box columns align into straight runs.
        let ordered = barycenterOrder(layers: layers, edges: segmentEdges)
        var breadth: [String: CGFloat] = [:]
        for layer in ordered { for id in layer { breadth[id] = allSizes[id]?.width ?? 0 } }
        var xCenter = brandesKoepfX(
            layers: ordered, segments: segmentEdges, breadth: breadth,
            dummies: dummies, minGap: nodeGap)
        // Same near-alignment jog fix as the flowchart pipeline: BK's
        // balancing leaves single-parent chains a few points off centre.
        straightenChains(layers: ordered, segments: segmentEdges,
                         breadth: breadth, minGap: nodeGap, center: &xCenter)
        var minCross = CGFloat.greatestFiniteMagnitude
        var maxCross = -CGFloat.greatestFiniteMagnitude
        for layer in ordered {
            for id in layer {
                let w = allSizes[id]?.width ?? 0
                let c = xCenter[id] ?? 0
                minCross = min(minCross, c - w / 2)
                maxCross = max(maxCross, c + w / 2)
            }
        }
        let shiftX = margin - (minCross.isFinite ? minCross : 0)
        let crossExtent = maxCross > minCross ? maxCross - minCross : 0

        var frames: [String: CGRect] = [:]
        var y = margin
        for (layerIndex, layer) in ordered.enumerated() {
            let layerHeight = layer.map { allSizes[$0]?.height ?? 0 }.max() ?? 0
            for id in layer {
                let size = allSizes[id] ?? .zero
                let cx = (xCenter[id] ?? 0) + shiftX
                frames[id] = CGRect(x: cx - size.width / 2, y: y, width: size.width, height: size.height)
            }
            y += layerHeight + layerGap
            if layerIndex < gapExtra.count { y += gapExtra[layerIndex] }
        }

        // Antiparallel detection: an edge whose reverse also exists must not
        // share the reverse's column, or the two render as one line.
        var directedPairs = Set<String>()
        for edge in routingEdges { directedPairs.insert(edge.from + "\u{1}" + edge.to) }

        // Route each edge through its chain waypoints.
        var routes: [[CGPoint]] = []
        for chain in chains {
            guard chain.count >= 2, let fromFrame = frames[chain[0]], let toFrame = frames[chain[chain.count - 1]] else {
                routes.append([.zero, .zero]); continue
            }
            // Self-loop (an edge from a box back to itself, e.g. an ER
            // "subcategory of" parent_id): route it as a small loop off the
            // right side, never a straight line through the box interior.
            if chain[0] == chain[chain.count - 1] {
                let f = fromFrame
                let ext: CGFloat = 24
                let yHi = f.midY - min(f.height * 0.24, 13)
                let yLo = f.midY + min(f.height * 0.24, 13)
                routes.append([
                    CGPoint(x: f.maxX, y: yHi),
                    CGPoint(x: f.maxX + ext, y: yHi),
                    CGPoint(x: f.maxX + ext, y: yLo),
                    CGPoint(x: f.maxX, y: yLo),
                ])
                continue
            }
            // Same layer → route the short way through side faces, UNLESS the
            // direct line would cross another box sitting between the two: then
            // dip into the gap just below the row and cross there instead of
            // straight through the intervening box.
            if abs(fromFrame.midY - toFrame.midY) < 1 {
                let right = toFrame.midX >= fromFrame.midX
                let start = CGPoint(x: right ? fromFrame.maxX : fromFrame.minX, y: fromFrame.midY)
                let end = CGPoint(x: right ? toFrame.minX : toFrame.maxX, y: toFrame.midY)
                let lo = min(start.x, end.x), hi = max(start.x, end.x)
                let blocked = frames.contains { id, fr in
                    id != chain[0] && id != chain[chain.count - 1] && !dummies.contains(id)
                        && abs(fr.midY - fromFrame.midY) < 1
                        && fr.minX < hi - 2 && fr.maxX > lo + 2
                }
                if blocked {
                    let dy = fromFrame.maxY + 16
                    routes.append([start, CGPoint(x: start.x, y: dy), CGPoint(x: end.x, y: dy), end])
                } else {
                    routes.append([start, end])
                }
                continue
            }
            let dummyCenters = chain[1..<(chain.count - 1)].compactMap { frames[$0].map { CGPoint(x: $0.midX, y: $0.midY) } }
            // Straight column: when the two boxes' x-ranges overlap and there
            // are no dummies to route around, attach both ends at one shared x
            // so the edge is a single straight segment — no tiny S-hook from a
            // near-alignment offset.
            let overlapLo = max(fromFrame.minX, toFrame.minX) + 4
            let overlapHi = min(fromFrame.maxX, toFrame.maxX) - 4
            if dummyCenters.isEmpty, overlapLo <= overlapHi {
                var x = min(max((fromFrame.midX + toFrame.midX) / 2, overlapLo), overlapHi)
                let down = toFrame.midY >= fromFrame.midY
                // If a reverse edge exists between the same pair, place the two
                // as a centred block a full separation apart (not an independent
                // ±offset, which the overlap clamp then compresses), so they read
                // as two clear parallel lines (e.g. state "connect"/"fail").
                if directedPairs.contains(chain[chain.count - 1] + "\u{1}" + chain[0]) {
                    let half = min(boxAntiparallelSep / 2, (overlapHi - overlapLo) / 2)
                    let center = min(max(x, overlapLo + half), overlapHi - half)
                    x = center + (down ? half : -half)
                }
                let start = CGPoint(x: x, y: down ? fromFrame.maxY : fromFrame.minY)
                let end = CGPoint(x: x, y: down ? toFrame.minY : toFrame.maxY)
                routes.append([start, end])
                continue
            }
            let firstNext = dummyCenters.first ?? CGPoint(x: toFrame.midX, y: toFrame.midY)
            let lastPrev = dummyCenters.last ?? CGPoint(x: fromFrame.midX, y: fromFrame.midY)
            func attach(_ f: CGRect, towardX: CGFloat, bottom: Bool) -> CGPoint {
                CGPoint(x: min(max(towardX, f.minX + 4), f.maxX - 4), y: bottom ? f.maxY : f.minY)
            }
            let start = attach(fromFrame, towardX: firstNext.x, bottom: firstNext.y >= fromFrame.midY)
            let end = attach(toFrame, towardX: lastPrev.x, bottom: lastPrev.y > toFrame.midY)
            let points = routePolyline([start] + dummyCenters + [end], horizontal: false)
            routes.append(points)
        }

        // Push horizontal runs out of box bands. A cross-layer edge's jog is
        // placed at the midpoint between its dummy and the target, which for a
        // TALL intermediate box lands inside it (class "contains" jogging at
        // y=272 through Customer, whose band is y179–300). Move any interior
        // horizontal segment that crosses a box to the nearest clear y — the
        // connecting vertical legs sit in dummy channels, so lengthening them
        // stays clear. Routes with no crossing are untouched.
        let realFrames = ids.compactMap { dummies.contains($0) ? nil : frames[$0] }
        for ri in routes.indices {
            var pts = routes[ri]
            guard pts.count >= 4 else { continue }
            var i = 1
            while i < pts.count - 2 {
                let a = pts[i], b = pts[i + 1]
                if abs(a.y - b.y) < 0.5 && abs(a.x - b.x) > 1 {
                    let lo = min(a.x, b.x) + 2, hi = max(a.x, b.x) - 2
                    let pad: CGFloat = 16
                    func crosses(_ yy: CGFloat) -> Bool {
                        realFrames.contains { $0.minY + 2 < yy && $0.maxY - 2 > yy && $0.minX < hi && $0.maxX > lo }
                    }
                    // A destination y must clear every crossed box by `pad`, so the
                    // run sits well inside the gap rather than skimming a border.
                    func clearWithPadding(_ yy: CGFloat) -> Bool {
                        !realFrames.contains { $0.minY - pad < yy && $0.maxY + pad > yy && $0.minX < hi && $0.maxX > lo }
                    }
                    if crosses(a.y) {
                        var moved: CGFloat?
                        var d: CGFloat = 4
                        while d <= 300 {
                            for cand in [a.y + d, a.y - d] where clearWithPadding(cand) { moved = cand; break }
                            if moved != nil { break }
                            d += 4
                        }
                        if let ny = moved { pts[i].y = ny; pts[i + 1].y = ny }
                    }
                }
                i += 1
            }
            routes[ri] = pts
        }

        // Same guarantee the flowchart router gives: no two edges' runs may
        // coincide on one track. Catches long/back-edge channels that land on a
        // box column (the antiparallel block above only covers adjacent pairs).
        separateRuns(&routes, horizontal: false, minSep: boxAntiparallelSep)

        var routeMaxX = crossExtent + margin
        for pts in routes { for p in pts { routeMaxX = max(routeMaxX, p.x) } }
        let size = CGSize(width: max(crossExtent, routeMaxX - margin) + margin * 2, height: y - layerGap + margin)
        // Place every caption on the longest clean straight run of its final
        // route, collision-avoiding node boxes, other captions, bends, and
        // crossings — the same run-based placement the flowchart pipeline uses,
        // so a state/class/ER label never lands on a corner or a junction, and
        // sibling adjacent-layer labels that share an inter-layer gap slide
        // apart instead of stacking on one midpoint. (The reserved median-dummy
        // channel and the grown gap give this pass the room it needs.)
        let realFrameList = ids.compactMap { dummies.contains($0) ? nil : frames[$0] }
        let labelSizes: [CGSize?] = routingEdges.indices.map { edgeLabelSizes?[$0] ?? nil }
        let labelAnchors = placeRunLabels(routes: routes, labelSizes: labelSizes,
                                          nodeFrames: realFrameList)
        // Dummy frames are internal scaffolding — don't leak them.
        for dummy in dummies { frames[dummy] = nil }
        return (frames, size, routes, labelAnchors)
    }

    // MARK: Brandes–Köpf horizontal coordinate assignment

    /// Assigns each node a cross-axis **center** coordinate using the
    /// Brandes–Köpf algorithm — Brandes & Köpf, "Fast and Simple Horizontal
    /// Coordinate Assignment", GD 2001, LNCS 2265, pp. 31–44 (the method dagre
    /// uses). Stage comments below cite the paper's Alg. 1–4 / sections. Given
    /// the barycenter-ordered `layers` and the `segments` joining consecutive
    /// layers, it aligns edges — especially dummy-chain "inner" segments — into
    /// straight runs while preserving each layer's order and a minimum gap.
    ///
    /// It runs four biased passes (align up/down × pack left/right, Alg. 4) and
    /// returns the per-node average median of the four, which cancels
    /// directional bias and is provably order- and separation-preserving
    /// (Lemma 1). Inner segments (dummy→dummy) win alignment over crossing
    /// non-inner segments via type-1 conflict marking, so long/back edges become
    /// vertical channels.
    ///
    /// Coordinates are relative (not yet normalized to a margin); the caller
    /// shifts them. `breadth[id]` is the node's extent along the cross axis and
    /// `dummies` marks the synthetic long-edge nodes.
    static func brandesKoepfX(
        layers: [[String]],
        segments: [(String, String)],
        breadth: [String: CGFloat],
        dummies: Set<String>,
        minGap: CGFloat
    ) -> [String: CGFloat] {
        // Flatten node list; index each node's layer and within-layer position.
        var layerOf: [String: Int] = [:]
        var posOf: [String: Int] = [:]
        for (li, layer) in layers.enumerated() {
            for (o, v) in layer.enumerated() { layerOf[v] = li; posOf[v] = o }
        }
        guard !layerOf.isEmpty else { return [:] }

        // Upper/lower adjacency (the paper's neighbor SETS N⁻/N⁺, §2) between
        // consecutive layers, from the segments. Deduplicated per node because
        // they are sets: BK's median heuristic is index-based, so a neighbor
        // counted twice (parallel edges, or a forward + back edge between the
        // same pair) would bias alignment toward it.
        var upN: [String: [String]] = [:]
        var downN: [String: [String]] = [:]
        var upSeen: [String: Set<String>] = [:]
        var downSeen: [String: Set<String>] = [:]
        for (a, b) in segments {
            guard let la = layerOf[a], let lb = layerOf[b], la != lb else { continue }
            let (hi, lo) = la < lb ? (a, b) : (b, a)
            if downSeen[hi, default: []].insert(lo).inserted { downN[hi, default: []].append(lo) }
            if upSeen[lo, default: []].insert(hi).inserted { upN[lo, default: []].append(hi) }
        }

        // Alg. 1 (§4.1) — mark type-1 conflicts: a non-inner segment that
        // crosses an inner (dummy→dummy) segment, resolved in favour of the
        // inner one. Computed once on the original ordering; lookup is
        // order-independent (pairs stored unordered). The paper's loop runs
        // i ← 2..h-2; scanning every pair here is equivalent because dummies
        // never occupy the top/bottom layer, so no inner segment touches those
        // pairs and none is marked there.
        var conflicts = Set<String>()
        func conflictKey(_ a: String, _ b: String) -> String { a < b ? a + "\u{1}" + b : b + "\u{1}" + a }
        func hasConflict(_ a: String, _ b: String) -> Bool { conflicts.contains(conflictKey(a, b)) }
        func isInnerLower(_ v: String) -> String? {
            guard dummies.contains(v) else { return nil }
            for u in upN[v] ?? [] where dummies.contains(u) { return u }
            return nil
        }
        for i in 0..<max(layers.count - 1, 0) {
            let lower = layers[i + 1]
            var k0 = 0
            var l = 0
            for l1 in 0..<lower.count {
                let v = lower[l1]
                let innerUpper = isInnerLower(v)
                if l1 == lower.count - 1 || innerUpper != nil {
                    let k1 = innerUpper.flatMap { posOf[$0] } ?? (layers[i].count - 1)
                    while l <= l1 {
                        let w = lower[l]
                        for u in upN[w] ?? [] {
                            let k = posOf[u] ?? 0
                            if k < k0 || k > k1 { conflicts.insert(conflictKey(u, w)) }
                        }
                        l += 1
                    }
                    k0 = k1
                }
            }
        }

        func sep(_ u: String, _ w: String) -> CGFloat {
            (breadth[u] ?? 0) / 2 + (breadth[w] ?? 0) / 2 + minGap
        }

        // Alg. 2 (§4.1) — vertical alignment into blocks (root/align chains):
        // align each vertex with its median neighbor when the segment isn't a
        // conflict and doesn't cross an already-used alignment. `neighbor` is
        // the adjacent-layer set to align against; `ordering` is the (possibly
        // reversed) layering.
        func verticalAlignment(
            _ ordering: [[String]], neighbor: [String: [String]]
        ) -> (root: [String: String], align: [String: String]) {
            var root: [String: String] = [:]
            var align: [String: String] = [:]
            var pos: [String: Int] = [:]
            for layer in ordering {
                for (o, v) in layer.enumerated() { root[v] = v; align[v] = v; pos[v] = o }
            }
            for layer in ordering {
                var prevIdx = -1
                for v in layer {
                    let ws = (neighbor[v] ?? []).sorted { (pos[$0] ?? 0) < (pos[$1] ?? 0) }
                    guard !ws.isEmpty else { continue }
                    // The two median neighbors: paper's m ← ⌊(d+1)/2⌋, ⌈(d+1)/2⌉
                    // (1-indexed) is ⌊mp⌋…⌈mp⌉ with mp=(d-1)/2 here (0-indexed).
                    let mp = Double(ws.count - 1) / 2
                    for m in Int(floor(mp))...Int(ceil(mp)) {
                        guard align[v] == v else { continue }
                        let w = ws[m]
                        let wp = pos[w] ?? 0
                        if prevIdx < wp, !hasConflict(v, w) {
                            align[w] = v
                            root[v] = root[w] ?? w
                            align[v] = root[v] ?? v
                            prevIdx = wp
                        }
                    }
                }
            }
            return (root, align)
        }

        // Alg. 3 (§4.2) — horizontal compaction: place each block as tight as
        // order + separation allow (longest-path within a class), then merge
        // block classes toward their sinks. `sep` generalizes the paper's
        // constant δ to variable-width boxes: (w_u + w_v)/2 + gap.
        func horizontalCompaction(
            _ ordering: [[String]], root: [String: String], align: [String: String]
        ) -> [String: CGFloat] {
            var pos: [String: Int] = [:]
            var lidx: [String: Int] = [:]
            for (li, layer) in ordering.enumerated() {
                for (o, v) in layer.enumerated() { pos[v] = o; lidx[v] = li }
            }
            var sink: [String: String] = [:]
            var shift: [String: CGFloat] = [:]
            var x: [String: CGFloat] = [:]
            for layer in ordering { for v in layer { sink[v] = v; shift[v] = .greatestFiniteMagnitude } }

            func placeBlock(_ v: String) {
                guard x[v] == nil else { return }
                x[v] = 0
                var w = v
                repeat {
                    let p = pos[w] ?? 0
                    if p > 0 {
                        let leftNode = ordering[lidx[w] ?? 0][p - 1]
                        let u = root[leftNode] ?? leftNode
                        placeBlock(u)
                        if sink[v] == v { sink[v] = sink[u] ?? u }
                        if sink[v] != sink[u] {
                            let s = sink[u] ?? u
                            shift[s] = min(shift[s] ?? .greatestFiniteMagnitude,
                                           (x[v] ?? 0) - (x[u] ?? 0) - sep(leftNode, w))
                        } else {
                            x[v] = max(x[v] ?? 0, (x[u] ?? 0) + sep(leftNode, w))
                        }
                    }
                    w = align[w] ?? w
                } while w != v
            }

            for layer in ordering { for v in layer where (root[v] ?? v) == v { placeBlock(v) } }
            for layer in ordering {
                for v in layer {
                    let r = root[v] ?? v
                    x[v] = x[r] ?? 0
                    let s = shift[sink[r] ?? r] ?? .greatestFiniteMagnitude
                    if s < .greatestFiniteMagnitude { x[v] = (x[v] ?? 0) + s }
                }
            }
            return x
        }

        // Alg. 4 (§4.3) — run the four passes: {up, down} alignment × {left,
        // right} packing. Right passes reverse each layer and negate the result
        // (the standard trick, so the symmetric case reuses the same code).
        func run(up: Bool, left: Bool) -> [String: CGFloat] {
            var ordering = up ? layers : Array(layers.reversed())
            if !left { ordering = ordering.map { $0.reversed() } }
            let neighbor = up ? upN : downN
            let alignment = verticalAlignment(ordering, neighbor: neighbor)
            var xs = horizontalCompaction(ordering, root: alignment.root, align: alignment.align)
            if !left { for k in xs.keys { xs[k] = -(xs[k] ?? 0) } }
            return xs
        }
        let xss: [[String: CGFloat]] = [
            run(up: true, left: true), run(up: true, left: false),
            run(up: false, left: true), run(up: false, left: false),
        ]

        // Balancing (§4.3): align the four layouts against the smallest-width
        // one (left passes to its min, right passes to its max), then take the
        // per-node "average median" — mean of the two middle values. Lemma 1
        // proves this stays order- and separation-preserving.
        func width(_ xs: [String: CGFloat]) -> CGFloat {
            var mn = CGFloat.greatestFiniteMagnitude, mx = -CGFloat.greatestFiniteMagnitude
            for (v, x) in xs {
                let hw = (breadth[v] ?? 0) / 2
                mn = min(mn, x - hw); mx = max(mx, x + hw)
            }
            return mx - mn
        }
        let alignTo = xss.min { width($0) < width($1) } ?? xss[0]
        let alignMin = alignTo.values.min() ?? 0
        let alignMax = alignTo.values.max() ?? 0
        var aligned: [[String: CGFloat]] = []
        for (idx, xs) in xss.enumerated() {
            let left = idx % 2 == 0   // order above is [ul, ur, dl, dr]
            let delta = left ? alignMin - (xs.values.min() ?? 0) : alignMax - (xs.values.max() ?? 0)
            aligned.append(delta == 0 ? xs : xs.mapValues { $0 + delta })
        }

        var result: [String: CGFloat] = [:]
        for v in layerOf.keys {
            let four = aligned.map { $0[v] ?? 0 }.sorted()
            result[v] = (four[1] + four[2]) / 2
        }
        return result
    }
}
