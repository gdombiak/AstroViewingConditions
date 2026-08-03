import Foundation

/// Runtime decoder for the LPATLAS1 hierarchical light-pollution artifact.
///
/// Initialization validates magic, version, header geometry/quantization invariants, and
/// every root-index entry (safe `Int` ranges). Each root blob is then structurally validated
/// (full DFS walk) so truncated/malformed node payloads fail **at init**, not as silent NoData.
///
/// Lookup is O(depth) within one root blob and does not materialize a full global raster.
/// Not yet wired into observing-quality scoring or any UI surface.
///
/// Corruption vs NoData:
/// - Malformed header/index/node structure → `init` throws.
/// - Legitimate geographic unavailability / NoData tags → `modeledZenithSkyBrightness` returns `nil`.
public final class BinaryLightPollutionProvider: LightPollutionProviding, @unchecked Sendable {
    public enum Error: Swift.Error, Equatable {
        case truncated
        case badMagic
        case unsupportedVersion(UInt16)
        case invalidHeader
        case invalidRootIndex
        case invalidNode
    }

    private static let magic = Data("LPATLAS1".utf8)
    private static let version: UInt16 = 1
    private static let headerSize = 128
    private static let rootIndexEntrySize = 12
    private static let maxValidQuantCode: UInt8 = 254

    private static let tagAllNodata: UInt8 = 0
    private static let tagDefault: UInt8 = 1
    private static let tagDefaultMask: UInt8 = 2
    private static let tagConstant: UInt8 = 3
    private static let tagConstantMask: UInt8 = 4
    private static let tagCoarse: UInt8 = 5
    private static let tagCoarseMask: UInt8 = 6
    private static let tagChildren: UInt8 = 7

    private struct RootRange: Sendable {
        let offset: Int
        let length: Int
    }

    private let data: Data
    private let header: Header
    private let rootRanges: [RootRange]
    private let lock = NSLock()
    private var blobCache: [Int: Data] = [:]

    public struct Header: Sendable, Equatable {
        public let version: UInt16
        public let rootCells: UInt16
        public let finestCells: UInt16
        public let width: UInt32
        public let height: UInt32
        public let originLon: Double
        public let originLat: Double
        public let pixelSize: Double
        public let qMMin: Float
        public let qMMax: Float
        public let pristineDefault: Float
        public let errorBudget: Double
        public let nRootCols: UInt16
        public let nRootRows: UInt16
        public let rootIndexOffset: UInt32
        public let rootDataOffset: UInt32
        public let fileSize: UInt32

        public var nRoots: Int {
            // Validated at init: product fits in Int.
            Int(nRootCols) * Int(nRootRows)
        }

        public var quantStep: Double {
            Double(qMMax - qMMin) / 254.0
        }
    }

    public var artifactHeader: Header { header }

    public convenience init(fileURL: URL) throws {
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        try self.init(data: data)
    }

    public init(data: Data) throws {
        self.header = try Self.parseAndValidateHeader(data: data)
        self.rootRanges = try Self.validateRootIndex(data: data, header: header)
        try Self.validateAllRootBlobStructures(
            data: data,
            header: header,
            ranges: rootRanges
        )
        self.data = data
    }

    public func modeledZenithSkyBrightness(latitude: Double, longitude: Double) -> Double? {
        guard latitude.isFinite, longitude.isFinite else { return nil }
        guard let (col, row) = Self.lonLatToCell(
            lon: longitude,
            lat: latitude,
            header: header
        ) else {
            return nil
        }
        let rc = Int(header.rootCells)
        let rootI = col / rc
        let rootJ = row / rc
        let localC = col - rootI * rc
        let localR = row - rootJ * rc
        guard let blob = rootBlob(rootI: rootI, rootJ: rootJ) else {
            // Ranges were validated at init; out-of-range root is geographic/logic failure → nil.
            return nil
        }
        // Node structure already validated at init; walk is trusted for well-formed trees.
        // Any unexpected residual parse failure fails closed to nil (not pristine).
        return try? Self.lookup(
            blob: blob,
            localR: localR,
            localC: localC,
            rootH: rc,
            rootW: rc,
            header: header
        )
    }

    // MARK: - Header

    private static func parseAndValidateHeader(data: Data) throws -> Header {
        guard data.count >= headerSize else { throw Error.truncated }
        guard data.prefix(8) == magic else { throw Error.badMagic }

        let version: UInt16 = readU16(data, 8)
        guard version == Self.version else { throw Error.unsupportedVersion(version) }

        let rootCells: UInt16 = readU16(data, 12)
        let finestCells: UInt16 = readU16(data, 14)
        let width: UInt32 = readU32(data, 16)
        let height: UInt32 = readU32(data, 20)
        let originLon: Double = readF64(data, 24)
        let originLat: Double = readF64(data, 32)
        let pixelSize: Double = readF64(data, 40)
        let qMin: Float = readF32(data, 48)
        let qMax: Float = readF32(data, 52)
        let pristine: Float = readF32(data, 56)
        let errMilli: UInt16 = readU16(data, 60)
        let nCols: UInt16 = readU16(data, 62)
        let nRows: UInt16 = readU16(data, 64)
        let headerSizeField: UInt16 = readU16(data, 66)
        let rootIndexOffset: UInt32 = readU32(data, 68)
        let rootDataOffset: UInt32 = readU32(data, 72)
        let fileSize: UInt32 = readU32(data, 76)

        guard headerSizeField == UInt16(headerSize) else { throw Error.invalidHeader }

        // Geometry / counts
        guard rootCells > 0 else { throw Error.invalidHeader }
        guard finestCells > 0, finestCells <= rootCells else { throw Error.invalidHeader }
        guard width > 0, height > 0 else { throw Error.invalidHeader }
        guard nCols > 0, nRows > 0 else { throw Error.invalidHeader }

        // Finite spatial / quant metadata
        guard originLon.isFinite, originLat.isFinite, pixelSize.isFinite else {
            throw Error.invalidHeader
        }
        guard pixelSize > 0 else { throw Error.invalidHeader }
        guard qMin.isFinite, qMax.isFinite, pristine.isFinite else { throw Error.invalidHeader }
        guard qMax > qMin else { throw Error.invalidHeader }

        // pristineDefault must lie in the supported quantization range (inclusive).
        guard pristine >= qMin, pristine <= qMax else { throw Error.invalidHeader }

        let quantStep = Double(qMax - qMin) / 254.0
        guard quantStep.isFinite, quantStep > 0 else { throw Error.invalidHeader }

        // Root grid must cover the raster with ceil division.
        let expectedCols = ceilDiv(UInt64(width), UInt64(rootCells))
        let expectedRows = ceilDiv(UInt64(height), UInt64(rootCells))
        guard expectedCols == UInt64(nCols), expectedRows == UInt64(nRows) else {
            throw Error.invalidHeader
        }

        // nRoots product must fit in Int without overflow.
        let nRootsU = UInt64(nCols) * UInt64(nRows)
        guard nRootsU > 0, nRootsU <= UInt64(Int.max) else { throw Error.invalidHeader }
        let nRoots = Int(nRootsU)

        // Offsets
        guard rootIndexOffset >= UInt32(headerSize) else { throw Error.invalidHeader }

        let indexByteCountU = UInt64(nRoots) * UInt64(rootIndexEntrySize)
        guard indexByteCountU <= UInt64(UInt32.max) else { throw Error.invalidHeader }
        let indexEndU = UInt64(rootIndexOffset) + indexByteCountU
        guard indexEndU <= UInt64(UInt32.max) else { throw Error.invalidHeader }

        guard UInt64(rootDataOffset) >= indexEndU else { throw Error.invalidHeader }

        // v1: declared fileSize must equal actual Data count.
        guard UInt64(fileSize) == UInt64(data.count) else { throw Error.invalidHeader }
        guard fileSize >= rootDataOffset else { throw Error.invalidHeader }
        guard UInt64(rootDataOffset) <= UInt64(data.count) else { throw Error.invalidHeader }

        // Index must fully fit before root data and within file.
        guard indexEndU <= UInt64(fileSize) else { throw Error.invalidHeader }

        return Header(
            version: version,
            rootCells: rootCells,
            finestCells: finestCells,
            width: width,
            height: height,
            originLon: originLon,
            originLat: originLat,
            pixelSize: pixelSize,
            qMMin: qMin,
            qMMax: qMax,
            pristineDefault: pristine,
            errorBudget: Double(errMilli) / 1000.0,
            nRootCols: nCols,
            nRootRows: nRows,
            rootIndexOffset: rootIndexOffset,
            rootDataOffset: rootDataOffset,
            fileSize: fileSize
        )
    }

    private static func ceilDiv(_ num: UInt64, _ den: UInt64) -> UInt64 {
        precondition(den > 0)
        return (num + den - 1) / den
    }

    // MARK: - Root index

    private static func validateRootIndex(data: Data, header: Header) throws -> [RootRange] {
        let nRoots = header.nRoots
        var ranges: [RootRange] = []
        ranges.reserveCapacity(nRoots)

        let fileSize = Int(header.fileSize)
        let rootDataOffset = Int(header.rootDataOffset)
        let indexBase = Int(header.rootIndexOffset)

        for i in 0..<nRoots {
            let entryOffset = indexBase + i * rootIndexEntrySize
            // entryOffset + 12 already bounded by header validation against fileSize.
            guard entryOffset >= 0, entryOffset + rootIndexEntrySize <= data.count else {
                throw Error.invalidRootIndex
            }

            let blobOffU = readU64(data, entryOffset)
            let blobLenU = UInt64(readU32(data, entryOffset + 8))

            // Safe conversion to Int (no trapping Int(UInt64)).
            guard blobOffU <= UInt64(Int.max) else { throw Error.invalidRootIndex }
            guard blobLenU <= UInt64(Int.max) else { throw Error.invalidRootIndex }
            let blobOff = Int(blobOffU)
            let blobLen = Int(blobLenU)

            // v1: every root has a non-empty blob (at least one tag byte).
            guard blobLen > 0 else { throw Error.invalidRootIndex }
            guard blobOff >= rootDataOffset else { throw Error.invalidRootIndex }

            // offset + length without overflow, within file.
            guard blobLen <= fileSize - blobOff else { throw Error.invalidRootIndex }
            let end = blobOff + blobLen
            guard end <= fileSize, end <= data.count else { throw Error.invalidRootIndex }

            // Must not point into header or root index.
            guard blobOff >= rootDataOffset else { throw Error.invalidRootIndex }

            ranges.append(RootRange(offset: blobOff, length: blobLen))
        }
        return ranges
    }

    /// Eager structural validation of every root blob (approach A).
    private static func validateAllRootBlobStructures(
        data: Data,
        header: Header,
        ranges: [RootRange]
    ) throws {
        let rc = Int(header.rootCells)
        for range in ranges {
            let end = range.offset + range.length
            guard range.offset >= 0, end <= data.count else { throw Error.invalidRootIndex }
            let blob = data.subdata(in: range.offset..<end)
            try validateTreeStructure(blob: blob, rootH: rc, rootW: rc)
        }
    }

    /// Walks a DFS node tree and requires exact blob consumption.
    private static func validateTreeStructure(blob: Data, rootH: Int, rootW: Int) throws {
        var pos = 0

        func readU8() throws -> UInt8 {
            guard pos < blob.count else { throw Error.invalidNode }
            let v = blob[pos]
            pos += 1
            return v
        }
        func readU16() throws -> UInt16 {
            guard pos + 2 <= blob.count else { throw Error.invalidNode }
            let v = UInt16(blob[pos]) | (UInt16(blob[pos + 1]) << 8)
            pos += 2
            return v
        }
        func skipBytes(_ n: Int) throws {
            guard n >= 0, pos + n <= blob.count else { throw Error.invalidNode }
            pos += n
        }

        func walk(h: Int, w: Int) throws {
            guard h > 0, w > 0 else { throw Error.invalidNode }
            let tag = try readU8()
            switch tag {
            case tagAllNodata, tagDefault:
                return
            case tagDefaultMask:
                try skipBytes(maskLen(h: h, w: w))
            case tagConstant:
                _ = try readU8()
            case tagConstantMask:
                _ = try readU8()
                try skipBytes(maskLen(h: h, w: w))
            case tagCoarse, tagCoarseMask:
                let factor = Int(try readU16())
                guard factor >= 1 else { throw Error.invalidNode }
                let (gh, gw) = coarseShape(h: h, w: w, factor: factor)
                let n = gh * gw
                guard n > 0, n <= blob.count else { throw Error.invalidNode }
                try skipBytes(n)
                if tag == tagCoarseMask {
                    try skipBytes(maskLen(h: h, w: w))
                }
            case tagChildren:
                let mh = h / 2
                let mw = w / 2
                let dims = [
                    (mh, mw),
                    (mh, w - mw),
                    (h - mh, mw),
                    (h - mh, w - mw),
                ]
                for (qh, qw) in dims {
                    if qh > 0 && qw > 0 {
                        try walk(h: qh, w: qw)
                    }
                }
            default:
                throw Error.invalidNode
            }
        }

        try walk(h: rootH, w: rootW)
        // Exact consumption: no trailing garbage, no shortfall.
        guard pos == blob.count else { throw Error.invalidNode }
    }

    // MARK: - Roots

    private func rootBlob(rootI: Int, rootJ: Int) -> Data? {
        let h = header
        guard rootI >= 0, rootI < Int(h.nRootCols), rootJ >= 0, rootJ < Int(h.nRootRows) else {
            return nil
        }
        let idx = rootJ * Int(h.nRootCols) + rootI
        guard idx >= 0, idx < rootRanges.count else { return nil }

        lock.lock()
        if let cached = blobCache[idx] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let range = rootRanges[idx]
        let end = range.offset + range.length
        guard range.offset >= 0, end <= data.count else { return nil }
        let slice = data.subdata(in: range.offset..<end)

        lock.lock()
        blobCache[idx] = slice
        lock.unlock()
        return slice
    }

    // MARK: - Geometry

    private static func normalizeLongitude(_ lon: Double) -> Double {
        var x = (lon + 180.0).truncatingRemainder(dividingBy: 360.0)
        if x < 0 { x += 360.0 }
        return x - 180.0
    }

    private static func lonLatToCell(lon: Double, lat: Double, header: Header) -> (Int, Int)? {
        let lonN = normalizeLongitude(lon)
        let col = Int(floor((lonN - header.originLon) / header.pixelSize))
        let row = Int(floor((header.originLat - lat) / header.pixelSize))
        guard col >= 0, col < Int(header.width), row >= 0, row < Int(header.height) else {
            return nil
        }
        return (col, row)
    }

    private static func dequantize(code: UInt8, header: Header) -> Double {
        Double(header.qMMin) + Double(code) * header.quantStep
    }

    private static func quantizePristine(header: Header) -> UInt8 {
        let step = header.quantStep
        let q = ((Double(header.pristineDefault) - Double(header.qMMin)) / step).rounded()
        return UInt8(max(0, min(Int(maxValidQuantCode), Int(q))))
    }

    private static func maskLen(h: Int, w: Int) -> Int {
        (h * w + 7) / 8
    }

    private static func coarseShape(h: Int, w: Int, factor: Int) -> (Int, Int) {
        ((h + factor - 1) / factor, (w + factor - 1) / factor)
    }

    private static func maskIsNodata(mask: Data, h: Int, w: Int, r: Int, c: Int) -> Bool {
        let bitIndex = r * w + c
        let byteIndex = bitIndex / 8
        let bit = 7 - (bitIndex % 8) // packbits MSB first
        guard byteIndex < mask.count else { return true }
        return (mask[byteIndex] & (1 << bit)) != 0
    }

    // MARK: - Tree walk (lookup)

    private static func lookup(
        blob: Data,
        localR: Int,
        localC: Int,
        rootH: Int,
        rootW: Int,
        header: Header
    ) throws -> Double? {
        var pos = 0
        let pristineCode = quantizePristine(header: header)

        func readU8() throws -> UInt8 {
            guard pos < blob.count else { throw Error.invalidNode }
            let v = blob[pos]
            pos += 1
            return v
        }
        func readU16() throws -> UInt16 {
            guard pos + 2 <= blob.count else { throw Error.invalidNode }
            let v = UInt16(blob[pos]) | (UInt16(blob[pos + 1]) << 8)
            pos += 2
            return v
        }
        func readBytes(_ n: Int) throws -> Data {
            guard n >= 0, pos + n <= blob.count else { throw Error.invalidNode }
            let d = blob.subdata(in: pos..<(pos + n))
            pos += n
            return d
        }

        func skipNode(h: Int, w: Int) throws {
            let tag = try readU8()
            switch tag {
            case tagAllNodata, tagDefault:
                return
            case tagDefaultMask:
                _ = try readBytes(maskLen(h: h, w: w))
            case tagConstant:
                _ = try readU8()
            case tagConstantMask:
                _ = try readU8()
                _ = try readBytes(maskLen(h: h, w: w))
            case tagCoarse, tagCoarseMask:
                let factor = Int(try readU16())
                guard factor >= 1 else { throw Error.invalidNode }
                let (gh, gw) = coarseShape(h: h, w: w, factor: factor)
                _ = try readBytes(gh * gw)
                if tag == tagCoarseMask {
                    _ = try readBytes(maskLen(h: h, w: w))
                }
            case tagChildren:
                let mh = h / 2
                let mw = w / 2
                let dims = [(mh, mw), (mh, w - mw), (h - mh, mw), (h - mh, w - mw)]
                for (qh, qw) in dims where qh > 0 && qw > 0 {
                    try skipNode(h: qh, w: qw)
                }
            default:
                throw Error.invalidNode
            }
        }

        func walk(h: Int, w: Int, r: Int, c: Int) throws -> Double? {
            let tag = try readU8()
            switch tag {
            case tagAllNodata:
                return nil
            case tagDefault:
                return dequantize(code: pristineCode, header: header)
            case tagDefaultMask:
                let mask = try readBytes(maskLen(h: h, w: w))
                if maskIsNodata(mask: mask, h: h, w: w, r: r, c: c) { return nil }
                return dequantize(code: pristineCode, header: header)
            case tagConstant:
                let code = try readU8()
                return dequantize(code: code, header: header)
            case tagConstantMask:
                let code = try readU8()
                let mask = try readBytes(maskLen(h: h, w: w))
                if maskIsNodata(mask: mask, h: h, w: w, r: r, c: c) { return nil }
                return dequantize(code: code, header: header)
            case tagCoarse, tagCoarseMask:
                let factor = Int(try readU16())
                guard factor >= 1 else { throw Error.invalidNode }
                let (gh, gw) = coarseShape(h: h, w: w, factor: factor)
                let codes = try readBytes(gh * gw)
                if tag == tagCoarseMask {
                    let mask = try readBytes(maskLen(h: h, w: w))
                    if maskIsNodata(mask: mask, h: h, w: w, r: r, c: c) { return nil }
                }
                let gr = min(r / factor, gh - 1)
                let gc = min(c / factor, gw - 1)
                let code = codes[gr * gw + gc]
                return dequantize(code: code, header: header)
            case tagChildren:
                let mh = h / 2
                let mw = w / 2
                let quads: [(Int, Int, Int, Int)] = [
                    (0, 0, mh, mw),
                    (0, mw, mh, w - mw),
                    (mh, 0, h - mh, mw),
                    (mh, mw, h - mh, w - mw),
                ]
                var target = 0
                for (i, q) in quads.enumerated() {
                    let (qr, qc, qh, qw) = q
                    if r >= qr && r < qr + qh && c >= qc && c < qc + qw {
                        target = i
                        break
                    }
                }
                for (i, q) in quads.enumerated() {
                    let (qr, qc, qh, qw) = q
                    if qh <= 0 || qw <= 0 { continue }
                    if i == target {
                        return try walk(h: qh, w: qw, r: r - qr, c: c - qc)
                    }
                    try skipNode(h: qh, w: qw)
                }
                throw Error.invalidNode
            default:
                throw Error.invalidNode
            }
        }

        return try walk(h: rootH, w: rootW, r: localR, c: localC)
    }

    // MARK: - LE readers

    private static func readU16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func readU64(_ data: Data, _ offset: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 {
            v |= UInt64(data[offset + i]) << (8 * i)
        }
        return v
    }

    private static func readF32(_ data: Data, _ offset: Int) -> Float {
        Float(bitPattern: readU32(data, offset))
    }

    private static func readF64(_ data: Data, _ offset: Int) -> Double {
        Double(bitPattern: readU64(data, offset))
    }
}
