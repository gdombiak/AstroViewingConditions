@testable import SharedCode
import Foundation

/// Temporary F3 test infrastructure for observing-quality contract fixtures.
///
/// Not the Phase 10 generic parity runner. Mirrors the F2 Python helper: it only
/// understands the two OQ policy IDs and the comparators those policies use.
/// Field names and comparator ids are read from `contracts/equality-policy.yaml`
/// so a tolerance/name change there fails these tests instead of drifting silently.
enum F3ObservingQualityContractSupport {
    static let capabilityID = "observing_quality.assess"
    static let maxAncestorWalk = 16
    static let fixtureDirectory = "fixtures/capabilities/observing-quality"
    static let calibrationRelativePath = "data/calibration/observing-quality.json"

    private static let oqPolicyIDs: Set<String> = ["observing_quality", "observing_quality_anchor"]
    private static let absTolerances: [String: Double] = [
        "abs_1e9": 1e-9,
        "abs_1e12": 1e-12,
        "abs_1e4": 1e-4,
    ]

    struct Fixture {
        let id: String
        let directory: URL
        let capability: String
        let engineSemverRange: String
        let equality: String
        let origin: String
        let hosts: [String]
        let input: [String: Any]
        let expected: [String: Any]
    }

    struct Error: Swift.Error, CustomStringConvertible {
        let message: String
        var description: String { message }
        var localizedDescription: String { message }
    }

    // MARK: - contracts/ discovery

    /// Resolve `contracts/` using the F1/F2 model: `CONTRACTS_ROOT` if set, else ancestor walk.
    static func contractsDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        startingAt start: URL = URL(fileURLWithPath: #filePath)
    ) throws -> URL {
        if let env = environment["CONTRACTS_ROOT"], !env.isEmpty {
            let url = URL(fileURLWithPath: env, isDirectory: true)
            try requireEngineVersion(at: url)
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
        throw Error(message: "could not find contracts/ENGINE_VERSION")
    }

    static func engineSemver(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        startingAt start: URL = URL(fileURLWithPath: #filePath)
    ) throws -> String {
        let root = try contractsDirectory(environment: environment, startingAt: start)
        let text = try String(
            contentsOf: root.appendingPathComponent("ENGINE_VERSION"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            throw Error(message: "ENGINE_VERSION is empty")
        }
        return text
    }

    private static func requireEngineVersion(at url: URL) throws {
        let marker = url.appendingPathComponent("ENGINE_VERSION")
        guard FileManager.default.isReadableFile(atPath: marker.path) else {
            throw Error(message: "CONTRACTS_ROOT=\(url.path) does not contain ENGINE_VERSION")
        }
    }

    // MARK: - Fixtures

    static func loadAllFixtures(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        startingAt start: URL = URL(fileURLWithPath: #filePath)
    ) throws -> [Fixture] {
        let root = try contractsDirectory(environment: environment, startingAt: start)
            .appendingPathComponent(fixtureDirectory, isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw Error(message: "missing OQ fixture directory: \(root.path)")
        }
        let entries = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let directories = entries.filter { url in
            ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try directories.map(loadFixture)
    }

    static func loadFixture(_ directory: URL) throws -> Fixture {
        let metaURL = directory.appendingPathComponent("meta.yaml")
        let inputURL = directory.appendingPathComponent("input.json")
        let expectedURL = directory.appendingPathComponent("expected.json")
        for url in [metaURL, inputURL, expectedURL] {
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw Error(message: "fixture missing \(url.lastPathComponent) in \(directory.path)")
            }
        }

        let meta = parseSimpleMeta(try String(contentsOf: metaURL, encoding: .utf8))
        let input = try loadJSONObject(inputURL)
        let expected = try loadJSONObject(expectedURL)
        return Fixture(
            id: directory.lastPathComponent,
            directory: directory,
            capability: try metaString(meta, "capability"),
            engineSemverRange: try metaString(meta, "engine_semver"),
            equality: try metaString(meta, "equality"),
            origin: try metaString(meta, "origin"),
            hosts: try metaStringList(meta, "hosts"),
            input: input,
            expected: expected
        )
    }

    static func loadJSONObject(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let object = asObject(raw) else {
            throw Error(message: "expected JSON object in \(url.path)")
        }
        return object
    }

    // MARK: - YAML (intentionally tiny; F3 only)

    enum YAMLValue: Equatable {
        case string(String)
        case strings([String])
    }

    /// Indentation-based subset matching the F2 Python helper. Not a YAML library.
    static func parseSimpleMeta(_ text: String) -> [String: YAMLValue] {
        var result: [String: YAMLValue] = [:]
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < lines.count {
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }
            guard let colon = raw.firstIndex(of: ":") else {
                index += 1
                continue
            }
            let key = raw[..<colon].trimmingCharacters(in: .whitespaces)
            let rest = raw[raw.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if rest == ">" {
                var block: [String] = []
                index += 1
                while index < lines.count {
                    let line = lines[index]
                    if line.hasPrefix("  ") || line.hasPrefix("\t") || line.isEmpty {
                        let part = line.trimmingCharacters(in: .whitespaces)
                        if !part.isEmpty {
                            block.append(part)
                        }
                        index += 1
                    } else {
                        break
                    }
                }
                result[key] = .string(block.joined(separator: " "))
                continue
            }
            if rest.hasPrefix("["), rest.hasSuffix("]") {
                let inner = rest.dropFirst().dropLast()
                let items = inner.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }.filter { !$0.isEmpty }
                result[key] = .strings(items)
            } else if rest.count >= 2,
                      let first = rest.first,
                      first == rest.last,
                      first == "\"" || first == "'" {
                result[key] = .string(String(rest.dropFirst().dropLast()))
            } else {
                result[key] = .string(rest)
            }
            index += 1
        }
        return result
    }

    static func loadPolicyFields(
        _ policyID: String,
        contractsRoot: URL
    ) throws -> [String: String] {
        let header = "  \(policyID):"
        let text = try String(
            contentsOf: contractsRoot.appendingPathComponent("equality-policy.yaml"),
            encoding: .utf8
        )
        var inPolicy = false
        var inFields = false
        var fields: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("  "), !line.hasPrefix("    "), line.rstrip().hasSuffix(":") {
                inPolicy = line.rstrip() == header
                inFields = false
                continue
            }
            if inPolicy, line.trimmingCharacters(in: .whitespaces) == "fields:" {
                inFields = true
                continue
            }
            if inFields {
                let strippedLine = line.trimmingCharacters(in: .whitespaces)
                if strippedLine.hasPrefix("#") {
                    continue
                }
                if !line.hasPrefix("      ") {
                    break
                }
                let stripped = strippedLine.split(separator: "#", maxSplits: 1).first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if stripped.isEmpty || !stripped.contains(":") {
                    continue
                }
                let parts = stripped.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                fields[parts[0].trimmingCharacters(in: .whitespaces)] =
                    parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        if fields.isEmpty {
            throw Error(message: "no fields found for policy '\(policyID)' in equality-policy.yaml")
        }
        return fields
    }

    // MARK: - Semver (F1/F2 model)

    static func parseSemver(_ version: String) throws -> (Int, Int, Int) {
        let text = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ $0.allSatisfy(\.isNumber) && !$0.isEmpty }) else {
            throw Error(message: "unsupported version '\(version)'; expected X.Y.Z")
        }
        return (Int(parts[0])!, Int(parts[1])!, Int(parts[2])!)
    }

    static func satisfies(_ version: String, range rangeExpr: String) throws -> Bool {
        let actual = try parseSemver(version)
        let tokens = rangeExpr.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        if tokens.isEmpty {
            throw Error(message: "empty version range")
        }
        for token in tokens {
            if token.hasPrefix(">=") {
                if compareSemver(actual, try parseSemver(String(token.dropFirst(2)))) == .orderedAscending {
                    return false
                }
            } else if token.hasPrefix("<=") {
                if compareSemver(actual, try parseSemver(String(token.dropFirst(2)))) == .orderedDescending {
                    return false
                }
            } else if token.hasPrefix("==") {
                if compareSemver(actual, try parseSemver(String(token.dropFirst(2)))) != .orderedSame {
                    return false
                }
            } else if token.hasPrefix(">") {
                if compareSemver(actual, try parseSemver(String(token.dropFirst()))) != .orderedDescending {
                    return false
                }
            } else if token.hasPrefix("<") {
                if compareSemver(actual, try parseSemver(String(token.dropFirst()))) != .orderedAscending {
                    return false
                }
            } else {
                throw Error(message: "unsupported range token '\(token)'")
            }
        }
        return true
    }

    private static func compareSemver(
        _ lhs: (Int, Int, Int),
        _ rhs: (Int, Int, Int)
    ) -> ComparisonResult {
        if lhs.0 != rhs.0 { return lhs.0 < rhs.0 ? .orderedAscending : .orderedDescending }
        if lhs.1 != rhs.1 { return lhs.1 < rhs.1 ? .orderedAscending : .orderedDescending }
        if lhs.2 != rhs.2 { return lhs.2 < rhs.2 ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }

    // MARK: - Swift result → contract DTO

    static func contractResult(from assessment: ObservingQualityAssessment) -> [String: Any] {
        var result: [String: Any] = [
            "score": assessment.score,
            "night_conditions_score": assessment.nightConditionsScore,
        ]
        if let lightPollution = assessment.lightPollution {
            result["light_pollution"] = [
                "modeled_zenith_sky_brightness": lightPollution.modeledZenithSkyBrightness,
                "base_penalty": lightPollution.basePenalty,
                "applied_penalty": lightPollution.appliedPenalty,
            ]
        } else {
            result["light_pollution"] = NSNull()
        }
        return result
    }

    static func injectedInputs(from fixture: Fixture) throws -> (night: Int, brightness: Double?) {
        guard let injected = asObject(fixture.input["injected"]) else {
            throw Error(message: "\(fixture.id): input.json missing injected object")
        }
        guard let night = jsonInt(injected["night_conditions_score"]) else {
            throw Error(message: "\(fixture.id): night_conditions_score must be an integral JSON number")
        }
        if injected["modeled_zenith_sky_brightness"] == nil || isNull(injected["modeled_zenith_sky_brightness"]) {
            return (night, nil)
        }
        guard let brightness = jsonDouble(injected["modeled_zenith_sky_brightness"]) else {
            throw Error(
                message: "\(fixture.id): modeled_zenith_sky_brightness must be a finite JSON number or null"
            )
        }
        return (night, brightness)
    }

    // MARK: - Equality

    static func compareObservingQualityResult(
        _ actual: [String: Any],
        expected: [String: Any],
        policyID: String,
        contractsRoot: URL,
        path: String = ""
    ) throws {
        guard oqPolicyIDs.contains(policyID) else {
            throw Error(
                message: "F3 helper only implements \(oqPolicyIDs.sorted()), not '\(policyID)'"
            )
        }
        let fields = try loadPolicyFields(policyID, contractsRoot: contractsRoot)
        try compareObject(actual, expected: expected, fields: fields, pathPrefix: path)
    }

    private static func compareObject(
        _ actual: [String: Any],
        expected: [String: Any],
        fields: [String: String],
        pathPrefix: String
    ) throws {
        let extra = Set(actual.keys).subtracting(expected.keys)
        let missing = Set(expected.keys).subtracting(actual.keys)
        if !extra.isEmpty {
            throw Error(message: "\(pathLabel(pathPrefix)): extra result keys: \(extra.sorted())")
        }
        if !missing.isEmpty {
            throw Error(message: "\(pathLabel(pathPrefix)): missing result keys: \(missing.sorted())")
        }
        for (key, expectedValue) in expected {
            let fieldPath = pathPrefix.isEmpty ? key : "\(pathPrefix).\(key)"
            let spec = fields[fieldPath] ?? "exact"
            try compareSpec(
                actual[key],
                expected: expectedValue,
                spec: spec,
                path: fieldPath,
                fields: fields
            )
        }
    }

    private static func compareSpec(
        _ actual: Any?,
        expected: Any,
        spec: String,
        path: String,
        fields: [String: String]
    ) throws {
        if spec == "null_or_object" {
            if isNull(expected) {
                guard isNull(actual) else {
                    throw Error(message: "\(path): expected null")
                }
                return
            }
            guard let expectedObject = asObject(expected), let actualObject = asObject(actual) else {
                throw Error(message: "\(path): expected object")
            }
            try compareObject(actualObject, expected: expectedObject, fields: fields, pathPrefix: path)
            return
        }
        if spec == "exact" {
            if let expectedObject = asObject(expected), let actualObject = asObject(actual) {
                try compareObject(actualObject, expected: expectedObject, fields: fields, pathPrefix: path)
                return
            }
            guard valuesExactlyEqual(actual, expected) else {
                throw Error(message: "\(path): \(stringify(actual)) != \(stringify(expected))")
            }
            return
        }
        if let absTol = absTolerances[spec] {
            guard let actualNumber = jsonDouble(actual), let expectedNumber = jsonDouble(expected) else {
                throw Error(
                    message: "\(path): \(stringify(actual)) not within \(spec) of \(stringify(expected))"
                )
            }
            guard abs(actualNumber - expectedNumber) <= absTol else {
                throw Error(
                    message: "\(path): \(stringify(actual)) not within \(spec) of \(stringify(expected))"
                )
            }
            return
        }
        throw Error(
            message: "F3 OQ test helper does not implement comparator '\(spec)' at \(path); "
                + "the Phase 10 parity runner must read the contract"
        )
    }

    private static func valuesExactlyEqual(_ actual: Any?, _ expected: Any) -> Bool {
        if isNull(actual), isNull(expected) { return true }
        if let actualBool = jsonBool(actual), let expectedBool = jsonBool(expected) {
            return actualBool == expectedBool
        }
        if let actualNumber = jsonDouble(actual), let expectedNumber = jsonDouble(expected) {
            return actualNumber == expectedNumber
        }
        if let actualString = actual as? String, let expectedString = expected as? String {
            return actualString == expectedString
        }
        return false
    }

    // MARK: - JSON helpers

    static func asObject(_ value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            return dict
        }
        if let dict = value as? NSDictionary {
            var result: [String: Any] = [:]
            for (key, item) in dict {
                guard let stringKey = key as? String else { return nil }
                result[stringKey] = item
            }
            return result
        }
        return nil
    }

    static func asArray(_ value: Any?) -> [Any]? {
        if let array = value as? [Any] { return array }
        if let array = value as? NSArray { return array.map { $0 as Any } }
        return nil
    }

    static func isNull(_ value: Any?) -> Bool {
        value == nil || value is NSNull
    }

    static func jsonBool(_ value: Any?) -> Bool? {
        // JSONSerialization uses NSNumber for both booleans and numbers. Check CFBoolean
        // before `as Bool`, which also matches NSNumber(0) / NSNumber(1).
        if let number = value as? NSNumber {
            guard CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() else { return nil }
            return number.boolValue
        }
        return value as? Bool
    }

    static func jsonInt(_ value: Any?) -> Int? {
        guard let number = jsonDouble(value), number.rounded(.towardZero) == number else {
            return nil
        }
        let asInt = Int(number)
        guard Double(asInt) == number else { return nil }
        return asInt
    }

    static func jsonDouble(_ value: Any?) -> Double? {
        if jsonBool(value) != nil { return nil }
        if let number = value as? NSNumber {
            let doubleValue = number.doubleValue
            return doubleValue.isFinite ? doubleValue : nil
        }
        if let number = value as? Double {
            return number.isFinite ? number : nil
        }
        if let number = value as? Int {
            return Double(number)
        }
        return nil
    }

    private static func metaString(_ meta: [String: YAMLValue], _ key: String) throws -> String {
        switch meta[key] {
        case .string(let value) where !value.isEmpty:
            return value
        default:
            throw Error(message: "meta.yaml missing string field '\(key)'")
        }
    }

    private static func metaStringList(_ meta: [String: YAMLValue], _ key: String) throws -> [String] {
        switch meta[key] {
        case .strings(let value) where !value.isEmpty:
            return value
        case .string(let value) where !value.isEmpty:
            return [value]
        default:
            throw Error(message: "meta.yaml missing list field '\(key)'")
        }
    }

    private static func pathLabel(_ path: String) -> String {
        path.isEmpty ? "result" : path
    }

    private static func stringify(_ value: Any?) -> String {
        switch value {
        case nil:
            return "nil"
        case is NSNull:
            return "null"
        case let number as NSNumber:
            return number.stringValue
        default:
            return String(describing: value!)
        }
    }
}

private extension String {
    func rstrip() -> String {
        var end = endIndex
        while end > startIndex {
            let previous = index(before: end)
            if self[previous].isWhitespace || self[previous].isNewline {
                end = previous
            } else {
                break
            }
        }
        return String(self[..<end])
    }
}
