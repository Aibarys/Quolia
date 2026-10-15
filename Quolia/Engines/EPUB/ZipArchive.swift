import Foundation
import Compression

/// Minimal read-only ZIP reader — enough for EPUB containers.
/// Supports stored (0) and deflated (8) entries; ZIP64 is not needed for books.
struct ZipArchive: Sendable {
    struct Entry: Sendable {
        let path: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    enum ZipError: LocalizedError {
        case notAZip
        case unsupportedCompression(UInt16)
        case corrupted(String)
        case missingEntry(String)

        var errorDescription: String? {
            switch self {
            case .notAZip: String(localized: "The file is not a valid archive.")
            case .unsupportedCompression(let method): String(localized: "Unsupported compression method \(Int(method)).")
            case .corrupted(let reason): String(localized: "The archive is damaged (\(reason)).")
            case .missingEntry(let path): String(localized: "Missing file in book: \(path)")
            }
        }
    }

    private let data: Data
    let entries: [String: Entry]

    init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    init(data: Data) throws {
        self.data = data
        self.entries = try Self.readCentralDirectory(data)
    }

    var paths: [String] { Array(entries.keys) }

    func contains(_ path: String) -> Bool { entries[path] != nil || entry(caseInsensitive: path) != nil }

    func data(for path: String) throws -> Data {
        guard let entry = entries[path] ?? entry(caseInsensitive: path) else { throw ZipError.missingEntry(path) }
        return try extract(entry)
    }

    func string(for path: String) throws -> String {
        let raw = try data(for: path)
        if let string = String(data: raw, encoding: .utf8) { return string }
        if let string = String(data: raw, encoding: .utf16) { return string }
        return String(decoding: raw, as: UTF8.self)
    }

    private func entry(caseInsensitive path: String) -> Entry? {
        let lower = path.lowercased()
        return entries.first { $0.key.lowercased() == lower }?.value
    }

    // MARK: - Parsing

    private static func readCentralDirectory(_ data: Data) throws -> [String: Entry] {
        let eocdSignature: UInt32 = 0x0605_4b50
        guard data.count >= 22 else { throw ZipError.notAZip }

        // The End Of Central Directory record lives in the last 64KB + 22 bytes.
        let searchStart = max(0, data.count - 65_557)
        var eocdOffset: Int?
        var index = data.count - 22
        while index >= searchStart {
            if data.uint32(at: index) == eocdSignature { eocdOffset = index; break }
            index -= 1
        }
        guard let eocd = eocdOffset else { throw ZipError.notAZip }

        let entryCount = Int(data.uint16(at: eocd + 10))
        let directoryOffset = Int(data.uint32(at: eocd + 16))
        guard directoryOffset < data.count else { throw ZipError.corrupted("directory offset") }

        var entries: [String: Entry] = [:]
        entries.reserveCapacity(entryCount)
        var cursor = directoryOffset
        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count, data.uint32(at: cursor) == 0x0201_4b50 else {
                throw ZipError.corrupted("central directory")
            }
            let method = data.uint16(at: cursor + 10)
            let compressed = Int(data.uint32(at: cursor + 20))
            let uncompressed = Int(data.uint32(at: cursor + 24))
            let nameLength = Int(data.uint16(at: cursor + 28))
            let extraLength = Int(data.uint16(at: cursor + 30))
            let commentLength = Int(data.uint16(at: cursor + 32))
            let localOffset = Int(data.uint32(at: cursor + 42))
            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else { throw ZipError.corrupted("entry name") }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            if !name.hasSuffix("/") {
                entries[name] = Entry(path: name, method: method, compressedSize: compressed,
                                      uncompressedSize: uncompressed, localHeaderOffset: localOffset)
            }
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    private func extract(_ entry: Entry) throws -> Data {
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count, data.uint32(at: header) == 0x0403_4b50 else {
            throw ZipError.corrupted("local header")
        }
        let nameLength = Int(data.uint16(at: header + 26))
        let extraLength = Int(data.uint16(at: header + 28))
        let start = header + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard end <= data.count else { throw ZipError.corrupted("entry bounds") }
        let payload = data.subdata(in: start..<end)

        switch entry.method {
        case 0:
            return payload
        case 8:
            return try Self.inflate(payload, expectedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedCompression(entry.method)
        }
    }

    /// Raw DEFLATE (RFC 1951) — exactly what `COMPRESSION_ZLIB` decodes.
    private static func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        if expectedSize == 0 { return Data() }
        var capacity = max(expectedSize, input.count * 4)
        for _ in 0..<4 {
            var output = Data(count: capacity)
            let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
                input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                    guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress,
                          let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(dstBase, capacity, srcBase, input.count, nil, COMPRESSION_ZLIB)
                }
            }
            if written == 0 { throw ZipError.corrupted("inflate") }
            if written < capacity || written == expectedSize {
                output.count = written
                return output
            }
            capacity *= 2
        }
        throw ZipError.corrupted("inflate size")
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16 {
        let i = startIndex + offset
        return UInt16(self[i]) | (UInt16(self[i + 1]) << 8)
    }

    func uint32(at offset: Int) -> UInt32 {
        let i = startIndex + offset
        return UInt32(self[i]) | (UInt32(self[i + 1]) << 8) | (UInt32(self[i + 2]) << 16) | (UInt32(self[i + 3]) << 24)
    }
}
