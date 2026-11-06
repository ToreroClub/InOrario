import Foundation
import CoreLocation
import Combine

public struct NearbyStation: Identifiable, Sendable {
    public var id: String { station.name }
    public let station: Station
    public let distanceMeters: Double
    
    public var distanceText: String {
        if distanceMeters < 1000 {
            return "\(Int(distanceMeters)) m"
        } else {
            return String(format: "%.1f km", distanceMeters / 1000.0)
        }
    }
}

@MainActor
public final class ClipLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    public static let shared = ClipLocationManager()
    
    private let locationManager = CLLocationManager()
    @Published public var userLocation: CLLocation?
    @Published public var nearbyStations: [NearbyStation] = []
    @Published public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    private var allStationsWithCoords: [Station] = []
    
    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.authorizationStatus = locationManager.authorizationStatus
        
        loadStations()
        
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            if let last = locationManager.location, last.horizontalAccuracy >= 0, abs(last.timestamp.timeIntervalSinceNow) < 600 {
                self.userLocation = last
                updateNearbyStations()
            }
            locationManager.requestLocation()
        }
    }
    
    public func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    public func requestLocation() {
        locationManager.requestLocation()
    }
    
    private func loadStations() {
        guard let url = Bundle.main.url(forResource: "rfi_stations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([RFIStation].self, from: data) else {
            return
        }
        self.allStationsWithCoords = decoded.compactMap { rfi in
            guard rfi.lat != nil, rfi.lon != nil else { return nil }
            return Station(name: rfi.name, rfiID: rfi.rfiID, vtID: rfi.vtID, lat: rfi.lat, lon: rfi.lon)
        }
    }
    
    private func updateNearbyStations() {
        guard let loc = userLocation else {
            self.nearbyStations = []
            return
        }
        
        let sorted = allStationsWithCoords.compactMap { st -> NearbyStation? in
            guard let coord = st.coordinate else { return nil }
            let dist = loc.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            return NearbyStation(station: st, distanceMeters: dist)
        }.sorted { $0.distanceMeters < $1.distanceMeters }
        
        self.nearbyStations = Array(sorted.prefix(10))
    }
    
    public var closestStation: Station? {
        return nearbyStations.first?.station
    }
    
    // MARK: - CLLocationManagerDelegate
    
    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }
    
    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        Task { @MainActor in
            self.userLocation = loc
            self.updateNearbyStations()
        }
    }
    
    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Ignora silenziosamente errori temporanei
    }
}
