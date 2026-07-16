// Linux rendering backend platform layer.
//
// On Apple platforms MermaidRender draws with CoreGraphics/CoreText and its
// types come from AppKit/UIKit. On Linux there is no CoreGraphics; this file
// vends the same *surface* the shared drawing code expects — `PlatformColor`,
// `PlatformFont`, `PlatformImage`, `resolvedCGColor`, plus an adapter that
// gives Silica's `CGContext` the exact Apple-CoreGraphics method names the
// renderer calls — backed by Silica (Cairo/FontConfig). The per-diagram
// drawing code is then identical across platforms.
//
// `canImport(SilicaCairo)` is true only where the Linux backend is linked
// (see Package.swift's platform-conditioned dependency), so it is the precise
// "Linux render backend available" signal.
#if canImport(SilicaCairo) && !canImport(AppKit) && !canImport(UIKit)
import Foundation
// Re-export the Silica stack module-wide so the shared render files (whose
// CoreGraphics imports are Apple-only) see CGContext/CGColor/CGPath/CGFont,
// CairoContext, and Cairo.Surface on Linux without importing them each.
@_exported import Silica
@_exported import SilicaCairo
@_exported import Cairo
import MermaidLayout

// MARK: - Platform color

/// A fixed sRGB color. The Apple backend uses `NSColor`/`UIColor` (including
/// appearance-dynamic colors); on Linux there is no appearance system, and —
/// since `themeDynamic` is unused and every built-in theme color is a fixed
/// literal or the system accent — a plain RGBA value is a faithful stand-in.
public struct PlatformColor: Sendable, Hashable {
    public var red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    /// The same color at a new opacity (mirrors `NSColor.withAlphaComponent`).
    public func withAlphaComponent(_ a: CGFloat) -> PlatformColor {
        PlatformColor(red: red, green: green, blue: blue, alpha: a)
    }
    /// Mirrors `NSColor.getRed(_:green:blue:alpha:)`; always succeeds here.
    @discardableResult
    public func getRed(_ r: inout CGFloat, green g: inout CGFloat,
                       blue b: inout CGFloat, alpha a: inout CGFloat) -> Bool {
        r = red; g = green; b = blue; a = alpha; return true
    }
    public var description: String {
        "rgba(\(red),\(green),\(blue),\(alpha))"
    }
    /// A neutral system accent (macOS/iOS resolve a live one; Linux is fixed) —
    /// the palette blue, so preset themes read consistently.
    public static let controlAccentColor = PlatformColor(red: 0x5B / 255, green: 0x8F / 255, blue: 0xF9 / 255, alpha: 1)
    public static let tintColor = controlAccentColor
    // System palette approximations (Apple's sRGB system colors) used by the
    // gantt status tints etc.
    public static let systemRed = PlatformColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1)
    public static let systemGreen = PlatformColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
    public static let systemOrange = PlatformColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1)
    public static let systemYellow = PlatformColor(red: 1.0, green: 0.80, blue: 0.0, alpha: 1)
    public static let white = PlatformColor(red: 1, green: 1, blue: 1, alpha: 1)
}

/// A fixed color from a 0xRRGGBB literal (sRGB) — matches the Apple helper.
func rgbStatic(_ hex: UInt32, alpha: CGFloat = 1) -> PlatformColor {
    PlatformColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// On Linux there is no draw-time appearance to follow, so a "dynamic" color
/// resolves immediately to its light variant. (Currently unused; kept for
/// API parity with the Apple backend.)
func themeDynamic(light: PlatformColor, dark: PlatformColor) -> PlatformColor { light }

/// The color as a Silica `CGColor` for fills/strokes. Unlike the AppKit twin
/// (`Platform.swift`), no sRGB / appearance resolution is needed: `PlatformColor`
/// is already a fixed sRGB value here.
func resolvedCGColor(_ color: PlatformColor) -> Silica.CGColor {
    Silica.CGColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
}

// MARK: - Platform font

/// The Apple backend uses `NSFont`/`UIFont` + CoreText. On Linux fonts are
/// resolved by FontConfig via Silica's `CGFont`; this thin type carries a
/// weight and resolves a cached family, so the shared code's
/// `PlatformFont.Weight` references compile and Linux text uses the same font
/// as its measurement.
public struct PlatformFont: Sendable {
    public enum Weight: Sendable { case regular, medium, semibold, bold }
    /// The FontConfig *pattern* (not a bare family name) for a weight, passed to
    /// `CGFont(name:)`: the `:bold` suffix is FontConfig syntax selecting the
    /// bold face. "DejaVu Sans" is present in the minimal container image;
    /// FontConfig substitutes the platform's default sans otherwise. Medium and
    /// semibold aren't distinguished from regular/bold here — FontConfig has no
    /// closer face in the base image, and diagram chrome doesn't lean on the
    /// intermediate weights the way body text would.
    static func familyName(_ weight: Weight) -> String {
        switch weight {
        case .regular, .medium: return "DejaVu Sans"
        case .semibold, .bold: return "DejaVu Sans:bold"
        }
    }
}

/// Process-wide cache of FontConfig-resolved fonts. The `NSLock` fully guards
/// the dictionary; the cached `CGFont` values are then used concurrently by the
/// async render path (`renderImage` runs on a detached task), each drawing into
/// its own context but sharing the font. That is sound because the underlying
/// Cairo `ScaledFont` / FreeType face carry their own internal locking — the
/// `@unchecked Sendable` rests on that library guarantee, not on this lock,
/// which only protects the `store` dictionary.
private final class FontCache: @unchecked Sendable {
    static let shared = FontCache()
    private var store: [String: Silica.CGFont] = [:]
    private let lock = NSLock()
    func font(_ name: String) -> Silica.CGFont? {
        lock.lock(); defer { lock.unlock() }
        if let f = store[name] { return f }
        guard let f = Silica.CGFont(name: name) else { return nil }
        store[name] = f
        return f
    }
}

func linuxFont(_ weight: PlatformFont.Weight) -> Silica.CGFont? {
    FontCache.shared.font(PlatformFont.familyName(weight))
}

// MARK: - Platform image

/// A rendered raster: the Cairo image surface plus its point size. The Apple
/// backend returns `NSImage`/`UIImage`; on Linux `PlatformImage` exposes PNG
/// bytes (the portable diagram artifact) and the pixel dimensions.
public struct PlatformImage: @unchecked Sendable {
    public let surface: Cairo.Surface
    public let size: CGSize
    /// Accessibility text, mirroring the Apple image's `accessibilityDescription`.
    public var accessibilityDescription: String?

    public init(surface: Cairo.Surface, size: CGSize) {
        self.surface = surface; self.size = size
    }

    /// PNG-encoded bytes, or nil if encoding fails. Silica's Cairo surface only
    /// vends `writePNG(atPath:)` — there is no in-memory PNG encoder — so the
    /// bytes must round-trip through a uniquely-named temp file we immediately
    /// delete. A failed write leaves no readable file, so `Data(contentsOf:)`
    /// returns nil, which is the contract.
    public func pngData() -> Data? {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("mermaidkit-\(UUID().uuidString).png")
        surface.flush()
        surface.writePNG(atPath: url.path)
        defer { try? FileManager.default.removeItem(at: url) }
        return try? Data(contentsOf: url)
    }

    /// Writes the PNG to `path`, returning whether a valid PNG landed there.
    /// `writePNG` is non-throwing and a pre-existing file would make a bare
    /// `fileExists` check a false positive, so confirm the write by reading back
    /// the 8-byte PNG signature (cheap; a failed/partial write won't match).
    @discardableResult
    public func writePNG(to path: String) -> Bool {
        surface.flush()
        surface.writePNG(atPath: path)
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        return handle.readData(ofLength: 8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}

// MARK: - CGContext adapter (Apple-CoreGraphics method names over Silica)

extension Silica.CGContext {
    /// Graphics-state stack (Silica spells these `save`/`restore`, throwing).
    func saveGState() { try? save() }
    func restoreGState() { try? restore() }

    /// Rotation (Silica: `rotateBy`).
    func rotate(by angle: CGFloat) { rotateBy(angle) }

    /// Line attributes Silica exposes as properties, not setters.
    func setLineJoin(_ join: CGLineJoin) { lineJoin = join }
    func setLineCap(_ cap: CGLineCap) { lineCap = cap }

    /// Rect/ellipse convenience that bypass the current path on Apple.
    func fill(_ rect: CGRect) { beginPath(); addRect(rect); fillPath(using: .winding) }
    func stroke(_ rect: CGRect) { beginPath(); addRect(rect); strokePath() }
    func fillEllipse(in rect: CGRect) { beginPath(); addEllipse(in: rect); fillPath(using: .winding) }
    func strokeEllipse(in rect: CGRect) { beginPath(); addEllipse(in: rect); strokePath() }

    /// No-argument fill (Apple's default winding-rule fill).
    func fillPath() { fillPath(using: .winding) }
}

// MARK: - CGPath convenience initializers (Apple-shaped, over CGMutablePath)

extension Silica.CGPath {
    /// A rounded rectangle, corners approximated with quad curves — a parabolic
    /// stand-in for the circular quarter-arc, since Silica's `CGMutablePath` has
    /// no arc primitive. Imperceptible at the small corner radii (~4–8pt) the
    /// renderer uses. `cornerWidth`/`cornerHeight` are clamped to half the rect;
    /// `transform` is accepted for call-site parity and unused (every renderer
    /// call passes nil).
    public convenience init(roundedRect rect: CGRect, cornerWidth: CGFloat,
                            cornerHeight: CGFloat, transform: UnsafePointer<CGAffineTransform>? = nil) {
        let rx = Swift.min(cornerWidth, rect.width / 2)
        let ry = Swift.min(cornerHeight, rect.height / 2)
        let p = CGMutablePath()
        let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        p.move(to: CGPoint(x: minX + rx, y: minY))
        p.addLine(to: CGPoint(x: maxX - rx, y: minY))
        p.addQuadCurve(to: CGPoint(x: maxX, y: minY + ry), control: CGPoint(x: maxX, y: minY))
        p.addLine(to: CGPoint(x: maxX, y: maxY - ry))
        p.addQuadCurve(to: CGPoint(x: maxX - rx, y: maxY), control: CGPoint(x: maxX, y: maxY))
        p.addLine(to: CGPoint(x: minX + rx, y: maxY))
        p.addQuadCurve(to: CGPoint(x: minX, y: maxY - ry), control: CGPoint(x: minX, y: maxY))
        p.addLine(to: CGPoint(x: minX, y: minY + ry))
        p.addQuadCurve(to: CGPoint(x: minX + rx, y: minY), control: CGPoint(x: minX, y: minY))
        p.closeSubpath()
        self.init(elements: p.elements)
    }

    /// An ellipse inscribed in `rect`.
    public convenience init(ellipseIn rect: CGRect, transform: UnsafePointer<CGAffineTransform>? = nil) {
        let p = CGMutablePath()
        p.addEllipse(in: rect)
        self.init(elements: p.elements)
    }
}
#endif
