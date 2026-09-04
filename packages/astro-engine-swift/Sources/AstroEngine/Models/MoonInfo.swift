import Foundation

public struct MoonInfo: Sendable, Codable {
    public let phase: Double
    public let phaseName: String
    public let altitude: Double
    public let illumination: Int
    public let emoji: String
    
    public init(
        phase: Double,
        phaseName: String,
        altitude: Double,
        illumination: Int,
        emoji: String
    ) {
        self.phase = phase
        self.phaseName = phaseName
        self.altitude = altitude
        self.illumination = illumination
        self.emoji = emoji
    }
}
