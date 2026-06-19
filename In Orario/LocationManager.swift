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
    
    func requestAuthorization() {
        print("Richiesta esplicita di autorizzazione GPS...")
        manager.requestWhenInUseAuthorization()
    }
    
    func requestLocation() {
        print("Richiesta esplicita della posizione GPS in corso...")
        manager.requestLocation()
    }
    
    private func updateNearbyStation() {
        guard let userLoc = userLocation else {
            self.nearbyStation = nil
            return
        }
        
        let passanteStations = [
            Station(name: "Rho Fiera", rfiID: "3098", vtID: "S01026", lat: 45.5215, lon: 9.0883),
            Station(name: "Certosa", rfiID: "1708", vtID: "S01027", lat: 45.5085, lon: 9.1272),
            Station(name: "Villapizzone", rfiID: "3099", vtID: "S01057", lat: 45.4998, lon: 9.1465),
            Station(name: "Lancetti", rfiID: "1713", vtID: "S01059", lat: 45.4925, lon: 9.1751),
            Station(name: "P. Garibaldi Passante", rfiID: "1714", vtID: "S01058", lat: 45.4844, lon: 9.1887),
            Station(name: "Repubblica", rfiID: "1719", vtID: "S01060", lat: 45.4795, lon: 9.1963),
            Station(name: "Porta Venezia", rfiID: "1723", vtID: "S01061", lat: 45.4746, lon: 9.2052),
            Station(name: "Dateo", rfiID: "3468", vtID: "S01062", lat: 45.4682, lon: 9.2158),
            Station(name: "Porta Vittoria", rfiID: "1718", vtID: "S01063", lat: 45.4613, lon: 9.2227),
            Station(name: "Forlanini", rfiID: "3169", vtID: "S01064", lat: 45.4625, lon: 9.2368)
        ]
        
        let mainStations = [
            Station(name: "Magenta", rfiID: "1618", vtID: "S01021", lat: 45.4641, lon: 8.8845),
            Station(name: "Rho Fiera", rfiID: "3098", vtID: "S01026", lat: 45.5215, lon: 9.0883),
            Station(name: "Porta Garibaldi", rfiID: "1715", vtID: "S01058", lat: 45.4844, lon: 9.1887),
            Station(name: "Milano Centrale", rfiID: "1728", vtID: "S01700", lat: 45.4849, lon: 9.2033),
            Station(name: "Vittuone-Arluno", rfiID: "3119", vtID: "S01023", lat: 45.4921, lon: 8.9568),
            Station(name: "Pregnana Milanese", rfiID: "381", vtID: "S01024", lat: 45.5036, lon: 9.0069),
            Station(name: "Novara", rfiID: "1917", vtID: "S01017", lat: 45.4524, lon: 8.6253),
            Station(name: "Trecate", rfiID: "2909", vtID: "S01019", lat: 45.4374, lon: 8.7428),
            Station(name: "Rho", rfiID: "2345", vtID: "S01025", lat: 45.5262, lon: 9.0402)
        ]
        
        let allReferenceStations = mainStations + passanteStations
        
        let sortedCandidates = allReferenceStations.compactMap { s -> (Station, Double)? in
            guard let c = s.coordinate else { return nil }
            let dist = userLoc.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            return (s, dist)
        }.sorted(by: { $0.1 < $1.1 })
        
        if let closest = sortedCandidates.first, closest.1 < 15000 {
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
            print("Posizione GPS aggiornata con successo: \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
            Task { @MainActor in self.userLocation = loc }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Errore localizzazione GPS (didFailWithError): \(error.localizedDescription)")
    }
}
