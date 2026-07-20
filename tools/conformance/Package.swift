// swift-tools-version:6.0
import PackageDescription

// The cross-platform conformance harness (tools/conformance). A standalone
// executable that dumps stable SceneWire/SVG signatures for a fixed fixture set,
// so the SAME binary source can be compiled to macOS, Linux, Android, WASM, and
// Windows and its output compared byte-for-byte. Not part of the main package
// graph. Depends only on the platform-free MermaidLayout.
let package = Package(
    name: "mmk-conform",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "mmk-conform",
            dependencies: [.product(name: "MermaidLayout", package: "MermaidKit")]),
    ]
)
