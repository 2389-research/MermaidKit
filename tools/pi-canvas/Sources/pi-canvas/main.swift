import Foundation
import MermaidRender

// pi-canvas: an infinite, pannable canvas of Mermaid diagrams composited into a
// 640×480 framebuffer — the shape of what runs on a Raspberry Pi's /dev/fb0, but
// with a PNG-writing framebuffer stand-in so it's verifiable without the hardware.
//
//   swift run pi-canvas <out-dir>                    # macOS: CoreGraphics raster
//   swift run --traits LinuxRaster pi-canvas <dir>   # Linux/Pi: Silica/Cairo raster
//
// On a real Pi you'd swap PNGFramebuffer for LinuxFramebuffer() and drive
// viewportX/Y from evdev (touch/gamepad); nothing else changes.

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// A wall of diagrams scattered across a large virtual canvas (~1700×1200 pt).
let items: [Placed] = [
    Placed(source: """
    flowchart LR
      A[Ingest] --> B{Valid?}
      B -->|yes| C[(Store)]
      B -->|no| D[Reject]
    """, x: 40, y: 40, baseWidth: 360),
    Placed(source: """
    sequenceDiagram
      Client->>API: request
      API-->>Client: 200 OK
    """, x: 470, y: 70, baseWidth: 320),
    Placed(source: """
    stateDiagram-v2
      [*] --> Idle
      Idle --> Busy: start
      Busy --> Idle: done
      Busy --> [*]
    """, x: 900, y: 40, baseWidth: 300),
    Placed(source: """
    pie title Traffic
      "Cache" : 62
      "Origin" : 28
      "Error" : 10
    """, x: 120, y: 360, baseWidth: 300),
    Placed(source: """
    classDiagram
      class Node { +id +draw() }
      Node <|-- Shape
    """, x: 520, y: 420, baseWidth: 320),
    Placed(source: """
    gitGraph
      commit
      branch dev
      commit
      checkout main
      merge dev
    """, x: 950, y: 400, baseWidth: 340),
]

let canvas = InfiniteCanvas(
    items: items,
    theme: DiagramTheme(prefersDark: false),
    canvasBG: (0xEC, 0xEE, 0xF2),  // light gray canvas
    cardBG: (0xFF, 0xFF, 0xFF))    // white cards

let fb = PNGFramebuffer(width: 640, height: 480, directory: outDir)

// A pan sequence across the canvas, then a zoom-in — each frame culls to what's
// visible and blits only those cards.
let shots: [(x: Int, y: Int, zoom: Double, label: String)] = [
    (0, 0, 1.0, "top-left"),
    (360, 120, 1.0, "pan right+down"),
    (760, 300, 1.0, "bottom-right cluster"),
    (300, 200, 1.6, "zoomed in 1.6× (re-rasterized, crisp)"),
]

for (n, s) in shots.enumerated() {
    canvas.composite(viewportX: s.x, viewportY: s.y, zoom: s.zoom, into: fb)
    print("frame \(n): viewport (\(s.x),\(s.y)) @\(s.zoom)×  — \(s.label)")
}
print("rendered \(canvas.renders) diagram rasters (cached across frames); wrote \(shots.count) frames to \(outDir)")
