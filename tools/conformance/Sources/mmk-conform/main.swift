// Cross-platform conformance harness.
//
// The claim it proves: the platform-free core (parse → layout → RenderScene →
// SceneWire/SVG) produces BYTE-IDENTICAL output on every platform it compiles to
// — macOS, Linux, Android, WASM, Windows — given the same measurement input.
// The scene fully determines the picture, so identical scene bytes == functional
// equivalence; each platform's renderer is only a thin painter over that scene.
//
// It uses the DETERMINISTIC coarse measurer (pure arithmetic, no platform fonts),
// so any difference across platforms is a real core divergence, not a font-metric
// one. For each embedded fixture it prints a stable FNV-1a signature of the
// sorted-key SceneWire JSON and of the SVG, then a combined digest line. Compare
// the output across platforms: identical == conformant.

import Foundation
import MermaidLayout

// FNV-1a — seed-independent, so signatures compare across processes/platforms
// (Swift's Hasher is per-process seeded and would differ every run).
func fnv1a(_ bytes: [UInt8]) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in bytes { h = (h ^ UInt64(b)) &* 0x100000001b3 }
    return h
}

func fnv1a(_ s: String) -> UInt64 { fnv1a([UInt8](s.utf8)) }

// The reference theme — the same light preset MermaidKitC ships (mirrors
// RenderSceneTests). Fixed so the only variable is the platform.
let theme = RenderTheme(
    ink: DiagramColor(hex: 0x1D1D1F),
    accent: DiagramColor(hex: 0x5B8FF9),
    canvas: DiagramColor(hex: 0xFFFFFF),
    hairline: DiagramColor(hex: 0x000000, alpha: 0.12),
    secondaryText: DiagramColor(hex: 0x1D1D1F, alpha: 0.55),
    tertiaryText: DiagramColor(hex: 0x1D1D1F, alpha: 0.38),
    palette: [
        DiagramColor(hex: 0x5B8FF9), DiagramColor(hex: 0x5AD8A6),
        DiagramColor(hex: 0xF6BD16), DiagramColor(hex: 0xE8684A),
        DiagramColor(hex: 0x6DC8EC), DiagramColor(hex: 0x9270CA),
    ],
    prefersDark: false)

// The deterministic coarse measurer — pure math, so identical on every platform.
let measure: DiagramTextMeasurer = { text, size in
    CGSize(width: CGFloat(max(text.count, 1)) * size * 0.6, height: size + 4)
}

// Embedded fixtures (no file IO, so the harness runs in the WASM/WASI sandbox).
// One per major family so a divergence in any lowering path shows up.
let fixtures: [(String, String)] = [
    ("flowchart", """
    flowchart LR
        A[Start] --> B{Choice}
        B -->|yes| C((Done))
        B -->|no| D[Stop]
    """),
    ("sequence", """
    sequenceDiagram
        Alice->>Bob: Hello
        Bob-->>Alice: Hi there
        Alice->>Bob: How are you?
    """),
    ("state", """
    stateDiagram-v2
        [*] --> Idle
        Idle --> Running: start
        Running --> Idle: stop
        Running --> [*]
    """),
    ("class", """
    classDiagram
        class Animal {
            +String name
            +move()
        }
        Animal <|-- Dog
    """),
    ("pie", """
    pie title Pets
        "Dogs" : 42
        "Cats" : 30
        "Birds" : 12
    """),
]

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]

// --json <name>: dump raw SceneWire JSON for one fixture (conformance diffing).
if CommandLine.arguments.count >= 3, (CommandLine.arguments[1] == "--json" || CommandLine.arguments[1] == "--svg") {
    let want = CommandLine.arguments[2]
    for (name, source) in fixtures where name == want {
        let diagram = MermaidParser.parse(source)!
        let scene = RenderScene.from(diagram, theme: theme, measure: measure)!
        if CommandLine.arguments[1] == "--svg" { print(SVGRenderer.svg(scene)) }
        else { print(String(data: try! encoder.encode(SceneWire(scene)), encoding: .utf8)!) }
    }
    exit(0)
}

var combined = [UInt8]()
for (name, source) in fixtures {
    guard let diagram = MermaidParser.parse(source) else {
        print("\(name)\tPARSE_FAILED")
        continue
    }
    guard let scene = RenderScene.from(diagram, theme: theme, measure: measure) else {
        print("\(name)\tLOWER_FAILED")
        continue
    }
    let wireData = (try? encoder.encode(SceneWire(scene))) ?? Data()
    let svg = SVGRenderer.svg(scene)

    let wireSig = fnv1a([UInt8](wireData))
    let svgSig = fnv1a(svg)
    print("\(name)\twire=\(wireData.count):\(String(wireSig, radix: 16))\tsvg=\(svg.count):\(String(svgSig, radix: 16))")

    combined.append(contentsOf: [UInt8](wireData))
    combined.append(contentsOf: [UInt8](svg.utf8))
}

print("COMBINED\t\(String(fnv1a(combined), radix: 16))")
