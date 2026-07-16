#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation

// swift-corelibs-foundation (Linux, Windows, WASI) vends CGFloat, CGPoint,
// CGSize, CGRect, and CGAffineTransform — but NOT CGVector, which lives only
// in Apple's CoreGraphics. MermaidLayout is the deliberately platform-free,
// zero-dependency half of the package, so rather than pull in a CoreGraphics
// reimplementation (Silica et al.) for one two-field struct, we vend an
// identical local CGVector off-Apple. On Apple the real type is used; the
// shim is source- and layout-compatible, so callers are none the wiser.
//
// Public because it surfaces in public API (`SceneDelta.movedNodes`); a public
// property may not expose a non-public type.
public struct CGVector: Equatable, Sendable {
    public var dx: CGFloat
    public var dy: CGFloat
    @inlinable public init(dx: CGFloat = 0, dy: CGFloat = 0) {
        self.dx = dx
        self.dy = dy
    }
}
#endif
