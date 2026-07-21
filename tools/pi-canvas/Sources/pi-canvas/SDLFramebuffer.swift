#if canImport(CSDL2)
import CSDL2
import Foundation

/// A `Framebuffer` backed by SDL2 — the presentation surface for the whole
/// game/GPU/embedded class (SDL runs on desktops, consoles, Steam Deck, the Pi
/// with KMS/DRM, …). SDL has no vector/text drawing of its own, so this is the
/// canonical pattern: upload the composited RGBA as a streaming texture and
/// present it. The pixels come from MermaidKit's raw raster — the primitive that
/// makes any of this possible.
///
/// It runs **headless** for verification: the window is hidden and rendered with
/// the software renderer (`SDL_VIDEODRIVER=dummy` needs no display), and each
/// frame is read back with `SDL_RenderReadPixels` and written as a PNG — proving
/// the upload → render → present → readback pipeline without a screen. On a real
/// desktop you'd drop the hidden flag and pump the event loop.
final class SDLFramebuffer: Framebuffer {
    let width: Int
    let height: Int
    private let window: OpaquePointer
    private let renderer: OpaquePointer
    private let texture: OpaquePointer
    private let readbackDir: String?
    private var frame = 0
    // SDL_PIXELFORMAT_ABGR8888: on little-endian, bytes are R,G,B,A — our layout.
    private let format = SDL_PIXELFORMAT_ABGR8888

    init?(width: Int, height: Int, readbackDir: String?) {
        guard SDL_Init(SDL_INIT_VIDEO) == 0 else { return nil }
        guard let window = SDL_CreateWindow(
            "pi-canvas", 0, 0, Int32(width), Int32(height), SDL_WINDOW_HIDDEN.rawValue) else {
            SDL_Quit(); return nil
        }
        guard let renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE.rawValue) else {
            SDL_DestroyWindow(window); SDL_Quit(); return nil
        }
        guard let texture = SDL_CreateTexture(
            renderer, format.rawValue, Int32(SDL_TEXTUREACCESS_STREAMING.rawValue),
            Int32(width), Int32(height)) else {
            SDL_DestroyRenderer(renderer); SDL_DestroyWindow(window); SDL_Quit(); return nil
        }
        self.width = width; self.height = height
        self.window = window; self.renderer = renderer; self.texture = texture
        self.readbackDir = readbackDir
    }

    deinit {
        SDL_DestroyTexture(texture)
        SDL_DestroyRenderer(renderer)
        SDL_DestroyWindow(window)
        SDL_Quit()
    }

    func present(_ rgba: [UInt8]) {
        rgba.withUnsafeBytes { buf in
            SDL_UpdateTexture(texture, nil, buf.baseAddress, Int32(width * 4))
        }
        SDL_RenderClear(renderer)
        SDL_RenderCopy(renderer, texture, nil, nil)
        SDL_RenderPresent(renderer)

        // Headless proof: read the rendered frame back and write a PNG.
        if let dir = readbackDir {
            var out = [UInt8](repeating: 0, count: width * height * 4)
            let ok = out.withUnsafeMutableBytes { p in
                SDL_RenderReadPixels(renderer, nil, format.rawValue, p.baseAddress, Int32(width * 4))
            }
            if ok == 0 {
                let data = PNG.encode(rgba: out, width: width, height: height)
                try? data.write(to: URL(fileURLWithPath: "\(dir)/sdl-frame-\(String(format: "%02d", frame)).png"))
            }
        }
        frame += 1
    }
}
#endif
