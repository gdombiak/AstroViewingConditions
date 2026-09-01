import Foundation

public struct SunEvents: Sendable, Codable {
    public let sunrise: Date
    public let sunset: Date
    public let civilTwilightBegin: Date
    public let civilTwilightEnd: Date
    public let nauticalTwilightBegin: Date
    public let nauticalTwilightEnd: Date
    public let astronomicalTwilightBegin: Date
    public let astronomicalTwilightEnd: Date
    
    public init(
        sunrise: Date,
        sunset: Date,
        civilTwilightBegin: Date,
        civilTwilightEnd: Date,
        nauticalTwilightBegin: Date,
        nauticalTwilightEnd: Date,
        astronomicalTwilightBegin: Date,
        astronomicalTwilightEnd: Date
    ) {
        self.sunrise = sunrise
        self.sunset = sunset
        self.civilTwilightBegin = civilTwilightBegin
        self.civilTwilightEnd = civilTwilightEnd
        self.nauticalTwilightBegin = nauticalTwilightBegin
        self.nauticalTwilightEnd = nauticalTwilightEnd
        self.astronomicalTwilightBegin = astronomicalTwilightBegin
        self.astronomicalTwilightEnd = astronomicalTwilightEnd
    }
    
    public var astronomicalNightStart: Date {
        astronomicalTwilightEnd
    }
    
    public var astronomicalNightEnd: Date {
        astronomicalTwilightBegin
    }
    
    public var astronomicalNightDuration: TimeInterval {
        astronomicalNightEnd.timeIntervalSince(astronomicalNightStart)
    }
    
    public func astronomicalNightEnd(using tomorrowSunEvents: SunEvents?) -> Date {
        tomorrowSunEvents?.astronomicalTwilightBegin ?? astronomicalNightEnd
    }
    
    public func astronomicalNightDuration(using tomorrowSunEvents: SunEvents?) -> TimeInterval {
        astronomicalNightEnd(using: tomorrowSunEvents).timeIntervalSince(astronomicalNightStart)
    }
}
