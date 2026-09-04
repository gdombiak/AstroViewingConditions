import Foundation

public struct ISSPass: Identifiable, Sendable, Codable {
    public let id: String
    public let riseTime: Date
    public let duration: TimeInterval
    public let maxElevation: Double
    public let maxTime: Date?
    public let endTime: Date?
    public let startDirection: String?
    public let maxDirection: String?
    public let endDirection: String?
    public let startElevation: Double?
    public let endElevation: Double?
    
    public init(
        id: String? = nil,
        riseTime: Date,
        duration: TimeInterval,
        maxElevation: Double,
        maxTime: Date? = nil,
        endTime: Date? = nil,
        startDirection: String? = nil,
        maxDirection: String? = nil,
        endDirection: String? = nil,
        startElevation: Double? = nil,
        endElevation: Double? = nil
    ) {
        self.id = id ?? Self.stableID(
            riseTime: riseTime,
            duration: duration
        )
        self.riseTime = riseTime
        self.duration = duration
        self.maxElevation = maxElevation
        self.maxTime = maxTime
        self.endTime = endTime
        self.startDirection = startDirection
        self.maxDirection = maxDirection
        self.endDirection = endDirection
        self.startElevation = startElevation
        self.endElevation = endElevation
    }
    
    public var setTime: Date {
        endTime ?? riseTime.addingTimeInterval(duration)
    }

    private static func stableID(
        riseTime: Date,
        duration: TimeInterval
    ) -> String {
        "\(riseTime.timeIntervalSince1970.bitPattern)-\(duration.bitPattern)"
    }
}
