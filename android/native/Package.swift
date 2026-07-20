// swift-tools-version:6.0
import PackageDescription

// A standalone package that builds the Android JNI shared library. It is NOT part
// of the main package graph — it is only ever built when cross-compiling for
// Android (via android/native/build-jni.sh), so its `<jni.h>` dependency never
// touches the macOS/Linux CI.
//
// The `mermaidkit` product is a C target (the JNI shim) that statically links
// `MermaidKitC` from the parent package; `swift build --swift-sdk <abi>-android`
// emits `libmermaidkit.so` with the Swift core inside and the Swift runtime as
// NEEDED deps — letting swift build own every Android linker detail.
let package = Package(
    name: "MermaidJNI",
    products: [
        .library(name: "mermaidkit", type: .dynamic, targets: ["MermaidJNI"]),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(
            name: "MermaidJNI",
            dependencies: [.product(name: "MermaidKitC", package: "MermaidKit")],
            // <jni.h> resolves from the Android SDK sysroot when cross-compiling.
            cSettings: [.unsafeFlags(["-fvisibility=default"])]
        ),
    ]
)
