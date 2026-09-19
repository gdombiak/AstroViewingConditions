import Foundation

public struct N2YOResponse: Codable {
    public let info: N2YOInfo
    public let passes: [N2YOPass]?
}

public struct N2YOInfo: Codable {
    public let satid: Int
    public let satname: String
    public let transactionscount: Int
    public let passescount: Int?
}

public struct N2YOPass: Codable {
    public let startAz: Double
    public let startAzCompass: String
    public let startEl: Double
    public let startUTC: Int
    public let maxAz: Double
    public let maxAzCompass: String
    public let maxEl: Double
    public let maxUTC: Int
    public let endAz: Double
    public let endAzCompass: String
    public let endEl: Double
    public let endUTC: Int
    public let mag: Double
    public let duration: Int
}

public enum N2YOPassDecoder: Sendable {
    public static func passes(from response: N2YOResponse) -> [ISSPass] {
        guard response.passes != nil else {
            return []
        }

        return response.passes?.map { pass in
            ISSPass(
                riseTime: Date(timeIntervalSince1970: TimeInterval(pass.startUTC)),
                duration: TimeInterval(pass.duration),
                maxElevation: pass.maxEl,
                maxTime: Date(timeIntervalSince1970: TimeInterval(pass.maxUTC)),
                endTime: Date(timeIntervalSince1970: TimeInterval(pass.endUTC)),
                startDirection: pass.startAzCompass,
                maxDirection: pass.maxAzCompass,
                endDirection: pass.endAzCompass,
                startElevation: pass.startEl,
                endElevation: pass.endEl
            )
        } ?? []
    }

    public static func decodePasses(from data: Data) throws -> [ISSPass] {
        let response = try JSONDecoder().decode(N2YOResponse.self, from: data)
        return passes(from: response)
    }
}
