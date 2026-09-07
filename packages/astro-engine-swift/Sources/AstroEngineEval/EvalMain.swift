import Foundation
import AstroEngine

private let stdinLimitBytes = 1_048_576
private let exitOK = 0
private let exitEngine = 1
private let exitValidation = 2
private let exitUsage = 3

private let usage = """
usage: astro-engine-eval --engine-version
       astro-engine-eval <capability-id> --input -|FILE [--pretty]
       astro-engine-eval --fixture DIR [--pretty]

Eval allow-list (not the public Python CLI):
  observing_quality.assess
  night_conditions.analyze
  night_conditions.score
  fog.score
  seeing.penalty
  transparency.penalty
  weather.decode
  iss.decode
  location.grid
  location.compare
  catalog.deep_sky
  targets.recommend
  equipment.match
  observing_window.select
  targets.requirements
  catalog.solar_system
  targets.moon_sensitivity
  astronomy.horizontal_position
  targets.deep_sky_windows
  astronomy.sun_events
  astronomy.moon_info
  astronomy.moon_series
  astronomy.moon_observation
  targets.moon_recommendation
  astronomy.planet_observation
  targets.planet_recommendation
  targets.compose_recommendations
  targets.filter_recommendations_by_equipment
  observing_night.resolve_active
  night_forecast.derive_window
"""

private let supportedCapabilities: Set<String> = [
    "observing_quality.assess",
    "night_conditions.analyze",
    "night_conditions.score",
    "fog.score",
    "seeing.penalty",
    "transparency.penalty",
    "weather.decode",
    "iss.decode",
    "location.grid",
    "location.compare",
    "catalog.deep_sky",
    "targets.recommend",
    "equipment.match",
    "observing_window.select",
    "targets.requirements",
    "catalog.solar_system",
    "targets.moon_sensitivity",
    "astronomy.horizontal_position",
    "targets.deep_sky_windows",
    "astronomy.sun_events",
    "astronomy.moon_info",
    "astronomy.moon_series",
    "astronomy.moon_observation",
    "targets.moon_recommendation",
    "astronomy.planet_observation",
    "targets.planet_recommendation",
    "targets.compose_recommendations",
    "targets.filter_recommendations_by_equipment",
    "observing_night.resolve_active",
    "night_forecast.derive_window",
]

@main
enum AstroEngineEval {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let parsed: Parsed
        do {
            parsed = try parse(args)
        } catch let error as UsageError {
            fputs(usage, stderr)
            if !error.message.isEmpty {
                fputs(error.message + "\n", stderr)
            }
            exit(Int32(exitUsage))
        } catch {
            fputs(usage, stderr)
            fputs(String(describing: error) + "\n", stderr)
            exit(Int32(exitUsage))
        }

        switch parsed {
        case .engineVersion:
            do {
                let version = try ContractsRoot.engineSemver()
                writeJSON(["engine_semver": version], pretty: false)
                exit(Int32(exitOK))
            } catch {
                fputs(String(describing: error) + "\n", stderr)
                writeErrorEnvelope(
                    capability: nil,
                    code: "engine_failure",
                    message: (error as? ContractsRootError)?.message ?? String(describing: error),
                    pretty: false,
                    version: nil
                )
                exit(Int32(exitEngine))
            }
        case let .capability(id, inputPath, pretty):
            exit(Int32(runCapability(id: id, inputPath: inputPath, pretty: pretty)))
        case let .fixture(directory, pretty):
            let inputPath = directory.appendingPathComponent("input.json").path
            let capability = fixtureCapability(directory: directory)
            exit(Int32(runCapability(id: capability, inputPath: inputPath, pretty: pretty)))
        }
    }
}

private enum Parsed {
    case engineVersion
    case capability(id: String, inputPath: String, pretty: Bool)
    case fixture(directory: URL, pretty: Bool)
}

private struct UsageError: Error {
    let message: String
}

private func parse(_ args: [String]) throws -> Parsed {
    if args.contains("--help") || args.contains("-h") {
        throw UsageError(message: "")
    }

    var engineVersion = false
    var pretty = false
    var inputPath: String?
    var fixturePath: String?
    var positional: [String] = []
    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--engine-version":
            engineVersion = true
        case "--pretty":
            pretty = true
        case "--input":
            index += 1
            guard index < args.count else { throw UsageError(message: "--input requires a path") }
            inputPath = args[index]
        case "--fixture":
            index += 1
            guard index < args.count else { throw UsageError(message: "--fixture requires a directory") }
            fixturePath = args[index]
        default:
            if arg.hasPrefix("-") {
                throw UsageError(message: "unknown option: \(arg)")
            }
            positional.append(arg)
        }
        index += 1
    }

    if engineVersion {
        if pretty || inputPath != nil || fixturePath != nil || !positional.isEmpty {
            throw UsageError(message: "--engine-version cannot be combined with other arguments")
        }
        return .engineVersion
    }

    if let fixturePath {
        if inputPath != nil || !positional.isEmpty {
            throw UsageError(message: "--fixture cannot be combined with a capability-id or --input")
        }
        return .fixture(directory: URL(fileURLWithPath: fixturePath, isDirectory: true), pretty: pretty)
    }

    guard let capability = positional.first, positional.count == 1 else {
        throw UsageError(message: "capability-id is required")
    }
    guard let inputPath else {
        throw UsageError(message: "--input is required")
    }
    return .capability(id: capability, inputPath: inputPath, pretty: pretty)
}

private func fixtureCapability(directory: URL) -> String {
    let inputURL = directory.appendingPathComponent("input.json")
    if let data = try? Data(contentsOf: inputURL),
       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let capability = object["capability"] as? String {
        return capability
    }
    return directory.deletingLastPathComponent().lastPathComponent.contains("night-conditions-score")
        ? "night_conditions.score"
        : directory.deletingLastPathComponent().lastPathComponent.replacingOccurrences(of: "-", with: ".")
}

private func runCapability(id: String, inputPath: String, pretty: Bool) -> Int {
    guard supportedCapabilities.contains(id) else {
        fputs(usage, stderr)
        fputs("unknown capability: \(id)\n", stderr)
        return exitUsage
    }

    do {
        let raw = try readInputBytes(inputPath)
        let document = try loadJSONObject(raw)
        let result = try CapabilityDispatch.run(capability: id, document: document)
        var envelope: [String: Any] = [
            "capability": id,
            "ok": true,
            "result": result,
        ]
        if let version = try? ContractsRoot.engineSemver() {
            envelope["engine_semver"] = version
        }
        writeJSON(envelope, pretty: pretty)
        return exitOK
    } catch is PayloadTooLarge {
        writeErrorEnvelope(
            capability: id,
            code: "payload_too_large",
            message: "input exceeds 1 MiB",
            pretty: pretty,
            version: try? ContractsRoot.engineSemver()
        )
        return exitValidation
    } catch let error as EvalValidationError {
        writeErrorEnvelope(
            capability: id,
            code: error.code,
            message: error.message,
            pretty: pretty,
            version: try? ContractsRoot.engineSemver()
        )
        return error.code == "engine_failure" ? exitEngine : exitValidation
    } catch let error as NightConditionsAnalysisError {
        writeErrorEnvelope(
            capability: id,
            code: "validation",
            message: error.message,
            pretty: pretty,
            version: try? ContractsRoot.engineSemver()
        )
        return exitValidation
    } catch let error as ContractsRootError {
        fputs(error.message + "\n", stderr)
        writeErrorEnvelope(
            capability: id,
            code: "engine_failure",
            message: error.message,
            pretty: pretty,
            version: nil
        )
        return exitEngine
    } catch {
        fputs("engine failure: \(error)\n", stderr)
        writeErrorEnvelope(
            capability: id,
            code: "engine_failure",
            message: String(describing: error),
            pretty: pretty,
            version: try? ContractsRoot.engineSemver()
        )
        return exitEngine
    }
}

private struct PayloadTooLarge: Error {}

struct EvalValidationError: Error {
    let code: String
    let message: String
}

private func readInputBytes(_ inputPath: String) throws -> Data {
    if inputPath == "-" {
        var chunks: [Data] = []
        var total = 0
        let handle = FileHandle.standardInput
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            total += chunk.count
            if total > stdinLimitBytes { throw PayloadTooLarge() }
            chunks.append(chunk)
        }
        return chunks.reduce(into: Data()) { $0.append($1) }
    }

    let url = URL(fileURLWithPath: inputPath)
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    if let size = values.fileSize, size > stdinLimitBytes {
        throw PayloadTooLarge()
    }
    let data = try Data(contentsOf: url)
    if data.count > stdinLimitBytes {
        throw PayloadTooLarge()
    }
    return data
}

private func loadJSONObject(_ data: Data) throws -> [String: Any] {
    let raw: Any
    do {
        raw = try JSONSerialization.jsonObject(with: data, options: [])
    } catch {
        throw EvalValidationError(code: "validation", message: "malformed JSON: \(error.localizedDescription)")
    }
    try assertFinite(raw, path: "$")
    guard let object = raw as? [String: Any] else {
        throw EvalValidationError(code: "validation", message: "input JSON must be an object")
    }
    return object
}

private func assertFinite(_ value: Any, path: String) throws {
    if value is NSNull { return }
    if let number = value as? NSNumber {
        if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() { return }
        let doubleValue = number.doubleValue
        if !doubleValue.isFinite {
            throw EvalValidationError(code: "validation", message: "non-finite number at \(path)")
        }
        return
    }
    if let object = value as? [String: Any] {
        for (key, item) in object {
            try assertFinite(item, path: "\(path).\(key)")
        }
        return
    }
    if let array = value as? [Any] {
        for (index, item) in array.enumerated() {
            try assertFinite(item, path: "\(path)[\(index)]")
        }
    }
}

private func writeJSON(_ value: [String: Any], pretty: Bool) {
    let options: JSONSerialization.WritingOptions = pretty
        ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        : [.sortedKeys, .withoutEscapingSlashes]
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: options),
          var text = String(data: data, encoding: .utf8) else {
        fputs("engine failure: could not encode JSON\n", stderr)
        exit(Int32(exitEngine))
    }
    if pretty, !text.hasSuffix("\n") {
        text.append("\n")
    } else if !pretty {
        text.append("\n")
    }
    fputs(text, stdout)
}

private func writeErrorEnvelope(
    capability: String?,
    code: String,
    message: String,
    pretty: Bool,
    version: String?
) {
    var payload: [String: Any] = [
        "ok": false,
        "error": ["code": code, "message": message],
    ]
    if let capability {
        payload["capability"] = capability
    }
    if let version {
        payload["engine_semver"] = version
    }
    writeJSON(payload, pretty: pretty)
}
