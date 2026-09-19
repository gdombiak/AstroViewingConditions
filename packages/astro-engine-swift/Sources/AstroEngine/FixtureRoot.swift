import Foundation

public enum FixtureRootError: Error, Equatable, Sendable {
    case fixturesDirectoryMissing(String)
    case fixtureMissing(String)
    case refEscape(String)

    public var message: String {
        switch self {
        case .fixturesDirectoryMissing(let path):
            return "contracts/fixtures is missing at \(path)"
        case .fixtureMissing(let relativePath):
            return "missing contract fixture: \(relativePath)"
        case .refEscape(let relativePath):
            return "fixture path escapes contracts/fixtures: \(relativePath)"
        }
    }
}

/// Resolves language-neutral files under `contracts/fixtures`.
///
/// This is test/eval path discovery only. Production iOS/watch runtime must not
/// call it and does not require the fixture tree to be present in the bundle.
public enum FixtureRoot {
    public static func directory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        startingAt start: URL = URL(fileURLWithPath: #filePath)
    ) throws -> URL {
        let contracts = try ContractsRoot.resolve(environment: environment, startingAt: start)
        let fixtures = contracts.appendingPathComponent("fixtures", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: fixtures.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw FixtureRootError.fixturesDirectoryMissing(fixtures.path)
        }
        return fixtures.resolvingSymlinksInPath()
    }

    public static func url(
        _ relativePath: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        startingAt start: URL = URL(fileURLWithPath: #filePath)
    ) throws -> URL {
        let fixtures = try directory(environment: environment, startingAt: start)
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard
            !relativePath.isEmpty,
            !relativePath.hasPrefix("/"),
            !relativePath.contains("\\"),
            components.allSatisfy({ $0 != ".." && $0 != "." && !$0.isEmpty })
        else {
            throw FixtureRootError.refEscape(relativePath)
        }

        var candidate = fixtures
        for component in components {
            candidate.appendPathComponent(component)
        }

        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard isInside(resolved, root: fixtures) else {
            throw FixtureRootError.refEscape(relativePath)
        }
        guard FileManager.default.isReadableFile(atPath: resolved.path) else {
            throw FixtureRootError.fixtureMissing(relativePath)
        }
        return resolved
    }

    private static func isInside(_ url: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        if urlPath == rootPath {
            return true
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return urlPath.hasPrefix(prefix)
    }
}
