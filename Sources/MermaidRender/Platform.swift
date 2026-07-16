// Apple rendering backend platform layer (AppKit/UIKit + CoreGraphics). The
// Linux counterpart — the same PlatformColor/Font/Image surface over Silica —
// lives in `PlatformLinux.swift`.
#if canImport(AppKit) || canImport(UIKit)
import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
/// `NSColor` on macOS, `UIColor` on UIKit platforms.
public typealias PlatformColor = NSColor
/// `NSFont` on macOS, `UIFont` on UIKit platforms.
public typealias PlatformFont = NSFont
/// `NSImage` on macOS, `UIImage` on UIKit platforms.
public typealias PlatformImage = NSImage
#else
import UIKit
/// `NSColor` on macOS, `UIColor` on UIKit platforms.
public typealias PlatformColor = UIColor
/// `NSFont` on macOS, `UIFont` on UIKit platforms.
public typealias PlatformFont = UIFont
/// `NSImage` on macOS, `UIImage` on UIKit platforms.
public typealias PlatformImage = UIImage
#endif

/// A fixed color from a 0xRRGGBB literal (sRGB components) — identical in
/// light and dark appearance; use `themeDynamic` for appearance-following.
func rgbStatic(_ hex: UInt32, alpha: CGFloat = 1) -> PlatformColor {
    PlatformColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
/// An appearance-following color, re-resolved at draw time: `dark` when the
/// effective `NSAppearance` best-matches dark aqua (macOS) or the trait
/// collection's `userInterfaceStyle` is dark (UIKit), else `light`.
func themeDynamic(light: PlatformColor, dark: PlatformColor) -> PlatformColor {
    #if canImport(AppKit)
    return NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    #else
    return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    #endif
}
/// The color as a concrete `CGColor` for CoreGraphics fills/strokes. On
/// AppKit it converts through sRGB first so catalog/dynamic `NSColor`s
/// resolve to component form under the current appearance (falling back to
/// plain `cgColor` when conversion fails); UIKit's `cgColor` already
/// resolves against the current trait collection.
func resolvedCGColor(_ color: PlatformColor) -> CGColor {
    #if canImport(AppKit)
    return color.usingColorSpace(.sRGB)?.cgColor ?? color.cgColor
    #else
    return color.cgColor
    #endif
}
#endif
