import Foundation
import CoreLocation

#if os(iOS)
@Observable
public class LocationManager: NSObject, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var timeoutTask: Task<Void, Never>?
    
    public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    public var currentLocation: CLLocation?
    public var locationError: Error?
    
    public var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }
    
    public override init() {
        super.init()
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
    }
    
    public func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }
    
    public func getCurrentLocation() async throws -> CLLocationCoordinate2D {
        guard isAuthorized else {
            throw LocationError.notAuthorized
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            manager.requestLocation()
            
            // Set up timeout
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard let self = self else { return }
                
                if let cont = self.locationContinuation {
                    self.locationContinuation = nil
                    cont.resume(throwing: LocationError.timeout)
                }
            }
        }
    }
    
    public func geocodeAddress(_ address: String) async throws -> [CLPlacemark] {
        let geocoder = CLGeocoder()
        return try await geocoder.geocodeAddressString(address)
    }
    
    public func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> CLPlacemark? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        return placemarks.first
    }
    
    private func completeLocationRequest(with location: CLLocation) {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let continuation = locationContinuation {
            locationContinuation = nil
            continuation.resume(returning: location.coordinate)
        }
    }
    
    private func failLocationRequest(with error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let continuation = locationContinuation {
            locationContinuation = nil
            continuation.resume(throwing: error)
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        completeLocationRequest(with: location)
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationError = error
        failLocationRequest(with: error)
    }
}

// MARK: - Errors

public enum LocationError: Error, LocalizedError {
    case notAuthorized
    case timeout
    case locationUnavailable
    
    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Location access not authorized. Please enable location services in Settings."
        case .timeout:
            return "Location request timed out. Please try again."
        case .locationUnavailable:
            return "Unable to determine location. Please check your device settings."
        }
    }
}

// MARK: - Convenience Extensions

extension CLPlacemark {
    public var formattedName: String {
        if let name = name {
            return name
        } else if let locality = locality {
            return locality
        } else if let subAdministrativeArea = subAdministrativeArea {
            return subAdministrativeArea
        } else {
            return "Unknown Location"
        }
    }
}

#else
// macOS stub implementation
@Observable
public class LocationManager: NSObject {
    public var authorizationStatus: CLAuthorizationStatus = .denied
    public var currentLocation: CLLocation?
    public var locationError: Error?
    
    public var isAuthorized: Bool { false }
    
    public override init() {
        super.init()
    }
    
    public func requestAuthorization() {}
    
    public func getCurrentLocation() async throws -> CLLocationCoordinate2D {
        throw LocationError.notAuthorized
    }
    
    public func geocodeAddress(_ address: String) async throws -> [CLPlacemark] {
        []
    }
    
    public func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> CLPlacemark? {
        nil
    }
}

public enum LocationError: Error, LocalizedError {
    case notAuthorized
    case timeout
    case locationUnavailable
    
    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Location access not authorized."
        case .timeout:
            return "Location request timed out."
        case .locationUnavailable:
            return "Unable to determine location."
        }
    }
}

extension CLPlacemark {
    public var formattedName: String {
        "Unknown Location"
    }
}
#endif
