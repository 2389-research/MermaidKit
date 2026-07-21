// swift-tools-version:6.2
import PackageDescription

// A demo/proof: an infinite, pannable canvas of Mermaid diagrams composited into
// a fixed viewport (a 640×480 framebuffer, e.g. /dev/fb0 on a Raspberry Pi) — all
// over MermaidKit's existing HEADLESS raster (`MermaidRenderer.rgbaRaster`), no
// display server. Not part of the main package graph.
//
// The `LinuxRaster` trait forwards to MermaidKit's, so on Linux (the Pi) the
// Silica/Cairo raster backend is used: build/run with `--traits LinuxRaster`. On
// macOS, plain `swift run` uses the CoreGraphics raster — same API, same demo.
let package = Package(
    name: "pi-canvas",
    platforms: [.macOS(.v14)],
    traits: [
        .trait(name: "LinuxRaster", description: "Forward MermaidKit's Silica raster backend (Linux/Pi)."),
    ],
    dependencies: [
        .package(path: "../..", traits: [
            .trait(name: "LinuxRaster", condition: .when(traits: ["LinuxRaster"])),
        ]),
    ],
    targets: [
        .executableTarget(
            name: "pi-canvas",
            dependencies: [
                .product(name: "MermaidRender", package: "MermaidKit"),
                .product(name: "MermaidLayout", package: "MermaidKit"),
            ]),
    ]
)
