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
    
    @Published var selectedPassanteStation: Station = Station(name: "Porta Venezia", rfiID: "1723", vtID: "S01061", lat: 45.4746, lon: 9.2052) {
        didSet { save() }
    }
    @Published var passanteTrains: [Train] = []
    @Published var isLoadingPassanteBoard = false
    @Published var passanteTunnelHealthMessage: String = "Circolazione Regolare"
    @Published var passanteTunnelHealthColor: String = "#009640"
    @Published var passanteTunnelAverageDelay: Int = 0
    @Published var passanteTunnelTrains: [Train] = []
    @Published var passanteLiveStatuses: [String: TrainStatus] = [:]
    
    @Published var passanteTunnelWestHealthMessage: String = "Ovest: Regolare"
    @Published var passanteTunnelWestHealthColor: String = "#009640"
    @Published var passanteTunnelEastHealthMessage: String = "Est: Regolare"
    @Published var passanteTunnelEastHealthColor: String = "#009640"
    @Published var passanteSelectedLinesAlerts: [String] = []
    
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
        let decodedStation = selectedStationData.flatMap { try? JSONDecoder().decode(Station.self, from: $0) } ?? Station(name: "Porta Venezia", rfiID: "1723", vtID: "S01061", lat: 45.4746, lon: 9.2052)
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
                let statuses: [String: TrainStatus]
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
                
                if includePositions {
                    self.passanteLiveStatuses = decoded.statuses
                }
            }
        } catch {
            print("Errore caricamento salute passante dal server: \(error)")
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
        let name = stationName.lowercased()
        let direction = getPassanteDirection(for: train) ?? "Est"
        let cat = train.category.uppercased()
        
        if name.contains("rho fiera") {
            return direction == "Ovest" ? "1" : "2"
        }
        if name.contains("certosa") {
            return direction == "Est" ? "5" : "6"
        }
        if name.contains("villapizzone") {
            return direction == "Ovest" ? "1" : "2"
        }
        if name.contains("lancetti") {
            if direction == "Est" {
                return (cat == "S5" || cat == "S6") ? "1" : "2"
            } else {
                return (cat == "S5" || cat == "S6") ? "3" : "4"
            }
        }
        if name.contains("garibaldi") {
            return direction == "Est" ? "1" : "2"
        }
        if name.contains("repubblica") {
            return direction == "Est" ? "1" : "2"
        }
        if name.contains("venezia") || name.contains("porta venezia") {
            return direction == "Est" ? "1" : "2"
        }
        if name.contains("dateo") {
            return direction == "Est" ? "1" : "2"
        }
        if name.contains("vittoria") || name.contains("porta vittoria") {
            if direction == "Est" {
                return (cat == "S5" || cat == "S6") ? "3" : "4"
            } else {
                return (cat == "S5" || cat == "S6") ? "1" : "2"
            }
        }
        if name.contains("forlanini") {
            if cat == "S9" {
                return direction == "Est" ? "3" : "4"
            } else {
                return direction == "Est" ? "1" : "2"
            }
        }
        
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
