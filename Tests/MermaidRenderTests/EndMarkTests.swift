import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif
@testable import MermaidRender
@testable import MermaidLayout

/// The CoreGraphics twin of `RenderSceneTests.testEndMarksStayWithinHalfAShortSegment`:
/// `drawEndMark` must stop its line where `RenderScene.endMark` does.
final class EndMarkTests: XCTestCase {
    private let theme = DiagramTheme(prefersDark: false)

    func testEndMarksStayWithinHalfAShortSegment() {
        let tip = CGPoint(x: 0, y: 0)
        for head in [Flowchart.Edge.Head.circle, .cross] {
            let stop = DiagramRenderer.drawEndMark(head, at: tip, from: CGPoint(x: 10, y: 0),
                                                   color: theme.ink, canvas: theme.canvas, in: nil)
            XCTAssertGreaterThanOrEqual(stop.x, 0, "\(head)")
            XCTAssertLessThanOrEqual(stop.x, 5, "\(head)")
        }
    }

    func testEndMarkStopsMatchTheScene() {
        let tip = CGPoint(x: 0, y: 0)
        for head in [Flowchart.Edge.Head.circle, .cross, .arrow] {
            for len in [4.0, 10, 18, 40, 100] as [CGFloat] {
                let approach = CGPoint(x: len, y: 0)
                var marks: [RenderScene.Element] = []
                let scene = RenderScene.endMark(head, at: tip, from: approach,
                                                color: DiagramColor(red: 0, green: 0, blue: 0),
                                                canvas: DiagramColor(red: 1, green: 1, blue: 1),
                                                into: &marks)
                let drawn = DiagramRenderer.drawEndMark(head, at: tip, from: approach,
                                                        color: theme.ink, canvas: theme.canvas, in: nil)
                XCTAssertEqual(drawn.x, scene.x, accuracy: 0.0001, "\(head) len \(len)")
            }
        }
    }
}
