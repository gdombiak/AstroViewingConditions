//
//  LocationManager.swift
//  SharedCode
//
//  Created by Gaston on 11/17/24.
//

import Foundation
import CoreLocation
#if os(iOS)
import SwiftUI
#endif

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

#if os(iOS)

@Observable
public class LocationManager: NSObject, @unchecked Sendable {
    private let manager = CLLocationManager()
    
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
        }
    }
    
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    
    public func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> CLPlacemark? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        return placemarks.first
    }
    
    func userLocationName() async -> String {
        guard let location = currentLocation else { return "Unknown Location" }
        
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                return placemark.locality ?? placemark.administrativeArea ?? placemark.country ?? "Unknown Location"
            }
        } catch {
            print("Geocoding error: \(error)")
        }
        
        return "Lat: \(String(format: "%.2f", location.coordinate.latitude)), Lon: \(String(format: "%.2f", location.coordinate.longitude))"
    }
}

extension LocationManager: CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        
        if let continuation = locationContinuation {
            locationContinuation = nil
            continuation.resume(returning: location.coordinate)
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationError = error
        
        if let continuation = locationContinuation {
            locationContinuation = nil
            continuation.resume(throwing: error)
        }
    }
}

#elseif os(watchOS)

public class LocationManager: NSObject, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var authContinuation: CheckedContinuation<Void, Error>?
    
    public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    public var currentLocation: CLLocation?
    public var locationError: Error?
    
    public var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }
    
    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.allowsBackgroundLocationUpdates = false
        authorizationStatus = manager.authorizationStatus
    }
    
    public func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }
    
    public func waitForAuthorization() async throws {
        guard authorizationStatus == .notDetermined else { return }
        
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.authContinuation = continuation
                
                Task {
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                    if let cont = self.authContinuation {
                        self.authContinuation = nil
                        cont.resume(throwing: LocationError.timeout)
                    }
                }
            }
        } catch {
            if authorizationStatus != .notDetermined {
                return
            }
            throw error
        }
    }
    
    public func getCurrentLocation() async throws -> CLLocationCoordinate2D {
        guard isAuthorized else {
            throw LocationError.notAuthorized
        }
        
        if let cachedLocation = manager.location {
            return cachedLocation.coordinate
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            self.manager.startUpdatingLocation()
            
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard let self = self else { return }
                
                self.manager.stopUpdatingLocation()
                if let cont = self.locationContinuation {
                    self.locationContinuation = nil
                    cont.resume(throwing: LocationError.timeout)
                }
            }
        }
    }
    
    @available(watchOS, deprecated: 26.0, message: "Use MapKit geocoding instead")
    public func geocodeAddress(_ address: String) async throws -> [CLPlacemark] {
        let geocoder = CLGeocoder()
        return try await geocoder.geocodeAddressString(address)
    }
    
    @available(watchOS, deprecated: 26.0, message: "Use MapKit reverse geocoding instead")
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

extension LocationManager: CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        
        if let cont = authContinuation, isAuthorized {
            authContinuation = nil
            cont.resume()
        }
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

#endif