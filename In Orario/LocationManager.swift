import Foundation
import CoreLocation
import Combine

@MainActor class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var userLocation: CLLocation? {
        didSet {
            updateNearbyStation()
        }
    }
    @Published var nearbyStation: Station?
    @Published var manualNearbyStation: Station?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorizationStatus: CLAuthorizationStatus {
        return manager.authorizationStatus
    }

    func requestAuthorization() {
        print("Richiesta esplicita di autorizzazione GPS...")
        manager.requestWhenInUseAuthorization()
    }
    
    func requestLocation() {
        print("Richiesta esplicita della posizione GPS in corso...")
        manager.requestLocation()
    }
    
    private var allReferenceStations: [Station] = []
    
    private func loadStationsIfNeeded() {
        guard allReferenceStations.isEmpty else { return }
        if let url = Bundle.main.url(forResource: "rfi_stations", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([RFIStation].self, from: data) {
            self.allReferenceStations = decoded.compactMap { rfi in
                guard rfi.lat != nil, rfi.lon != nil else { return nil }
                return Station(
                    name: rfi.name,
                    rfiID: rfi.rfiID,
                    vtID: rfi.vtID,
                    lat: rfi.lat,
                    lon: rfi.lon
                )
            }
        }
    }
    
    private func updateNearbyStation() {
        guard let userLoc = userLocation else {
            self.nearbyStation = nil
            return
        }
        
        loadStationsIfNeeded()
        
        let sortedCandidates = allReferenceStations.compactMap { s -> (Station, Double)? in
            guard let c = s.coordinate else { return nil }
            let dist = userLoc.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            return (s, dist)
        }.sorted(by: { $0.1 < $1.1 })
        
        // Se la stazione più vicina è entro 5 km, considerala vicina
        if let closest = sortedCandidates.first, closest.1 < 5000 {
            self.nearbyStation = closest.0
        } else {
            self.nearbyStation = nil
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        print("Stato autorizzazione GPS: \(status.rawValue)")
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            print("Permesso GPS accordato.")
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            let age = abs(loc.timestamp.timeIntervalSinceNow)
            if age > 60 {
                print("Posizione GPS ignorata perché obsoleta (cached da \(age) secondi)")
                return
            }
            print("Posizione GPS aggiornata con successo: \(loc.coordinate.latitude), \(loc.coordinate.longitude) (accuratezza: \(loc.horizontalAccuracy)m)")
            Task { @MainActor in self.userLocation = loc }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Errore localizzazione GPS (didFailWithError): \(error.localizedDescription)")
    }
}
