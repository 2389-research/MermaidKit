// swift-tools-version:6.2
import PackageDescription

// A demo/proof: an infinite, pannable canvas of Mermaid diagrams composited into
// a fixed viewport (a 640×480 framebuffer, e.g. /dev/fb0 on a Raspberry Pi, or an
// SDL2 window/GPU surface) — all over MermaidKit's existing HEADLESS raster
// (`MermaidRenderer.rgbaRaster`), no display server. Not part of the main graph.
//
// Traits:
//   LinuxRaster — forward MermaidKit's Silica/Cairo raster (Linux/Pi).
//   SDL         — build the SDL2 presentation backend (needs libsdl2-dev).
//
//   swift run pi-canvas <dir>                                   # PNG frames (macOS)
//   swift run --traits LinuxRaster pi-canvas <dir>             # PNG frames (Linux/Pi)
//   swift run --traits "LinuxRaster SDL" pi-canvas --sdl <dir> # SDL2 backend
let package = Package(
    name: "pi-canvas",
    platforms: [.macOS(.v14)],
    traits: [
        .trait(name: "LinuxRaster", description: "Forward MermaidKit's Silica raster backend (Linux/Pi)."),
        .trait(name: "SDL", description: "Build the SDL2 presentation backend."),
    ],
    dependencies: [
        .package(path: "../..", traits: [
            .trait(name: "LinuxRaster", condition: .when(traits: ["LinuxRaster"])),
        ]),
    ],
    targets: [
        .systemLibrary(
            name: "CSDL2", path: "Sources/CSDL2", pkgConfig: "sdl2",
            providers: [.apt(["libsdl2-dev"]), .brew(["sdl2"])]),
        .executableTarget(
            name: "pi-canvas",
            dependencies: [
                .product(name: "MermaidRender", package: "MermaidKit"),
                .product(name: "MermaidLayout", package: "MermaidKit"),
                .target(name: "CSDL2", condition: .when(traits: ["SDL"])),
            ]),
    ]
)
