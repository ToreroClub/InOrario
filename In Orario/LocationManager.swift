import Foundation
import CoreLocation
import Combine

// MARK: - DeviceLocationService
/// Punto unico e centralizzato per la gestione della posizione GPS del dispositivo.
/// - Gestisce l'hardware CoreLocation in modo on-demand: si attiva solo quando un servizio lo richiede espressamente.
/// - Include una cache intelligente: se esiste già una posizione recente (< maxAge), risponde all'istante senza svegliare il GPS.
/// - Coalescing delle richieste: se più servizi richiedono la posizione contemporaneamente, effettua una singola richiesta hardware e risponde a tutti insieme.
@MainActor
final class DeviceLocationService: NSObject, CLLocationManagerDelegate {
    static let shared = DeviceLocationService()
    
    private let manager = CLLocationManager()
    
    // Cache dell'ultima posizione valida
    private(set) var lastLocation: CLLocation?
    
    // Lista di continuation in attesa (coalescing)
    private var pendingContinuations: [CheckedContinuation<CLLocation?, Never>] = []
    private var isRequesting = false
    
    // Callback di notifica
    var onLocationUpdate: ((CLLocation) -> Void)?
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
    
    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        
        // Se il sistema ha già una posizione recente in cache (< 5 min), memorizzala subito
        if let last = manager.location, last.horizontalAccuracy >= 0, abs(last.timestamp.timeIntervalSinceNow) < 300 {
            self.lastLocation = last
        }
    }
    
    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }
    
    func requestAuthorization() {
        print("[DeviceLocationService] Richiesta autorizzazione GPS...")
        manager.requestWhenInUseAuthorization()
    }
    
    /// Raccoglie la posizione su richiesta in modo ordinato.
    /// - Se è disponibile una posizione recente (< maxAge secondi), la restituisce subito dalla cache.
    /// - Se più servizi la richiedono contemporaneamente, effettua una sola richiesta hardware e risponde a tutti.
    func getCurrentLocation(maxAge: TimeInterval = 60, timeout: TimeInterval = 6) async -> CLLocation? {
        // 1. Controlla la cache recente
        if let cached = lastLocation, cached.horizontalAccuracy >= 0, abs(cached.timestamp.timeIntervalSinceNow) < maxAge {
            return cached
        }
        
        // 2. Verifica autorizzazione
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return lastLocation
        }
        
        // 3. Richiesta coordinata con coalescing
        return await withCheckedContinuation { continuation in
            pendingContinuations.append(continuation)
            
            if !isRequesting {
                isRequesting = true
                print("[DeviceLocationService] Richiesta posizione GPS in corso...")
                manager.requestLocation()
                
                // Timeout di sicurezza
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    guard let self = self, self.isRequesting else { return }
                    print("[DeviceLocationService] Timeout GPS (\(timeout)s), rispondo con l'ultima posizione disponibile.")
                    self.resolvePending(with: self.lastLocation)
                }
            }
        }
    }
    
    /// Richiesta fire-and-forget (per pulsanti o trigger UI)
    func requestLocation(maxAge: TimeInterval = 30) {
        Task {
            _ = await getCurrentLocation(maxAge: maxAge)
        }
    }
    
    private func resolvePending(with location: CLLocation?) {
        guard isRequesting else { return }
        isRequesting = false
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        for cont in continuations {
            cont.resume(returning: location)
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            print("[DeviceLocationService] Stato autorizzazione GPS: \(status.rawValue)")
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                if let loc = manager.location, loc.horizontalAccuracy >= 0 {
                    self.lastLocation = loc
                    self.onLocationUpdate?(loc)
                }
                self.manager.requestLocation()
            }
            self.onAuthorizationChange?(status)
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        let age = abs(loc.timestamp.timeIntervalSinceNow)
        guard age < 600 else { return }
        
        Task { @MainActor in
            if let current = self.lastLocation {
                let dist = current.distance(from: loc)
                // Ignora micro-jitter (< 10m) a meno di 10 secondi di distanza
                if dist < 10 && abs(current.timestamp.timeIntervalSince(loc.timestamp)) < 10 {
                    self.resolvePending(with: current)
                    return
                }
            }
            print("[DeviceLocationService] Posizione aggiornata: \(loc.coordinate.latitude), \(loc.coordinate.longitude) (±\(Int(loc.horizontalAccuracy))m)")
            self.lastLocation = loc
            self.onLocationUpdate?(loc)
            self.resolvePending(with: loc)
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("[DeviceLocationService] Errore GPS: \(error.localizedDescription)")
            self.resolvePending(with: self.lastLocation)
        }
    }
}

// MARK: - RFIStationCatalog
/// Catalogo condiviso delle stazioni RFI/VT caricato una sola volta per processo e condiviso
/// tra LocationManager, TrainManager, LocalScrapingService e SmartQueryExecutor.
final class RFIStationCatalog: @unchecked Sendable {
    static let shared = RFIStationCatalog()

    private final class BundleToken {}

    private let lock = NSLock()
    private var cachedRFIStations: [RFIStation]? = nil
    private var cachedGeoStations: [Station]? = nil

    private init() {}

    var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cachedRFIStations != nil
    }

    var rfiStations: [RFIStation] {
        lock.lock()
        if let existing = cachedRFIStations {
            lock.unlock()
            return existing
        }
        lock.unlock()

        let loaded = Self.decodeFromBundle()
        let geo = loaded.compactMap { rfi -> Station? in
            guard rfi.lat != nil, rfi.lon != nil else { return nil }
            return Station(
                name: rfi.name,
                rfiID: rfi.rfiID,
                vtID: rfi.vtID,
                lat: rfi.lat,
                lon: rfi.lon
            )
        }

        lock.lock()
        if cachedRFIStations == nil {
            cachedRFIStations = loaded
            cachedGeoStations = geo
        }
        let result = cachedRFIStations ?? loaded
        lock.unlock()
        return result
    }

    var geoStations: [Station] {
        lock.lock()
        if let existing = cachedGeoStations {
            lock.unlock()
            return existing
        }
        lock.unlock()

        _ = rfiStations
        lock.lock()
        let result = cachedGeoStations ?? []
        lock.unlock()
        return result
    }

    private static func decodeFromBundle() -> [RFIStation] {
        let bundles = [Bundle.main, Bundle(for: BundleToken.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: "rfi_stations", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([RFIStation].self, from: data),
               !decoded.isEmpty {
                return decoded
            }
        }
        return []
    }

    /// Ricerca O(k) della stazione più vicina con pre-filtro bounding-box in aritmetica pura
    /// prima di allocare oggetti CLLocation.
    nonisolated static func nearestStation(
        to targetLocation: CLLocation,
        in stations: [Station],
        maxDistanceMeters: Double = 4000
    ) -> (station: Station, distance: Double)? {
        let uLat = targetLocation.coordinate.latitude
        let uLon = targetLocation.coordinate.longitude
        let latDelta = max(0.05, (maxDistanceMeters / 111_000.0) * 1.35)
        let lonDelta = max(0.075, (maxDistanceMeters / 72_000.0) * 1.35)

        var bestStation: Station? = nil
        var bestDistance = maxDistanceMeters

        for station in stations {
            guard let lat = station.lat, let lon = station.lon else { continue }
            if abs(lat - uLat) > latDelta || abs(lon - uLon) > lonDelta {
                continue
            }
            let d = targetLocation.distance(from: CLLocation(latitude: lat, longitude: lon))
            if d <= bestDistance {
                bestDistance = d
                bestStation = station
            }
        }

        if let bestStation {
            return (bestStation, bestDistance)
        }
        return nil
    }
}

// MARK: - LocationManager
/// Bridge ObservableObject per le viste SwiftUI dell'applicazione.
/// Si interfaccia con DeviceLocationService e calcola le stazioni vicine.
@MainActor
class LocationManager: ObservableObject {
    @Published var userLocation: CLLocation? {
        didSet {
            updateNearbyStation()
        }
    }
    @Published var nearbyStation: Station?
    @Published var nearbyStationDistance: Double?
    @Published var manualNearbyStation: Station?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    
    private let locationService = DeviceLocationService.shared
    private var isWarmingCatalog = false
    
    init() {
        self.userLocation = locationService.lastLocation
        self.authorizationStatus = locationService.authorizationStatus
        
        locationService.onLocationUpdate = { [weak self] newLocation in
            self?.userLocation = newLocation
        }
        
        locationService.onAuthorizationChange = { [weak self] status in
            self?.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self?.requestLocation(force: true)
            }
        }
        
        updateNearbyStation()
    }
    
    func refreshAuthorizationStatus() {
        let latest = locationService.authorizationStatus
        if authorizationStatus != latest {
            authorizationStatus = latest
        }
    }
    
    func requestAuthorization() {
        locationService.requestAuthorization()
    }
    
    /// Richiesta fire-and-forget
    func requestLocation(force: Bool = false) {
        locationService.requestLocation(maxAge: force ? 0 : 30)
    }
    
    /// Raccoglie la posizione su richiesta (on-demand)
    func getCurrentLocation(maxAge: TimeInterval = 60, timeout: TimeInterval = 6) async -> CLLocation? {
        let loc = await locationService.getCurrentLocation(maxAge: maxAge, timeout: timeout)
        if let loc = loc {
            self.userLocation = loc
        }
        return loc
    }
    
    private func updateNearbyStation() {
        guard let userLoc = userLocation else {
            self.nearbyStation = nil
            self.nearbyStationDistance = nil
            return
        }

        if !RFIStationCatalog.shared.isLoaded {
            if !isWarmingCatalog {
                isWarmingCatalog = true
                Task.detached(priority: .userInitiated) {
                    _ = RFIStationCatalog.shared.geoStations
                    await MainActor.run { [weak self] in
                        self?.isWarmingCatalog = false
                        self?.updateNearbyStation()
                    }
                }
            }
            return
        }

        if let match = RFIStationCatalog.nearestStation(
            to: userLoc,
            in: RFIStationCatalog.shared.geoStations,
            maxDistanceMeters: 4000
        ) {
            self.nearbyStation = match.station
            self.nearbyStationDistance = match.distance
        } else {
            self.nearbyStation = nil
            self.nearbyStationDistance = nil
        }
    }
    
    func findNearestStation(among candidateNames: [String]) -> (name: String, distance: Double)? {
        guard let userLoc = userLocation else { return nil }
        let stations = RFIStationCatalog.shared.geoStations
        
        func compact(_ s: String) -> String {
            s.lowercased()
                .replacingOccurrences(of: "p.za ", with: "piazza")
                .replacingOccurrences(of: "p.za", with: "piazza")
                .replacingOccurrences(of: "p.ta ", with: "porta")
                .replacingOccurrences(of: "p.ta", with: "porta")
                .replacingOccurrences(of: "p. ", with: "porta")
                .replacingOccurrences(of: "p.", with: "porta")
                .replacingOccurrences(of: "sant'", with: "san")
                .replacingOccurrences(of: "sant ", with: "san")
                .replacingOccurrences(of: "s. ", with: "san")
                .replacingOccurrences(of: "s.", with: "san")
                .replacingOccurrences(of: "santa ", with: "san")
                .replacingOccurrences(of: "santa", with: "san")
                .replacingOccurrences(of: "santo ", with: "san")
                .replacingOccurrences(of: "santo", with: "san")
                .replacingOccurrences(of: "c.le", with: "centrale")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: ".", with: "")
                .folding(options: .diacriticInsensitive, locale: .current)
        }

        var matches: [(String, Double)] = []
        for cand in candidateNames {
            let norm = cand.lowercased().trimmingCharacters(in: .whitespaces)
            let isCandGaribaldi = norm.contains("garibaldi") && !norm.contains("pavia") && !norm.contains("casalecchio") && !norm.contains("napoli")
            let candCompact = compact(cand)

            let found: Station?
            if isCandGaribaldi {
                found = stations.first { st in
                    let sNorm = st.name.lowercased()
                    return sNorm.contains("garibaldi") && !sNorm.contains("pavia") && !sNorm.contains("casalecchio") && !sNorm.contains("napoli")
                }
            } else {
                found = stations.first { $0.name.lowercased() == norm }
                    ?? stations.first { $0.name.lowercased() == "milano " + norm }
                    ?? stations.first { compact($0.name) == candCompact }
                    ?? stations.first { st in
                        let sNorm = st.name.lowercased()
                        if norm == "certosa" && sNorm.contains("pavia") { return false }
                        return sNorm.contains(norm)
                    }
            }
            if let st = found, let coord = st.coordinate {
                let d = userLoc.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
                matches.append((cand, d))
            }
        }
        return matches.min(by: { $0.1 < $1.1 })
    }
}
