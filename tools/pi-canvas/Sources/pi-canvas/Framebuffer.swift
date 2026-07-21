import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// A fixed-size presentation surface the compositor blits into each frame.
protocol Framebuffer {
    var width: Int { get }
    var height: Int { get }
    /// Present one RGBA8888 frame (`width * height * 4` bytes).
    func present(_ rgba: [UInt8])
}

/// RGB565 packing — the pixel format most Raspberry Pi framebuffers use at 16bpp.
/// Pure and platform-free, so it's unit-testable without a real device.
enum Rgb565 {
    /// Pack one 8-bit-per-channel color into a 16-bit 5-6-5 value.
    static func pack(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> UInt16 {
        (UInt16(r >> 3) << 11) | (UInt16(g >> 2) << 5) | UInt16(b >> 3)
    }

    /// Convert an RGBA8888 buffer to little-endian RGB565 rows at `stride` bytes.
    static func convert(rgba: [UInt8], width: Int, height: Int, stride: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: stride * height)
        for y in 0..<height {
            var d = y * stride
            let s0 = y * width * 4
            for x in 0..<width {
                let s = s0 + x * 4
                let v = pack(rgba[s], rgba[s + 1], rgba[s + 2])
                out[d] = UInt8(v & 0xFF); out[d + 1] = UInt8(v >> 8) // little-endian
                d += 2
            }
        }
        return out
    }
}

/// The testable stand-in for a real framebuffer: each presented frame is written
/// out as a PNG. Blitting to `/dev/fb0` and encoding a PNG are the same shape —
/// take the composited RGBA and copy it somewhere — so this proves everything
/// except the final `mmap`+`memcpy`.
final class PNGFramebuffer: Framebuffer {
    let width: Int
    let height: Int
    private let directory: String
    private var frame = 0

    init(width: Int, height: Int, directory: String) {
        self.width = width; self.height = height; self.directory = directory
    }

    func present(_ rgba: [UInt8]) {
        let data = PNG.encode(rgba: rgba, width: width, height: height)
        let path = "\(directory)/frame-\(String(format: "%02d", frame)).png"
        try? data.write(to: URL(fileURLWithPath: path))
        frame += 1
    }
}

#if os(Linux)
/// The real Raspberry Pi surface: `mmap` `/dev/fb0` and blit each frame. This is
/// the one piece that can only run on-device — everything above it (compositor,
/// culling, RGB565 packing) is exercised headlessly. Geometry is read via ioctl
/// (offsets are the stable 64-bit `fb_var_screeninfo`/`fb_fix_screeninfo` layout,
/// which is what a Pi 5 runs); 16bpp uses RGB565, 32bpp writes BGRA.
final class LinuxFramebuffer: Framebuffer {
    let width: Int
    let height: Int
    private let bpp: Int
    private let stride: Int
    private let map: UnsafeMutableRawPointer
    private let mapLen: Int
    private let fd: Int32

    init?(device: String = "/dev/fb0") {
        fd = open(device, O_RDWR)
        guard fd >= 0 else { return nil }

        // FBIOGET_VSCREENINFO (0x4600): xres@0, yres@4, bits_per_pixel@24.
        var vinfo = [UInt8](repeating: 0, count: 160)
        // FBIOGET_FSCREENINFO (0x4602): line_length@48 (64-bit layout).
        var finfo = [UInt8](repeating: 0, count: 80)
        guard ioctl(fd, UInt(0x4600), &vinfo) == 0, ioctl(fd, UInt(0x4602), &finfo) == 0 else {
            close(fd); return nil
        }
        func u32(_ b: [UInt8], _ o: Int) -> Int {
            Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24
        }
        width = u32(vinfo, 0)
        height = u32(vinfo, 4)
        bpp = u32(vinfo, 24)
        stride = u32(finfo, 48)
        mapLen = stride * height
        guard let m = mmap(nil, mapLen, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0),
              m != MAP_FAILED else { close(fd); return nil }
        map = m
    }

    deinit { munmap(map, mapLen); close(fd) }

    func present(_ rgba: [UInt8]) {
        if bpp == 16 {
            let rows = Rgb565.convert(rgba: rgba, width: width, height: height, stride: stride)
            rows.withUnsafeBytes { if let b = $0.baseAddress { memcpy(map, b, min($0.count, mapLen)) } }
        } else { // 32bpp: framebuffer is typically BGRA
            var out = [UInt8](repeating: 0, count: stride * height)
            for y in 0..<height {
                var d = y * stride, s = y * width * 4
                for _ in 0..<width {
                    out[d] = rgba[s + 2]; out[d + 1] = rgba[s + 1]; out[d + 2] = rgba[s]; out[d + 3] = 255
                    d += 4; s += 4
                }
            }
            out.withUnsafeBytes { if let b = $0.baseAddress { memcpy(map, b, min($0.count, mapLen)) } }
        }
    }
}
#endif
