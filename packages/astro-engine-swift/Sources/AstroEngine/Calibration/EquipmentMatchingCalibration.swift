import Foundation

public struct EquipmentMatchingCalibration: Hashable, Sendable, Decodable {
    public let preferences: Preferences
    public struct Preferences: Hashable, Sendable, Decodable {
        public let none: Int
        public let unknown: Int
        public let naked_eye_challenging: Int
        public let naked_eye_preferred: Int
        public let binocular_aperture_limited: Int
        public let binocular_magnification_limited: Int
        public let binocular_preferred: Int
        public let binocular_practical: Int
        public let aperture_limited: Int
        public let very_wide_visual: Int
        public let visual_preferred: Int
        public let visual_practical: Int
        public let wide_visual_adjustment: Int
        public let electronic_preferred: Int
        public let electronic_practical: Int
        public let electronic_supported: Int
    }
}
