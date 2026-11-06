import SwiftUI
import Combine
import Foundation
import CoreLocation
import ActivityKit
import StoreKit
import CoreSpotlight
import UniformTypeIdentifiers
import WidgetKit

struct Haptics {
    static func play(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}



@MainActor class TrainManager: ObservableObject {
    var isInitializing = true
    
    @Published var remoteNotificationsEnabled: Bool = false
    @Published var notifyOnStationPass: Bool = false
    @Published var strikeRegion: String = "Tutte" {
        didSet {
            guard !isInitializing else { return }
            saveFavorites()
            syncRemoteNotifications()
        }
    }
    @Published var strikeNotificationsEnabled: Bool = true {
        didSet {
            guard !isInitializing else { return }
            saveFavorites()
            syncRemoteNotifications()
        }
    }
    @Published var apnsToken: String? = nil {
        didSet {
            guard apnsToken != oldValue else { return }
            guard !isInitializing else { return }
            if let token = apnsToken, !token.isEmpty {
                UserDefaults.standard.set(token, forKey: apnsTokenKey)
                syncRemoteNotifications()
                syncLiveActivities()
            }
        }
    }
    @Published var notificationLimitError: String? = nil
    @Published var showPaywallSheet: Bool = false
    
    private let remoteNotificationsEnabledKey = "remoteNotificationsEnabled_v1"
    private let notifyOnStationPassKey = "notifyOnStationPass_v1"
    private let strikeRegionKey = "strikeRegion_v1"
    private let strikeNotificationsEnabledKey = "strikeNotificationsEnabled_v1"
    private let apnsTokenKey = "apnsTokenKey_v1"
    private var lastSyncedSignature: String = ""
    private var inFlightSyncSignature: String? = nil
    private var syncDebounceTask: Task<Void, Never>? = nil

    @Published var trains: [Train] = []
    @Published var selectedTrainStops: [Stop] = []
    @Published var favoriteTrainsStops: [String: [Stop]] = [:]
    @Published var currentTrainStatus: TrainStatus = TrainStatus()
    @Published var favoriteTrains: [SavedTrain] = []
    @Published var myStations: [Station] = []
    @Published var searchResults: [SavedTrain] = []
    @Published var searchStationResults: [VTSearchStation] = []
    @Published var searchTrenitaliaLocations: [TrenitaliaLocation] = []
    @Published var rfiStationDictionary: [String: String] = [:]
    @Published var rfiStationNormalizedDict: [String: String] = [:]
    @Published var vtStationDictionary: [String: String] = [:]
    @Published var vtStationNormalizedDict: [String: String] = [:]
    @Published var searchRFIStationResults: [RFIStation] = []
    @Published var allRFIStations: [RFIStation] = []
    @Published var sectionOrder: [AppSection] = AppSection.allCases
    @Published var isSearching: Bool = false
    @Published var isLoading = false
    @Published var isStopsLoading = false
    @Published var stopErrorMessage: String? = nil
    @Published var deepLinkTrain: Train? = nil
    @Published var deepLinkStation: Station? = nil
    @Published var lastFetchedStationKey: String = ""
    
    @Published var stationAlerts: String? = nil
    @Published var activeLiveActivities: Set<String> = []
    @Published var currentTrainReports: [String: Int] = ["crowded": 0, "hot": 0, "cold": 0, "stopped": 0]
    @Published var currentTrainBlockedLocations: [String] = []
    
    @Published var travelSolutions: [TravelSolution] = []
    @Published var favoriteRoutes: [FavoriteRoute] = []
    @Published var savedTrips: [SavedTrip] = []
    @Published var isSearchingSolutions: Bool = false
    
    @Published var smartRoutes: [SuburbanRoute] = []
    
    @Published var loadedSmartRouteDetails: [String: SmartRouteDetails] = [:]
    @Published var isLoadingSmartRoutes = false
    @Published var homeDestinationStationName: String = ""
    @Published var isHomeFilterActive: Bool = false
    @Published var recentTrains: [SavedTrain] = []
    @Published var recentStations: [VTSearchStation] = []
    @Published var viewedRecentTrains: [SavedTrain] = []
    @Published var viewedRecentStations: [VTSearchStation] = []
    
    private let viewedRecentTrainsKey = "viewedRecentTrains_v2"
    private let viewedRecentStationsKey = "viewedRecentStations_v2"
    
    @Published var userName: String = ""
    @Published var iCloudSyncEnabled: Bool = true
    
    private var refreshTimer: AnyCancellable?
    
    private let favoritesKey = "savedFavoriteTrains_v3"
    private let myStationsKey = "savedMyStations_v3"
    private let sectionOrderKey = "savedSectionOrder_v3"
    private let favoriteRoutesKey = "savedFavoriteRoutes_v1"
    private let savedTripsKey = "savedTrips_v1"
    private let smartRoutesKey = "savedSmartRoutes_v1"
    private let homeDestinationStationNameKey = "homeDestinationStationName_v1"
    private let userNameKey = "userName_v1"
    private let iCloudSyncEnabledKey = "iCloudSyncEnabled_v1"
    private let recentTrainsKey = "recentTrains_v1"
    private let recentStationsKey = "recentStations_v1"
    
    let rfiStationMap: [String: String] = [
        "novara": "1917",
        "trecate": "2909",
        "corbetta-s.stefano ticino": "1174",
        "corbetta": "1174",
        "vittuone arluno": "3119",
        "vittuone": "3119",
        "pregnana milanese": "381",
        "pregnana": "381",
        "rho": "2345",
        "magenta": "1618",
        "rho fiera": "3098",
        "rho fiera milano": "3098",
        "rho fiera - milano": "3098",
        "rho - fiera - milano": "3098",
        "milano porta garibaldi": "1715",
        "milano centrale": "1728"
    ]
    
    var lineHealth: (message: String, color: Color) {
        let totalTrains = trains.count
        if totalTrains == 0 { return ("Dati non disponibili", .gray) }
        
        let isAVOrLongDistance: (Train) -> Bool = { train in
            let cat = train.category.uppercased()
            let dest = train.destination.uppercased()
            return cat.contains("FR") || cat.contains("FA") || cat.contains("FB") ||
                   cat.contains("AV") || cat.contains("EC") || cat.contains("IC") ||
                   cat.contains("ITALO") || cat.contains("FRECCIA") ||
                   cat == "NTV" || cat == "EXP" || cat == "ES" ||
                   dest.contains("ITALO") || dest.contains("FRECCIAROSSA")
        }
        
        let regTrains = trains.filter { !isAVOrLongDistance($0) }
        
        let regCritical = regTrains.filter { train in
            let isCancelled = train.delay.lowercased().contains("soppresso") || train.delay.lowercased().contains("cancellato")
            if isCancelled { return true }
            let delayStr = train.delay.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "'", with: "")
            let delayMin = Int(delayStr) ?? 0
            return delayMin >= 20
        }
        
        let regDelayed = regTrains.filter { train in
            let isCancelled = train.delay.lowercased().contains("soppresso") || train.delay.lowercased().contains("cancellato")
            if isCancelled { return false }
            let delayStr = train.delay.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "'", with: "")
            let delayMin = Int(delayStr) ?? 0
            return delayMin >= 10 && delayMin < 20
        }
        
        let avTrains = trains.filter { isAVOrLongDistance($0) }
        
        let avCritical = avTrains.filter { train in
            let isCancelled = train.delay.lowercased().contains("soppresso") || train.delay.lowercased().contains("cancellato")
            if isCancelled { return true }
            let delayStr = train.delay.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "'", with: "")
            let delayMin = Int(delayStr) ?? 0
            return delayMin >= 30
        }
        
        let avDelayed = avTrains.filter { train in
            let isCancelled = train.delay.lowercased().contains("soppresso") || train.delay.lowercased().contains("cancellato")
            if isCancelled { return false }
            let delayStr = train.delay.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "'", with: "")
            let delayMin = Int(delayStr) ?? 0
            return delayMin >= 15 && delayMin < 30
        }
        
        
        if !regCritical.isEmpty {
            let directions = getUniqueDirections(for: regCritical)
            let hasCancellations = regCritical.contains { $0.delay.lowercased().contains("soppresso") || $0.delay.lowercased().contains("cancellato") }
            if hasCancellations {
                return (directions.isEmpty ? "Soppressioni in corso" : "Soppressioni dir. \(directions)", .red)
            } else {
                return (directions.isEmpty ? "Forti ritardi" : "Forti ritardi dir. \(directions)", .red)
            }
        }
        
        if !avCritical.isEmpty {
            let hasCancellations = avCritical.contains { $0.delay.lowercased().contains("soppresso") || $0.delay.lowercased().contains("cancellato") }
            return (hasCancellations ? "Soppressioni Alta Velocità" : "Forti Ritardi Alta Velocità", .red)
        }
        
        if !regDelayed.isEmpty {
            let directions = getUniqueDirections(for: regDelayed)
            return (directions.isEmpty ? "Rallentamenti" : "Rallentamenti dir. \(directions)", .orange)
        }
        
        if !avDelayed.isEmpty {
            return ("Ritardi Alta Velocità", .orange)
        }
        
        return ("Circolazione Regolare", .green)
    }
    
    private func getUniqueDirections(for trainsList: [Train]) -> String {
        let getCleanDirection: (Train) -> String = { train in
            let dest = train.destination.trimmingCharacters(in: .whitespacesAndNewlines)
            if dest.isEmpty { return "" }
            
            let lower = dest.lowercased()
            if lower.contains("milano") { return "Milano" }
            if lower.contains("torino") { return "Torino" }
            if lower.contains("venezia") { return "Venezia" }
            if lower.contains("roma") { return "Roma" }
            if lower.contains("genova") { return "Genova" }
            if lower.contains("bologna") { return "Bologna" }
            if lower.contains("napoli") { return "Napoli" }
            if lower.contains("verona") { return "Verona" }
            if lower.contains("brescia") { return "Brescia" }
            if lower.contains("varese") { return "Varese" }
            if lower.contains("como") { return "Como" }
            if lower.contains("lecco") { return "Lecco" }
            if lower.contains("novara") { return "Novara" }
            if lower.contains("pavia") { return "Pavia" }
            if lower.contains("cremona") { return "Cremona" }
            if lower.contains("piacenza") { return "Piacenza" }
            
            let parts = dest.split(separator: " ")
            if let first = parts.first { return String(first) }
            return dest
        }
        
        var affectedDirs = Set<String>()
        for t in trainsList {
            let dir = getCleanDirection(t)
            if !dir.isEmpty {
                affectedDirs.insert(dir)
            }
        }
        let sorted = affectedDirs.sorted().prefix(2)
        return sorted.joined(separator: ", ")
    }
    
    init() { 
        loadFavorites()
        // Carica le stazioni RFI in background per non bloccare il main thread all'avvio
        Task { await loadRFIStationsAsync() }
        observeAllLiveActivityPushTokens()
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("PurchasesUpdated"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.syncRemoteNotifications()
            }
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudStoreDidChangeExternally(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        
        isInitializing = false
        
        checkAndAutoEnableNotifications()
        
        if self.remoteNotificationsEnabled {
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        
        loadViewedRecentTrains()
        loadViewedRecentStations()
        checkAndCleanOneShotNotifications()
    }
    
    private func loadRFIStations() {
        if let url = Bundle.main.url(forResource: "rfi_stations", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([RFIStation].self, from: data) {
            self.allRFIStations = decoded
            
            var dict: [String: String] = [:]
            var normDict: [String: String] = [:]
            var vtDict: [String: String] = [:]
            var vtNormDict: [String: String] = [:]
            for station in decoded {
                let lower = station.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let norm = normalizeStationName(station.name)
                if let rfiID = station.rfiID, !rfiID.isEmpty {
                    dict[lower] = rfiID
                    normDict[norm] = rfiID
                }
                if let vtID = station.vtID, !vtID.isEmpty {
                    vtDict[lower] = vtID
                    vtNormDict[norm] = vtID
                }
            }
            self.rfiStationDictionary = dict
            self.rfiStationNormalizedDict = normDict
            self.vtStationDictionary = vtDict
            self.vtStationNormalizedDict = vtNormDict
            self.sanitizeRecentStations()
        }
    }
    
    /// Versione async di loadRFIStations: carica il JSON su un thread in background
    /// e poi aggiorna le proprietà pubblicate sul MainActor, evitando freeze all'avvio.
    private func loadRFIStationsAsync() async {
        guard let url = Bundle.main.url(forResource: "rfi_stations", withExtension: "json") else { return }
        
        // Lettura e parsing su thread in background (nonisolated context di Task.detached)
        let result = await Task.detached(priority: .utility) { () -> ([RFIStation], [String: String], [String: String], [String: String], [String: String])? in
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([RFIStation].self, from: data) else { return nil }
            var dict: [String: String] = [:]
            var normDict: [String: String] = [:]
            var vtDict: [String: String] = [:]
            var vtNormDict: [String: String] = [:]
            
            func normKey(_ s: String) -> String {
                return s.lowercased()
                    .replacingOccurrences(of: "&#39;", with: "'")
                    .replacingOccurrences(of: "&#39", with: "'")
                    .replacingOccurrences(of: "&39;", with: "'")
                    .replacingOccurrences(of: "&39", with: "'")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "p.ta ", with: "porta")
                    .replacingOccurrences(of: "p.ta", with: "porta")
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
                    .replacingOccurrences(of: "`", with: "")
                    .replacingOccurrences(of: ".", with: "")
                    .folding(options: .diacriticInsensitive, locale: .current)
            }
            
            for station in decoded {
                let lower = station.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let norm = normKey(station.name)
                if let rfiID = station.rfiID, !rfiID.isEmpty {
                    dict[lower] = rfiID
                    normDict[norm] = rfiID
                }
                if let vtID = station.vtID, !vtID.isEmpty {
                    vtDict[lower] = vtID
                    vtNormDict[norm] = vtID
                }
            }
            return (decoded, dict, normDict, vtDict, vtNormDict)
        }.value
        
        // Aggiorna le proprietà sul MainActor
        if let (decoded, dict, normDict, vtDict, vtNormDict) = result {
            self.allRFIStations = decoded
            self.rfiStationDictionary = dict
            self.rfiStationNormalizedDict = normDict
            self.vtStationDictionary = vtDict
            self.vtStationNormalizedDict = vtNormDict
            self.sanitizeRecentStations()
        }
    }

    
    func normalizeStationName(_ name: String) -> String {
        return name.lowercased()
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#39", with: "'")
            .replacingOccurrences(of: "&39;", with: "'")
            .replacingOccurrences(of: "&39", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "p.ta ", with: "porta")
            .replacingOccurrences(of: "p.ta", with: "porta")
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
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: ".", with: "")
            .folding(options: .diacriticInsensitive, locale: .current)
    }
    
    func getRfiID(for vtName: String) -> String? {
        let lower = vtName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = rfiStationDictionary[lower] {
            return exact
        }
        let norm = normalizeStationName(vtName)
        return rfiStationNormalizedDict[norm]
    }
    
    func getVtID(for name: String) -> String? {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = vtStationDictionary[lower] {
            return exact
        }
        let norm = normalizeStationName(name)
        return vtStationNormalizedDict[norm]
    }
    
    func resolveStation(name: String, fallbackVtID: String? = nil, fallbackRfiID: String? = nil) -> Station {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let norm = normalizeStationName(name)
        
        let validFallbackVt: String? = {
            guard let fb = fallbackVtID, !fb.isEmpty else { return nil }
            return (fb.hasPrefix("S") || fb.hasPrefix("N")) ? fb : nil
        }()
        
        let validFallbackRfi: String? = {
            guard let fb = fallbackRfiID, !fb.isEmpty else { return nil }
            if fb.hasPrefix("S") || fb.hasPrefix("N") { return nil }
            return fb
        }()
        
        // 1. Risoluzione immediata alias Fiera Milano / Rho Fiera
        if (norm.contains("fiera") && (norm.contains("milano") || norm.contains("rho"))) ||
           (lower.contains("fiera") && (lower.contains("milano") || lower.contains("rho"))) ||
           norm.contains("fieramilano") || lower == "fieramilano" || lower == "fiera milano" {
            return Station(name: "RHO FIERA", rfiID: "3098", vtID: "S01039", lat: 45.521258, lon: 9.088038)
        }
        
        // Risoluzione rapida Sant'Ilario, Forlì, Bianzè
        if lower.contains("ilario") {
            return Station(name: "S.ILARIO D'ENZA", rfiID: "2526", vtID: "S05021", lat: 44.765795, lon: 10.450469)
        }
        if lower == "forli" || lower == "forlì" || lower == "forli'" || lower.contains("forli") {
            if !lower.contains("forlimpopoli") {
                return Station(name: "FORLI'", rfiID: "1350", vtID: "S05059", lat: 44.22413, lon: 12.054871)
            }
        }
        if lower == "bianze" || lower == "bianzè" || lower == "bianze'" || lower.contains("bianze") {
            return Station(name: "BIANZE'", rfiID: "640", vtID: "S00238", lat: 45.309488, lon: 8.115523)
        }
        
        // 2. Risoluzione rapida hub principali e nodi frequenti
        if lower.contains("malpensa") {
            if lower.contains("t2") || lower.contains("terminal 2") {
                return Station(name: "MALPENSA AEROPORTO TERMINAL 2", rfiID: nil, vtID: "S01146", lat: 45.6450, lon: 8.7230)
            }
            return Station(name: "MALPENSA AEROPORTO TERMINAL 1", rfiID: nil, vtID: "S01139", lat: 45.6277, lon: 8.7118)
        }
        
        if lower == "bovisa" || lower == "milano bovisa" || lower == "bovisa politecnico" || lower == "milano bovisa politecnico" {
            return Station(name: "MILANO BOVISA POLITECNICO", rfiID: nil, vtID: "S01642", lat: 45.5019, lon: 9.1627)
        }
        
        if lower == "cadorna" || lower == "milano cadorna" || lower == "cadorna fn" || lower == "milano nord cadorna" {
            return Station(name: "MILANO CADORNA", rfiID: nil, vtID: "S01066", lat: 45.4688, lon: 9.1764)
        }
        
        if lower.contains("garibaldi") {
            if lower.contains("passante") || lower.contains("sotterranea") {
                return Station(name: "MILANO PORTA GARIBALDI SOTTERRANEA", rfiID: "1714", vtID: "S01647", lat: 45.4842, lon: 9.1884)
            } else if !lower.contains("pavia") && !lower.contains("casalecchio") && !lower.contains("napoli") {
                return Station(name: "MILANO PORTA GARIBALDI", rfiID: "1715", vtID: "S01645", lat: 45.4842, lon: 9.1884)
            }
        }
        
        if lower == "centrale" || lower == "milano centrale" || lower == "m.centrale" || lower == "m. centrale" {
            return Station(name: "MILANO CENTRALE", rfiID: "1728", vtID: "S01700", lat: 45.4862, lon: 9.2045)
        }
        
        if lower == "rogoredo" || lower == "milano rogoredo" {
            return Station(name: "MILANO ROGOREDO", rfiID: "1720", vtID: "S01820", lat: 45.4339, lon: 9.2392)
        }
        
        if lower == "lambrate" || lower == "milano lambrate" {
            return Station(name: "MILANO LAMBRATE", rfiID: "1712", vtID: "S01701", lat: 45.4851, lon: 9.2366)
        }
        
        if lower == "greco" || lower == "greco pirelli" || lower == "milano greco" || lower == "milano greco pirelli" {
            return Station(name: "MILANO GRECO PIRELLI", rfiID: "1711", vtID: "S01326", lat: 45.5117, lon: 9.2155)
        }
        
        if lower.contains("cristoforo") && !lower.contains("lago") {
            return Station(name: "MILANO S.CRISTOFORO", rfiID: "1721", vtID: "S01630", lat: 45.4424, lon: 9.1302)
        }
        
        if lower.contains("tibaldi") {
            return Station(name: "MILANO TIBALDI UNIVERSITA' BOCCONI", rfiID: "3251", vtID: "S01022", lat: 45.4448, lon: 9.1918)
        }
        
        if lower.contains("domodossola") && lower.contains("milano") {
            return Station(name: "MILANO DOMODOSSOLA", rfiID: nil, vtID: "S01067", lat: 45.4809, lon: 9.1620)
        }
        
        // Passante Ferroviario di Milano (alias veloci)
        if lower == "porta vittoria" || lower == "p.ta vittoria" || lower == "p. vittoria" {
            return Station(name: "MILANO PORTA VITTORIA", rfiID: "1718", vtID: "S01633", lat: 45.4613, lon: 9.2227)
        }
        if lower == "porta venezia" || lower == "p.ta venezia" || lower == "p. venezia" {
            return Station(name: "MILANO PORTA VENEZIA", rfiID: "1723", vtID: "S01649", lat: 45.4746, lon: 9.2052)
        }
        if lower == "dateo" {
            return Station(name: "MILANO DATEO", rfiID: "3468", vtID: "S01650", lat: 45.4682, lon: 9.2158)
        }
        if lower == "lancetti" {
            return Station(name: "MILANO LANCETTI", rfiID: "1713", vtID: "S01643", lat: 45.4925, lon: 9.1751)
        }
        if lower == "repubblica" {
            return Station(name: "MILANO REPUBBLICA", rfiID: "1719", vtID: "S01648", lat: 45.4795, lon: 9.1963)
        }
        if lower == "villapizzone" {
            return Station(name: "MILANO VILLAPIZZONE", rfiID: "3099", vtID: "S01639", lat: 45.4998, lon: 9.1465)
        }
        if lower == "certosa" || lower == "milano certosa" {
            return Station(name: "MILANO CERTOSA", rfiID: "1708", vtID: "S01640", lat: 45.5085, lon: 9.1272)
        }
        if lower == "forlanini" || lower == "milano forlanini" {
            return Station(name: "MILANO FORLANINI", rfiID: "3169", vtID: "S01492", lat: 45.4625, lon: 9.2368)
        }
        if lower == "romolo" || lower == "milano romolo" {
            return Station(name: "MILANO ROMOLO", rfiID: "58", vtID: "S01032", lat: 45.4436, lon: 9.1678)
        }
        if lower == "bruzzano" || lower.contains("bruzzano") {
            return Station(name: "MILANO BRUZZANO PARCO NORD", rfiID: nil, vtID: "S01079", lat: 45.5262, lon: 9.1762)
        }
        if lower == "affori" || lower == "milano affori" {
            return Station(name: "MILANO AFFORI", rfiID: nil, vtID: "S01078", lat: 45.5208, lon: 9.1685)
        }
        if lower.contains("quarto oggiaro") {
            return Station(name: "MILANO QUARTO OGGIARO", rfiID: nil, vtID: "S01069", lat: 45.5121, lon: 9.1412)
        }
        
        if lower.contains("sesto") && (lower.contains("giovanni") || lower.contains("maggio") || lower.contains("fs")) {
            return Station(name: "SESTO S.GIOVANNI", rfiID: "2716", vtID: "S01325", lat: 45.5417, lon: 9.2384)
        }
        
        if lower.contains("firenze") && (lower.contains("smn") || lower.contains("novella") || lower.contains("s.m.n")) {
            return Station(name: "FIRENZE SANTA MARIA NOVELLA", rfiID: "1325", vtID: "S06421", lat: 43.7765, lon: 11.2479)
        }
        if lower.contains("campo") && lower.contains("marte") {
            return Station(name: "FIRENZE CAMPO MARTE", rfiID: "1312", vtID: "S06900", lat: 43.7768, lon: 11.2770)
        }
        if lower == "rifredi" || lower == "firenze rifredi" {
            return Station(name: "FIRENZE RIFREDI", rfiID: "1315", vtID: "S06420", lat: 43.7981, lon: 11.2372)
        }
        
        if lower.contains("venezia") && (lower.contains("lucia") || lower.contains("s.lucia")) {
            return Station(name: "VENEZIA S.LUCIA", rfiID: "3009", vtID: "S02593", lat: 45.4411, lon: 12.3211)
        }
        
        if lower == "termini" || lower == "roma termini" {
            return Station(name: "ROMA TERMINI", rfiID: "2416", vtID: "S08409", lat: 41.9014, lon: 12.5015)
        }
        if lower == "tiburtina" || lower == "roma tiburtina" {
            return Station(name: "ROMA TIBURTINA", rfiID: "2385", vtID: "S08217", lat: 41.9100, lon: 12.5310)
        }
        if lower == "ostiense" || lower == "roma ostiense" {
            return Station(name: "ROMA OSTIENSE", rfiID: "2379", vtID: "S08406", lat: 41.8722, lon: 12.4842)
        }
        if lower == "tuscolana" || lower == "roma tuscolana" {
            return Station(name: "ROMA TUSCOLANA", rfiID: "2388", vtID: "S08408", lat: 41.8821, lon: 12.5222)
        }
        if lower == "trastevere" || lower == "roma trastevere" {
            return Station(name: "ROMA TRASTEVERE", rfiID: "2387", vtID: "S08405", lat: 41.8725, lon: 12.4661)
        }
        if lower.contains("san pietro") || lower.contains("s.pietro") || lower.contains("s. pietro") {
            if lower.contains("roma") || lower == "san pietro" || lower == "s.pietro" {
                return Station(name: "ROMA S.PIETRO", rfiID: "2383", vtID: "S08323", lat: 41.8978, lon: 12.4542)
            }
        }
        
        if lower == "porta nuova" || lower == "torino porta nuova" || lower == "torino p. nuova" || lower == "torino p.nuova" {
            return Station(name: "TORINO PORTA NUOVA", rfiID: "2876", vtID: "S00219", lat: 45.0622, lon: 7.6784)
        }
        if lower == "porta susa" || lower == "torino porta susa" || lower == "torino p. susa" || lower == "torino p.susa" {
            return Station(name: "TORINO PORTA SUSA", rfiID: "3163", vtID: "S00035", lat: 45.0719, lon: 7.6657)
        }
        if lower == "lingotto" || lower == "torino lingotto" {
            return Station(name: "TORINO LINGOTTO", rfiID: "2855", vtID: "S00452", lat: 45.0272, lon: 7.6606)
        }
        
        if lower.contains("mediopadana") || (lower.contains("reggio") && lower.contains("av")) {
            return Station(name: "REGGIO EMILIA AV MEDIOPADANA", rfiID: "4054", vtID: "S05254", lat: 44.7798, lon: 10.7441)
        }
        if lower.contains("reggio") && lower.contains("calabria") && lower.contains("centrale") {
            return Station(name: "REGGIO DI CALABRIA CENTRALE", rfiID: "116", vtID: "S11781", lat: 38.1038, lon: 15.6358)
        }
        
        if lower.contains("piazza principe") || lower.contains("p.za principe") {
            return Station(name: "GENOVA PIAZZA PRINCIPE", rfiID: "257", vtID: "S04700", lat: 44.4172, lon: 8.9217)
        }
        if lower == "brignole" || lower == "genova brignole" {
            return Station(name: "GENOVA BRIGNOLE", rfiID: "245", vtID: "S04702", lat: 44.4061, lon: 8.9472)
        }
        if lower == "sampierdarena" || lower == "genova sampierdarena" {
            return Station(name: "GENOVA SAMPIERDARENA", rfiID: "263", vtID: "S04220", lat: 44.4139, lon: 8.8953)
        }
        
        if lower == "campi flegrei" || lower == "napoli campi flegrei" {
            return Station(name: "NAPOLI CAMPI FLEGREI", rfiID: "1873", vtID: "S09103", lat: 40.8242, lon: 14.1956)
        }
        if lower == "mergellina" || lower == "napoli mergellina" {
            return Station(name: "NAPOLI MERGELLINA", rfiID: "1876", vtID: "S09105", lat: 40.8306, lon: 14.2208)
        }
        if lower.contains("piazza garibaldi") && (lower.contains("napoli") || lower == "piazza garibaldi") {
            return Station(name: "NAPOLI PIAZZA GARIBALDI", rfiID: "1880", vtID: "S09109", lat: 40.8528, lon: 14.2711)
        }
        if lower == "notarbartolo" || lower == "palermo notarbartolo" {
            return Station(name: "PALERMO NOTARBARTOLO", rfiID: "1992", vtID: "S12134", lat: 38.1333, lon: 13.3444)
        }
        
        // 3. Pulizia prefissi/suffissi urbani comuni aggiunti da Trenitalia/LeFrecce (es. " - Milano", " Milano", " - Roma", etc.)
        let cleanedName = name
            .replacingOccurrences(of: " - Milano", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-Milano", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " Milano", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " - Roma", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-Roma", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " Roma", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " - Torino", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-Torino", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " Torino", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " - Napoli", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-Napoli", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " Napoli", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " - Firenze", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-Firenze", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " Firenze", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedLower = cleanedName.lowercased()
        let cleanedNorm = normalizeStationName(cleanedName)
        
        let cityPrefixes = ["milano", "roma", "torino", "firenze", "napoli", "genova", "bologna", "palermo", "venezia"]
        
        // 4. Ricerca nel catalogo ufficiale RFI (esatta, prefissata da città, o ripulita)
        if let match = allRFIStations.first(where: { st in
            let stLower = st.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let stNorm = normalizeStationName(st.name)
            if stLower == lower || stNorm == norm || stLower == cleanedLower || stNorm == cleanedNorm {
                return true
            }
            for cp in cityPrefixes {
                if stNorm == cp + norm || stNorm == cp + cleanedNorm {
                    return true
                }
            }
            return false
        }) {
            let rfi = (match.rfiID?.isEmpty == false ? match.rfiID : nil) ?? validFallbackRfi
            let vt = (match.vtID?.isEmpty == false ? match.vtID : nil) ?? validFallbackVt
            return Station(name: match.name, rfiID: rfi, vtID: vt, lat: match.lat, lon: match.lon)
        }
        
        let rfi = getRfiID(for: name) ?? getRfiID(for: cleanedName) ?? validFallbackRfi
        let vt = getVtID(for: name) ?? getVtID(for: cleanedName) ?? validFallbackVt
        return Station(name: name, rfiID: rfi, vtID: vt, lat: nil, lon: nil)
    }
    
    func sanitizeRecentStations() {
        var updatedViewed = false
        self.viewedRecentStations = self.viewedRecentStations.map { s in
            let resolved = resolveStation(name: s.nomeLungo, fallbackVtID: s.vtID)
            let newVt = resolved.vtID ?? s.vtID
            if newVt != s.vtID { updatedViewed = true }
            return VTSearchStation(nomeLungo: resolved.name, nomeBreve: resolved.name, vtID: newVt)
        }
        if updatedViewed { saveViewedRecentStations() }
        
        var updatedRecent = false
        self.recentStations = self.recentStations.map { s in
            let resolved = resolveStation(name: s.nomeLungo, fallbackVtID: s.vtID)
            let newVt = resolved.vtID ?? s.vtID
            if newVt != s.vtID { updatedRecent = true }
            return VTSearchStation(nomeLungo: resolved.name, nomeBreve: resolved.name, vtID: newVt)
        }
        if updatedRecent { saveFavorites() }
        
        var updatedMyStations = false
        self.myStations = self.myStations.map { st in
            let cleanRfi = (st.rfiID?.hasPrefix("S") == true || st.rfiID?.hasPrefix("N") == true) ? nil : st.rfiID
            let resolved = resolveStation(name: st.name, fallbackVtID: st.vtID, fallbackRfiID: cleanRfi)
            if resolved.rfiID != st.rfiID || resolved.vtID != st.vtID {
                updatedMyStations = true
            }
            return resolved
        }
        if updatedMyStations { saveFavorites() }
    }
    
    func loadFavorites() {
        // First, restore any missing preferences from iCloud key-value store
        loadFromiCloud(keys: nil, onlyIfLocalMissing: true)
        
        if let data = UserDefaults.standard.data(forKey: recentTrainsKey) {
            do {
                let decoded = try JSONDecoder().decode([SavedTrain].self, from: data)
                self.recentTrains = decoded
            } catch {
                print("recentTrains errore decodifica: \(error)")
            }
        }
        
        if let data = UserDefaults.standard.data(forKey: recentStationsKey) {
            do {
                let decoded = try JSONDecoder().decode([VTSearchStation].self, from: data)
                self.recentStations = decoded
            } catch {
                print("recentStations errore decodifica: \(error)")
            }
        }

        if let data = UserDefaults.standard.data(forKey: favoritesKey), let decoded = try? JSONDecoder().decode([SavedTrain].self, from: data) {
            self.favoriteTrains = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: myStationsKey), let decoded = try? JSONDecoder().decode([Station].self, from: data) {
            self.myStations = decoded.map { st in
                let cleanRfi = (st.rfiID?.hasPrefix("S") == true || st.rfiID?.hasPrefix("N") == true) ? nil : st.rfiID
                return resolveStation(name: st.name, fallbackVtID: st.vtID, fallbackRfiID: cleanRfi)
            }
        } else {
            self.myStations = []
        }
        
        if let data = UserDefaults.standard.data(forKey: sectionOrderKey), let decoded = try? JSONDecoder().decode([AppSection].self, from: data) {
            var loaded = decoded
            for section in AppSection.allCases {
                if !loaded.contains(section) { loaded.append(section) }
            }
            self.sectionOrder = loaded
        }
        
        if let data = UserDefaults.standard.data(forKey: favoriteRoutesKey), let decoded = try? JSONDecoder().decode([FavoriteRoute].self, from: data) {
            self.favoriteRoutes = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: savedTripsKey), let decoded = try? JSONDecoder().decode([SavedTrip].self, from: data) {
            self.savedTrips = decoded
        }
        if let homeDest = UserDefaults.standard.string(forKey: homeDestinationStationNameKey) {
            if self.homeDestinationStationName != homeDest {
                self.homeDestinationStationName = homeDest
            }
        }
        if let savedName = UserDefaults.standard.string(forKey: userNameKey) {
            if self.userName != savedName {
                self.userName = savedName
            }
        }
        if UserDefaults.standard.object(forKey: iCloudSyncEnabledKey) != nil {
            let val = UserDefaults.standard.bool(forKey: iCloudSyncEnabledKey)
            if self.iCloudSyncEnabled != val {
                self.iCloudSyncEnabled = val
            }
        } else {
            if !self.iCloudSyncEnabled {
                self.iCloudSyncEnabled = true
            }
        }
        
        if UserDefaults.standard.object(forKey: remoteNotificationsEnabledKey) != nil {
            let val = UserDefaults.standard.bool(forKey: remoteNotificationsEnabledKey)
            if self.remoteNotificationsEnabled != val {
                self.remoteNotificationsEnabled = val
            }
        }
        if UserDefaults.standard.object(forKey: notifyOnStationPassKey) != nil {
            let val = UserDefaults.standard.bool(forKey: notifyOnStationPassKey)
            if self.notifyOnStationPass != val {
                self.notifyOnStationPass = val
            }
        }
        if let storedRegion = UserDefaults.standard.string(forKey: strikeRegionKey) {
            if self.strikeRegion != storedRegion {
                self.strikeRegion = storedRegion
            }
        } else {
            if self.strikeRegion != "Tutte" {
                self.strikeRegion = "Tutte"
            }
        }
        if UserDefaults.standard.object(forKey: strikeNotificationsEnabledKey) != nil {
            let val = UserDefaults.standard.bool(forKey: strikeNotificationsEnabledKey)
            if self.strikeNotificationsEnabled != val {
                self.strikeNotificationsEnabled = val
            }
        } else {
            if !self.strikeNotificationsEnabled {
                self.strikeNotificationsEnabled = true
            }
        }
        if let token = UserDefaults.standard.string(forKey: apnsTokenKey), self.apnsToken != token {
            self.apnsToken = token
        }
    }
    
    func saveFavorites() {
        if let encoded = try? JSONEncoder().encode(favoriteTrains) { 
            UserDefaults.standard.set(encoded, forKey: favoritesKey) 
            if let groupDefaults = UserDefaults(suiteName: "group.carlo.InOrario") {
                groupDefaults.set(encoded, forKey: favoritesKey)
            }
        }
        if let encoded = try? JSONEncoder().encode(myStations) { 
            UserDefaults.standard.set(encoded, forKey: myStationsKey) 
            if let groupDefaults = UserDefaults(suiteName: "group.carlo.InOrario") {
                groupDefaults.set(encoded, forKey: myStationsKey)
            }
        }
        if let encoded = try? JSONEncoder().encode(favoriteRoutes) {
            UserDefaults.standard.set(encoded, forKey: favoriteRoutesKey)
            if let groupDefaults = UserDefaults(suiteName: "group.carlo.InOrario") {
                groupDefaults.set(encoded, forKey: favoriteRoutesKey)
            }
        }
        if let encoded = try? JSONEncoder().encode(savedTrips) {
            UserDefaults.standard.set(encoded, forKey: savedTripsKey)
            if let groupDefaults = UserDefaults(suiteName: "group.carlo.InOrario") {
                groupDefaults.set(encoded, forKey: savedTripsKey)
            }
        }
        if let encoded = try? JSONEncoder().encode(sectionOrder) {
            UserDefaults.standard.set(encoded, forKey: sectionOrderKey)
        }
        
        do {
            let encoded = try JSONEncoder().encode(recentTrains)
            UserDefaults.standard.set(encoded, forKey: recentTrainsKey)
        } catch {
            print("recentTrains errore codifica: \(error)")
        }
        
        do {
            let encoded = try JSONEncoder().encode(recentStations)
            UserDefaults.standard.set(encoded, forKey: recentStationsKey)
        } catch {
            print("recentStations errore codifica: \(error)")
        }
        
        indexSpotlightItems()
        
        UserDefaults.standard.set(homeDestinationStationName, forKey: homeDestinationStationNameKey)
        UserDefaults.standard.set(userName, forKey: userNameKey)
        UserDefaults.standard.set(iCloudSyncEnabled, forKey: iCloudSyncEnabledKey)
        
        UserDefaults.standard.set(remoteNotificationsEnabled, forKey: remoteNotificationsEnabledKey)
        UserDefaults.standard.set(notifyOnStationPass, forKey: notifyOnStationPassKey)
        UserDefaults.standard.set(strikeRegion, forKey: strikeRegionKey)
        UserDefaults.standard.set(strikeNotificationsEnabled, forKey: strikeNotificationsEnabledKey)
        UserDefaults.standard.set(apnsToken, forKey: apnsTokenKey)
        
        if iCloudSyncEnabled {
            let store = NSUbiquitousKeyValueStore.default
            if let encoded = try? JSONEncoder().encode(favoriteTrains) { store.set(encoded, forKey: favoritesKey) }
            if let encoded = try? JSONEncoder().encode(myStations) { store.set(encoded, forKey: myStationsKey) }
            if let encoded = try? JSONEncoder().encode(favoriteRoutes) { store.set(encoded, forKey: favoriteRoutesKey) }
            if let encoded = try? JSONEncoder().encode(savedTrips) { store.set(encoded, forKey: savedTripsKey) }
            if let encoded = try? JSONEncoder().encode(sectionOrder) { store.set(encoded, forKey: sectionOrderKey) }
            
            store.set(homeDestinationStationName, forKey: homeDestinationStationNameKey)
            store.set(userName, forKey: userNameKey)
            store.set(iCloudSyncEnabled, forKey: iCloudSyncEnabledKey)
            store.set(remoteNotificationsEnabled, forKey: remoteNotificationsEnabledKey)
            store.set(notifyOnStationPass, forKey: notifyOnStationPassKey)
            store.set(strikeRegion, forKey: strikeRegionKey)
            store.set(strikeNotificationsEnabled, forKey: strikeNotificationsEnabledKey)
        }
        
        if let groupDefaults = UserDefaults(suiteName: "group.carlo.InOrario") {
            groupDefaults.set(homeDestinationStationName, forKey: homeDestinationStationNameKey)
        }
        
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func indexSpotlightItems() {
        var searchableItems = [CSSearchableItem]()
        
        for train in favoriteTrains {
            let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
            attributeSet.title = "Treno \(train.number)"
            attributeSet.contentDescription = train.description
            attributeSet.keywords = ["treno", train.number, "inorario", "orario", train.description]
            
            let item = CSSearchableItem(uniqueIdentifier: "inorario://train/\(train.number)", domainIdentifier: "com.carlo.inorario.trains", attributeSet: attributeSet)
            searchableItems.append(item)
        }
        
        for station in myStations {
            let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
            attributeSet.title = "Stazione di \(station.name)"
            attributeSet.contentDescription = "Tabellone partenze e arrivi"
            attributeSet.keywords = ["stazione", station.name, "tabellone", "partenze", "arrivi", "inorario"]
            
            // Usiamo il nome o un ID come identificativo
            let stationId = station.vtID ?? station.rfiID ?? station.name
            let item = CSSearchableItem(uniqueIdentifier: "inorario://station/\(stationId)", domainIdentifier: "com.carlo.inorario.stations", attributeSet: attributeSet)
            searchableItems.append(item)
        }
        
        CSSearchableIndex.default().indexSearchableItems(searchableItems) { error in
            if let error = error {
                print("Spotlight indexing error: \(error.localizedDescription)")
            }
        }
    }
    

    func addToRecentTrains(_ train: SavedTrain) {
        recentTrains.removeAll { $0.number == train.number }
        recentTrains.insert(train, at: 0)
        if recentTrains.count > 10 {
            recentTrains.removeLast()
        }
        saveFavorites()
    }
    
    func addToRecentStations(_ station: VTSearchStation) {
        let resolved = resolveStation(name: station.nomeLungo, fallbackVtID: station.vtID)
        let cleanVtID = resolved.vtID ?? station.vtID
        let cleanStation = VTSearchStation(nomeLungo: resolved.name, nomeBreve: resolved.name, vtID: cleanVtID)
        recentStations.removeAll { $0.vtID == cleanStation.vtID || $0.nomeLungo.lowercased() == cleanStation.nomeLungo.lowercased() }
        recentStations.insert(cleanStation, at: 0)
        if recentStations.count > 10 {
            recentStations.removeLast()
        }
        saveFavorites()
    }
    
    func clearRecentTrains() {
        recentTrains = []
        saveFavorites()
    }
    
    func clearRecentStations() {
        recentStations = []
        saveFavorites()
    }
    
    func addToViewedRecentTrains(number: String, description: String, departureTime: String?) {
        let train = SavedTrain(number: number, description: description, notifyDelay: false, departureTime: departureTime)
        viewedRecentTrains.removeAll { $0.number == train.number }
        viewedRecentTrains.insert(train, at: 0)
        if viewedRecentTrains.count > 10 {
            viewedRecentTrains.removeLast()
        }
        saveViewedRecentTrains()
        
        // Save intent for TrainGuessingEngine
        UserDefaults.standard.set(number, forKey: "lastConsultedTrainID")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastConsultedTimestamp")
    }
    
    func saveViewedRecentTrains() {
        if let encoded = try? JSONEncoder().encode(viewedRecentTrains) {
            UserDefaults.standard.set(encoded, forKey: viewedRecentTrainsKey)
        }
    }
    
    func loadViewedRecentTrains() {
        if let data = UserDefaults.standard.data(forKey: viewedRecentTrainsKey),
           let decoded = try? JSONDecoder().decode([SavedTrain].self, from: data) {
            self.viewedRecentTrains = decoded
        }
    }
    
    func clearViewedRecentTrains() {
        viewedRecentTrains = []
        saveViewedRecentTrains()
    }
    
    func addToViewedRecentStations(name: String, vtID: String) {
        let resolved = resolveStation(name: name, fallbackVtID: vtID)
        let cleanVtID = resolved.vtID ?? vtID
        let station = VTSearchStation(nomeLungo: resolved.name, nomeBreve: resolved.name, vtID: cleanVtID)
        viewedRecentStations.removeAll { $0.vtID == station.vtID || $0.nomeLungo.lowercased() == station.nomeLungo.lowercased() }
        viewedRecentStations.insert(station, at: 0)
        if viewedRecentStations.count > 10 {
            viewedRecentStations.removeLast()
        }
        saveViewedRecentStations()
    }
    
    func saveViewedRecentStations() {
        if let encoded = try? JSONEncoder().encode(viewedRecentStations) {
            UserDefaults.standard.set(encoded, forKey: viewedRecentStationsKey)
        }
    }
    
    func loadViewedRecentStations() {
        if let data = UserDefaults.standard.data(forKey: viewedRecentStationsKey),
           let decoded = try? JSONDecoder().decode([VTSearchStation].self, from: data) {
            self.viewedRecentStations = decoded
        }
    }
    
    func clearViewedRecentStations() {
        viewedRecentStations = []
        saveViewedRecentStations()
    }
    
    func removeRecentTrain(number: String) {
        recentTrains.removeAll { $0.number == number }
        viewedRecentTrains.removeAll { $0.number == number }
        saveFavorites()
        saveViewedRecentTrains()
    }
    
    func removeRecentStation(name: String, vtID: String?) {
        let norm = normalizeStationName(name)
        recentStations.removeAll { 
            ($0.vtID == vtID && !(vtID ?? "").isEmpty) || normalizeStationName($0.nomeLungo) == norm 
        }
        viewedRecentStations.removeAll { 
            ($0.vtID == vtID && !(vtID ?? "").isEmpty) || normalizeStationName($0.nomeLungo) == norm 
        }
        saveFavorites()
        saveViewedRecentStations()
    }
    
    var unifiedRecentStations: [VTSearchStation] {
        var list: [VTSearchStation] = []
        var seenNames = Set<String>()
        var seenIDs = Set<String>()
        let combined = viewedRecentStations + recentStations
        for s in combined {
            let norm = normalizeStationName(s.nomeLungo)
            let id = s.vtID.trimmingCharacters(in: .whitespacesAndNewlines)
            if seenNames.contains(norm) { continue }
            if !id.isEmpty && (id.hasPrefix("S") || id.hasPrefix("N")) && seenIDs.contains(id) { continue }
            seenNames.insert(norm)
            if !id.isEmpty { seenIDs.insert(id) }
            list.append(s)
        }
        return list
    }
    
    var unifiedRecentTrains: [SavedTrain] {
        var list: [SavedTrain] = []
        var seen = Set<String>()
        for t in viewedRecentTrains {
            if !seen.contains(t.number) {
                seen.insert(t.number)
                list.append(t)
            }
        }
        for t in recentTrains {
            if !seen.contains(t.number) {
                seen.insert(t.number)
                list.append(t)
            }
        }
        return list
    }
    
    @objc private func iCloudStoreDidChangeExternally(_ notification: Notification) {
        guard iCloudSyncEnabled else { return }
        if let userInfo = notification.userInfo,
           let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] {
            loadFromiCloud(keys: changedKeys, onlyIfLocalMissing: false)
        } else {
            loadFromiCloud(keys: nil, onlyIfLocalMissing: false)
        }
    }
    
    private func loadFromiCloud(keys: [String]?, onlyIfLocalMissing: Bool) {
        guard iCloudSyncEnabled else { return }
        
        let store = NSUbiquitousKeyValueStore.default
        let keySet = keys != nil ? Set(keys!) : nil
        var didModify = false
        
        func shouldUpdate(_ key: String) -> Bool {
            if let ks = keySet, !ks.contains(key) { return false }
            if onlyIfLocalMissing, UserDefaults.standard.object(forKey: key) != nil { return false }
            return true
        }
        
        if shouldUpdate(favoritesKey), let data = store.data(forKey: favoritesKey), let decoded = try? JSONDecoder().decode([SavedTrain].self, from: data) {
            self.favoriteTrains = decoded
            UserDefaults.standard.set(data, forKey: favoritesKey)
            if let groupDefaults = UserDefaults(suiteName: "group.carlo.InOrario") { groupDefaults.set(data, forKey: favoritesKey) }
            didModify = true
        }
        
        if shouldUpdate(myStationsKey), let data = store.data(forKey: myStationsKey), let decoded = try? JSONDecoder().decode([Station].self, from: data) {
            self.myStations = decoded.map { st in
                let cleanRfi = (st.rfiID?.hasPrefix("S") == true || st.rfiID?.hasPrefix("N") == true) ? nil : st.rfiID
                return resolveStation(name: st.name, fallbackVtID: st.vtID, fallbackRfiID: cleanRfi)
            }
            UserDefaults.standard.set(data, forKey: myStationsKey)
            if let groupDefaults = UserDefaults(suiteName: "group.carlo.InOrario") { groupDefaults.set(data, forKey: myStationsKey) }
            didModify = true
        }
        
        if shouldUpdate(sectionOrderKey), let data = store.data(forKey: sectionOrderKey), let decoded = try? JSONDecoder().decode([AppSection].self, from: data) {
            var loaded = decoded
            for section in AppSection.allCases {
                if !loaded.contains(section) { loaded.append(section) }
            }
            self.sectionOrder = loaded
            UserDefaults.standard.set(data, forKey: sectionOrderKey)
            didModify = true
        }
        
        if shouldUpdate(favoriteRoutesKey), let data = store.data(forKey: favoriteRoutesKey), let decoded = try? JSONDecoder().decode([FavoriteRoute].self, from: data) {
            self.favoriteRoutes = decoded
            UserDefaults.standard.set(data, forKey: favoriteRoutesKey)
            if let groupDefaults = UserDefaults(suiteName: "group.carlo.InOrario") { groupDefaults.set(data, forKey: favoriteRoutesKey) }
            didModify = true
        }
        
        if shouldUpdate(savedTripsKey), let data = store.data(forKey: savedTripsKey), let decoded = try? JSONDecoder().decode([SavedTrip].self, from: data) {
            self.savedTrips = decoded
            UserDefaults.standard.set(data, forKey: savedTripsKey)
            if let groupDefaults = UserDefaults(suiteName: "group.carlo.InOrario") { groupDefaults.set(data, forKey: savedTripsKey) }
            didModify = true
        }
        
        if shouldUpdate(homeDestinationStationNameKey), let value = store.string(forKey: homeDestinationStationNameKey) {
            self.homeDestinationStationName = value
            UserDefaults.standard.set(value, forKey: homeDestinationStationNameKey)
            if let groupDefaults = UserDefaults(suiteName: "group.carlo.InOrario") { groupDefaults.set(value, forKey: homeDestinationStationNameKey) }
            didModify = true
        }
        
        if shouldUpdate(userNameKey), let value = store.string(forKey: userNameKey) {
            self.userName = value
            UserDefaults.standard.set(value, forKey: userNameKey)
            didModify = true
        }
        
        if shouldUpdate(iCloudSyncEnabledKey), store.object(forKey: iCloudSyncEnabledKey) != nil {
            let value = store.bool(forKey: iCloudSyncEnabledKey)
            self.iCloudSyncEnabled = value
            UserDefaults.standard.set(value, forKey: iCloudSyncEnabledKey)
            didModify = true
        }
        
        if shouldUpdate(remoteNotificationsEnabledKey), store.object(forKey: remoteNotificationsEnabledKey) != nil {
            let value = store.bool(forKey: remoteNotificationsEnabledKey)
            self.remoteNotificationsEnabled = value
            UserDefaults.standard.set(value, forKey: remoteNotificationsEnabledKey)
            didModify = true
        }
        
        if shouldUpdate(notifyOnStationPassKey), store.object(forKey: notifyOnStationPassKey) != nil {
            let value = store.bool(forKey: notifyOnStationPassKey)
            self.notifyOnStationPass = value
            UserDefaults.standard.set(value, forKey: notifyOnStationPassKey)
            didModify = true
        }
        
        if shouldUpdate(strikeRegionKey), let value = store.string(forKey: strikeRegionKey) {
            self.strikeRegion = value
            UserDefaults.standard.set(value, forKey: strikeRegionKey)
            didModify = true
        }
        
        if shouldUpdate(strikeNotificationsEnabledKey), store.object(forKey: strikeNotificationsEnabledKey) != nil {
            let value = store.bool(forKey: strikeNotificationsEnabledKey)
            self.strikeNotificationsEnabled = value
            UserDefaults.standard.set(value, forKey: strikeNotificationsEnabledKey)
            didModify = true
        }
        
        if didModify {
            if !isInitializing {
                syncRemoteNotifications()
            }
        }
    }
    
    
    
    func filterTrainsForHome(_ trains: [Train], currentStationName: String) -> [Train] {
        guard !homeDestinationStationName.isEmpty else { return trains }
        let homeLower = homeDestinationStationName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let currentLower = currentStationName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        if currentLower == homeLower {
            return trains
        }
        
        return trains.filter { train in
            let destLower = train.destination.lowercased()
            
            if homeLower.contains("magenta") {
                let eastOfMagenta = ["milano", "garibaldi", "repubblica", "venezia", "dateo", "vittoria", "forlanini", "certosa", "villapizzone", "lancetti", "rho", "pregnana", "vittuone", "arluno"]
                let isEast = eastOfMagenta.contains { currentLower.contains($0) }
                if isEast {
                    let cat = train.category.lowercased()
                    let isHighSpeed = cat.contains("fr") || cat.contains("freccia") || cat.contains("italo") || cat.contains("av") || cat.contains("ec") || cat.contains("ic")
                    
                    if currentLower.contains("garibaldi") {
                        return destLower.contains("novara") || destLower.contains("magenta") || destLower.contains("trecate")
                    } else {
                        let validDest = destLower.contains("novara") || destLower.contains("torino") || destLower.contains("magenta") || destLower.contains("trecate") || destLower.contains("lingotto")
                        return validDest && !isHighSpeed
                    }
                }
                let westOfMagenta = ["novara", "trecate"]
                let isWest = westOfMagenta.contains { currentLower.contains($0) }
                if isWest {
                    return destLower.contains("milano") || destLower.contains("pioltello") || destLower.contains("treviglio") || destLower.contains("passante")
                }
            }
            
            if homeLower.contains("bovisa") {
                let northWestOfBovisa = ["saronno", "mariano", "camnago", "meda", "seveso", "cesano", "bovisio", "varedo", "paderno", "cormano", "cusano", "caronno", "garbagnate", "bollate", "novate"]
                let isNorthWest = northWestOfBovisa.contains { currentLower.contains($0) }
                if isNorthWest {
                    return destLower.contains("cadorna") || destLower.contains("milano") || destLower.contains("pavia") || destLower.contains("lodi") || destLower.contains("rogoredo")
                }
                let southEastOfBovisa = ["cadorna", "domodossola", "lancetti", "garibaldi", "repubblica", "venezia", "dateo", "vittoria", "rogoredo", "lodi", "pavia"]
                let isSouthEast = southEastOfBovisa.contains { currentLower.contains($0) }
                if isSouthEast {
                    return destLower.contains("saronno") || destLower.contains("mariano") || destLower.contains("camnago") || destLower.contains("bovisa")
                }
            }
            
            if homeLower.contains("rogoredo") {
                let northWestOfRogoredo = ["bovisa", "lancetti", "garibaldi", "repubblica", "venezia", "dateo", "vittoria", "forlanini", "certosa", "villapizzone", "rho", "greco", "lambrate"]
                let isNorthWest = northWestOfRogoredo.contains { currentLower.contains($0) }
                if isNorthWest {
                    return destLower.contains("rogoredo") || destLower.contains("lodi") || destLower.contains("pavia") || destLower.contains("piacenza") || destLower.contains("mantova") || destLower.contains("genova") || destLower.contains("bologna") || destLower.contains("parma") || destLower.contains("melegnano")
                }
                let southEastOfRogoredo = ["pavia", "lodi", "melegnano", "piacenza"]
                let isSouthEast = southEastOfRogoredo.contains { currentLower.contains($0) }
                if isSouthEast {
                    return destLower.contains("milano") || destLower.contains("bovisa") || destLower.contains("saronno") || destLower.contains("mariano") || destLower.contains("cadorna") || destLower.contains("torino")
                }
            }
            
            if homeLower.contains("monza") {
                let southOfMonza = ["milano", "greco", "garibaldi", "lambrate", "forlanini", "rogoredo", "albairate", "cristoforo", "romolo", "romana", "tibaldi", "sesto"]
                let isSouth = southOfMonza.contains { currentLower.contains($0) }
                if isSouth {
                    return destLower.contains("chiasso") || destLower.contains("como") || destLower.contains("seregno") || destLower.contains("lecco") || destLower.contains("monza") || destLower.contains("bergamo") || destLower.contains("carnate") || destLower.contains("molteno") || destLower.contains("colico") || destLower.contains("sondrio")
                }
                let northOfMonza = ["como", "chiasso", "lecco", "seregno", "desio", "lissone", "carnate", "arcore"]
                let isNorth = northOfMonza.contains { currentLower.contains($0) }
                if isNorth {
                    return destLower.contains("milano") || destLower.contains("greco") || destLower.contains("albairate") || destLower.contains("saronno") || destLower.contains("rho")
                }
            }
            
            if homeLower.contains("saronno") {
                let southEastOfSaronno = ["milano", "cadorna", "bovisa", "domodossola", "greco", "monza", "lodi", "albairate", "romolo", "cristoforo", "lambrate", "garibaldi"]
                let isSouthEast = southEastOfSaronno.contains { currentLower.contains($0) }
                if isSouthEast {
                    return destLower.contains("saronno") || destLower.contains("laveno") || destLower.contains("como") || destLower.contains("novara") || destLower.contains("varese")
                }
                let northWestOfSaronno = ["laveno", "como", "varese", "gerenzano", "turate", "lomazzo", "fino", "grandate"]
                let isNorthWest = northWestOfSaronno.contains { currentLower.contains($0) }
                if isNorthWest {
                    return destLower.contains("cadorna") || destLower.contains("milano") || destLower.contains("lodi") || destLower.contains("albairate")
                }
            }
            
            return destLower.contains(homeLower) || homeLower.contains(destLower)
        }
    }
    
                func addSmartRoute(origin: String, destination: String) {
        let route = SuburbanRoute(originName: origin, destinationName: destination)
        if !smartRoutes.contains(where: { $0.id == route.id }) {
            smartRoutes.append(route)
            saveFavorites()
            Task {
                await refreshSmartRoute(route: route)
            }
        }
    }
    
    func removeSmartRoute(id: String) {
        smartRoutes.removeAll { $0.id == id }
        loadedSmartRouteDetails.removeValue(forKey: id)
        saveFavorites()
    }
    
    func fetchSmartRoutesLive() async {
        self.isLoadingSmartRoutes = true
        await withTaskGroup(of: (String, SmartRouteDetails?).self) { group in
            for route in smartRoutes {
                group.addTask {
                    let details = await self.findSuburbanRouteDetails(origin: route.originName, destination: route.destinationName)
                    return await (route.id, details)
                }
            }
            
            for await (routeId, details) in group {
                if let det = details {
                    self.loadedSmartRouteDetails[routeId] = det
                }
            }
        }
        self.isLoadingSmartRoutes = false
    }
    
    func refreshSmartRoute(route: SuburbanRoute) async {
        if let details = await self.findSuburbanRouteDetails(origin: route.originName, destination: route.destinationName) {
            self.loadedSmartRouteDetails[route.id] = details
        }
    }
    
    private func findSuburbanRouteDetails(origin: String, destination: String) async -> SmartRouteDetails? {
        let allStations = SuburbanData.shared.allLines.flatMap { $0.stations }
        guard let origStation = allStations.first(where: { $0.name.lowercased() == origin.lowercased() }),
              let destStation = allStations.first(where: { $0.name.lowercased() == destination.lowercased() }) else {
            return nil
        }
        
        let origLines = SuburbanData.shared.allLines.filter { line in
            line.stations.contains { $0.name.lowercased() == origin.lowercased() }
        }
        let destLines = SuburbanData.shared.allLines.filter { line in
            line.stations.contains { $0.name.lowercased() == destination.lowercased() }
        }
        
        let directLines = origLines.filter { ol in destLines.contains { dl in dl.id == ol.id } }
        
        if !directLines.isEmpty {
            let scraped = await fetchTrainsForStation(station: origStation)
            let directTrains = scraped.filter { t in
                let cat = t.category.uppercased()
                return directLines.contains { $0.id == cat || t.number.hasPrefix($0.id) }
            }
            return SmartRouteDetails(isDirect: true, exchangeStation: nil, originStation: origStation, destinationStation: destStation, originTrains: Array(directTrains.prefix(3)), exchangeTrains: [])
        } else {
            let tunnelStations = [
                "Lancetti", "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria"
            ]
            
            var bestExchange: Station? = nil
            for ts in tunnelStations {
                if origLines.contains(where: { $0.stations.contains(where: { $0.name == ts }) }) &&
                   destLines.contains(where: { $0.stations.contains(where: { $0.name == ts }) }) {
                    bestExchange = allStations.first(where: { $0.name == ts })
                    break
                }
            }
            
            if bestExchange == nil {
                for line in origLines {
                    for s in line.stations {
                        if destLines.contains(where: { $0.stations.contains(where: { $0.name == s.name }) }) {
                            bestExchange = s
                            break
                        }
                    }
                    if bestExchange != nil { break }
                }
            }
            
            guard let exchange = bestExchange else { return nil }
            
            async let origFetch = fetchTrainsForStation(station: origStation)
            async let exchangeFetch = fetchTrainsForStation(station: exchange)
            
            let (origTrains, exTrains) = await (origFetch, exchangeFetch)
            
            let toExchangeTrains = origTrains.filter { t in
                let cat = t.category.uppercased()
                return origLines.contains { $0.id == cat }
            }
            
            let toDestTrains = exTrains.filter { t in
                let cat = t.category.uppercased()
                return destLines.contains { $0.id == cat }
            }
            
            return SmartRouteDetails(
                isDirect: false,
                exchangeStation: exchange,
                originStation: origStation,
                destinationStation: destStation,
                originTrains: Array(toExchangeTrains.prefix(2)),
                exchangeTrains: Array(toDestTrains.prefix(2))
            )
        }
    }
    
    nonisolated func fetchTrainsForStation(station: Station) async -> [Train] {
        return await StationRepository.shared.getTrainsForStation(station: station)
    }
    
    func saveSectionOrder() {
        saveFavorites()
    }
    
    func toggleFavorite(trainNumber: String, description: String, departureTime: String? = nil) {
        if let index = favoriteTrains.firstIndex(where: { $0.number == trainNumber }) {
            favoriteTrains.remove(at: index)
            Haptics.notify(.warning)
            if let token = apnsToken {
                unregisterTrainForPush(trainNumber: trainNumber, token: token)
            }
        } else {
            let cleanDescription = description.replacingOccurrences(of: "\(trainNumber) - ", with: "")
            favoriteTrains.append(SavedTrain(number: trainNumber, description: cleanDescription, departureTime: departureTime))
            Haptics.notify(.success)
            // Asynchronously enrich with origin and arrival time from API
            Task {
                await enrichFavoriteTrainData(trainNumber: trainNumber)
            }
        }
        saveFavorites()
    }
    
    /// Fetches live stops for a favorited train and updates departureTime (origin), arrivalTime (destination).
    func enrichFavoriteTrainData(trainNumber: String) async {
        let result = await fetchLiveStops(for: trainNumber)
        guard !result.stops.isEmpty else { return }
        let firstStop = result.stops.first
        let lastStop = result.stops.last
        await MainActor.run {
            if let index = favoriteTrains.firstIndex(where: { $0.number == trainNumber }) {
                var changed = false
                if let newDep = firstStop?.time, favoriteTrains[index].departureTime != newDep {
                    favoriteTrains[index].departureTime = newDep
                    changed = true
                }
                if favoriteTrains[index].arrivalTime == nil, let newArr = lastStop?.time {
                    favoriteTrains[index].arrivalTime = newArr
                    changed = true
                }
                // Populate description with Origin - Destination if it's just the destination
                let origin = firstStop?.stationName ?? ""
                let destination = lastStop?.stationName ?? ""
                if !origin.isEmpty && !destination.isEmpty {
                    let newDesc = "\(origin) - \(destination)"
                    if favoriteTrains[index].description != newDesc {
                        favoriteTrains[index].description = newDesc
                        changed = true
                    }
                }
                
                // Update cached delay for Widget fallback
                let isCancelled = result.status.statusMessage.contains("Soppresso")
                let stopDelay = result.stops.last?.delay ?? 0
                let delayStr: String
                let colorStr: String
                if isCancelled {
                    delayStr = "Soppresso"
                    colorStr = "red"
                } else if stopDelay > 0 {
                    delayStr = "Ritardo \(stopDelay) min"
                    colorStr = "red"
                } else if stopDelay < 0 {
                    delayStr = "Anticipo \(abs(stopDelay)) min"
                    colorStr = "green"
                } else {
                    delayStr = "In orario"
                    colorStr = "green"
                }
                
                if favoriteTrains[index].lastDelayText != delayStr || favoriteTrains[index].lastDelayColorName != colorStr {
                    favoriteTrains[index].lastDelayText = delayStr
                    favoriteTrains[index].lastDelayColorName = colorStr
                    changed = true
                }
                
                if changed {
                    saveFavorites()
                }
            }
        }
    }
    
    func syncRemoteNotifications() {
        guard UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") else { return }
        
        if remoteNotificationsEnabled && apnsToken == nil {
            print("[syncRemoteNotifications] Notifiche abilitate e token nil. Richiedo registrazione token APNs ad Apple...")
            UIApplication.shared.registerForRemoteNotifications()
        }
        
        guard let token = apnsToken, !token.isEmpty else {
            print("[syncRemoteNotifications] Esco: token è ancora nil.")
            return
        }
        
        if !remoteNotificationsEnabled {
            print("[syncRemoteNotifications] Notifiche globali disabilitate. Sincronizzo stato vuoto sul server.")
            unregisterDeviceForStrikes(token: token)
            Task {
                for train in favoriteTrains {
                    unregisterTrainForPush(trainNumber: train.number, token: token)
                }
            }
            // Non faccio return, proseguo per sincronizzare sul server che le notifiche sono disabilitate
        }
        
        let strikeEnabled = remoteNotificationsEnabled ? strikeNotificationsEnabled : false
        
        var trainsPayload: [[String: Any]] = []
        if remoteNotificationsEnabled {
            for train in favoriteTrains {
                let isEnabled = (train.notifyDelay == true) ||
                                (train.notifyDeparture == true) ||
                                (train.notifyStationPass == true) ||
                                (train.notifyPlatformChange == true)
                if isEnabled {
                    trainsPayload.append([
                        "train_number": train.number,
                        "notify_delay": train.notifyDelay ?? true,
                        "notify_station_pass": train.notifyStationPass ?? false,
                        "station_pass_name": train.stationPassName ?? "",
                        "notify_departure": train.notifyDeparture ?? false,
                        "departure_time": train.departureTime ?? "",
                        "arrival_time": train.arrivalTime ?? "",
                        "active_days": train.activeDays ?? [],
                        "notify_platform_change": train.notifyPlatformChange ?? false,
                        "platform_change_station_name": train.platformChangeStationName ?? ""
                    ])
                }
            }
        }
        
        let support = hasSupport()
        let aiEngine = support ? (AIFeatureManager.shared.preferLocalAI ? "local" : "cloud") : (AIFeatureManager.shared.isLocalModelInstalled ? "local" : "none")
        let currentSignature = "\(token)|\(remoteNotificationsEnabled)|\(strikeRegion)|\(strikeEnabled)|\(support)|\(aiEngine)|\(trainsPayload.description)"
        
        if currentSignature == lastSyncedSignature || currentSignature == inFlightSyncSignature {
            return
        }
        
        self.inFlightSyncSignature = currentSignature
        syncDebounceTask?.cancel()
        
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/notifications/sync") else {
            self.inFlightSyncSignature = nil
            return
        }
        
        let payload: [String: Any] = [
            "token": token,
            "platform": "ios",
            "strike_region": strikeRegion,
            "strike_enabled": strikeEnabled,
            "trains": trainsPayload,
            "device_model": getDeviceModelName(),
            "os_version": UIDevice.current.systemVersion,
            "ai_engine": aiEngine,
            "has_support": support
        ]
        
        syncDebounceTask = Task { @MainActor in
            // Debounce di 500ms per raggruppare chiamate multiple ed evitare flood del server
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            
            print("[syncRemoteNotifications] Avvio sincronizzazione. Token: \(token), remoteNotificationsEnabled: \(remoteNotificationsEnabled), preferiti: \(favoriteTrains.map { "\($0.number): \($0.notifyDelay ?? false)" })")
            
            do {
                let (_, response) = try await NetworkService.shared.post(url: url, payload: payload)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    print("[syncRemoteNotifications] Sincronizzazione completata con successo sul server.")
                    self.lastSyncedSignature = currentSignature
                } else {
                    print("[syncRemoteNotifications] Risposta server non 200 per sincronizzazione")
                }
            } catch {
                print("[syncRemoteNotifications] Errore nell'invio della sincronizzazione: \(error.localizedDescription)")
            }
            self.inFlightSyncSignature = nil
        }
    }
    
    func ignoreStrike(strikeId: String) {
        guard let token = apnsToken else { return }
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/notifications/ignore-strike") else { return }
        
        let payload: [String: Any] = [
            "token": token,
            "strike_id": strikeId
        ]
        
        Task {
            do {
                _ = try await NetworkService.shared.post(url: url, payload: payload)
                print("Sciopero \(strikeId) ignorato con successo per il token.")
            } catch {
                print("Errore ignoreStrike: \(error)")
            }
        }
    }
    
    func getDeviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        switch identifier {
        case "iPhone10,1", "iPhone10,4": return "iPhone 8"
        case "iPhone10,2", "iPhone10,5": return "iPhone 8 Plus"
        case "iPhone10,3", "iPhone10,6": return "iPhone X"
        case "iPhone11,2": return "iPhone XS"
        case "iPhone11,4", "iPhone11,6": return "iPhone XS Max"
        case "iPhone11,8": return "iPhone XR"
        case "iPhone12,1": return "iPhone 11"
        case "iPhone12,3": return "iPhone 11 Pro"
        case "iPhone12,5": return "iPhone 11 Pro Max"
        case "iPhone12,8": return "iPhone SE (2nd Gen)"
        case "iPhone13,1": return "iPhone 12 mini"
        case "iPhone13,2": return "iPhone 12"
        case "iPhone13,3": return "iPhone 12 Pro"
        case "iPhone13,4": return "iPhone 12 Pro Max"
        case "iPhone14,4": return "iPhone 13 mini"
        case "iPhone14,5": return "iPhone 13"
        case "iPhone14,2": return "iPhone 13 Pro"
        case "iPhone14,3": return "iPhone 13 Pro Max"
        case "iPhone14,6": return "iPhone SE (3rd Gen)"
        case "iPhone14,7": return "iPhone 14"
        case "iPhone14,8": return "iPhone 14 Plus"
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
        case "iPhone15,4": return "iPhone 15"
        case "iPhone15,5": return "iPhone 15 Plus"
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"
        case "iPhone17,1": return "iPhone 16 Pro"
        case "iPhone17,2": return "iPhone 16 Pro Max"
        case "iPhone17,3": return "iPhone 16"
        case "iPhone17,4": return "iPhone 16 Plus"
        case "i386", "x86_64", "arm64": return "iPhone Simulator"
        default: return identifier.isEmpty ? "iPhone" : identifier
        }
    }
    
    func registerDeviceForStrikes(token: String) {
        guard remoteNotificationsEnabled else { return }
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/notifications/register") else { return }
        let region = hasSupport() ? strikeRegion : "Tutte"
        
        let model = getDeviceModelName()
        let os = "iOS \(UIDevice.current.systemVersion)"
        let ai = hasSupport() ? (AIFeatureManager.shared.preferLocalAI ? "local" : "cloud") : (AIFeatureManager.shared.isLocalModelInstalled ? "local" : "none")
        let support = hasSupport()
        
        let payload: [String: Any] = [
            "token": token,
            "platform": "ios",
            "strike_region": region,
            "strike_enabled": strikeNotificationsEnabled,
            "device_model": model,
            "os_version": os,
            "ai_engine": ai,
            "has_support": support
        ]
        
        Task {
            do {
                _ = try await NetworkService.shared.post(url: url, payload: payload)
                print("Registrato dispositivo per scioperi con regione: \(region), strike_enabled: \(strikeNotificationsEnabled)")
            } catch {
                print("Errore registrazione dispositivo per scioperi: \(error.localizedDescription)")
            }
        }
    }
    
    func unregisterDeviceForStrikes(token: String) {
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/notifications/unregister") else { return }
        
        let payload: [String: Any] = [
            "token": token
        ]
        
        Task {
            do {
                _ = try await NetworkService.shared.post(url: url, payload: payload)
                print("Dispositivo generale e notifiche scioperi disattivati con successo.")
            } catch {
                print("Errore disattivazione dispositivo generale: \(error.localizedDescription)")
            }
        }
    }
    
    func hasSupport() -> Bool {
        return UserDefaults.standard.bool(forKey: "tip.colazionee")
    }
    
    func getLimit() -> Int {
        if hasSupport() { return 10 }
        return 1
    }
    
    func checkAndCleanOneShotNotifications() {
        let lastCleanDateStr = UserDefaults.standard.string(forKey: "lastOneShotCleanDate")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        // Se siamo prima delle 03:00, consideriamo il "giorno del treno" come ieri
        let trainDayDate = hour < 3 ? Calendar.current.date(byAdding: .day, value: -1, to: now)! : now
        let currentTrainDayStr = formatter.string(from: trainDayDate)
        
        if lastCleanDateStr != currentTrainDayStr {
            var updated = false
            for i in 0..<favoriteTrains.count {
                let train = favoriteTrains[i]
                let activeDays = train.activeDays ?? []
                if activeDays.isEmpty {
                    // È una notifica one-shot
                    if (train.notifyDelay == true || train.notifyDeparture == true || train.notifyStationPass == true || train.notifyPlatformChange == true) {
                        favoriteTrains[i].notifyDelay = false
                        favoriteTrains[i].notifyDeparture = false
                        favoriteTrains[i].notifyStationPass = false
                        favoriteTrains[i].notifyPlatformChange = false
                        updated = true
                        
                        // Deregistra dal server
                        if let token = apnsToken {
                            unregisterTrainForPush(trainNumber: train.number, token: token)
                        }
                    }
                }
            }
            if updated {
                saveFavorites()
            }
            UserDefaults.standard.set(currentTrainDayStr, forKey: "lastOneShotCleanDate")
        }
    }
    
    func disableTrainNotificationsForNonPremium() {
        guard !hasSupport() else { return }
        var updated = false
        for i in 0..<favoriteTrains.count {
            let train = favoriteTrains[i]
            if (train.notifyDelay == true || train.notifyDeparture == true || train.notifyStationPass == true || train.notifyPlatformChange == true) {
                favoriteTrains[i].notifyDelay = false
                favoriteTrains[i].notifyDeparture = false
                favoriteTrains[i].notifyStationPass = false
                favoriteTrains[i].notifyPlatformChange = false
                updated = true
                
                if let token = apnsToken {
                    unregisterTrainForPush(trainNumber: train.number, token: token)
                }
            }
        }
        if updated {
            saveFavorites()
            notificationLimitError = "Nella versione gratuita puoi attivare un solo servizio alla volta tra Notifiche Push e Live Activity. Le notifiche treni sono state sospese per dare priorità alla Live Activity."
        }
    }
    
    func disableLiveActivitiesForNonPremium() {
        guard !hasSupport() else { return }
        if !activeLiveActivities.isEmpty {
            for act in Activity<TrainLiveActivityAttributes>.activities {
                Task {
                    await act.end(nil, dismissalPolicy: .immediate)
                }
            }
            activeLiveActivities.removeAll()
            notificationLimitError = "Nella versione gratuita puoi attivare un solo servizio alla volta tra Notifiche Push e Live Activity. La Live Activity è stata disattivata per dare priorità alle Notifiche Treni."
        }
    }
    
    func registerTrainForPush(trainNumber: String, token: String) {
        print("[registerTrainForPush] Tentativo di registrazione per treno \(trainNumber)...")
        if !remoteNotificationsEnabled {
            print("[registerTrainForPush] Annullato: remoteNotificationsEnabled è false")
            return
        }
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/notifications/register") else { return }
        
        let trainPref = favoriteTrains.first(where: { $0.number == trainNumber })
        let notifyDelay = trainPref?.notifyDelay ?? true
        let notifyStationPass = trainPref?.notifyStationPass ?? false
        let stationPassName = trainPref?.stationPassName ?? ""
        let notifyDeparture = trainPref?.notifyDeparture ?? false
        let notifyPlatformChange = trainPref?.notifyPlatformChange ?? false
        let platformChangeStationName = trainPref?.platformChangeStationName ?? ""
        
        let limit = getLimit()
        
        let model = "\(UIDevice.current.model) (\(UIDevice.current.name))"
        let os = "iOS \(UIDevice.current.systemVersion)"
        let ai = hasSupport() ? (AIFeatureManager.shared.preferLocalAI ? "local" : "cloud") : (AIFeatureManager.shared.isLocalModelInstalled ? "local" : "none")
        let support = hasSupport()
        
        var payload: [String: Any] = [
            "token": token,
            "platform": "ios",
            "train_number": trainNumber,
            "notify_delay": notifyDelay,
            "notify_station_pass": notifyStationPass,
            "station_pass_name": stationPassName,
            "notify_departure": notifyDeparture,
            "limit": limit,
            "strike_region": hasSupport() ? strikeRegion : "Tutte",
            "departure_time": trainPref?.departureTime ?? "",
            "arrival_time": trainPref?.arrivalTime ?? "",
            "notify_platform_change": notifyPlatformChange,
            "platform_change_station_name": platformChangeStationName,
            "device_model": model,
            "os_version": os,
            "ai_engine": ai,
            "has_support": support
        ]
        
        if let activeDays = trainPref?.activeDays {
            payload["active_days"] = activeDays
        }
        
        Task {
            do {
                let (_, response) = try await NetworkService.shared.post(url: url, payload: payload)
                if let httpResponse = response as? HTTPURLResponse {
                    print("[registerTrainForPush] Risposta server per treno \(trainNumber): codice \(httpResponse.statusCode)")
                    if httpResponse.statusCode == 200 {
                        print("[registerTrainForPush] Registrato con successo treno \(trainNumber) per notifiche push")
                    } else if httpResponse.statusCode == 403 {
                        await MainActor.run {
                            if self.hasSupport() {
                                self.notificationLimitError = "Puoi monitorare al massimo \(limit) treni alla volta per il tuo livello."
                            } else {
                                self.notificationLimitError = "Hai raggiunto il limite di monitoraggio per la versione gratuita. Sostieni il progetto per sbloccare fino a 10 treni in tempo reale, Live Activity senza limiti e avvisi scioperi dedicati."
                            }
                        }
                    }
                }
            } catch {
                print("[registerTrainForPush] Errore invio registrazione push treno \(trainNumber): \(error.localizedDescription)")
            }
        }
    }
    
    func unregisterTrainForPush(trainNumber: String, token: String) {
        print("[unregisterTrainForPush] Tentativo di rimozione per treno \(trainNumber)...")
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/notifications/unregister") else { return }
        
        let payload: [String: Any] = [
            "token": token,
            "train_number": trainNumber
        ]
        
        Task {
            do {
                let (_, response) = try await NetworkService.shared.post(url: url, payload: payload)
                if let httpResponse = response as? HTTPURLResponse {
                    print("[unregisterTrainForPush] Risposta server rimozione treno \(trainNumber): codice \(httpResponse.statusCode)")
                }
            } catch {
                print("[unregisterTrainForPush] Errore invio cancellazione push treno \(trainNumber): \(error.localizedDescription)")
            }
        }
    }

    func registerLiveActivityToken(pushToken: Data, trainNumber: String, deviceToken: String) {
        guard hasSupport() else { return }
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/liveactivity/register") else { return }
        let tokenString = pushToken.map { String(format: "%02x", $0) }.joined()
        let payload: [String: Any] = [
            "token": deviceToken,
            "push_token": tokenString,
            "train_number": trainNumber,
            "is_supporter": true
        ]
        Task {
            do {
                let (_, response) = try await NetworkService.shared.post(url: url, payload: payload)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    print("Token LiveActivity registrato per treno \(trainNumber)")
                }
            } catch {
                print("Errore registrazione LiveActivity token: \(error.localizedDescription)")
            }
        }
    }
    
    func unregisterLiveActivityToken(trainNumber: String, deviceToken: String) {
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/liveactivity/unregister") else { return }
        let payload: [String: Any] = [
            "token": deviceToken,
            "train_number": trainNumber
        ]
        Task {
            do {
                let (_, response) = try await NetworkService.shared.post(url: url, payload: payload)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    print("Token LiveActivity rimosso per treno \(trainNumber)")
                }
            } catch {
                print("Errore rimozione LiveActivity token: \(error.localizedDescription)")
            }
        }
    }
    
    func checkAndAutoEnableNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let isAuthorized = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
                if isAuthorized {
                    var changed = false
                    if !self.remoteNotificationsEnabled {
                        print("[checkAndAutoEnableNotifications] Permessi push autorizzati. Attivazione automatica notifiche.")
                        self.remoteNotificationsEnabled = true
                        changed = true
                    }
                    if !self.strikeNotificationsEnabled {
                        print("[checkAndAutoEnableNotifications] Attivazione automatica notifiche scioperi.")
                        self.strikeNotificationsEnabled = true
                        changed = true
                    }
                    if changed {
                        self.saveFavorites()
                    }
                    UIApplication.shared.registerForRemoteNotifications()
                    self.syncRemoteNotifications()
                }
            }
        }
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    self.remoteNotificationsEnabled = true
                    self.strikeNotificationsEnabled = true
                    UIApplication.shared.registerForRemoteNotifications()
                    self.syncRemoteNotifications()
                } else {
                    self.remoteNotificationsEnabled = false
                }
                self.saveFavorites()
            }
        }
    }
    
    func disableNotifications() {
        self.remoteNotificationsEnabled = false
        self.syncRemoteNotifications()
        self.saveFavorites()
    }
    
    func isFavorite(trainNumber: String) -> Bool { favoriteTrains.contains { $0.number == trainNumber } }
    
    func toggleFavoriteRoute(originName: String, originID: String, destName: String, destID: String) {
        if let index = favoriteRoutes.firstIndex(where: { $0.originID == originID && $0.destinationID == destID }) {
            favoriteRoutes.remove(at: index)
            Haptics.notify(.warning)
        } else {
            favoriteRoutes.append(FavoriteRoute(originName: originName, originID: originID, destinationName: destName, destinationID: destID))
            Haptics.notify(.success)
        }
        saveFavorites()
    }
    
    func isFavoriteRoute(originID: String, destID: String) -> Bool {
        return favoriteRoutes.contains { $0.originID == originID && $0.destinationID == destID }
    }
    
    func toggleSavedTrip(solution: TravelSolution) {
        let tripId = "\(solution.origin)-\(solution.destination)-\(solution.departureTime)"
        if let index = savedTrips.firstIndex(where: { $0.id == tripId }) {
            savedTrips.remove(at: index)
            Haptics.notify(.warning)
        } else {
            let segs = solution.segments.map { SavedTripSegment(origin: $0.origin, destination: $0.destination, departureTime: $0.departureTime, arrivalTime: $0.arrivalTime, trainNumber: $0.trainNumber, trainCategory: $0.trainCategory) }
            let saved = SavedTrip(id: tripId, origin: solution.origin, destination: solution.destination, departureTime: solution.departureTime, arrivalTime: solution.arrivalTime, duration: solution.duration, segments: segs)
            savedTrips.append(saved)
            Haptics.notify(.success)
        }
        saveFavorites()
    }
    
    func isTripSaved(solution: TravelSolution) -> Bool {
        let tripId = "\(solution.origin)-\(solution.destination)-\(solution.departureTime)"
        return savedTrips.contains { $0.id == tripId }
    }
    
    func addMyStation(name: String, vtID: String) {
        let resolved = resolveStation(name: name, fallbackVtID: vtID)
        let key = resolved.name.lowercased()
        if !myStations.contains(where: { $0.name.lowercased() == key || ($0.vtID != nil && $0.vtID == resolved.vtID) }) {
            myStations.append(resolved)
            saveFavorites()
            Haptics.notify(.success)
        }
    }
    
    func addMyStation(_ station: Station) {
        let cleanRfi = (station.rfiID?.hasPrefix("S") == true || station.rfiID?.hasPrefix("N") == true) ? nil : station.rfiID
        let resolved = resolveStation(name: station.name, fallbackVtID: station.vtID, fallbackRfiID: cleanRfi)
        let key = resolved.name.lowercased()
        if !myStations.contains(where: { $0.name.lowercased() == key || ($0.vtID != nil && $0.vtID == resolved.vtID) }) {
            myStations.append(resolved)
            saveFavorites()
            Haptics.notify(.success)
        }
    }
    
    func moveFavoriteTrains(from source: IndexSet, to destination: Int) {
        favoriteTrains.move(fromOffsets: source, toOffset: destination)
        saveFavorites()
    }
    
    func moveMyStations(from source: IndexSet, to destination: Int) {
        myStations.move(fromOffsets: source, toOffset: destination)
        saveFavorites()
    }
    
    func removeMyStation(vtID: String) {
        myStations.removeAll { $0.vtID == vtID }
        saveFavorites()
        Haptics.notify(.warning)
    }
    
    func removeMyStation(_ station: Station) {
        let key = station.name.lowercased()
        myStations.removeAll { $0.name.lowercased() == key || ($0.vtID != nil && $0.vtID == station.vtID) }
        saveFavorites()
        Haptics.notify(.warning)
    }
    
    func isMyStation(vtID: String) -> Bool {
        return myStations.contains { $0.vtID == vtID }
    }
    
    func isMyStation(_ station: Station) -> Bool {
        let key = station.name.lowercased()
        return myStations.contains { $0.name.lowercased() == key || ($0.vtID != nil && $0.vtID == station.vtID) }
    }
    
    func searchTrains(query: String) async {
        guard query.count >= 2 else { self.searchResults = []; return }
        self.isSearching = true
        let urlString = "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/cercaNumeroTrenoTrenoAutocomplete/\(query)"
        guard let url = URL(string: urlString) else { self.isSearching = false; return }
        do {
            let (data, _) = try await NetworkService.shared.get(url: url)
            guard !Task.isCancelled else { self.isSearching = false; return }
            
            var parsed = await Task.detached(priority: .userInitiated) { () -> [SavedTrain] in
                guard let result = String(data: data, encoding: .utf8) else { return [] }
                let lines = result.components(separatedBy: .newlines).filter { !$0.isEmpty }
                return lines.compactMap { line -> SavedTrain? in
                    let parts = line.components(separatedBy: "|")
                    guard parts.count > 0 else { return nil }
                    let desc = parts[0].components(separatedBy: " - ")
                    return SavedTrain(number: desc[0].trimmingCharacters(in: .whitespaces), description: desc.count > 1 ? desc[1].trimmingCharacters(in: .whitespaces) : desc[0])
                }
            }.value
            
            guard !Task.isCancelled else { self.isSearching = false; return }
            
            // Se ViaggiaTreno non ha restituito risultati ed è un numero treno di almeno 4 cifre, tenta su Italo
            if parsed.isEmpty && query.count >= 4 && query.allSatisfy({ $0.isNumber }) {
                let italoRes = await ItaloService.shared.getLiveStops(for: query)
                if italoRes.errorMessage == nil && !italoRes.stops.isEmpty {
                    let orig = italoRes.stops.first?.stationName ?? "Origine"
                    let dest = italoRes.stops.last?.stationName ?? "Destinazione"
                    parsed = [SavedTrain(number: query, description: "Italo - \(orig) → \(dest)")]
                }
            }
            
            self.searchResults = parsed
            self.isSearching = false
        } catch {
            if query.count >= 4 && query.allSatisfy({ $0.isNumber }) {
                let italoRes = await ItaloService.shared.getLiveStops(for: query)
                if italoRes.errorMessage == nil && !italoRes.stops.isEmpty {
                    let orig = italoRes.stops.first?.stationName ?? "Origine"
                    let dest = italoRes.stops.last?.stationName ?? "Destinazione"
                    self.searchResults = [SavedTrain(number: query, description: "Italo - \(orig) → \(dest)")]
                }
            }
            self.isSearching = false
        }
    }
    
    nonisolated static func isValidStationName(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.contains("bivio") || lower.contains("bivi ") || lower.contains("biv.") || lower.hasSuffix(" bivi") { return false }
        if lower.hasPrefix("pc ") || lower.contains(" pc ") || lower.hasSuffix(" pc") || lower.contains("p.c.") || lower.contains("/pc") { return false }
        if lower.hasPrefix("pm ") || lower.contains(" pm ") || lower.hasSuffix(" pm") || lower.contains("p.m.") || lower.contains("/pm") { return false }
        if lower.contains("posto di movimento") || lower.contains("posto di comunicazione") { return false }
        return true
    }
    
    func isValidStationName(_ name: String) -> Bool {
        Self.isValidStationName(name)
    }
    
    func searchStations(query: String) async {
        guard query.count >= 2 else { self.searchStationResults = []; return }
        self.isSearching = true
        
        let lowerQ = normalizeStationName(query)
        let stationsCopy = allRFIStations
        
        // Esegui il filtraggio e l'ordinamento su un thread secondario per non bloccare la tastiera e la UI
        let sortedResults = await Task.detached(priority: .userInitiated) { () -> [VTSearchStation] in
            func normFast(_ name: String) -> String {
                return name.lowercased()
                    .replacingOccurrences(of: "&#39;", with: "'")
                    .replacingOccurrences(of: "&#39", with: "'")
                    .replacingOccurrences(of: "&39;", with: "'")
                    .replacingOccurrences(of: "&39", with: "'")
                    .replacingOccurrences(of: "p.ta ", with: "porta")
                    .replacingOccurrences(of: "p.ta", with: "porta")
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
                    .replacingOccurrences(of: "`", with: "")
                    .replacingOccurrences(of: ".", with: "")
                    .folding(options: .diacriticInsensitive, locale: .current)
            }
            let hits = stationsCopy.filter { st in
                let norm = normFast(st.name)
                return norm.contains(lowerQ)
            }
            
            var results: [VTSearchStation] = []
            var seenIDs = Set<String>()
            for r in hits {
                guard Self.isValidStationName(r.name) else { continue }
                let vtID = r.vtID ?? r.rfiID ?? ""
                let key = vtID.isEmpty ? r.name : vtID
                if !seenIDs.contains(key) {
                    seenIDs.insert(key)
                    results.append(VTSearchStation(nomeLungo: r.name, nomeBreve: r.name, vtID: vtID))
                }
            }
            results.sort { $0.nomeLungo < $1.nomeLungo }
            return results
        }.value
        
        guard !Task.isCancelled else { self.isSearching = false; return }
        self.searchStationResults = sortedResults
        self.isSearching = false
    }
    
    func searchTravelLocations(query: String) async {
        guard query.count >= 2 else { self.searchTrenitaliaLocations = []; return }
        self.isSearching = true
        
        func fetchLocations(for q: String) async -> [TrenitaliaLocation]? {
            let safeQuery = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            let urlString = "https://www.lefrecce.it/Channels.Website.BFF.WEB/website/locations/search?name=\(safeQuery)"
            guard let url = URL(string: urlString) else { return nil }
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            do {
                let (data, _) = try await NetworkService.shared.get(request: request)
                let decoded = (try? JSONDecoder().decode([TrenitaliaLocation].self, from: data)) ?? []
                return decoded.filter { isValidStationName($0.name) }
            } catch {
                return nil
            }
        }
        
        var results = await fetchLocations(for: query) ?? []
        
        if results.isEmpty && (query.contains("-") || query.contains(".") || query.contains("/")) {
            let spaceCleaned = query.replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "/", with: " ")
                .replacingOccurrences(of: ".", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if spaceCleaned != query && spaceCleaned.count >= 2 {
                results = await fetchLocations(for: spaceCleaned) ?? []
            }
        }
        
        if results.isEmpty {
            let parts = query.components(separatedBy: CharacterSet(charactersIn: "-/"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 2 }
            if let first = parts.first, first != query {
                results = await fetchLocations(for: first) ?? []
            }
        }
        
        guard !Task.isCancelled else { self.isSearching = false; return }
        self.searchTrenitaliaLocations = results
        self.isSearching = false
    }
    
struct MetroDirectRoute: Sendable {
    let line: String
    let headsign: String
    let minutes: Int
}

nonisolated static func addMinutesToTime(_ timeStr: String, _ mins: Int) -> String {
    let upper = timeStr.uppercased()
    let isPM = upper.contains("PM")
    let isAM = upper.contains("AM")
    let clean = upper.replacingOccurrences(of: "AM", with: "").replacingOccurrences(of: "PM", with: "").trimmingCharacters(in: .whitespaces)
    let parts = clean.split(separator: ":")
    guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return timeStr }
    var hour = h
    if isPM && hour < 12 { hour += 12 }
    else if isAM && hour == 12 { hour = 0 }
    let total = (hour * 60 + m + mins) % 1440
    let newH = total / 60
    let newM = total % 60
    if isPM || isAM {
        let suffix = newH >= 12 ? "PM" : "AM"
        var dispH = newH % 12
        if dispH == 0 { dispH = 12 }
        return String(format: "%d:%02d %@", dispH, newM, suffix)
    } else {
        return String(format: "%02d:%02d", newH, newM)
    }
}

nonisolated func addMinutesToTime(_ timeStr: String, _ mins: Int) -> String {
    Self.addMinutesToTime(timeStr, mins)
}

nonisolated static func calculateDurationBetween(dep: String, arr: String) -> String? {
    func parseMins(_ s: String) -> Int? {
        let clean = s.uppercased().replacingOccurrences(of: "AM", with: "").replacingOccurrences(of: "PM", with: "").trimmingCharacters(in: .whitespaces)
        let parts = clean.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        var hour = h
        if s.uppercased().contains("PM") && hour < 12 { hour += 12 }
        else if s.uppercased().contains("AM") && hour == 12 { hour = 0 }
        return hour * 60 + m
    }
    guard let m1 = parseMins(dep), let m2 = parseMins(arr) else { return nil }
    var diff = m2 - m1
    if diff < 0 { diff += 1440 }
    if diff < 60 {
        return "\(diff)min"
    } else {
        let hrs = diff / 60
        let rem = diff % 60
        return rem > 0 ? "\(hrs)h \(rem)min" : "\(hrs)h"
    }
}

nonisolated func calculateDurationBetween(dep: String, arr: String) -> String? {
    Self.calculateDurationBetween(dep: dep, arr: arr)
}

nonisolated static func localResolveUrbanLeg(orig: String, dest: String, time: String) -> (line: String, headsign: String, mins: Int, dep: String, arr: String)? {
    let oLow = orig.lowercased()
    let dLow = dest.lowercased()
    
    // Milano Porta Garibaldi Superficie e Passante sono la stessa identica stazione: nessun tragitto urbano
    if oLow.contains("garibaldi") && dLow.contains("garibaldi") &&
       !oLow.contains("pavia") && !dLow.contains("pavia") &&
       !oLow.contains("casalecchio") && !dLow.contains("casalecchio") &&
       !oLow.contains("napoli") && !dLow.contains("napoli") {
        return nil
    }
    
    func cleanStation(_ s: String) -> String {
        var str = s.uppercased()
        let toRemove = ["MILANO ", "PASSANTE", "SUPERFICIE", "SOTTERRANEA", "FS", "F.S.", "POLITECNICO", "PORTA ", "P.TA ", "P. ", "P "]
        for w in toRemove { str = str.replacingOccurrences(of: w, with: "") }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var c1 = cleanStation(orig)
    var c2 = cleanStation(dest)
    guard !c1.isEmpty && !c2.isEmpty else { return nil }
    
    if c1 == c2 {
        // Stessa stazione: nessun tragitto urbano necessario
        return nil
    }
    
    if c1.contains("GARIBALDI") && !c1.contains("PAVIA") && !c1.contains("CASALECCHIO") && !c1.contains("NAPOLI") { c1 = "GARIBALDI" }
    if c2.contains("GARIBALDI") && !c2.contains("PAVIA") && !c2.contains("CASALECCHIO") && !c2.contains("NAPOLI") { c2 = "GARIBALDI" }
    if c1.contains("CENTRALE") { c1 = "CENTRALE" }
    if c2.contains("CENTRALE") { c2 = "CENTRALE" }
    if c1.contains("CADORNA") { c1 = "CADORNA" }
    if c2.contains("CADORNA") { c2 = "CADORNA" }
    if c1.contains("REPUBBLICA") { c1 = "REPUBBLICA" }
    if c2.contains("REPUBBLICA") { c2 = "REPUBBLICA" }
    if c1.contains("DATEO") { c1 = "DATEO" }
    if c2.contains("DATEO") { c2 = "DATEO" }
    if c1.contains("LAMBRATE") { c1 = "LAMBRATE" }
    if c2.contains("LAMBRATE") { c2 = "LAMBRATE" }
    if c1.contains("ROGOREDO") { c1 = "ROGOREDO" }
    if c2.contains("ROGOREDO") { c2 = "ROGOREDO" }
    
    let routes: [String: [String: MetroDirectRoute]] = [
        "GARIBALDI": [
            "CADORNA": MetroDirectRoute(line: "M2", headsign: "Assago Forum / Abbiategrasso", minutes: 5),
            "CENTRALE": MetroDirectRoute(line: "M2", headsign: "Cologno Nord / Gessate", minutes: 4),
            "DOMODOSSOLA": MetroDirectRoute(line: "M5", headsign: "San Siro Stadio", minutes: 5),
            "LAMBRATE": MetroDirectRoute(line: "M2", headsign: "Cologno Nord / Gessate", minutes: 13),
            "PORTA GENOVA": MetroDirectRoute(line: "M2", headsign: "Assago Forum / Abbiategrasso", minutes: 10),
            "ROMOLO": MetroDirectRoute(line: "M2", headsign: "Assago Forum / Abbiategrasso", minutes: 12),
            "FAMAGOSTA": MetroDirectRoute(line: "M2", headsign: "Assago Forum / Abbiategrasso", minutes: 15),
            "PORTA VENEZIA": MetroDirectRoute(line: "M2", headsign: "Cologno Nord / Gessate", minutes: 10),
            "DUOMO": MetroDirectRoute(line: "M2", headsign: "Assago Forum (cambio Cadorna M1)", minutes: 9),
            "SAN BABILA": MetroDirectRoute(line: "M2", headsign: "Cologno Nord (cambio Loreto M1)", minutes: 11)
        ],
        "CADORNA": [
            "GARIBALDI": MetroDirectRoute(line: "M2", headsign: "Gessate / Cologno Nord", minutes: 5),
            "CENTRALE": MetroDirectRoute(line: "M2", headsign: "Gessate / Cologno Nord", minutes: 9),
            "DUOMO": MetroDirectRoute(line: "M1", headsign: "Sesto 1° Maggio FS", minutes: 4),
            "SAN BABILA": MetroDirectRoute(line: "M1", headsign: "Sesto 1° Maggio FS", minutes: 6),
            "PORTA VENEZIA": MetroDirectRoute(line: "M1", headsign: "Sesto 1° Maggio FS", minutes: 9),
            "PORTA GENOVA": MetroDirectRoute(line: "M2", headsign: "Assago Forum / Abbiategrasso", minutes: 5),
            "ROMOLO": MetroDirectRoute(line: "M2", headsign: "Assago Forum / Abbiategrasso", minutes: 7),
            "SESTO 1 MAGGIO": MetroDirectRoute(line: "M1", headsign: "Sesto 1° Maggio FS", minutes: 20),
            "RHO FIERA": MetroDirectRoute(line: "M1", headsign: "Rho Fieramilano", minutes: 22),
            "LOTTO": MetroDirectRoute(line: "M1", headsign: "Rho Fieramilano", minutes: 10),
            "DATEO": MetroDirectRoute(line: "M1", headsign: "Sesto (cambio S. Babila M4)", minutes: 12)
        ],
        "CENTRALE": [
            "CADORNA": MetroDirectRoute(line: "M2", headsign: "Assago Forum / Abbiategrasso", minutes: 9),
            "GARIBALDI": MetroDirectRoute(line: "M2", headsign: "Assago Forum / Abbiategrasso", minutes: 4),
            "REPUBBLICA": MetroDirectRoute(line: "M3", headsign: "San Donato", minutes: 2),
            "DUOMO": MetroDirectRoute(line: "M3", headsign: "San Donato", minutes: 6),
            "PORTA ROMANA": MetroDirectRoute(line: "M3", headsign: "San Donato", minutes: 10),
            "ROGOREDO": MetroDirectRoute(line: "M3", headsign: "San Donato", minutes: 14),
            "LAMBRATE": MetroDirectRoute(line: "M2", headsign: "Cologno Nord / Gessate", minutes: 9),
            "LORETO": MetroDirectRoute(line: "M2", headsign: "Cologno Nord / Gessate", minutes: 4),
            "AFFORI": MetroDirectRoute(line: "M3", headsign: "Comasina", minutes: 8),
            "SAN BABILA": MetroDirectRoute(line: "M3", headsign: "San Donato (cambio Duomo M1)", minutes: 8)
        ],
        "REPUBBLICA": [
            "CENTRALE": MetroDirectRoute(line: "M3", headsign: "Comasina", minutes: 2),
            "DUOMO": MetroDirectRoute(line: "M3", headsign: "San Donato", minutes: 4),
            "ROGOREDO": MetroDirectRoute(line: "M3", headsign: "San Donato", minutes: 12),
            "CADORNA": MetroDirectRoute(line: "M3", headsign: "Comasina (cambio Centrale M2)", minutes: 11),
            "GARIBALDI": MetroDirectRoute(line: "M3", headsign: "Comasina (cambio Centrale M2)", minutes: 6)
        ],
        "DATEO": [
            "SAN BABILA": MetroDirectRoute(line: "M4", headsign: "San Cristoforo", minutes: 4),
            "SAN CRISTOFORO": MetroDirectRoute(line: "M4", headsign: "San Cristoforo", minutes: 14),
            "LINATE AEROPORTO": MetroDirectRoute(line: "M4", headsign: "Linate Aeroporto", minutes: 8),
            "CADORNA": MetroDirectRoute(line: "M4", headsign: "San Cristoforo (cambio S. Babila M1)", minutes: 12),
            "CENTRALE": MetroDirectRoute(line: "M4", headsign: "San Cristoforo (cambio S. Babila M1/M3)", minutes: 14)
        ],
        "ROGOREDO": [
            "CENTRALE": MetroDirectRoute(line: "M3", headsign: "Comasina", minutes: 14),
            "DUOMO": MetroDirectRoute(line: "M3", headsign: "Comasina", minutes: 9),
            "REPUBBLICA": MetroDirectRoute(line: "M3", headsign: "Comasina", minutes: 12)
        ],
        "LAMBRATE": [
            "CENTRALE": MetroDirectRoute(line: "M2", headsign: "Assago Forum / Abbiategrasso", minutes: 9),
            "GARIBALDI": MetroDirectRoute(line: "M2", headsign: "Assago Forum / Abbiategrasso", minutes: 13),
            "CADORNA": MetroDirectRoute(line: "M2", headsign: "Assago Forum / Abbiategrasso", minutes: 18)
        ]
    ]
    
    if let destMap = routes[c1], let route = destMap[c2] {
        let arr = Self.addMinutesToTime(time, route.minutes)
        return (line: route.line, headsign: route.headsign, mins: route.minutes, dep: time, arr: arr)
    }
    
    return nil
}

nonisolated func localResolveUrbanLeg(orig: String, dest: String, time: String) -> (line: String, headsign: String, mins: Int, dep: String, arr: String)? {
    Self.localResolveUrbanLeg(orig: orig, dest: dest, time: time)
}

nonisolated static func collapseUrbanSegments(_ rawSegments: [TravelSegment]) -> [TravelSegment] {
    func isSameStation(_ s1: String, _ s2: String) -> Bool {
        let low1 = s1.lowercased()
        let low2 = s2.lowercased()
        if low1.contains("garibaldi") && low2.contains("garibaldi") &&
           !low1.contains("pavia") && !low2.contains("pavia") &&
           !low1.contains("casalecchio") && !low2.contains("casalecchio") &&
           !low1.contains("napoli") && !low2.contains("napoli") {
            return true
        }
        func clean(_ s: String) -> String {
            var str = s.uppercased()
            let toRemove = ["MILANO ", "ROMA ", "NAPOLI ", "TORINO ", "BOLOGNA ", "FIRENZE ", "PASSANTE", "SUPERFICIE", "SOTTERRANEA", "SOTTERRANEO", "SOTT.", "FS", "F.S.", "POLITECNICO", "PORTA ", "P.TA ", "P. ", "P "]
            for w in toRemove { str = str.replacingOccurrences(of: w, with: "") }
            return str.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let c1 = clean(s1)
        let c2 = clean(s2)
        return !c1.isEmpty && !c2.isEmpty && c1 == c2
    }
    
    // Rimuovi prima qualsiasi segmento che sia un passaggio interno alla stessa stazione
    let filtered = rawSegments.filter { !isSameStation($0.origin, $0.destination) }
    guard filtered.count > 1 else { return filtered }
    var result: [TravelSegment] = []
    var i = 0
    while i < filtered.count {
        let current = filtered[i]
        let isCurrentUrban = current.trainCategory == "Trasporto Urbano" || current.trainCategory == "Interscambio a piedi"
        
        if isCurrentUrban && i + 1 < filtered.count {
            let next = filtered[i + 1]
            let isNextUrban = next.trainCategory == "Trasporto Urbano" || next.trainCategory == "Interscambio a piedi"
            
            if isNextUrban {
                let mergedOrig = current.origin
                let mergedDest = next.destination
                let depTime = current.departureTime
                
                if isSameStation(mergedOrig, mergedDest) {
                    i += 2
                    continue
                }
                
                var resolvedCat = "Trasporto Urbano"
                var resolvedNum = "(Metro / Mezzi)"
                var resolvedMins: Int? = nil
                var resolvedHeadsign: String? = nil
                var resolvedArrTime = next.arrivalTime
                var isWalk = false
                
                if let solved = localResolveUrbanLeg(orig: mergedOrig, dest: mergedDest, time: depTime) {
                    if solved.line.isEmpty {
                        resolvedCat = "Interscambio a piedi"
                        resolvedNum = "A piedi"
                        isWalk = true
                    } else {
                        resolvedCat = "Metro \(solved.line)"
                        resolvedNum = "\(solved.line) (Metro)"
                    }
                    resolvedHeadsign = solved.headsign
                    resolvedMins = solved.mins
                    resolvedArrTime = solved.arr
                }
                
                var merged = TravelSegment(
                    origin: mergedOrig,
                    destination: mergedDest,
                    departureTime: depTime,
                    arrivalTime: resolvedArrTime,
                    trainNumber: resolvedNum,
                    trainCategory: resolvedCat,
                    travelMinutes: resolvedMins,
                    urbanHeadsign: resolvedHeadsign,
                    isStationWalk: isWalk
                )
                
                i += 2
                while i < filtered.count && (filtered[i].trainCategory == "Trasporto Urbano" || filtered[i].trainCategory == "Interscambio a piedi") {
                    merged.destination = filtered[i].destination
                    if isSameStation(merged.origin, merged.destination) {
                        break
                    }
                    if let solved = localResolveUrbanLeg(orig: merged.origin, dest: merged.destination, time: merged.departureTime) {
                        merged.trainCategory = solved.line.isEmpty ? "Interscambio a piedi" : "Metro \(solved.line)"
                        merged.trainNumber = solved.line.isEmpty ? "A piedi" : "\(solved.line) (Metro)"
                        merged.urbanHeadsign = solved.headsign
                        merged.travelMinutes = solved.mins
                        merged.arrivalTime = solved.arr
                    } else {
                        merged.arrivalTime = filtered[i].arrivalTime
                    }
                    i += 1
                }
                if !isSameStation(merged.origin, merged.destination) {
                    result.append(merged)
                }
                continue
            }
        }
        
        result.append(current)
        i += 1
    }
    return result
}

nonisolated func collapseUrbanSegments(_ rawSegments: [TravelSegment]) -> [TravelSegment] {
    Self.collapseUrbanSegments(rawSegments)
}

    func searchTravelSolutions(originID: String, destID: String, date: Date) async {
        self.isSearchingSolutions = true
        self.travelSolutions = []
        
        guard let depId = Int(originID), let arrId = Int(destID) else {
            self.isSearchingSolutions = false
            return
        }
        
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.000ZZZZZ"
        let dateStr = f.string(from: date)
        
        let urlString = "https://www.lefrecce.it/Channels.Website.BFF.WEB/website/ticket/solutions"
        guard let url = URL(string: urlString) else { self.isSearchingSolutions = false; return }
        
        let payload: [String: Any] = [
            "departureLocationId": depId,
            "arrivalLocationId": arrId,
            "departureTime": dateStr,
            "adults": 1,
            "children": 0,
            "criteria": [
                "frecceOnly": false,
                "regionalOnly": false,
                "noChanges": false,
                "order": "DEPARTURE_DATE",
                "offset": 0,
                "limit": 15
            ],
            "advancedSearchRequest": [
                "bestFare": false
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, _) = try await NetworkService.shared.post(request: request)
            guard !Task.isCancelled else { self.isSearchingSolutions = false; return }
            
            let parsedSolutions = await Task.detached(priority: .userInitiated) {
                Self.parseTravelSolutions(from: data)
            }.value
            
            guard !Task.isCancelled else { self.isSearchingSolutions = false; return }
            self.travelSolutions = parsedSolutions
            self.isSearchingSolutions = false
        } catch {
            self.isSearchingSolutions = false
        }
    }
    
    nonisolated static func parseTravelSolutions(from data: Data) -> [TravelSolution] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.000ZZZZZ"
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let solutions = json["solutions"] as? [[String: Any]] else {
            return []
        }
        
        var parsedSolutions: [TravelSolution] = []
        
        for item in solutions {
            guard let sol = item["solution"] as? [String: Any] else { continue }
            
            let origin = (sol["origin"] as? String) ?? ""
            let destination = (sol["destination"] as? String) ?? ""
            var duration = (sol["duration"] as? String) ?? ""
            
            var depTimeStr = "--:--"
            var arrTimeStr = "--:--"
            
            if let dt = sol["departureTime"] as? String, let d = f.date(from: dt) {
                depTimeStr = SharedFormatters.time.string(from: d)
            }
            if let at = sol["arrivalTime"] as? String, let a = f.date(from: at) {
                arrTimeStr = SharedFormatters.time.string(from: a)
            }
            
            var category = "Treno"
            var num = ""
            
            if let trains = sol["trains"] as? [[String: Any]], let firstTrain = trains.first {
                category = (firstTrain["trainCategory"] as? String) ?? (firstTrain["acronym"] as? String) ?? "Treno"
                num = (firstTrain["name"] as? String) ?? (firstTrain["description"] as? String) ?? ""
                
                if trains.count > 1 {
                    num += " (+\(trains.count - 1) cambi)"
                }
            }
            
            var segments: [TravelSegment] = []
            
            if let nodes = sol["nodes"] as? [[String: Any]] {
                for node in nodes {
                    let nodeOrigin = (node["origin"] as? String) ?? ""
                    let nodeDest = (node["destination"] as? String) ?? ""
                    var nDepStr = "--:--"
                    var nArrStr = "--:--"
                    
                    if let dt = node["departureTime"] as? String, let d = f.date(from: dt) { nDepStr = SharedFormatters.time.string(from: d) }
                    if let at = node["arrivalTime"] as? String, let a = f.date(from: at) { nArrStr = SharedFormatters.time.string(from: a) }
                    
                    var nCat = "Treno"
                    var nNum = ""
                    if let train = node["train"] as? [String: Any] {
                        nCat = (train["trainCategory"] as? String) ?? (train["acronym"] as? String) ?? "Treno"
                        nNum = (train["name"] as? String) ?? (train["description"] as? String) ?? ""
                    }
                    
                    var isWalk = false
                    var travelMins: Int? = nil
                    
                    func isSameStationWalk(orig: String, dest: String) -> Bool {
                        let oLow = orig.lowercased()
                        let dLow = dest.lowercased()
                        if oLow.contains("garibaldi") && dLow.contains("garibaldi") &&
                           !oLow.contains("pavia") && !dLow.contains("pavia") &&
                           !oLow.contains("casalecchio") && !dLow.contains("casalecchio") &&
                           !oLow.contains("napoli") && !dLow.contains("napoli") {
                            return true
                        }
                        func clean(_ s: String) -> String {
                            var str = s.uppercased()
                            let toRemove = ["MILANO ", "ROMA ", "NAPOLI ", "TORINO ", "BOLOGNA ", "FIRENZE ", "PASSANTE", "SUPERFICIE", "SOTTERRANEA", "SOTTERRANEO", "SOTT.", "FS", "F.S.", "POLITECNICO", "PORTA ", "P.TA ", "P. ", "P "]
                            for w in toRemove { str = str.replacingOccurrences(of: w, with: "") }
                            return str.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        let c1 = clean(orig)
                        let c2 = clean(dest)
                        return !c1.isEmpty && !c2.isEmpty && c1 == c2
                    }
                    
                    var resolvedHeadsign: String? = nil
                    
                    let isUrbanNode = {
                        if let isU = (node["train"] as? [String: Any])?["urban"] as? Bool, isU { return true }
                        let catLower = nCat.lowercased()
                        let numLower = nNum.lowercased()
                        if catLower.contains("suburbano") || numLower.contains("suburbano") { return false }
                        if catLower == "ub" || numLower == "ub" || catLower.contains("urban") || numLower.contains("urban") || catLower.contains("metro") { return true }
                        if ((node["train"] as? [String: Any])?["acronym"] as? String)?.uppercased() == "UB" { return true }
                        return false
                    }()
                    
                    // Se è un interscambio interno alla stessa stazione (es. Garibaldi Superficie <-> Garibaldi Passante / Sotterranea),
                    // NON deve MAI comparire come segmento di viaggio! È la stessa stazione, il passeggero va direttamente al binario.
                    if isSameStationWalk(orig: nodeOrigin, dest: nodeDest) {
                        continue
                    } else if isUrbanNode || (nodeOrigin.lowercased().hasPrefix("milano") && nodeDest.lowercased().hasPrefix("milano") && nodeOrigin != nodeDest && (nNum.isEmpty || nNum.lowercased() == "ub")) {
                        if let solved = Self.localResolveUrbanLeg(orig: nodeOrigin, dest: nodeDest, time: nDepStr) {
                            if solved.line.isEmpty {
                                nCat = "Interscambio a piedi"
                                nNum = "A piedi"
                                isWalk = true
                            } else {
                                nCat = "Metro \(solved.line)"
                                nNum = "\(solved.line) (Metro)"
                            }
                            travelMins = solved.mins
                            resolvedHeadsign = solved.headsign
                            nArrStr = solved.arr
                        } else {
                            nCat = "Trasporto Urbano"
                            nNum = "(Metro / Mezzi)"
                        }
                    }
                    
                    segments.append(TravelSegment(
                        origin: nodeOrigin,
                        destination: nodeDest,
                        departureTime: nDepStr,
                        arrivalTime: nArrStr,
                        trainNumber: nNum,
                        trainCategory: nCat,
                        travelMinutes: travelMins,
                        urbanHeadsign: resolvedHeadsign,
                        isStationWalk: isWalk
                    ))
                }
            }
            
            // 1. Collassa eventuali collegamenti urbani consecutivi (es. Garibaldi -> Centrale e poi Centrale -> Cadorna diventano un unico Garibaldi -> Cadorna diretto!)
            segments = Self.collapseUrbanSegments(segments)
            
            // 2. Se sono stati rimossi segmenti o modificati collegamenti, sincronizza orari reali e durata complessiva
            if let f = segments.first, f.departureTime != "--:--" {
                depTimeStr = f.departureTime
            }
            if let last = segments.last, last.arrivalTime != "--:--" {
                arrTimeStr = last.arrivalTime
            }
            if let f = segments.first, let last = segments.last, f.departureTime != "--:--", last.arrivalTime != "--:--",
               let updatedDur = Self.calculateDurationBetween(dep: f.departureTime, arr: last.arrivalTime) {
                duration = updatedDur
            }
            
            parsedSolutions.append(TravelSolution(
                trainNumber: num,
                category: category,
                departureTime: depTimeStr,
                arrivalTime: arrTimeStr,
                origin: origin.capitalized,
                destination: destination.capitalized,
                duration: duration,
                segments: segments
            ))
        }
        
        return parsedSolutions
    }
    
    func searchRFIStationsLocally(query: String) {
        guard query.count >= 2 else { self.searchRFIStationResults = []; return }
        let lowerQuery = normalizeStationName(query)
        let hits = self.allRFIStations.filter { normalizeStationName($0.name).contains(lowerQuery) && isValidStationName($0.name) }
        
        var unique: [RFIStation] = []
        var seen = Set<String>()
        for r in hits {
            let key = r.vtID ?? r.rfiID ?? r.name
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(r)
            }
        }
        self.searchRFIStationResults = unique
    }
    
    
    func fetchVTTrains(for vtID: String, isDepartures: Bool, force: Bool = false) async {
        let dummyStation = Station(name: "", rfiID: nil, vtID: vtID, lat: nil, lon: nil)
        await fetchTrains(for: dummyStation, isDepartures: isDepartures, force: force)
    }
    
    func fetchTrains(for station: Station, isDepartures: Bool, force: Bool = false) async {
        let stationKey = "\(station.vtID ?? station.rfiID ?? station.name)_\(isDepartures)"
        
        if self.lastFetchedStationKey != stationKey {
            self.trains = []
            self.lastFetchedStationKey = stationKey
        }
        self.isLoading = true
        self.stationAlerts = nil
        
        let board = await StationRepository.shared.getStationBoard(station: station, isDepartures: isDepartures, force: force)
        guard !Task.isCancelled else {
            self.isLoading = false
            return
        }
        
        self.trains = board.trains
        self.stationAlerts = board.alerts
        self.isLoading = false
    }
    
    nonisolated func resolveUrbanLeg(orig: String, dest: String, time: String) async -> (line: String, headsign: String, mins: Int, dep: String, arr: String)? {
        let local = localResolveUrbanLeg(orig: orig, dest: dest, time: time)
        
        guard let urlOrig = orig.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let urlDest = dest.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let urlTime = time.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://gestioneinorario.toreroclub.com/metro/solve_leg?orig=\(urlOrig)&dest=\(urlDest)&time=\(urlTime)") else {
            return local
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2.5
            let (data, response) = try await NetworkService.shared.get(request: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let line = json["line"] as? String,
                  let dep = json["departure_time"] as? String,
                  let arr = json["arrival_time"] as? String else {
                return local
            }
            let headsign = (json["headsign"] as? String) ?? (local?.headsign ?? "")
            let mins = (json["travel_minutes"] as? Int) ?? (local?.mins ?? 5)
            return (line: line, headsign: headsign, mins: mins, dep: dep, arr: arr)
        } catch {
            return local
        }
    }
    
    nonisolated func fetchLiveStops(
        for trainNumber: String,
        category: String? = nil,
        destination: String? = nil,
        origin: String? = nil,
        scheduledTime: String? = nil,
        force: Bool = false
    ) async -> StopsResult {
        await TrainRepository.shared.getLiveStops(
            for: trainNumber,
            category: category,
            destination: destination,
            origin: origin,
            scheduledTime: scheduledTime,
            force: force
        )
    }
    
    func fetchStops(for train: Train, isRefresh: Bool = false) async {
        if !isRefresh {
            self.selectedTrainStops = []
            self.currentTrainStatus = TrainStatus()
            self.isStopsLoading = true
            self.stopErrorMessage = nil
        }
        
        let cleanNumber = train.number.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await fetchLiveStops(
            for: cleanNumber,
            category: train.category,
            destination: train.destination,
            origin: train.origin,
            scheduledTime: train.time,
            force: isRefresh
        )
        guard !Task.isCancelled else {
            if !isRefresh { self.isStopsLoading = false }
            return
        }
        
        if !isRefresh || result.errorMessage == nil {
            self.selectedTrainStops = result.stops
            self.currentTrainStatus = result.status
            self.stopErrorMessage = result.errorMessage
        }
        
        self.fetchComfortReports(for: cleanNumber)
        
        if !isRefresh {
            self.isStopsLoading = false
        }
        
        if result.errorMessage == nil {
            let globalDelay = result.status.statusMessage.contains("Soppresso") ? 0 : (result.stops.last?.delay ?? 0)
            let delayStr = globalDelay > 0 ? "+\(globalDelay)'" : "In orario"
            let stops = result.stops
            let lastStation = result.status.lastStation
            let isArrived = result.status.isArrived
            
            var progressVal: Double = 0.0
            if isArrived {
                progressVal = 1.0
            } else if !stops.isEmpty {
                if stops.count == 1 {
                    progressVal = 1.0
                } else {
                    let lastClean = lastStation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if let idx = stops.firstIndex(where: { 
                        $0.stationName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lastClean 
                    }) {
                        progressVal = Double(idx) / Double(stops.count - 1)
                    }
                }
            }
            
            let updatedState = TrainLiveActivityAttributes.ContentState(
                delay: delayStr,
                statusMessage: result.status.statusMessage,
                lastStation: lastStation,
                progress: progressVal
            )
            
            for activity in Activity<TrainLiveActivityAttributes>.activities {
                if activity.attributes.trainNumber == cleanNumber {
                    await activity.update(ActivityContent(state: updatedState, staleDate: nil))
                }
            }
            
            if let favIdx = favoriteTrains.firstIndex(where: { $0.number == cleanNumber }) {
                let isCanc = result.status.statusMessage.contains("Soppresso")
                let dText = isCanc ? "Soppresso" : (globalDelay > 0 ? "Ritardo \(globalDelay) min" : "In orario")
                let cText = isCanc ? "red" : (globalDelay > 0 ? "red" : "green")
                if favoriteTrains[favIdx].lastDelayText != dText || favoriteTrains[favIdx].lastDelayColorName != cText {
                    favoriteTrains[favIdx].lastDelayText = dText
                    favoriteTrains[favIdx].lastDelayColorName = cText
                    saveFavorites()
                }
            }
        }
    }
    
    func fetchComfortReports(for trainNumber: String) {
        let cleanNumber = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/trains/\(cleanNumber)/reports") else { return }
        
        Task {
            do {
                let (data, _) = try await NetworkService.shared.get(url: url)
                if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    await MainActor.run {
                        var counts: [String: Int] = ["crowded": 0, "hot": 0, "cold": 0, "stopped": 0]
                        for key in counts.keys {
                            counts[key] = dict[key] as? Int ?? 0
                        }
                        self.currentTrainReports = counts
                        self.currentTrainBlockedLocations = dict["blocked_locations"] as? [String] ?? []
                        
                        // Automated self-healing check:
                        if let stoppedMetadata = dict["stopped_metadata"] as? [[String: String]], !stoppedMetadata.isEmpty {
                            let currentStatus = self.currentTrainStatus
                            if currentStatus.isDeparted {
                                let currentStation = currentStatus.lastStation.trimmingCharacters(in: .whitespacesAndNewlines)
                                let currentTime = currentStatus.lastTime.trimmingCharacters(in: .whitespacesAndNewlines)
                                
                                var hasMoved = false
                                for meta in stoppedMetadata {
                                    let repStation = (meta["last_station"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                    let repTime = (meta["last_time"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                    
                                    if (!repStation.isEmpty && currentStation != repStation) || 
                                       (!repTime.isEmpty && currentTime != repTime) {
                                        hasMoved = true
                                        break
                                    }
                                }
                                
                                if hasMoved {
                                    print("[-] Rilevato movimento ufficiale del treno (\(currentStation) alle \(currentTime)). Invio cancellazione automatica blocco.")
                                    self.postComfortReport(for: trainNumber, type: "moving")
                                }
                            }
                        }
                    }
                }
            } catch {
                AppLogger.decodingError(context: "ComfortReports:\(cleanNumber)", error: error)
            }
        }
    }
    
    func postComfortReport(for trainNumber: String, type: String, locality: String? = nil, lastStation: String? = nil, lastTime: String? = nil) {
        let cleanNumber = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/trains/report") else { return }
        
        var payload: [String: Any] = [
            "train_number": cleanNumber,
            "report_type": type
        ]
        if let loc = locality {
            payload["locality"] = loc
        }
        if let ls = lastStation {
            payload["last_station"] = ls
        }
        if let lt = lastTime {
            payload["last_time"] = lt
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        Task {
            do {
                _ = try await NetworkService.shared.post(url: url, payload: payload)
                await MainActor.run {
                    self.fetchComfortReports(for: cleanNumber)
                }
            } catch {
                print("Errore encoding/invio comfort report: \(error)")
            }
        }
    }
    
    func startAutoRefresh(for station: Station, isDepartures: Bool) {
        refreshTimer?.cancel()
        refreshTimer = Timer.publish(every: 45, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { await self?.fetchTrains(for: station, isDepartures: isDepartures) }
        }
    }
    
    func stopAutoRefresh() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }
    
    func getEffectiveDeviceToken() -> String {
        if let token = self.apnsToken, !token.isEmpty {
            return token
        }
        let fallbackKey = "app_unique_client_id_v1"
        if let saved = UserDefaults.standard.string(forKey: fallbackKey), !saved.isEmpty {
            return saved
        }
        let newId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(newId, forKey: fallbackKey)
        return newId
    }

    func syncLiveActivities() {
        let active = Activity<TrainLiveActivityAttributes>.activities.map { $0.attributes.trainNumber }
        self.activeLiveActivities = Set(active)
        
        guard self.hasSupport() else { return }
        
        let deviceToken = getEffectiveDeviceToken()
        for activity in Activity<TrainLiveActivityAttributes>.activities {
            if let pushToken = activity.pushToken {
                self.registerLiveActivityToken(pushToken: pushToken, trainNumber: activity.attributes.trainNumber, deviceToken: deviceToken)
            }
            Task {
                for await tokenData in activity.pushTokenUpdates {
                    let dt = self.getEffectiveDeviceToken()
                    self.registerLiveActivityToken(pushToken: tokenData, trainNumber: activity.attributes.trainNumber, deviceToken: dt)
                    break
                }
            }
        }
    }
    
    func observeAllLiveActivityPushTokens() {
        // Ascolta la creazione di NUOVE Live Activities (solo sostenitori)
        Task {
            for await activity in Activity<TrainLiveActivityAttributes>.activityUpdates {
                Task {
                    for await tokenData in activity.pushTokenUpdates {
                        guard self.hasSupport() else { break }
                        let deviceToken = self.getEffectiveDeviceToken()
                        self.registerLiveActivityToken(pushToken: tokenData, trainNumber: activity.attributes.trainNumber, deviceToken: deviceToken)
                    }
                }
                
                Task {
                    for await state in activity.activityStateUpdates {
                        if state == .ended || state == .dismissed {
                            let deviceToken = self.getEffectiveDeviceToken()
                            self.unregisterLiveActivityToken(trainNumber: activity.attributes.trainNumber, deviceToken: deviceToken)
                        }
                    }
                }
            }
        }
        
        // Ascolta gli aggiornamenti dei token per le Live Activities GIÀ ESISTENTI (es. riapertura app)
        for activity in Activity<TrainLiveActivityAttributes>.activities {
            Task {
                for await tokenData in activity.pushTokenUpdates {
                    guard self.hasSupport() else { break }
                    let deviceToken = self.getEffectiveDeviceToken()
                    self.registerLiveActivityToken(pushToken: tokenData, trainNumber: activity.attributes.trainNumber, deviceToken: deviceToken)
                }
            }
            
            Task {
                for await state in activity.activityStateUpdates {
                    if state == .ended || state == .dismissed {
                        let deviceToken = self.getEffectiveDeviceToken()
                        self.unregisterLiveActivityToken(trainNumber: activity.attributes.trainNumber, deviceToken: deviceToken)
                    }
                }
            }
        }
    }
    
    func backgroundLiveActivityUpdate() async {
        syncLiveActivities()
        guard !activeLiveActivities.isEmpty else { return }
        
        for trainNumber in activeLiveActivities {
            let dummy = Train(category: "REG", number: trainNumber, destination: "", time: "", delay: "", platform: "")
            await fetchStops(for: dummy, isRefresh: true)
        }
    }
    
    func createDummyTrain(from saved: SavedTrain) -> Train {
        var cat = "REG"
        if isItaloTrain(category: nil, number: saved.number) || saved.description.localizedCaseInsensitiveContains("Italo") { cat = "Italo" }
        else if saved.number.hasPrefix("20") || saved.number.hasPrefix("21") { cat = "RV" }
        else if saved.number.hasPrefix("24") || saved.number.hasPrefix("10") { cat = "S" }
        else if saved.number.hasPrefix("9") { cat = "FR" }
        return Train(category: cat, number: saved.number, destination: saved.description.capitalized, time: "--:--", delay: "In orario", platform: "--")
    }
    // MARK: - Hybrid AI / Fetching News
    
    func fetchStrikesAndNews(forceRefresh: Bool = false) async -> [NewsItem] {
        let strikeRegion = self.strikeRegion
        let isPremium = hasSupport()
        let smartSummaryEnabled = UserDefaults.standard.object(forKey: "ai_smartSummaryEnabled") as? Bool ?? true
        
        let lastFetch = UserDefaults.standard.double(forKey: "cachedNewsTimestamp")
        let now = Date().timeIntervalSince1970
        let cacheAge = now - lastFetch
        
        let cachedRegion = UserDefaults.standard.string(forKey: "cachedNewsRegion") ?? ""
        // Carica la cache se non è richiesto un aggiornamento forzato, è per la stessa regione ed è più recente di 5 minuti (300s)
        if !forceRefresh, cacheAge < 300.0, cachedRegion == strikeRegion, let cached = loadCache() {
            return Self.filterExpiredStrikes(cached)
        }
        
        var result: [NewsItem]
        let aiManager = AIFeatureManager.shared
        // Gli utenti con supporto attivo, oppure TUTTI gli utenti su "Lombardia" o "Tutte" (Nazionale), usano il Cloud backend con Gemini
        let isFreeCloudEligible = strikeRegion == "Lombardia" || strikeRegion == "Tutte" || strikeRegion.lowercased().contains("nazional")
        let canUseCloudBackend = (isPremium || isFreeCloudEligible) && !aiManager.preferLocalAI && aiManager.aiModeChoice != .none
        
        if canUseCloudBackend {
            let regionParam = strikeRegion.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Tutte"
            async let backendTask = fetchFromBackend(regionParam: regionParam)
            async let trenitaliaTask = LocalScrapingService.shared.scrapeTrenitalia(region: strikeRegion)
            let backendItems = await backendTask
            let localItems = await trenitaliaTask
            result = backendItems + localItems.filter { $0.category == "realtime" }
            
            saveCache(items: result)
        } else if aiManager.aiModeChoice == .local && (aiManager.isAppleIntelligenceAvailable || (aiManager.isHardwareCompatible && aiManager.isLocalModelInstalled)) && smartSummaryEnabled {
            let canRun = isPremium || aiManager.canRunFreeLocalAI()
            if canRun {
                let items = await executeLocalScrapingAndAI(region: strikeRegion)
                if !isPremium && !items.isEmpty {
                    aiManager.recordLocalAIExecution()
                    saveCache(items: items)
                }
                result = items
            } else {
                // Quota giornaliera esaurita: usa cache se disponibile, altrimenti scraping diretto
                if let cached = loadCache() {
                    result = cached
                } else {
                    result = await executeRawScraping(region: strikeRegion)
                    saveCache(items: result)
                }
            }
        } else {
            result = await executeRawScraping(region: strikeRegion)
            saveCache(items: result)
        }
        
        return Self.sortAndFilterNews(result)
    }
    
    nonisolated static func filterExpiredStrikes(_ items: [NewsItem]) -> [NewsItem] {
        let today = Calendar.current.startOfDay(for: Date())
        
        return items.filter { item in
            guard item.category == "sciopero", let dateStr = item.date else {
                return true // InfoLavori o altri item rimangono sempre
            }
            if item.isUrgent { return true }
            if let date = SharedFormatters.dateIT.date(from: dateStr) ?? SharedFormatters.dateISO.date(from: dateStr) {
                let strikeDay = Calendar.current.startOfDay(for: date)
                return strikeDay >= today
            }
            return true
        }
    }
    
    nonisolated static func sortAndFilterNews(_ items: [NewsItem]) -> [NewsItem] {
        var sorted = items
        sorted.sort { a, b in
            let dateA = a.sortableDate
            let dateB = b.sortableDate
            if dateA != dateB {
                return dateA < dateB
            }
            if a.isUrgent != b.isUrgent { return a.isUrgent }
            let catA = a.category ?? ""
            let catB = b.category ?? ""
            if catA == "sciopero" && catB != "sciopero" { return true }
            if catB == "sciopero" && catA != "sciopero" { return false }
            
            return a.title < b.title
        }
        return filterExpiredStrikes(sorted)
    }
    
    private func executeLocalScrapingAndAI(region: String) async -> [NewsItem] {
        // Scraping parallelo di entrambe le sorgenti
        async let trenitalia = LocalScrapingService.shared.scrapeTrenitalia(region: region)
        async let ministero  = LocalScrapingService.shared.scrapeMinistero(region: region)
        
        let allItems = await trenitalia + ministero
        guard !allItems.isEmpty else { return [] }
        
        // Il modello AI formatta TUTTI gli item (scioperi MIT e InfoLavori Trenitalia)
        if await AIEngine.shared.initializeIfNeeded() {
            return await AIEngine.shared.formatWithLocalModel(rawItems: allItems)
        }
        return allItems
    }
    
    func executeRawScraping(region: String) async -> [NewsItem] {
        async let trenitalia = LocalScrapingService.shared.scrapeTrenitalia(region: region)
        async let ministero  = LocalScrapingService.shared.scrapeMinistero(region: region)
        return await trenitalia + ministero
    }
    
    private func fetchFromBackend(regionParam: String) async -> [NewsItem] {
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/news?region=\(regionParam)") else { return [] }
        do {
            let (data, _) = try await NetworkService.shared.get(url: url)
            return try JSONDecoder().decode([NewsItem].self, from: data)
        } catch {
            AppLogger.decodingError(context: "NewsBackend:\(regionParam)", error: error)
            AppLogger.refreshFailed(target: "NewsBackend:\(regionParam)", error: error)
            return []
        }
    }
    
    func saveCache(items: [NewsItem]) {
        let region = strikeRegion
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(items) {
                UserDefaults.standard.set(data, forKey: "cachedStrikesAndNews")
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "cachedNewsTimestamp")
                UserDefaults.standard.set(region, forKey: "cachedNewsRegion")
            }
        }
    }
    
    func getCachedStrikesAndNews() -> [NewsItem] {
        if let cached = loadCache() {
            return Self.filterExpiredStrikes(cached)
        }
        return []
    }
    
    private func loadCache() -> [NewsItem]? {
        guard let data = UserDefaults.standard.data(forKey: "cachedStrikesAndNews"),
              let decoded = try? JSONDecoder().decode([NewsItem].self, from: data),
              !decoded.isEmpty else { return nil }
        return decoded
    }
}


enum PurchaseState: Equatable {
    case idle
    case purchasing
    case success
    case error(String)
}

enum TipError: Error {
    case unverified
}

@MainActor
class TipManager: ObservableObject {
    @Published var products: [Product] = []
    @Published var isLoadingProducts: Bool = true
    @Published var purchaseState: PurchaseState = .idle
    @Published var activeProductType: SupporterTierType? = nil
    
    enum SupporterTierType: String {
        case legacy = "legacy"
        case yearly = "yearly"
        case lifetime = "lifetime"
    }

    static let legacyProductID = "tip.colazionee"
    static let yearlySubscriptionID = "sub.supporter.yearly"
    static let lifetimeProductID = "tip.supporter.lifetime"
    
    // In vendita per i nuovi utenti: abbonamento annuale e acquisto una tantum
    private let productIDs = [yearlySubscriptionID, lifetimeProductID]
    private var transactionListener: Task<Void, Error>?
    
    init() {
        transactionListener = Task.detached {
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try TipManager.checkVerified(result)
                    await self.deliver(transaction)
                    await transaction.finish()
                } catch {
                    print("Errore durante l'ascolto delle transazioni di StoreKit: \(error)")
                }
            }
        }
    }
    
    deinit {
        transactionListener?.cancel()
    }
    
    func updatePurchases() async {
        var isSupporter = false
        var originalID: UInt64? = nil
        var detectedTier: SupporterTierType? = nil
        
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.legacyProductID {
                    isSupporter = true
                    originalID = transaction.originalID
                    detectedTier = .legacy
                } else if transaction.productID == Self.lifetimeProductID {
                    isSupporter = true
                    originalID = transaction.originalID
                    detectedTier = .lifetime
                } else if transaction.productID == Self.yearlySubscriptionID {
                    isSupporter = true
                    originalID = transaction.originalID
                    detectedTier = .yearly
                }
            }
        }
        
        self.activeProductType = detectedTier
        UserDefaults.standard.set(isSupporter, forKey: "tip.colazionee")
        if let origID = originalID {
            let supporterKey = "sup_\(origID)"
            UserDefaults.standard.set(supporterKey, forKey: "supporter_eternal_id")
            NSUbiquitousKeyValueStore.default.set(supporterKey, forKey: "supporter_eternal_id")
        }
        if let groupDefaults = UserDefaults(suiteName: "group.carlo.InOrario") {
            groupDefaults.set(isSupporter, forKey: "tip.colazionee")
        }
        NotificationCenter.default.post(name: NSNotification.Name("PurchasesUpdated"), object: nil)
    }
    
    func fetchProducts() async {
        self.isLoadingProducts = true
        await updatePurchases()
        do {
            let storeProducts = try await Product.products(for: productIDs)
            // Mostra prima l'annuale a 3,99 € e poi il lifetime a 9,99 €
            self.products = storeProducts.sorted(by: { $0.price < $1.price })
            self.isLoadingProducts = false
        } catch {
            print("Errore nel caricamento dei prodotti da StoreKit: \(error)")
            self.isLoadingProducts = false
        }
    }
    
    func purchase(_ product: Product) async {
        purchaseState = .purchasing
        Haptics.play(.medium)
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try TipManager.checkVerified(verification)
                await deliver(transaction)
                await transaction.finish()
                purchaseState = .success
                Haptics.notify(.success)
                
            case .pending:
                purchaseState = .error("L'acquisto è in attesa di approvazione dal tuo account.")
                Haptics.notify(.warning)
                
            case .userCancelled:
                purchaseState = .idle
                
            @unknown default:
                purchaseState = .error("Si è verificato un errore imprevisto.")
                Haptics.notify(.error)
            }
        } catch {
            purchaseState = .error(error.localizedDescription)
            Haptics.notify(.error)
        }
    }
    
    nonisolated static private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw TipError.unverified
        case .verified(let safeValue):
            return safeValue
        }
    }
    
    private func deliver(_ transaction: StoreKit.Transaction) async {
        let isSupporter = transaction.productID == Self.legacyProductID ||
                          transaction.productID == Self.lifetimeProductID ||
                          transaction.productID == Self.yearlySubscriptionID
        
        if isSupporter {
            UserDefaults.standard.set(true, forKey: "tip.colazionee")
            let supporterKey = "sup_\(transaction.originalID)"
            UserDefaults.standard.set(supporterKey, forKey: "supporter_eternal_id")
            NSUbiquitousKeyValueStore.default.set(supporterKey, forKey: "supporter_eternal_id")
        }
        
        if let groupDefaults = UserDefaults(suiteName: "group.carlo.InOrario") {
            if isSupporter {
                groupDefaults.set(true, forKey: "tip.colazionee")
            }
        }
        await updatePurchases()
        NotificationCenter.default.post(name: NSNotification.Name("PurchasesUpdated"), object: nil)
    }
    
    func resetState() {
        purchaseState = .idle
    }
}

// MARK: - MetroManager

@MainActor class MetroManager: ObservableObject {
    @Published var favoriteMetroStationIDs: [String] = [] {
        didSet { save() }
    }
    @Published var recentMetroStationIDs: [String] = [] {
        didSet { save() }
    }

    private let favKey = "metroFavoriteIDs_v1"
    private let recentKey = "metroRecentIDs_v1"
    private let maxRecent = 5

    // MARK: - Alerts and Status
    @Published var lineStatuses: [String: String] = [:]
    @Published var metroAlertMessage: String = ""
    @Published var isFetchingStatus = false

    init() { 
        load()
        Task {
            await fetchMetroStatus()
        }
    }

    // MARK: - Persistence
    private func save() {
        UserDefaults.standard.set(favoriteMetroStationIDs, forKey: favKey)
        UserDefaults.standard.set(recentMetroStationIDs, forKey: recentKey)
    }
    private func load() {
        favoriteMetroStationIDs = UserDefaults.standard.stringArray(forKey: favKey) ?? []
        recentMetroStationIDs = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }

    // MARK: - Fetch Status
    func fetchMetroStatus() async {
        guard !isFetchingStatus else { return }
        isFetchingStatus = true
        defer { isFetchingStatus = false }

        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/metro/status/milano") else { return }
        do {
            let (data, _) = try await NetworkService.shared.get(url: url)
            struct StatusResponse: Codable {
                let M1: String?
                let M2: String?
                let M3: String?
                let M4: String?
                let M5: String?
                let message: String?
            }
            let decoded = try JSONDecoder().decode(StatusResponse.self, from: data)
            lineStatuses = [
                "M1": decoded.M1 ?? "Regolare",
                "M2": decoded.M2 ?? "Regolare",
                "M3": decoded.M3 ?? "Regolare",
                "M4": decoded.M4 ?? "Regolare",
                "M5": decoded.M5 ?? "Regolare"
            ]
            metroAlertMessage = decoded.message ?? ""
        } catch {
            print("Errore caricamento stato metropolitana: \(error)")
        }
    }

    // MARK: - Data
    let allStations: [MetroStation] = MilanoMetroCatalog.stations

    var favoriteStations: [MetroStation] {
        favoriteMetroStationIDs.compactMap { id in allStations.first { $0.id == id } }
    }
    var recentStations: [MetroStation] {
        recentMetroStationIDs.compactMap { id in allStations.first { $0.id == id } }
    }

    // MARK: - Favorites
    func isFavorite(_ station: MetroStation) -> Bool {
        favoriteMetroStationIDs.contains(station.id)
    }
    func toggleFavorite(_ station: MetroStation) {
        if let idx = favoriteMetroStationIDs.firstIndex(of: station.id) {
            favoriteMetroStationIDs.remove(at: idx)
        } else {
            favoriteMetroStationIDs.append(station.id)
        }
    }

    // MARK: - Recents
    func addToRecent(_ station: MetroStation) {
        recentMetroStationIDs.removeAll { $0 == station.id }
        recentMetroStationIDs.insert(station.id, at: 0)
        if recentMetroStationIDs.count > maxRecent {
            recentMetroStationIDs = Array(recentMetroStationIDs.prefix(maxRecent))
        }
    }

    // MARK: - Search
    func search(query: String) -> [MetroStation] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return allStations }
        let cleanedQuery = query.lowercased().replacingOccurrences(of: " ", with: "")
        var searchTerms = [cleanedQuery]
        if cleanedQuery.count == 2 {
            let first = cleanedQuery.prefix(1)
            let last = cleanedQuery.suffix(1)
            if (first >= "1" && first <= "5") && (last == "m") {
                searchTerms.append("m" + first)
            }
        }
        
        return allStations.filter { station in
            let nameMatch = searchTerms.contains { term in station.displayName.lowercased().contains(term) }
            let lineMatch = station.lines.contains { line in
                searchTerms.contains { term in line.name.lowercased().contains(term) }
            }
            return nameMatch || lineMatch
        }
    }

    // MARK: - Nearby
    func nearbyStation(from location: CLLocationCoordinate2D?) -> MetroStation? {
        guard let loc = location else { return nil }
        let threshold = 0.008  // ~800m in degrees approx
        return allStations
            .map { station -> (MetroStation, Double) in
                let dlat = station.latitude - loc.latitude
                let dlon = station.longitude - loc.longitude
                return (station, sqrt(dlat*dlat + dlon*dlon))
            }
            .filter { $0.1 < threshold }
            .min(by: { $0.1 < $1.1 })
            .map { $0.0 }
    }
}
