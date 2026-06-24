import Foundation
import Combine

@MainActor class MetroCache: ObservableObject {
    @Published var allSchedules: [String: MetroDeparturesResponse] = [:]
    @Published var isOfflineMode: [String: Bool] = [:]
    
    private let storageKey = "com.magenta.metro.cache.departures"
    private let baseURL = "https://gestioneinorario.toreroclub.com"
    
    init() {}
    
    private var activeSyncs = Set<String>()
    private var lastFetchTime: [String: Date] = [:]
    private let cacheTTL: TimeInterval = 60 // 1 minuto

    func sync(line: String, pdfID: String, direction: Int, time: String? = nil, force: Bool = false) async {
        let cacheKey = "\(line)_\(pdfID)_\(direction)_\(time ?? "")"

        // Dati freschi in cache? Salta la chiamata al server (a meno di sync forzato)
        if !force,
           let lastFetch = lastFetchTime[cacheKey],
           Date().timeIntervalSince(lastFetch) < cacheTTL,
           allSchedules[cacheKey] != nil {
            return
        }

        if activeSyncs.contains(cacheKey) { return }
        activeSyncs.insert(cacheKey)
        defer { activeSyncs.remove(cacheKey) }
        
        var components = URLComponents(string: "\(baseURL)/metro/departures/\(line)/\(pdfID)")!
        var queryItems = [URLQueryItem(name: "direction", value: String(direction))]
        if let t = time {
            queryItems.append(URLQueryItem(name: "time", value: t))
        }
        components.queryItems = queryItems
        guard let url = components.url else { return }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5.0))
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                if allSchedules[cacheKey] == nil {
                    self.isOfflineMode[cacheKey] = true
                }
                return
            }
            let decoded = try JSONDecoder().decode(MetroDeparturesResponse.self, from: data)
            self.allSchedules[cacheKey] = decoded
            self.isOfflineMode[cacheKey] = false
            self.lastFetchTime[cacheKey] = Date() // aggiorna timestamp solo su successo
        } catch {
            if allSchedules[cacheKey] == nil {
                self.isOfflineMode[cacheKey] = true
            }
        }
    }

    
    func getNextDepartures(metro: MetroLine, time: String? = nil, now: Date) -> MetroDisplayMode {
        let hour = Calendar.current.component(.hour, from: now)
        if hour >= 2 && hour <= 4 { return .closed }
        
        let line = String(metro.name.prefix(2))
        let cacheKey = "\(line)_\(metro.pdfID ?? "")_\(metro.direction)_\(time ?? "")"
        guard let response = allSchedules[cacheKey] else { return .frequency("In aggiornamento...") }
        
        if response.departures.isEmpty {
            return .frequency("Nessuna partenza programmata")
        }
        
        let deps = response.departures.prefix(4).map { dep in
            return FormattedDeparture(timeString: dep.time, destinationName: dep.destination)
        }
        return .exact(Array(deps))
    }
}
