import Combine
import Foundation
import SwiftUI

@MainActor class PassanteManager: ObservableObject {
    @Published var selectedSuburbanLines: [String] = [] {
        didSet { save() }
    }
    @Published var hiddenSuburbanStations: [String: [String]] = [:] {
        didSet { save() }
    }
    
    @Published var selectedPassanteStation: Station = Station(name: "Porta Venezia", rfiID: "1723", vtID: "S01649", lat: 45.4746, lon: 9.2052) {
        didSet { save() }
    }
    @Published var passanteTrains: [Train] = []
    @Published var isLoadingPassanteBoard = false
    @Published var passanteTunnelHealthMessage: String = "Circolazione Regolare"
    @Published var passanteTunnelHealthColor: String = "#009640"
    @Published var passanteTunnelAverageDelay: Int = 0
    @Published var passanteSelectedLinesAlerts: [String] = []
    
    @Published var passanteLiveStatuses: [String: TrainStatus] = [:]
    
    @Published var serverStuckTrains: [StuckTrainInfo] = []
    @Published var passanteLastUpdatedTimestamp: TimeInterval = 0
    @Published var isUsingLocalEngine: Bool = false
    @Published var isServerHealthOffline: Bool = false
    @Published var isLocalUpdating: Bool = false
    var lastLocalUpdateTimestamp: TimeInterval = 0
    
    @Published var passanteTunnelWestHealthMessage: String = "Ovest: Regolare"
    @Published var passanteTunnelWestHealthColor: String = "#009640"
    @Published var passanteTunnelEastHealthMessage: String = "Est: Regolare"
    @Published var passanteTunnelEastHealthColor: String = "#009640"
    @Published var passanteTunnelTrains: [Train] = []
    
    @Published var useSpecialPassanteView: Bool = false {
        didSet { UserDefaults.standard.set(useSpecialPassanteView, forKey: useSpecialPassanteViewKey) }
    }
    
    private let selectedSuburbanLinesKey = "selectedSuburbanLines_v1"
    private let hiddenSuburbanStationsKey = "hiddenSuburbanStations_v1"
    private let selectedPassanteStationKey = "selectedPassanteStation_v1"
    private let useSpecialPassanteViewKey = "useSpecialPassanteView_v1"
    
    init() {
        let selectedLinesData = UserDefaults.standard.data(forKey: selectedSuburbanLinesKey)
        let decodedLines = selectedLinesData.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        self._selectedSuburbanLines = Published(initialValue: decodedLines)
        
        let hiddenStationsData = UserDefaults.standard.data(forKey: hiddenSuburbanStationsKey)
        let decodedHidden = hiddenStationsData.flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
        self._hiddenSuburbanStations = Published(initialValue: decodedHidden)
        
        let selectedStationData = UserDefaults.standard.data(forKey: selectedPassanteStationKey)
        let decodedStation = selectedStationData.flatMap { try? JSONDecoder().decode(Station.self, from: $0) } ?? Station(name: "Porta Venezia", rfiID: "1723", vtID: "S01649", lat: 45.4746, lon: 9.2052)
        self._selectedPassanteStation = Published(initialValue: decodedStation)
        
        self.useSpecialPassanteView = UserDefaults.standard.bool(forKey: useSpecialPassanteViewKey)
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(selectedSuburbanLines) { UserDefaults.standard.set(data, forKey: selectedSuburbanLinesKey) }
        if let data = try? JSONEncoder().encode(hiddenSuburbanStations) { UserDefaults.standard.set(data, forKey: hiddenSuburbanStationsKey) }
        if let data = try? JSONEncoder().encode(selectedPassanteStation) { UserDefaults.standard.set(data, forKey: selectedPassanteStationKey) }
        UserDefaults.standard.synchronize()
    }

    func selectPassanteStation(_ station: Station, manager: TrainManager) {
        self.selectedPassanteStation = station
        save()
        Task {
            await fetchPassanteLive(manager: manager)
        }
    }
    
    func fetchPassanteLive(manager: TrainManager, includePositions: Bool = false) async {
        guard !isLoadingPassanteBoard else { return }
        self.isLoadingPassanteBoard = true
        let trainsFetched = await manager.fetchTrainsForStation(station: selectedPassanteStation)
        self.passanteTrains = trainsFetched
        self.isLoadingPassanteBoard = false
        
        await fetchTunnelHealth(manager: manager, includePositions: includePositions)
        await fetchAllPassanteTrains(manager: manager)
    }
    
    func forceLocalUpdate(manager: TrainManager) async {
        let now = Date().timeIntervalSince1970
        guard now - lastLocalUpdateTimestamp >= 10 else { return }
        self.lastLocalUpdateTimestamp = now
        
        await MainActor.run { self.isLocalUpdating = true }
        await fetchAllPassanteTrains(manager: manager, force: true)
        await MainActor.run { self.isLocalUpdating = false }
    }
    
    func fetchAllPassanteTrains(manager: TrainManager, force: Bool = false) async {
        let now = Date().timeIntervalSince1970
        if !force {
            // Rate limit: limit automatic background updates to once every 90 seconds
            guard now - lastLocalUpdateTimestamp >= 90.0 else { return }
        }
        self.lastLocalUpdateTimestamp = now
        
        let centralStation = Station(name: "Milano Porta Venezia", rfiID: nil, vtID: "S01649", lat: 45.4746, lon: 9.2052)
        let lancettiStation = Station(name: "Milano Lancetti", rfiID: nil, vtID: "S01643", lat: 45.4925, lon: 9.1751)
        
        async let trainsVenezia = manager.fetchTrainsForStation(station: centralStation)
        async let trainsLancetti = manager.fetchTrainsForStation(station: lancettiStation)
        
        let ven = await trainsVenezia
        let lan = await trainsLancetti
        
        var allTrains = ven
        let existingNumbers = Set(ven.map { $0.number })
        for t in lan {
            if !existingNumbers.contains(t.number) {
                allTrains.append(t)
            }
        }
        
        // We only fetch live statuses for the first 8 trains (which is the max displayed in the detail sheet)
        let trainsToFetch = Array(allTrains.prefix(8))
        
        var statuses: [String: TrainStatus] = [:]
        await withTaskGroup(of: (String, TrainStatus)?.self) { group in
            for train in trainsToFetch {
                group.addTask {
                    let result = await manager.fetchLiveStops(for: train.number, destination: train.destination)
                    if !result.stops.isEmpty || result.status.isDeparted {
                        return (train.number, result.status)
                    }
                    return nil
                }
            }
            for await item in group {
                if let (num, status) = item {
                    statuses[num] = status
                }
            }
        }
        
        var validDelays: [Int] = []
        var selectedTrains: [Train] = []
        var seenNumbers = Set<String>()
        
        for t in ven.prefix(4) {
            if !seenNumbers.contains(t.number) {
                seenNumbers.insert(t.number)
                selectedTrains.append(t)
            }
        }
        for t in lan.prefix(3) {
            if !seenNumbers.contains(t.number) {
                seenNumbers.insert(t.number)
                selectedTrains.append(t)
            }
        }
        
        for t in selectedTrains {
            let delayStr = t.delay.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "R: ", with: "")
            let isCancelled = t.delay.lowercased().contains("soppresso") || t.delay.lowercased().contains("cancellato")
            if !isCancelled {
                let d = delayStr.lowercased().contains("orario") ? 0 : (Int(delayStr) ?? 0)
                validDelays.append(d)
            }
        }
        let avgDelay = validDelays.isEmpty ? 0 : (validDelays.reduce(0, +) / validDelays.count)
        
        await MainActor.run {
            self.passanteTunnelTrains = allTrains
            self.passanteLiveStatuses = statuses
            self.passanteLastUpdatedTimestamp = Date().timeIntervalSince1970
            
            if self.isServerHealthOffline {
                self.isUsingLocalEngine = true
                self.passanteTunnelHealthMessage = "Motore Locale Attivo"
                self.passanteTunnelHealthColor = "#007AFF" // Blue for local engine
                self.passanteTunnelWestHealthMessage = "Ovest: Solo Live"
                self.passanteTunnelWestHealthColor = "#007AFF"
                self.passanteTunnelEastHealthMessage = "Est: Solo Live"
                self.passanteTunnelEastHealthColor = "#007AFF"
                self.passanteTunnelAverageDelay = avgDelay
            }
            self.passanteSelectedLinesAlerts = []
            self.serverStuckTrains = []
        }
    }
    
    func fetchTunnelHealth(manager: TrainManager, includePositions: Bool = false) async {
        let linesParam = selectedSuburbanLines.joined(separator: ",")
        let urlString = "https://gestioneinorario.toreroclub.com/passante/health" + 
                        "?include_positions=\(includePositions)" + 
                        (linesParam.isEmpty ? "" : "&lines=\(linesParam)")
        
        guard let url = URL(string: urlString) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct ServerHealthResponse: Codable {
                let healthMessage: String
                let healthColor: String
                let averageDelay: Int
                let westMessage: String
                let westColor: String
                let eastMessage: String
                let eastColor: String
                let alerts: [String]
                let statuses: [String: TrainStatus]?
                let stuckTrains: [StuckTrainInfo]?
                let lastUpdatedTimestamp: TimeInterval?
            }
            
            let decoded = try JSONDecoder().decode(ServerHealthResponse.self, from: data)
            
            await MainActor.run {
                self.passanteTunnelHealthMessage = decoded.healthMessage
                self.passanteTunnelHealthColor = decoded.healthColor
                self.passanteTunnelAverageDelay = decoded.averageDelay
                self.passanteTunnelWestHealthMessage = decoded.westMessage
                self.passanteTunnelWestHealthColor = decoded.westColor
                self.passanteTunnelEastHealthMessage = decoded.eastMessage
                self.passanteTunnelEastHealthColor = decoded.eastColor
                self.passanteSelectedLinesAlerts = decoded.alerts
                if let serverTimestamp = decoded.lastUpdatedTimestamp {
                    self.passanteLastUpdatedTimestamp = serverTimestamp
                }
                
                if includePositions {
                    self.passanteLiveStatuses = decoded.statuses ?? [:]
                    if let sTrains = decoded.stuckTrains {
                        self.serverStuckTrains = sTrains
                    }
                    self.isUsingLocalEngine = false
                }
                self.isServerHealthOffline = false
            }
        } catch {
            print("Errore caricamento salute passante dal server: \(error)")
            await MainActor.run {
                self.isServerHealthOffline = true
                self.isUsingLocalEngine = true
            }
        }
    }
    
    private func isRogoredoDestination(_ dest: String) -> Bool {
        let d = dest.lowercased()
        return d.contains("rogoredo") || d.contains("lodi") ||
               d.contains("pavia") || d.contains("melegnano") ||
               d.contains("locate") || d.contains("borgolombardo") ||
               d.contains("s.donato") || d.contains("san donato") ||
               d.contains("cremona") || d.contains("piacenza") ||
               d.contains("mantova") || d.contains("s.giuliano") ||
               d.contains("san giuliano")
    }
    
    private func isBovisaDestination(_ dest: String) -> Bool {
        let d = dest.lowercased()
        return d.contains("bovisa") || d.contains("saronno") ||
               d.contains("mariano") || d.contains("como") ||
               d.contains("camnago") || d.contains("chiasso") ||
               d.contains("cormano") || d.contains("domodossola") ||
               d.contains("garbagnate") || d.contains("seveso") ||
               d.contains("cesano") || d.contains("cogliate") ||
               d.contains("meda") || d.contains("cabiate") ||
               d.contains("seregno") || d.contains("canzo") ||
               d.contains("asso") || d.contains("calolziocorte") ||
               d.contains("molteno") || d.contains("lecco")
    }
    
    private func isForlaniniDestination(_ dest: String) -> Bool {
        let d = dest.lowercased()
        return d.contains("treviglio") || d.contains("pioltello") ||
               d.contains("segrate") || d.contains("melzo") ||
               d.contains("vignate") || d.contains("pozzuolo") ||
               (d.contains("forlanini") && !d.contains("rogoredo"))
    }
    
    private func isRhoDestination(_ dest: String) -> Bool {
        let d = dest.lowercased()
        return d.contains("novara") || d.contains("varese") ||
               d.contains("gallarate") || d.contains("malpensa") ||
               d.contains("rho") || d.contains("certosa") ||
               d.contains("busto") || d.contains("casale")
    }

    var passanteTrainsViaBovisa: [Train] {
        passanteTrains.filter { train in
            let cat = train.category.uppercased()
            let dest = train.destination
            if cat == "S1" || cat == "S2" || cat == "S12" || cat == "S13" {
                return !isRogoredoDestination(dest)
            }
            return isBovisaDestination(dest)
        }
    }
    
    var passanteTrainsViaRho: [Train] {
        passanteTrains.filter { train in
            let cat = train.category.uppercased()
            let dest = train.destination
            if cat == "S5" || cat == "S6" {
                return !isForlaniniDestination(dest)
            }
            return isRhoDestination(dest)
        }
    }
    
    var passanteTrainsViaForlanini: [Train] {
        passanteTrains.filter { train in
            let cat = train.category.uppercased()
            let dest = train.destination
            if cat == "S5" || cat == "S6" {
                return isForlaniniDestination(dest)
            }
            return isForlaniniDestination(dest)
        }
    }
    
    var passanteTrainsViaRogoredo: [Train] {
        passanteTrains.filter { train in
            let cat = train.category.uppercased()
            let dest = train.destination
            if cat == "S1" || cat == "S2" || cat == "S12" || cat == "S13" {
                return isRogoredoDestination(dest)
            }
            return isRogoredoDestination(dest)
        }
    }
    
    func getPassanteBranch(for train: Train) -> String? {
        let cat = train.category.uppercased()
        let dest = train.destination
        
        if cat == "S1" || cat == "S2" || cat == "S12" || cat == "S13" {
            return isRogoredoDestination(dest) ? "Rogoredo" : "Bovisa"
        } else if cat == "S5" || cat == "S6" {
            return isForlaniniDestination(dest) ? "Forlanini" : "Rho"
        }
        return nil
    }
    
    func isCentralPassanteStation(_ stationName: String) -> Bool {
        let name = stationName.lowercased()
        let centralStations = [
            "villapizzone", "porta garibaldi", "garibaldi",
            "repubblica", "porta venezia", "venezia", "dateo", "porta vittoria", "vittoria"
        ]
        return centralStations.contains { name.contains($0) }
    }
    
    func isPassanteDirectionalStation(_ stationName: String) -> Bool {
        if !useSpecialPassanteView { return false }
        
        let name = stationName.lowercased()
        
        if name == "milano porta garibaldi" {
            return false
        }
        
        let passanteStations = [
            "lancetti",
            "garibaldi sotterranea", "garibaldi passante",
            "repubblica", "porta venezia", "venezia", "dateo", "porta vittoria", "vittoria"
        ]
        return passanteStations.contains { name.contains($0) }
    }
    
    func getPassanteDirection(for train: Train) -> String? {
        guard let branch = getPassanteBranch(for: train) else { return nil }
        if branch == "Bovisa" || branch == "Rho" {
            return "Ovest"
        } else if branch == "Rogoredo" || branch == "Forlanini" {
            return "Est"
        }
        return nil
    }
    
    func resolvedPlatform(for stationName: String, train: Train) -> String {
        // I binari non vengono MAI manipolati. Si usa sempre il binario reale ricevuto da RFI.
        return train.platform
    }


    var passanteTrainsWestbound: [Train] { passanteTrainsViaBovisa + passanteTrainsViaRho }
    var passanteTrainsEastbound: [Train] { passanteTrainsViaForlanini + passanteTrainsViaRogoredo }

    static let tunnelLineIDs: Set<String> = ["S1", "S2", "S3", "S4", "S5", "S6", "S12", "S13"]
    
    var userUsesTunnel: Bool {
        selectedSuburbanLines.contains { PassanteManager.tunnelLineIDs.contains($0) }
    }
    
    
    func toggleSuburbanLine(_ id: String) {
        if selectedSuburbanLines.contains(id) {
            selectedSuburbanLines.removeAll { $0 == id }
        } else {
            selectedSuburbanLines.append(id)
        }
        save()
    }
    
    func toggleHiddenStation(lineId: String, stationName: String) {
        var hiddenForLine = hiddenSuburbanStations[lineId] ?? []
        if hiddenForLine.contains(stationName) {
            hiddenForLine.removeAll { $0 == stationName }
        } else {
            hiddenForLine.append(stationName)
        }
        hiddenSuburbanStations[lineId] = hiddenForLine
        save()
    }

    var passanteStationsForUser: [Station] {
        let selectedLines = SuburbanData.shared.allLines.filter { selectedSuburbanLines.contains($0.id) }
        let source = selectedLines.isEmpty ? SuburbanData.shared.allLines : selectedLines
        var seen = Set<String>()
        return source.flatMap { $0.stations }.filter { seen.insert($0.name).inserted }
    }
}
