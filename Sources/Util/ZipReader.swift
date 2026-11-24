// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import Foundation
#if canImport(Compression)
import Compression
#endif

/// Minimal ZIP reader for `.pkpass` files (#20): the central directory, stored and deflated entries.
/// Enough for Wallet passes (a few small JSON and PNG files); no encryption, no ZIP64.
enum ZipReader {
    enum Failure: Error { case notZip, unsupported, damaged }

    /// The largest entry read (a pass is a few hundred KB; this stops a hostile file from filling memory).
    static let maxEntryBytes = 20 * 1024 * 1024

    struct Entry: Sendable {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let size: Int
        let offset: Int
    }

    static func entries(_ data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        // End of central directory: signature 0x06054b50 in the last 64 KB + 22 bytes.
        guard bytes.count >= 22 else { throw Failure.notZip }
        var eocd = -1
        var i = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        while i >= lowest {
            if u32(bytes, i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw Failure.notZip }
        let count = Int(u16(bytes, eocd + 10))
        var p = Int(u32(bytes, eocd + 16))
        var list: [Entry] = []
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(bytes, p) == 0x02014b50 else { throw Failure.damaged }
            let method = u16(bytes, p + 10)
            let csize = Int(u32(bytes, p + 20)), size = Int(u32(bytes, p + 24))
            let nameLen = Int(u16(bytes, p + 28)), extraLen = Int(u16(bytes, p + 30)), commentLen = Int(u16(bytes, p + 32))
            let offset = Int(u32(bytes, p + 42))
            guard p + 46 + nameLen <= bytes.count else { throw Failure.damaged }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            list.append(Entry(name: name, method: method, compressedSize: csize, size: size, offset: offset))
            p += 46 + nameLen + extraLen + commentLen
        }
        return list
    }

    /// The file `name` (case-insensitive), or nil when the archive has no such file.
    static func file(_ name: String, in data: Data) throws -> Data? {
        guard let entry = try entries(data).first(where: { $0.name.lowercased() == name.lowercased() }) else { return nil }
        return try read(entry, in: data)
    }

    static func read(_ entry: Entry, in data: Data) throws -> Data {
        guard entry.size <= maxEntryBytes, entry.compressedSize <= maxEntryBytes else { throw Failure.unsupported }
        let bytes = [UInt8](data)
        let h = entry.offset
        guard h + 30 <= bytes.count, u32(bytes, h) == 0x04034b50 else { throw Failure.damaged }
        let start = h + 30 + Int(u16(bytes, h + 26)) + Int(u16(bytes, h + 28))
        guard start + entry.compressedSize <= bytes.count else { throw Failure.damaged }
        let raw = Data(bytes[start..<(start + entry.compressedSize)])
        switch entry.method {
        case 0: return raw
        case 8: return try inflate(raw, size: entry.size)
        default: throw Failure.unsupported
        }
    }

    private static func inflate(_ raw: Data, size: Int) throws -> Data {
        #if canImport(Compression)
        guard size > 0 else { return Data() }
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { dst in
            raw.withUnsafeBytes { src in
                // COMPRESSION_ZLIB is raw DEFLATE (RFC 1951), as in ZIP.
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                          src.bindMemory(to: UInt8.self).baseAddress!, raw.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw Failure.damaged }
        return out
        #else
        throw Failure.unsupported
        #endif
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
}
