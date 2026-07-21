import Foundation

// A tiny, dependency-free PNG encoder for an RGBA8888 buffer. Pure Swift (no
// zlib): the IDAT is a zlib stream using *stored* (uncompressed) deflate blocks,
// which is valid and needs no compressor. Platform-free — the same code runs on
// macOS, Linux, and the Pi — so the composited viewport can be written out
// identically anywhere, as a stand-in for blitting to a real framebuffer.
enum PNG {

    static func encode(rgba: [UInt8], width: Int, height: Int) -> Data {
        precondition(rgba.count == width * height * 4, "rgba size mismatch")
        var out = Data([137, 80, 78, 71, 13, 10, 26, 10]) // signature

        // IHDR
        var ihdr = Data()
        ihdr.appendBE(UInt32(width))
        ihdr.appendBE(UInt32(height))
        ihdr.append(contentsOf: [8, 6, 0, 0, 0]) // 8-bit, colortype 6 (RGBA), deflate, no filter, no interlace
        out.append(chunk("IHDR", ihdr))

        // IDAT: zlib(stored) over the filtered scanlines (filter byte 0 per row).
        var raw = [UInt8]()
        raw.reserveCapacity(height * (1 + width * 4))
        for y in 0..<height {
            raw.append(0) // filter: none
            let start = y * width * 4
            raw.append(contentsOf: rgba[start..<start + width * 4])
        }
        out.append(chunk("IDAT", zlibStored(raw)))

        out.append(chunk("IEND", Data()))
        return out
    }

    // A zlib stream whose deflate payload is stored (BTYPE=00) blocks.
    private static func zlibStored(_ data: [UInt8]) -> Data {
        var z = Data([0x78, 0x01]) // zlib header (CM=8, no preset dict, default level)
        var offset = 0
        let n = data.count
        if n == 0 {
            z.append(contentsOf: [0x01, 0x00, 0x00, 0xFF, 0xFF]) // final empty stored block
        }
        while offset < n {
            let len = min(65535, n - offset)
            let isLast = (offset + len == n)
            z.append(isLast ? 0x01 : 0x00)         // BFINAL + BTYPE=00
            z.append(UInt8(len & 0xFF)); z.append(UInt8((len >> 8) & 0xFF))         // LEN (LE)
            let nlen = ~UInt16(len)
            z.append(UInt8(nlen & 0xFF)); z.append(UInt8((nlen >> 8) & 0xFF))       // NLEN (LE)
            z.append(contentsOf: data[offset..<offset + len])
            offset += len
        }
        z.appendBE(adler32(data))
        return z
    }

    private static func chunk(_ type: String, _ data: Data) -> Data {
        var c = Data()
        c.appendBE(UInt32(data.count))
        let typeBytes = Array(type.utf8)
        c.append(contentsOf: typeBytes)
        c.append(data)
        var crcInput = [UInt8](typeBytes)
        crcInput.append(contentsOf: data)
        c.appendBE(crc32(crcInput))
        return c
    }

    // MARK: checksums

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
            return c
        }
    }()

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in bytes { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    private static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }
}

private extension Data {
    mutating func appendBE(_ v: UInt32) {
        append(UInt8((v >> 24) & 0xFF)); append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 8) & 0xFF)); append(UInt8(v & 0xFF))
    }
}
