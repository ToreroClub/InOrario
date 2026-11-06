import Foundation

public final class ClipLinkHandler: @unchecked Sendable {
    public static let shared = ClipLinkHandler()
    
    private var stations: [Station] = []
    private var byVtId: [String: Station] = [:]
    private var byRfiId: [String: Station] = [:]
    private var byNormalizedName: [String: Station] = [:]
    private var isLoaded = false
    private let lock = NSLock()
    
    public init() {
        loadStations()
    }
    
    public func ensureLoaded() {
        if !isLoaded {
            loadStations()
        }
    }
    
    private func loadStations() {
        lock.lock()
        defer { lock.unlock() }
        guard !isLoaded else { return }
        
        guard let url = Bundle.main.url(forResource: "rfi_stations", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            self.stations = [
                Station(name: "MILANO CENTRALE", rfiID: "1700", vtID: "S01700"),
                Station(name: "MAGENTA", rfiID: "1104", vtID: "S01104"),
                Station(name: "ROMA TERMINI", rfiID: "8409", vtID: "S08409"),
                Station(name: "TORINO LINGOTTO", rfiID: "30", vtID: "S00030")
            ]
            self.isLoaded = true
            return
        }
        
        if let decoded = try? JSONDecoder().decode([RFIStation].self, from: data) {
            var list: [Station] = []
            var vtDict: [String: Station] = [:]
            var rfiDict: [String: Station] = [:]
            var normDict: [String: Station] = [:]
            
            for item in decoded {
                let st = Station(name: item.name, rfiID: item.rfiID, vtID: item.vtID, lat: item.lat, lon: item.lon)
                list.append(st)
                
                if let vt = item.vtID {
                    vtDict[vt.uppercased()] = st
                }
                if let rf = item.rfiID {
                    rfiDict[rf] = st
                }
                let norm = normalize(item.name)
                normDict[norm] = st
            }
            
            self.stations = list
            self.byVtId = vtDict
            self.byRfiId = rfiDict
            self.byNormalizedName = normDict
            self.isLoaded = true
        }
    }
    
    public func resolveStation(from url: URL) -> Station? {
        ensureLoaded()
        
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
           let items = components.queryItems {
            for item in items {
                if (item.name == "id" || item.name == "station" || item.name == "s"),
                   let val = item.value, !val.isEmpty {
                    if let found = findStation(byCodeOrName: val) {
                        return found
                    }
                }
            }
        }
        
        let pathParts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        if let last = pathParts.last, !last.isEmpty {
            if let found = findStation(byCodeOrName: last) {
                return found
            }
        }
        
        return nil
    }
    
    public func findStation(byCodeOrName raw: String) -> Station? {
        ensureLoaded()
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        
        let lower = clean.lowercased()
        if lower.contains("porta di susa") || lower.contains("porta susa") {
            clean = "Torino Porta Susa"
        } else if lower.contains("expo rho") || lower.contains("rho fiera") || lower.contains("rho-fiera") {
            clean = "Rho Fiera"
        } else if lower.contains("mediopadana") {
            clean = "Reggio Emilia AV Mediopadana"
        }
        
        let upper = clean.uppercased()
        
        if let st = byVtId[upper] { return st }
        if let st = byRfiId[clean] { return st }
        
        let norm = normalize(clean)
        if let st = byNormalizedName[norm] { return st }
        
        let matches = stations.filter {
            let stNorm = normalize($0.name)
            return stNorm.contains(norm) || norm.contains(stNorm)
        }
        if let best = matches.max(by: { $0.name.count < $1.name.count }) {
            return best
        }
        
        return nil
    }
    
    public func searchStations(query: String, limit: Int = 20) -> [Station] {
        ensureLoaded()
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        
        let norm = normalize(clean)
        return stations.filter { st in
            normalize(st.name).contains(norm) || (st.vtID?.uppercased().contains(clean.uppercased()) ?? false)
        }.prefix(limit).map { $0 }
    }
    
    public func defaultStation() -> Station {
        ensureLoaded()
        if let mc = byVtId["S01700"] ?? byNormalizedName["milanocentrale"] {
            return mc
        }
        return stations.first ?? Station(name: "MILANO CENTRALE", rfiID: "1700", vtID: "S01700")
    }
    
    private func normalize(_ text: String) -> String {
        return text.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "'", with: "")
            .folding(options: .diacriticInsensitive, locale: .current)
    }
}
