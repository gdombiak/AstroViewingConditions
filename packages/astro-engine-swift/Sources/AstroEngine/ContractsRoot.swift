import Foundation

public enum ContractsRootError: Error, Equatable, Sendable {
    case missingENGINEVersion(String)
    case notFound
    case emptyVersion

    public var message: String {
        switch self {
        case .missingENGINEVersion(let path):
            return "CONTRACTS_ROOT=\(path) does not contain ENGINE_VERSION"
        case .notFound:
            return "could not find contracts/ENGINE_VERSION"
        case .emptyVersion:
            return "ENGINE_VERSION is empty"
        }
    }
}

public enum ContractsRoot {
    public static let maxAncestorWalk = 16

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        startingAt start: URL = URL(fileURLWithPath: #filePath)
    ) throws -> URL {
        if let env = environment["CONTRACTS_ROOT"], !env.isEmpty {
            let url = URL(fileURLWithPath: env, isDirectory: true)
            let marker = url.appendingPathComponent("ENGINE_VERSION")
            guard FileManager.default.isReadableFile(atPath: marker.path) else {
                throw ContractsRootError.missingENGINEVersion(env)
            }
            return url.resolvingSymlinksInPath()
        }

        var dir = start
        if !dir.hasDirectoryPath {
            dir.deleteLastPathComponent()
        }
        for _ in 0..<maxAncestorWalk {
            let candidate = dir.appendingPathComponent("contracts", isDirectory: true)
            if FileManager.default.isReadableFile(
                atPath: candidate.appendingPathComponent("ENGINE_VERSION").path
            ) {
                return candidate.resolvingSymlinksInPath()
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path {
                break
            }
            dir = parent
        }
        throw ContractsRootError.notFound
    }

    public static func engineSemver(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        startingAt start: URL = URL(fileURLWithPath: #filePath)
    ) throws -> String {
        let root = try resolve(environment: environment, startingAt: start)
        let text = try String(
            contentsOf: root.appendingPathComponent("ENGINE_VERSION"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            throw ContractsRootError.emptyVersion
        }
        return text
    }
}
