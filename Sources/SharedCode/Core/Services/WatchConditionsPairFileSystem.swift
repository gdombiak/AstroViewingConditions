import Foundation

/// Minimal filesystem seam for watch conditions/OQ pair transactions (testable).
public protocol WatchConditionsPairFileSystem: Sendable {
    func fileExists(atPath path: String) -> Bool
    func readData(atPath path: String) throws -> Data
    func writeData(_ data: Data, toPath path: String, options: Data.WritingOptions) throws
    func removeItem(atPath path: String) throws
}

/// Production `FileManager` adapter.
public struct FoundationWatchConditionsPairFileSystem: WatchConditionsPairFileSystem {
    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func readData(atPath path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    public func writeData(_ data: Data, toPath path: String, options: Data.WritingOptions) throws {
        try data.write(to: URL(fileURLWithPath: path), options: options)
    }

    public func removeItem(atPath path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }
}
