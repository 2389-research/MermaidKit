import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidLayout

/// Parser + layout coverage for Gantt charts (Mermaid `gantt`). The parser
/// resolves each task's start/length to a numeric day timeline; the layout
/// maps that timeline to bounded geometry with an injected measurer.
final class GanttTests: XCTestCase {

    // A schedule exercising dates, `after` deps, implicit start, statuses,
    // sections, and a milestone — the same shape as the render fixture.
    private let source = """
    gantt
        title Renderer Hardening Schedule
        dateFormat  YYYY-MM-DD
        axisFormat  %m/%d
        excludes    weekends

        section Parser
        CommonMark baseline       :done,    cm, 2026-07-01, 2d
        GFM tables/tasks          :active,  gfm, after cm, 3d
        Unicode and RTL sweep     :         uni, after gfm, 2d

        section Extensions
        Mermaid pass              :crit,    mer, 2026-07-06, 4d
        MathJax pass              :crit,    mj,  after mer, 3d

        section Release
        Visual regression suite   :milestone, vr, 2026-07-17, 0d
        Canary                    :         canary, after vr, 2d
    """

    private func parseGantt(_ text: String) -> GanttChart? {
        guard case .gantt(let chart)? = MermaidParser.parse(text) else { return nil }
        return chart
    }

    // MARK: - Parser

    func testParsesTitleSectionsAndTaskCount() throws {
        let chart = try XCTUnwrap(parseGantt(source))
        XCTAssertEqual(chart.title, "Renderer Hardening Schedule")
        XCTAssertEqual(chart.sections, ["Parser", "Extensions", "Release"])
        XCTAssertEqual(chart.tasks.count, 7)
    }

    func testResolvesDatesDependenciesAndNormalizesToDayZero() throws {
        let chart = try XCTUnwrap(parseGantt(source))
        func task(_ label: String) -> GanttChart.Task? { chart.tasks.first { $0.label == label } }

        // Earliest task (2026-07-01) anchors day 0.
        let cm = try XCTUnwrap(task("CommonMark baseline"))
        XCTAssertEqual(cm.start, 0); XCTAssertEqual(cm.length, 2); XCTAssertEqual(cm.status, .done)

        // `after cm` starts at cm's end.
        let gfm = try XCTUnwrap(task("GFM tables/tasks"))
        XCTAssertEqual(gfm.start, 2); XCTAssertEqual(gfm.length, 3); XCTAssertEqual(gfm.status, .active)

        // Chained `after gfm`.
        XCTAssertEqual(task("Unicode and RTL sweep")?.start, 5)

        // Explicit date 2026-07-06 → 5 days after the 07-01 origin.
        let mer = try XCTUnwrap(task("Mermaid pass"))
        XCTAssertEqual(mer.start, 5); XCTAssertEqual(mer.length, 4); XCTAssertEqual(mer.status, .critical)

        // Milestone: zero length, flagged, 2026-07-17 → day 16.
        let vr = try XCTUnwrap(task("Visual regression suite"))
        XCTAssertTrue(vr.isMilestone); XCTAssertEqual(vr.length, 0); XCTAssertEqual(vr.start, 16)
        XCTAssertEqual(task("Canary")?.start, 16, "after a milestone starts at the milestone's instant")
    }

    func testImplicitSequentialStartWithoutDates() throws {
        let chart = try XCTUnwrap(parseGantt("""
        gantt
            section S
            A :a, 3d
            B :b, 2d
            C :c, 1d
        """))
        XCTAssertEqual(chart.tasks.map(\.start), [0, 3, 5], "each dateless task starts when the previous ends")
        XCTAssertEqual(chart.tasks.map(\.length), [3, 2, 1])
    }

    func testStartAndEndDateForm() throws {
        let chart = try XCTUnwrap(parseGantt("""
        gantt
            section S
            Span :t, 2026-07-01, 2026-07-05
        """))
        XCTAssertEqual(chart.tasks.first?.length, 4, "a second date is an end date, not a duration")
    }

    func testDegradesToNilWithoutTasks() {
        XCTAssertNil(parseGantt("gantt\n    title Empty\n    dateFormat YYYY-MM-DD"))
    }

    func testDurationAndDateHelpers() {
        XCTAssertEqual(MermaidParser.durationInDays("30d"), 30)
        XCTAssertEqual(MermaidParser.durationInDays("2w"), 14)
        XCTAssertEqual(MermaidParser.durationInDays("12h"), 0.5)
        XCTAssertEqual(MermaidParser.durationInDays("30"), 30, "a bare number is days")
        XCTAssertNil(MermaidParser.durationInDays("soon"))

        // Only day differences matter; check them across a month boundary.
        let d1 = try! XCTUnwrap(MermaidParser.dayOrdinal(fromISODate: "2026-07-01"))
        let d2 = try! XCTUnwrap(MermaidParser.dayOrdinal(fromISODate: "2026-08-01"))
        XCTAssertEqual(d2 - d1, 31)
        XCTAssertNil(MermaidParser.dayOrdinal(fromISODate: "2026-13-40"))
        XCTAssertNil(MermaidParser.dayOrdinal(fromISODate: "not-a-date"))
    }

    // MARK: - Layout

    /// width = 10 per character; deterministic and font-free.
    private let measure: DiagramTextMeasurer = { text, _ in CGSize(width: Double(text.count) * 10, height: 14) }

    func testLayoutIsNonDegenerateWithOneBarPerTask() throws {
        let chart = try XCTUnwrap(parseGantt(source))
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)

        XCTAssertGreaterThan(layout.size.width, 0)
        XCTAssertGreaterThan(layout.size.height, 0)
        XCTAssertLessThan(layout.size.width, 20_000, "bounded day-width keeps the canvas sane")
        XCTAssertEqual(layout.bars.count, chart.tasks.count)
        XCTAssertEqual(layout.sections.count, 3, "one tint band per section")
        XCTAssertFalse(layout.ticks.isEmpty)
    }

    func testLayoutOrdersRowsAndPlacesTimeLeftToRight() throws {
        let chart = try XCTUnwrap(parseGantt(source))
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)

        // Bars stack top to bottom in task order.
        for i in 1..<layout.bars.count {
            XCTAssertGreaterThan(layout.bars[i].frame.minY, layout.bars[i - 1].frame.minY)
        }
        // A later start sits further right: Mermaid pass (day 5) right of CommonMark (day 0).
        let cm = layout.bars[0].frame.minX
        let mer = try XCTUnwrap(layout.bars.first(where: { $0.label == "Mermaid pass" })).frame.minX
        XCTAssertGreaterThan(mer, cm)
        // The milestone is a small square, not a wide bar.
        let vr = try XCTUnwrap(layout.bars.first(where: { $0.isMilestone }))
        XCTAssertEqual(vr.frame.width, vr.frame.height, accuracy: 0.01, "milestone renders as a diamond box")
    }
}
