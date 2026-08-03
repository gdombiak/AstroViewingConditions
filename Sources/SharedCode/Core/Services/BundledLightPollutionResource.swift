import Foundation
import CryptoKit

/// Locates and loads the production LPATLAS1 artifact from an app resource bundle.
///
/// Canonical bundled path (main iOS app target only):
/// `Sources/AstroViewingConditions/Resources/LightPollution/light_pollution_global_v1.bin`
///
/// Not embedded in widget/watch targets in this phase.
public enum BundledLightPollutionResource: Sendable {
    public static let resourceName = "light_pollution_global_v1"
    public static let resourceExtension = "bin"
    public static let subdirectory = "LightPollution"

    /// Expected production artifact size (bytes).
    public static let expectedByteCount = 10_328_230

    /// Expected SHA-256 of the production LPATLAS1 v1 artifact (lowercase hex).
    public static let expectedSHA256 =
        "b9c60e83d866f28e781dcc89a4ad302597012cdb9df6c94743efdd44be86dce4"

    public enum Error: Swift.Error, Equatable, LocalizedError {
        case resourceNotFound
        case unexpectedSize(actual: Int)
        case unexpectedChecksum(actual: String)
        case providerInitFailed(String)

        public var errorDescription: String? {
            switch self {
            case .resourceNotFound:
                return "Bundled light-pollution artifact not found"
            case .unexpectedSize(let actual):
                return "Unexpected light-pollution artifact size \(actual)"
            case .unexpectedChecksum(let actual):
                return "Unexpected light-pollution artifact checksum \(actual)"
            case .providerInitFailed(let message):
                return "Light-pollution provider failed: \(message)"
            }
        }
    }

    /// Resolve the resource URL, checking preferred bundles then `Bundle.main` and all loaded bundles.
    public static func resourceURL(in preferredBundles: [Bundle] = []) -> URL? {
        var seen = Set<ObjectIdentifier>()
        var bundles: [Bundle] = []
        for b in preferredBundles + [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks {
            let id = ObjectIdentifier(b)
            if seen.insert(id).inserted {
                bundles.append(b)
            }
        }
        for bundle in bundles {
            if let url = urlInBundle(bundle) {
                return url
            }
        }
        return nil
    }

    private static func urlInBundle(_ bundle: Bundle) -> URL? {
        if let url = bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: subdirectory
        ) {
            return url
        }
        return bundle.url(forResource: resourceName, withExtension: resourceExtension)
    }

    /// Load and validate a provider from a resolved file URL.
    public static func loadProvider(
        from url: URL,
        verifyChecksum: Bool = false
    ) throws -> BinaryLightPollutionProvider {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let size = values.fileSize ?? 0
        guard size == expectedByteCount else {
            throw Error.unexpectedSize(actual: size)
        }
        if verifyChecksum {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            guard hex == expectedSHA256 else {
                throw Error.unexpectedChecksum(actual: hex)
            }
        }
        do {
            return try BinaryLightPollutionProvider(fileURL: url)
        } catch {
            throw Error.providerInitFailed(String(describing: error))
        }
    }

    /// Locate the bundled artifact and construct a provider.
    public static func loadProvider(
        preferredBundles: [Bundle] = [],
        verifyChecksum: Bool = false
    ) throws -> BinaryLightPollutionProvider {
        guard let url = resourceURL(in: preferredBundles) else {
            throw Error.resourceNotFound
        }
        return try loadProvider(from: url, verifyChecksum: verifyChecksum)
    }
}
