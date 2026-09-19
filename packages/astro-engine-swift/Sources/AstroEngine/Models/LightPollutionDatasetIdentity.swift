import Foundation

/// Logical identity of the light-pollution dataset used for cache validity and transport.
///
/// This is the **application-facing** contract for “is this sample still current?”
/// Packaging verification (byte count, SHA-256) stays on `BundledLightPollutionResource`
/// and is **not** the primary persisted version key.
///
/// Release procedure:
/// - New atlas/model content that should refresh derived samples → increment `datasetRevision`.
/// - Binary layout incompatibility (LPATLAS format break) → increment `formatVersion` as appropriate.
/// - Cached samples whose logical identity does not match `LightPollutionDatasetIdentity.current` are stale.
public struct LightPollutionDatasetIdentity: Codable, Sendable, Equatable, Hashable {
    /// Logical atlas family id (e.g. `"lpatlas1"`).
    public let datasetID: String
    /// Content/model revision for this family. Bump when derived brightness must be refreshed.
    public let datasetRevision: Int
    /// On-disk/binary format version (LPATLAS1 header version is currently `1`).
    public let formatVersion: Int

    public init(datasetID: String, datasetRevision: Int, formatVersion: Int) {
        self.datasetID = datasetID
        self.datasetRevision = datasetRevision
        self.formatVersion = formatVersion
    }

    /// Identity of the currently shipped production packaging.
    public static let current = LightPollutionDatasetIdentity(
        datasetID: "lpatlas1",
        datasetRevision: 1,
        formatVersion: 1
    )

    /// True when `other` may be used interchangeably with this identity for cache purposes.
    public func isCompatible(with other: LightPollutionDatasetIdentity) -> Bool {
        datasetID == other.datasetID
            && datasetRevision == other.datasetRevision
            && formatVersion == other.formatVersion
    }
}
