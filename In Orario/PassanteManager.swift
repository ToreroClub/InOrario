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
    @Published var favoriteSuburbanStations: [String] = [] {
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
    private(set) var isTunnelDetailOpen: Bool = false
    var lastLocalUpdateTimestamp: TimeInterval = 0
    private var lastLocalAverageDelay: Int = 0
    private var inFlightFetchTask: Task<Bool, Never>?
    private var tunnelDetailFetchTask: Task<Bool, Never>?
    private var activeTunnelDetailTaskID = UUID()
    private var lastPassanteFetchTimestamp: TimeInterval = 0
    private var pendingRefreshNeeds: (force: Bool, includePositions: Bool)?
    
    @Published var passanteTunnelWestHealthMessage: String = "Ovest: Regolare"
    @Published var passanteTunnelWestHealthColor: String = "#009640"
    @Published var passanteTunnelEastHealthMessage: String = "Est: Regolare"
    @Published var passanteTunnelEastHealthColor: String = "#009640"
    @Published var passanteTunnelTrains: [Train] = []
    
    private let selectedSuburbanLinesKey = "selectedSuburbanLines_v1"
    private let hiddenSuburbanStationsKey = "hiddenSuburbanStations_v1"
    private let favoriteSuburbanStationsKey = "favoriteSuburbanStations_v1"
    private let selectedPassanteStationKey = "selectedPassanteStation_v1"
    
    init() {
        let selectedLinesData = UserDefaults.standard.data(forKey: selectedSuburbanLinesKey)
        let decodedLines = selectedLinesData.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        self._selectedSuburbanLines = Published(initialValue: decodedLines)
        
        let hiddenStationsData = UserDefaults.standard.data(forKey: hiddenSuburbanStationsKey)
        let decodedHidden = hiddenStationsData.flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
        self._hiddenSuburbanStations = Published(initialValue: decodedHidden)
        
        let favoriteStationsData = UserDefaults.standard.data(forKey: favoriteSuburbanStationsKey)
        let decodedFavorites = favoriteStationsData.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        self._favoriteSuburbanStations = Published(initialValue: decodedFavorites)
        
        let selectedStationData = UserDefaults.standard.data(forKey: selectedPassanteStationKey)
        let decodedStation = selectedStationData.flatMap { try? JSONDecoder().decode(Station.self, from: $0) } ?? Station(name: "Porta Venezia", rfiID: "1723", vtID: "S01649", lat: 45.4746, lon: 9.2052)
        self._selectedPassanteStation = Published(initialValue: decodedStation)
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(selectedSuburbanLines) { UserDefaults.standard.set(data, forKey: selectedSuburbanLinesKey) }
        if let data = try? JSONEncoder().encode(hiddenSuburbanStations) { UserDefaults.standard.set(data, forKey: hiddenSuburbanStationsKey) }
        if let data = try? JSONEncoder().encode(favoriteSuburbanStations) { UserDefaults.standard.set(data, forKey: favoriteSuburbanStationsKey) }
        if let data = try? JSONEncoder().encode(selectedPassanteStation) { UserDefaults.standard.set(data, forKey: selectedPassanteStationKey) }
    }

    func selectPassanteStation(_ station: Station, manager: TrainManager) {
        self.selectedPassanteStation = station
        save()
        Task {
            await fetchPassanteLive(manager: manager, force: true)
        }
    }
    
    func setTunnelDetailOpen(_ isOpen: Bool) {
        self.isTunnelDetailOpen = isOpen
        if !isOpen {
            self.activeTunnelDetailTaskID = UUID()
            self.tunnelDetailFetchTask?.cancel()
            self.tunnelDetailFetchTask = nil
            if self.isLocalUpdating {
                self.isLocalUpdating = false
            }
        }
    }

    @discardableResult
    func fetchPassanteLive(manager: TrainManager, includePositions: Bool = false, force: Bool = false) async -> Bool {
        let now = Date().timeIntervalSince1970
        if !force && (now - lastPassanteFetchTimestamp < 15.0) {
            return true
        }
        
        if let ongoing = inFlightFetchTask {
            if force || includePositions {
                let existing = pendingRefreshNeeds ?? (force: false, includePositions: false)
                pendingRefreshNeeds = (force: existing.force || force, includePositions: existing.includePositions || includePositions)
            }
            return await ongoing.value
        }
        
        let task = Task { [weak self] () -> Bool in
            guard let self = self else { return false }
            self.isLoadingPassanteBoard = true
            defer {
                self.isLoadingPassanteBoard = false
                self.inFlightFetchTask = nil
                self.pendingRefreshNeeds = nil
            }
            
            var currentIncludePositions = includePositions
            var overallSuccess = false
            
            while true {
                var cycleSuccess = false
                let shouldIncludePositions = currentIncludePositions && self.isTunnelDetailOpen
                
                async let trainsTask = manager.fetchTrainsForStation(station: self.selectedPassanteStation)
                async let healthTask = self.fetchTunnelHealth(manager: manager, includePositions: shouldIncludePositions)
                let (trainsFetched, healthSuccess) = await (trainsTask, healthTask)
                guard !Task.isCancelled else { return false }
                
                if !trainsFetched.isEmpty {
                    if self.passanteTrains != trainsFetched {
                        self.passanteTrains = trainsFetched
                    }
                    cycleSuccess = true
                }
                if healthSuccess {
                    cycleSuccess = true
                }
                
                // Only update cooldown timestamp when at least one valid response was obtained
                if cycleSuccess {
                    overallSuccess = true
                    self.lastPassanteFetchTimestamp = Date().timeIntervalSince1970
                }
                
                // If another caller requested a forced or position-bearing refresh while we were running, run another pass
                if let pending = self.pendingRefreshNeeds {
                    self.pendingRefreshNeeds = nil
                    currentIncludePositions = pending.includePositions
                } else {
                    break
                }
            }
            return overallSuccess
        }
        inFlightFetchTask = task
        return await task.value
    }
    
    @discardableResult
    func fetchTunnelDetailData(manager: TrainManager, force: Bool = false) async -> Bool {
        guard isTunnelDetailOpen else { return false }
        if let ongoing = tunnelDetailFetchTask, !force {
            return await withTaskCancellationHandler {
                await ongoing.value
            } onCancel: {
                ongoing.cancel()
            }
        }
        if force {
            tunnelDetailFetchTask?.cancel()
        }
        let taskID = UUID()
        self.activeTunnelDetailTaskID = taskID
        
        let task = Task<Bool, Never> { [weak self] in
            guard let self = self else { return false }
            defer {
                if self.activeTunnelDetailTaskID == taskID {
                    self.tunnelDetailFetchTask = nil
                }
            }
            guard self.isTunnelDetailOpen, !Task.isCancelled else { return false }
            async let healthTask = self.fetchTunnelHealth(manager: manager, includePositions: true)
            async let localTask = self.fetchAllPassanteTrains(manager: manager, force: force)
            let (healthSuccess, localSuccess) = await (healthTask, localTask)
            
            guard self.isTunnelDetailOpen, !Task.isCancelled else { return false }
            if !healthSuccess && localSuccess && self.isServerHealthOffline {
                self.applyLocalEngineHealthFallback(avgDelay: self.lastLocalAverageDelay)
            }
            return healthSuccess || localSuccess
        }
        self.tunnelDetailFetchTask = task
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
    
    func forceLocalUpdate(manager: TrainManager) async {
        guard isTunnelDetailOpen else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastLocalUpdateTimestamp >= 10 else { return }
        self.lastLocalUpdateTimestamp = now
        
        _ = await fetchTunnelDetailData(manager: manager, force: true)
    }
    
    @discardableResult
    func fetchAllPassanteTrains(manager: TrainManager, force: Bool = false) async -> Bool {
        guard isTunnelDetailOpen, !Task.isCancelled else { return false }
        let now = Date().timeIntervalSince1970
        if !force && !passanteTunnelTrains.isEmpty {
            // Rate limit: avoid hammering ViaggiaTreno on rapid close/reopen within 15 seconds
            guard now - lastLocalUpdateTimestamp >= 15.0 else { return true }
        }
        
        let venezia = Station(name: "Milano Porta Venezia", rfiID: nil, vtID: "S01649", lat: 45.4746, lon: 9.2052)
        let repubblica = Station(name: "Milano Repubblica", rfiID: nil, vtID: "S01648", lat: 45.4795, lon: 9.1963)
        let lancetti = Station(name: "Milano Lancetti", rfiID: nil, vtID: "S01643", lat: 45.4925, lon: 9.1751)
        
        async let trainsVenezia = manager.fetchTrainsForStation(station: venezia)
        async let trainsRepubblica = manager.fetchTrainsForStation(station: repubblica)
        async let trainsLancetti = manager.fetchTrainsForStation(station: lancetti)
        
        let ven = await trainsVenezia
        let rep = await trainsRepubblica
        let lan = await trainsLancetti
        
        guard isTunnelDetailOpen, !Task.isCancelled else { return false }
        
        let (allTrains, avgDelay) = Self.processPassanteTrains(ven: ven, rep: rep, lan: lan)
        
        guard !allTrains.isEmpty else {
            return false
        }
        self.lastLocalUpdateTimestamp = now
        self.lastLocalAverageDelay = avgDelay
        
        // We fetch live statuses for the 5 sample trains displayed in the detail sheet
        let trainsToFetch = Array(allTrains.prefix(5))
        
        var statuses: [String: TrainStatus] = [:]
        await withTaskGroup(of: (String, TrainStatus)?.self) { group in
            for train in trainsToFetch {
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    let result = await manager.fetchLiveStops(for: train.number, destination: train.destination)
                    guard !Task.isCancelled else { return nil }
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
        
        guard self.isTunnelDetailOpen, !Task.isCancelled else {
            return false
        }
        
        if self.passanteTunnelTrains != allTrains {
            self.passanteTunnelTrains = allTrains
        }
        if !statuses.isEmpty {
            var merged = self.passanteLiveStatuses
            for (num, status) in statuses {
                merged[num] = status
            }
            self.passanteLiveStatuses = merged
        }
        self.passanteLastUpdatedTimestamp = Date().timeIntervalSince1970
        return true
    }

    private func applyLocalEngineHealthFallback(avgDelay: Int) {
        if self.passanteTunnelHealthMessage != "Motore Locale Attivo" {
            self.passanteTunnelHealthMessage = "Motore Locale Attivo"
        }
        if self.passanteTunnelHealthColor != "#007AFF" {
            self.passanteTunnelHealthColor = "#007AFF"
        }
        if self.passanteTunnelWestHealthMessage != "Ovest: Solo Live" {
            self.passanteTunnelWestHealthMessage = "Ovest: Solo Live"
        }
        if self.passanteTunnelWestHealthColor != "#007AFF" {
            self.passanteTunnelWestHealthColor = "#007AFF"
        }
        if self.passanteTunnelEastHealthMessage != "Est: Solo Live" {
            self.passanteTunnelEastHealthMessage = "Est: Solo Live"
        }
        if self.passanteTunnelEastHealthColor != "#007AFF" {
            self.passanteTunnelEastHealthColor = "#007AFF"
        }
        if self.passanteTunnelAverageDelay != avgDelay {
            self.passanteTunnelAverageDelay = avgDelay
        }
        if !self.passanteSelectedLinesAlerts.isEmpty {
            self.passanteSelectedLinesAlerts = []
        }
        if !self.serverStuckTrains.isEmpty {
            self.serverStuckTrains = []
        }
    }
    
    struct ServerHealthResponse: Codable, Sendable {
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
    
    nonisolated static func decodeHealthResponse(from data: Data) throws -> ServerHealthResponse {
        do {
            return try JSONDecoder().decode(ServerHealthResponse.self, from: data)
        } catch {
            AppLogger.decodingError(context: "PassanteHealthResponse", error: error)
            throw error
        }
    }
    
    nonisolated static func processPassanteTrains(ven: [Train], rep: [Train], lan: [Train]) -> (allTrains: [Train], avgDelay: Int) {
        var allTrains: [Train] = []
        var existingNumbers = Set<String>()
        
        let sources: [(station: String, trains: [Train])] = [
            ("Porta Venezia", ven),
            ("Repubblica", rep),
            ("Lancetti", lan)
        ].sorted(by: { $0.trains.count > $1.trains.count })
        
        for source in sources {
            for t in source.trains {
                if !existingNumbers.contains(t.number) {
                    let resolvedOrigin = (t.origin?.isEmpty == false) ? t.origin : source.station
                    let taggedTrain = Train(
                        category: t.category,
                        number: t.number,
                        destination: t.destination,
                        time: t.time,
                        delay: t.delay,
                        platform: t.platform,
                        isDelayUncertain: t.isDelayUncertain,
                        origin: resolvedOrigin
                    )
                    allTrains.append(taggedTrain)
                    existingNumbers.insert(t.number)
                }
            }
        }
        
        var validDelays: [Int] = []
        for t in allTrains.prefix(7) {
            let delayStr = t.delay.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "R: ", with: "")
            let isCancelled = t.delay.lowercased().contains("soppresso") || t.delay.lowercased().contains("cancellato")
            if !isCancelled {
                let d = delayStr.lowercased().contains("orario") ? 0 : (Int(delayStr) ?? 0)
                validDelays.append(d)
            }
        }
        let avgDelay = validDelays.isEmpty ? 0 : (validDelays.reduce(0, +) / validDelays.count)
        return (allTrains, avgDelay)
    }
    
    @discardableResult
    func fetchTunnelHealth(manager: TrainManager, includePositions: Bool = false) async -> Bool {
        let linesParam = selectedSuburbanLines.joined(separator: ",")
        let urlString = "https://gestioneinorario.toreroclub.com/passante/health" + 
                        "?include_positions=\(includePositions)" + 
                        (linesParam.isEmpty ? "" : "&lines=\(linesParam)")
        
        guard let url = URL(string: urlString) else { return false }
        do {
            let (data, _) = try await NetworkService.shared.get(url: url)
            guard !Task.isCancelled else { return false }
            let decoded = try Self.decodeHealthResponse(from: data)
            
            let newHealthMessage = Self.sanitizePassanteMessage(decoded.healthMessage)
            let newWestMessage = Self.sanitizePassanteMessage(decoded.westMessage)
            let newEastMessage = Self.sanitizePassanteMessage(decoded.eastMessage)
            
            if self.passanteTunnelHealthMessage != newHealthMessage {
                self.passanteTunnelHealthMessage = newHealthMessage
            }
            if self.passanteTunnelHealthColor != decoded.healthColor {
                self.passanteTunnelHealthColor = decoded.healthColor
            }
            if self.passanteTunnelAverageDelay != decoded.averageDelay {
                self.passanteTunnelAverageDelay = decoded.averageDelay
            }
            if self.passanteTunnelWestHealthMessage != newWestMessage {
                self.passanteTunnelWestHealthMessage = newWestMessage
            }
            if self.passanteTunnelWestHealthColor != decoded.westColor {
                self.passanteTunnelWestHealthColor = decoded.westColor
            }
            if self.passanteTunnelEastHealthMessage != newEastMessage {
                self.passanteTunnelEastHealthMessage = newEastMessage
            }
            if self.passanteTunnelEastHealthColor != decoded.eastColor {
                self.passanteTunnelEastHealthColor = decoded.eastColor
            }
            if self.passanteSelectedLinesAlerts != decoded.alerts {
                self.passanteSelectedLinesAlerts = decoded.alerts
            }
            if let serverTimestamp = decoded.lastUpdatedTimestamp,
               self.passanteLastUpdatedTimestamp != serverTimestamp {
                self.passanteLastUpdatedTimestamp = serverTimestamp
            }
            
            if includePositions {
                if let serverStatuses = decoded.statuses, !serverStatuses.isEmpty {
                    var merged = self.passanteLiveStatuses
                    for (num, serverStatus) in serverStatuses {
                        if let existing = merged[num],
                           !existing.lastStation.isEmpty,
                           existing.lastStation != "--" {
                            continue
                        }
                        merged[num] = serverStatus
                    }
                    self.passanteLiveStatuses = merged
                }
                if let sTrains = decoded.stuckTrains,
                   !(self.serverStuckTrains.isEmpty && sTrains.isEmpty) {
                    self.serverStuckTrains = sTrains
                }
                if self.isUsingLocalEngine {
                    self.isUsingLocalEngine = false
                }
            }
            if self.isServerHealthOffline {
                self.isServerHealthOffline = false
            }
            return true
        } catch {
            if error is CancellationError || (error as? AppNetworkError) == .cancelled || Task.isCancelled {
                return false
            }
            AppLogger.refreshFailed(target: "PassanteTunnelHealth", error: error)
            if !self.isServerHealthOffline {
                self.isServerHealthOffline = true
            }
            if !self.isUsingLocalEngine {
                self.isUsingLocalEngine = true
            }
            return false
        }
    }
    
    nonisolated static func sanitizePassanteMessage(_ message: String) -> String {
        var msg = message
        if msg.contains("Rischio Accodamento") || msg.contains("Tunnel Congestionato") || msg.contains("Congestionato") {
            return "Circolazione Rallentata"
        }
        msg = msg.replacingOccurrences(of: " nel Tunnel", with: "")
        msg = msg.replacingOccurrences(of: " nel tratto", with: "")
        msg = msg.replacingOccurrences(of: "compromessa", with: "fortemente rallentata")
        return msg
    }
    
    private func isRogoredoDestination(_ dest: String) -> Bool {
        let d = dest.lowercased()
        return d.contains("rogoredo") || d.contains("lodi") ||
               d.contains("pavia") || d.contains("melegnano") ||
               d.contains("locate") || d.contains("borgolombardo") ||
               d.contains("s.donato") || d.contains("san donato") ||
               d.contains("cremona") || d.contains("piacenza") ||
               d.contains("mantova") || d.contains("s.giuliano") ||
               d.contains("san giuliano") || d.contains("tavazzano") ||
               d.contains("pieve emanuele") || d.contains("villamaggiore") ||
               d.contains("certosa di pavia") || d.contains("voghera") ||
               d.contains("stradella") || d.contains("alessandria")
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
               d.contains("molteno") || d.contains("lecco") ||
               d.contains("novate") || d.contains("bollate") ||
               d.contains("cesate") || d.contains("caronno") ||
               d.contains("quarto oggiaro") || d.contains("bruzzano") ||
               d.contains("paderno") || d.contains("palazzolo") ||
               d.contains("varedo") || d.contains("bovisio") ||
               d.contains("cusano")
    }
    
    private func isForlaniniDestination(_ dest: String) -> Bool {
        let d = dest.lowercased()
        return d.contains("treviglio") || d.contains("pioltello") ||
               d.contains("segrate") || d.contains("melzo") ||
               d.contains("vignate") || d.contains("pozzuolo") ||
               d.contains("trecella") || d.contains("cassano") ||
               d.contains("brescia") || d.contains("bergamo") ||
               d.contains("verona") || d.contains("porta vittoria") ||
               d.contains("p. vittoria") ||
               (d.contains("forlanini") && !d.contains("rogoredo"))
    }
    
    private func isRhoDestination(_ dest: String) -> Bool {
        let d = dest.lowercased()
        return d.contains("novara") || d.contains("varese") ||
               d.contains("gallarate") || d.contains("malpensa") ||
               d.contains("rho") || (d.contains("certosa") && !d.contains("pavia")) ||
               d.contains("busto") || d.contains("casale") ||
               d.contains("magenta") || d.contains("trecate") ||
               d.contains("vittuone") || d.contains("corbetta") ||
               d.contains("pregnana") || d.contains("legnano") ||
               d.contains("parabiago") || d.contains("canegrate") ||
               d.contains("vanzago") || d.contains("villapizzone") ||
               d.contains("lancetti") || d.contains("arona") ||
               d.contains("luino") || d.contains("porto ceresio") ||
               d.contains("gazzada") || d.contains("castronno") ||
               d.contains("albizzate") || d.contains("cavaria")
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
        } else {
            if isRogoredoDestination(dest) { return "Rogoredo" }
            if isForlaniniDestination(dest) { return "Forlanini" }
            if isRhoDestination(dest) { return "Rho" }
            if isBovisaDestination(dest) { return "Bovisa" }
        }
        return nil
    }
    
    func isCentralPassanteStation(_ stationName: String) -> Bool {
        let name = stationName.lowercased()
        if name.contains("superficie") { return false }
        // I badge di ingresso/uscita (Bovisa, Rho, Rogoredo, Forlanini) vanno mostrati
        // SOLO nelle stazioni del tratto sotterraneo del Passante:
        // Lancetti · Garibaldi Passante · Repubblica · Porta Venezia · Dateo · Porta Vittoria
        // NON a Villapizzone (fuori tunnel) né al tabellone superficie di Garibaldi.
        let tunnelStations = [
            "lancetti",
            "garibaldi passante", "garibaldi sotterranea", "p. garibaldi passante",
            "repubblica",
            "porta venezia",
            "dateo",
            "porta vittoria"
        ]
        return tunnelStations.contains { name.contains($0) }
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
    
    func isTrain(_ train: Train, belongingToLine lineId: String) -> Bool {
        let cat = train.category.uppercased()
        let lid = lineId.uppercased()
        if cat == lid { return true }
        
        if cat == "SUB" || cat == "REG" || cat == "RV" {
            let d = train.destination.lowercased()
            if lid == "S5" && (d.contains("varese") || d.contains("treviglio") || d.contains("gallarate")) { return true }
            if lid == "S6" && (d.contains("novara") || d.contains("pioltello") || d.contains("magenta") || d.contains("rho")) { return true }
            if lid == "S1" && (d.contains("lodi") || d.contains("saronno")) { return true }
            if lid == "S2" && (d.contains("mariano") || d.contains("seveso") || (d.contains("rogoredo") && !d.contains("lodi"))) { return true }
            if lid == "S12" && (d.contains("melegnano") || d.contains("cormano")) { return true }
            if lid == "S13" && (d.contains("pavia") || d.contains("garbagnate") || d.contains("bovisa")) { return true }
            if lid == "S3" && (d.contains("saronno") || d.contains("cadorna")) { return true }
            if lid == "S4" && (d.contains("camnago") || d.contains("cadorna")) { return true }
            if lid == "S8" && (d.contains("lecco") || d.contains("garibaldi")) { return true }
            if lid == "S9" && (d.contains("saronno") || d.contains("albairate")) { return true }
            if lid == "S11" && (d.contains("chiasso") || d.contains("como") || d.contains("cantu") || d.contains("cantù") || d.contains("seregno") || d.contains("rho")) { return true }
        }
        return false
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

    func isFavoriteSuburbanStation(_ stationName: String) -> Bool {
        favoriteSuburbanStations.contains { $0.localizedCaseInsensitiveCompare(stationName) == .orderedSame }
    }
    
    func toggleFavoriteSuburbanStation(_ stationName: String) {
        if let idx = favoriteSuburbanStations.firstIndex(where: { $0.localizedCaseInsensitiveCompare(stationName) == .orderedSame }) {
            favoriteSuburbanStations.remove(at: idx)
        } else {
            favoriteSuburbanStations.append(stationName)
        }
        save()
    }

    var passanteStationsForUser: [Station] {
        let selectedLines = SuburbanData.shared.allLines.filter { selectedSuburbanLines.contains($0.id) }
        let source = selectedLines.isEmpty ? SuburbanData.shared.allLines : selectedLines
        var seen = Set<String>()
        return source.flatMap { $0.stations }.filter { seen.insert($0.name).inserted }
    }
}
