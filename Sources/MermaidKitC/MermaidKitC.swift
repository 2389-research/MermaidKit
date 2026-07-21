// MermaidKitC — a thin, platform-free C ABI over MermaidKit's render pipeline.
//
// This is the surface Android's JNI layer calls (Phase 1a of docs/notes/android.md):
// parse a Mermaid source, lower it to a `RenderScene`, and hand back deterministic
// JSON — with the device font's measurements threaded in through a C callback so
// layout measures with the same face that ultimately draws (Vinculum's #62 lesson:
// the measure seam must be pinned to the drawing face). It depends ONLY on
// `MermaidLayout` — no CoreGraphics/CoreText, no Silica/Cairo — so the whole target
// and its tests build and run on macOS and Linux today, before any NDK is in play.
//
// Memory contract: every non-nil `char *` returned by an `mmk_*` function is a
// heap allocation the CALLER owns and MUST release with `mmk_free`. Returns are
// `nil` on failure (nil/invalid source, parse failure) — these functions never
// trap.

import Foundation
import MermaidLayout
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#elseif canImport(Bionic)
import Bionic
#endif

// MARK: - Measurement callback

/// The device-measure seam. A JNI consumer passes a function that measures a
/// UTF-8 C string at a given point size using the *drawing* face (Kotlin's
/// `Paint.measureText`), writing the resulting width/height back through the two
/// out-pointers. `userdata` is an opaque pointer round-tripped from
/// `mmk_scene_json` so the callback can reach its `Paint`/context.
///
/// Layout must measure with the face that draws — see the Vinculum #62 lesson —
/// so this callback (not an approximation) is the truth on the product surface.
public typealias MmkMeasure = @convention(c) (
    _ text: UnsafePointer<CChar>?,
    _ fontSize: Double,
    _ userdata: UnsafeMutableRawPointer?,
    _ outW: UnsafeMutablePointer<Double>?,
    _ outH: UnsafeMutablePointer<Double>?
) -> Void

// MARK: - Default themes

// TODO(Phase 1b): accept explicit Material colors from the caller. v1 selects a
// built-in light or dark preset purely from `prefers_dark`; Phase 2's
// `MermaidTheme.fromMaterial()` will supply real tokens across the bridge.
//
// These mirror the reference theme in `RenderSceneTests` (and MermaidRender's
// built-in preset): a near-black/near-white ink ramp at 100/55/38% alpha, a
// white or near-black canvas, a blue accent, 12% hairlines, and the six-hue
// default palette.
private func defaultTheme(prefersDark: Bool) -> RenderTheme {
    let fg: UInt32 = prefersDark ? 0xF2F2F4 : 0x1D1D1F
    return RenderTheme(
        ink: DiagramColor(hex: fg),
        accent: DiagramColor(hex: 0x5B8FF9),
        canvas: DiagramColor(hex: prefersDark ? 0x1B1B1D : 0xFFFFFF),
        hairline: DiagramColor(hex: prefersDark ? 0xFFFFFF : 0x000000, alpha: 0.12),
        secondaryText: DiagramColor(hex: fg, alpha: 0.55),
        tertiaryText: DiagramColor(hex: fg, alpha: 0.38),
        palette: [
            DiagramColor(hex: 0x5B8FF9), // blue
            DiagramColor(hex: 0x5AD8A6), // green
            DiagramColor(hex: 0xF6BD16), // gold
            DiagramColor(hex: 0xE8684A), // coral
            DiagramColor(hex: 0x6DC8EC), // sky
            DiagramColor(hex: 0x9270CA), // purple
        ],
        prefersDark: prefersDark)
}

// MARK: - Measurer bridge

/// Wraps the C `MmkMeasure` callback (plus its opaque `userdata`) into the
/// Swift `DiagramTextMeasurer` closure the layout engine calls. When `measure`
/// is nil (headless / SVG paths with no device font) we fall back to a coarse
/// glyph-box approximation — `width ≈ count · size · 0.6`, `height ≈ size + 4` —
/// which matches the deterministic fake measurer used across the test suite.
private func makeMeasurer(_ measure: MmkMeasure?,
                          _ userdata: UnsafeMutableRawPointer?) -> DiagramTextMeasurer {
    guard let measure else {
        return { text, size in
            CGSize(width: CGFloat(max(text.count, 1)) * size * 0.6,
                   height: size + 4)
        }
    }
    return { text, size in
        var w: Double = 0
        var h: Double = 0
        text.withCString { cstr in
            measure(cstr, Double(size), userdata, &w, &h)
        }
        // A callback that measures nothing (both zero) is treated as the coarse
        // fallback so a degenerate `Paint` never collapses layout to a point.
        if w <= 0 && h <= 0 {
            return CGSize(width: CGFloat(max(text.count, 1)) * size * 0.6,
                          height: size + 4)
        }
        return CGSize(width: CGFloat(w), height: CGFloat(h))
    }
}

// MARK: - JSON encoding

/// The deterministic wire form: sorted keys so identical inputs produce
/// byte-for-byte identical JSON across processes and platforms (the golden /
/// JNI contract).
private let sceneEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}()

/// Copies a Swift `String` into a freshly malloc'd, NUL-terminated C string the
/// caller owns (and frees via `mmk_free`). `strdup` over the UTF-8 bytes.
private func cString(_ string: String) -> UnsafeMutablePointer<CChar>? {
    string.withCString { strdup($0) }
}

// MARK: - C ABI

/// The shared body behind `mmk_scene_json` / `mmk_scene_json_themed`: parse,
/// lower with `theme` + `measurer`, and encode the `SceneWire` JSON. Returns a
/// malloc'd C string the caller owns, or nil on parse/encode failure.
private func sceneJSON(source: UnsafePointer<CChar>?,
                      theme: RenderTheme,
                      measure: MmkMeasure?,
                      userdata: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<CChar>? {
    guard let source else { return nil }
    let swiftSource = String(cString: source)

    guard let diagram = MermaidParser.parse(swiftSource) else { return nil }

    let measurer = makeMeasurer(measure, userdata)

    guard let scene = RenderScene.from(diagram, theme: theme, measure: measurer) else {
        return nil
    }
    // Encode the explicit wire schema (`SceneWire`), not `RenderScene`'s
    // synthesized Codable — the JNI/plugin boundary reads self-describing,
    // `type`-tagged JSON with named fields, not Swift's `_0`/positional-array
    // quirks. See `SceneWire`.
    guard let data = try? sceneEncoder.encode(SceneWire(scene)),
          let json = String(data: data, encoding: .utf8) else {
        return nil
    }
    return cString(json)
}

/// Parse `source` (UTF-8), lower it to a `RenderScene` using `measure` (or the
/// coarse fallback when nil), and return the scene as deterministic JSON.
///
/// - `prefersDark`: non-zero selects the dark preset theme, zero the light one.
/// - Returns a malloc'd C string the caller owns (free via `mmk_free`), or `nil`
///   when `source` is nil or does not parse. Never traps.
@_cdecl("mmk_scene_json")
public func mmk_scene_json(_ source: UnsafePointer<CChar>?,
                           _ prefersDark: Int32,
                           _ measure: MmkMeasure?,
                           _ userdata: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<CChar>? {
    sceneJSON(source: source, theme: defaultTheme(prefersDark: prefersDark != 0),
              measure: measure, userdata: userdata)
}

/// Like `mmk_scene_json`, but themed with explicit caller colors instead of a
/// built-in preset. `theme_json` is a `ThemeWire` JSON object (colors as
/// `#RRGGBBAA` strings + a `prefersDark` flag) — the Android side builds it from
/// a Material `ColorScheme`.
///
/// - `theme_json` nil → falls back to the light preset (equivalent to
///   `mmk_scene_json(..., 0, ...)`). Present but malformed (bad JSON or a bad
///   color) → returns nil, so a caller error is visible rather than silently
///   themed wrong.
/// - Returns a malloc'd C string the caller owns (free via `mmk_free`), or `nil`
///   when `source` is nil, `source` doesn't parse, or `theme_json` is invalid.
@_cdecl("mmk_scene_json_themed")
public func mmk_scene_json_themed(_ source: UnsafePointer<CChar>?,
                                  _ themeJson: UnsafePointer<CChar>?,
                                  _ measure: MmkMeasure?,
                                  _ userdata: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<CChar>? {
    let theme: RenderTheme
    if let themeJson {
        let json = String(cString: themeJson)
        guard let wire = try? JSONDecoder().decode(ThemeWire.self, from: Data(json.utf8)),
              let resolved = try? wire.renderTheme() else {
            return nil // present-but-invalid theme is a caller error, not a silent fallback
        }
        theme = resolved
    } else {
        theme = defaultTheme(prefersDark: false)
    }
    return sceneJSON(source: source, theme: theme, measure: measure, userdata: userdata)
}

/// Narrate `source` as an accessibility walkthrough (threaded from the first
/// surface, per the plan — feeds Android's `contentDescription`).
///
/// - Returns a malloc'd C string the caller owns (free via `mmk_free`), or `nil`
///   when `source` is nil or does not parse. Never traps.
@_cdecl("mmk_narrate")
public func mmk_narrate(_ source: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let source else { return nil }
    let swiftSource = String(cString: source)
    guard let narration = MermaidAltText.narrate(source: swiftSource) else { return nil }
    return cString(narration)
}

/// Free a C string returned by `mmk_scene_json` / `mmk_narrate`. Safe on nil.
@_cdecl("mmk_free")
public func mmk_free(_ ptr: UnsafeMutablePointer<CChar>?) {
    free(ptr)
}

// A stable version string, malloc'd ONCE at first use into a module global that
// lives for the program's lifetime (Swift initializes globals lazily and
// thread-safely). Because it is returned by every call and never reallocated,
// the caller MUST NOT free it — unlike the other `mmk_*` returns.
// `nonisolated(unsafe)`: the pointer is written once at lazy init and only ever
// read thereafter (an immutable, program-lifetime C string), so the shared
// mutable-state check doesn't apply.
nonisolated(unsafe) private let versionCString: UnsafeMutablePointer<CChar>? =
    strdup("MermaidKitC 2.2.0")

/// The MermaidKitC ABI version. Returns a pointer to a static string that the
/// caller MUST NOT free (unlike the `mmk_scene_json` / `mmk_narrate` returns).
@_cdecl("mmk_version")
public func mmk_version() -> UnsafePointer<CChar>? {
    UnsafePointer(versionCString)
}
