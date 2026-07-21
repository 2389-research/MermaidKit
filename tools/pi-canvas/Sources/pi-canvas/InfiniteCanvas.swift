import Foundation
import MermaidLayout
import MermaidRender

/// A diagram placed at a position in an unbounded virtual canvas.
struct Placed {
    let source: String
    let x: Int          // virtual-space top-left, at zoom 1
    let y: Int
    let baseWidth: Int  // render target width at zoom 1
}

/// The infinite, pannable canvas. It renders each diagram to an RGBA raster once
/// (cached per zoom — `MermaidRenderer.rgbaRaster` is itself resolution-independent
/// behind the scene, so zooming RE-rasterizes for crispness rather than scaling a
/// bitmap), then each frame culls to the viewport and blits the visible cards into
/// the framebuffer. Panning is just moving the viewport and re-compositing —
/// pure memcpy over already-rendered cards.
final class InfiniteCanvas {
    private let items: [Placed]
    private let theme: DiagramTheme
    private let canvasBG: (r: UInt8, g: UInt8, b: UInt8)
    private let cardBG: (r: UInt8, g: UInt8, b: UInt8)
    private var cache: [String: (pixels: [UInt8], width: Int, height: Int)] = [:]
    private(set) var renders = 0

    init(items: [Placed],
         theme: DiagramTheme,
         canvasBG: (r: UInt8, g: UInt8, b: UInt8),
         cardBG: (r: UInt8, g: UInt8, b: UInt8)) {
        self.items = items; self.theme = theme; self.canvasBG = canvasBG; self.cardBG = cardBG
    }

    private func raster(_ i: Int, zoom: Double) -> (pixels: [UInt8], width: Int, height: Int)? {
        let key = "\(i)@\(zoom)"
        if let hit = cache[key] { return hit }
        let tw = max(1, Int((Double(items[i].baseWidth) * zoom).rounded()))
        guard let r = MermaidRenderer.rgbaRaster(
            source: items[i].source, theme: theme, targetWidth: tw, background: cardBG) else { return nil }
        // `rgbaRaster` returns bottom-up rows on the AppKit path (CoreGraphics
        // origin); a framebuffer/PNG is top-down, so flip. The Silica/Linux path
        // is already top-down (documented), so it doesn't.
        #if canImport(AppKit) || canImport(UIKit)
        let pixels = flipVertically(r.pixels, width: r.width, height: r.height)
        #else
        let pixels = r.pixels
        #endif
        let out = (pixels: pixels, width: r.width, height: r.height)
        cache[key] = out
        renders += 1
        return out
    }

    private func flipVertically(_ px: [UInt8], width: Int, height: Int) -> [UInt8] {
        let rowBytes = width * 4
        var out = [UInt8](repeating: 0, count: px.count)
        for y in 0..<height {
            let src = (height - 1 - y) * rowBytes
            let dst = y * rowBytes
            out.replaceSubrange(dst..<dst + rowBytes, with: px[src..<src + rowBytes])
        }
        return out
    }

    /// Composite the frame whose top-left is virtual point (`viewportX`,`viewportY`)
    /// at `zoom`, and present it. Off-screen cards are skipped (culled).
    func composite(viewportX: Int, viewportY: Int, zoom: Double, into fb: Framebuffer) {
        let W = fb.width, H = fb.height
        var buf = [UInt8](repeating: 255, count: W * H * 4)
        for p in stride(from: 0, to: buf.count, by: 4) {
            buf[p] = canvasBG.r; buf[p + 1] = canvasBG.g; buf[p + 2] = canvasBG.b
        }
        for i in items.indices {
            guard let r = raster(i, zoom: zoom) else { continue }
            let dx = Int((Double(items[i].x) * zoom).rounded()) - viewportX
            let dy = Int((Double(items[i].y) * zoom).rounded()) - viewportY
            if dx >= W || dy >= H || dx + r.width <= 0 || dy + r.height <= 0 { continue } // cull
            blit(r, into: &buf, W: W, dx: dx, dy: dy)
        }
        fb.present(buf)
    }

    /// Copy the visible overlap of a card into the frame buffer, with a 1px border
    /// so cards read as distinct on the canvas.
    private func blit(_ r: (pixels: [UInt8], width: Int, height: Int),
                      into buf: inout [UInt8], W: Int, dx: Int, dy: Int) {
        let H = buf.count / (W * 4)
        let x0 = max(0, dx), x1 = min(W, dx + r.width)
        let y0 = max(0, dy), y1 = min(H, dy + r.height)
        if x0 >= x1 || y0 >= y1 { return }
        for y in y0..<y1 {
            let sy = y - dy
            var d = (y * W + x0) * 4
            var sx = x0 - dx
            var s = (sy * r.width + sx) * 4
            for _ in x0..<x1 {
                let edge = sx == 0 || sx == r.width - 1 || sy == 0 || sy == r.height - 1
                if edge {
                    buf[d] = 176; buf[d + 1] = 178; buf[d + 2] = 184 // card border
                } else {
                    buf[d] = r.pixels[s]; buf[d + 1] = r.pixels[s + 1]; buf[d + 2] = r.pixels[s + 2]
                }
                buf[d + 3] = 255
                d += 4; s += 4; sx += 1
            }
        }
    }
}
