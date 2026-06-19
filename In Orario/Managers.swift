import SwiftUI
import Combine
import Foundation
import CoreLocation
import ActivityKit
import StoreKit

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
    @Published var remoteNotificationsEnabled: Bool = false
    @Published var notifyOnStationPass: Bool = false
    @Published var strikeRegion: String = "Tutte" {
        didSet {
            saveFavorites()
            syncRemoteNotifications()
        }
    }
    @Published var apnsToken: String? = nil
    @Published var notificationLimitError: String? = nil
    
    private let remoteNotificationsEnabledKey = "remoteNotificationsEnabled_v1"
    private let notifyOnStationPassKey = "notifyOnStationPass_v1"
    private let strikeRegionKey = "strikeRegion_v1"
    private let apnsTokenKey = "apnsTokenKey_v1"

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
    @Published var searchRFIStationResults: [RFIStation] = []
    @Published var allRFIStations: [RFIStation] = []
    @Published var sectionOrder: [AppSection] = AppSection.allCases
    @Published var isSearching: Bool = false
    @Published var isLoading = false
    @Published var isStopsLoading = false
    @Published var stopErrorMessage: String? = nil
    @Published var deepLinkTrain: Train? = nil
    
    @Published var stationAlerts: String? = nil
    @Published var activeLiveActivities: Set<String> = []
    
    @Published var travelSolutions: [TravelSolution] = []
    @Published var favoriteRoutes: [FavoriteRoute] = []
    @Published var savedTrips: [SavedTrip] = []
    @Published var isSearchingSolutions: Bool = false
    
    @Published var selectedSuburbanLines: [String] = []
    @Published var hiddenSuburbanStations: [String: [String]] = [:]
    
    @Published var selectedPassanteStation: Station = Station(name: "Porta Venezia", rfiID: "1723", vtID: "S01061", lat: 45.4746, lon: 9.2052)
    @Published var passanteTrains: [Train] = []
    @Published var isLoadingPassanteBoard = false
    @Published var passanteTunnelHealthMessage: String = "Circolazione Regolare nel Tunnel"
    @Published var passanteTunnelHealthColor: String = "#009640"
    @Published var passanteTunnelAverageDelay: Int = 0
    @Published var passanteTunnelTrains: [Train] = []
    @Published var passanteLiveStatuses: [String: TrainStatus] = [:]
    @Published var smartRoutes: [SuburbanRoute] = []
    
    @Published var loadedSmartRouteDetails: [String: SmartRouteDetails] = [:]
    @Published var isLoadingSmartRoutes = false
    @Published var homeDestinationStationName: String = ""
    @Published var isHomeFilterActive: Bool = false
    @Published var recentTrains: [SavedTrain] = []
    @Published var recentStations: [VTSearchStation] = []
    
    @Published var userName: String = ""
    @Published var useSpecialPassanteView: Bool = true
    @Published var iCloudSyncEnabled: Bool = true
    
    private var refreshTimer: AnyCancellable?
    
    private let favoritesKey = "savedFavoriteTrains_v3"
    private let myStationsKey = "savedMyStations_v3"
    private let sectionOrderKey = "savedSectionOrder_v3"
    private let favoriteRoutesKey = "savedFavoriteRoutes_v1"
    private let savedTripsKey = "savedTrips_v1"
    private let selectedSuburbanLinesKey = "selectedSuburbanLines_v1"
    private let hiddenSuburbanStationsKey = "hiddenSuburbanStations_v1"
    private let selectedPassanteStationKey = "selectedPassanteStation_v1"
    private let smartRoutesKey = "savedSmartRoutes_v1"
    private let homeDestinationStationNameKey = "homeDestinationStationName_v1"
    private let userNameKey = "userName_v1"
    private let useSpecialPassanteViewKey = "useSpecialPassanteView_v1"
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
        NSUbiquitousKeyValueStore.default.synchronize()
        loadFavorites()
        loadRFIStations()
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
        NSUbiquitousKeyValueStore.default.synchronize()
        
        if self.remoteNotificationsEnabled {
            UIApplication.shared.registerForRemoteNotifications()
        }
        
        checkAndCleanOneShotNotifications()
    }
    
    private func loadRFIStations() {
        if let url = Bundle.main.url(forResource: "rfi_stations", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([RFIStation].self, from: data) {
            self.allRFIStations = decoded
            
            var dict: [String: String] = [:]
            var normDict: [String: String] = [:]
            for station in decoded {
                guard let rfiID = station.rfiID, !rfiID.isEmpty else { continue }
                let lower = station.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                dict[lower] = rfiID
                
                let norm = normalizeStationName(station.name)
                normDict[norm] = rfiID
            }
            self.rfiStationDictionary = dict
            self.rfiStationNormalizedDict = normDict
        }
    }
    
    func normalizeStationName(_ name: String) -> String {
        return name.lowercased()
            .replacingOccurrences(of: "p.", with: "porta")
            .replacingOccurrences(of: "s.", with: "san")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "'", with: "")
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
    
    func loadFavorites() {
        // First, restore any missing preferences from iCloud key-value store
        loadFromiCloud(keys: nil, onlyIfLocalMissing: true)
        
        if let data = UserDefaults.standard.data(forKey: recentTrainsKey) {
            do {
                let decoded = try JSONDecoder().decode([SavedTrain].self, from: data)
                self.recentTrains = decoded
                print("recentTrains caricati: \(decoded.count) elementi")
            } catch {
                print("recentTrains errore decodifica: \(error)")
            }
        } else {
            print("recentTrains non trovati in UserDefaults")
        }
        
        if let data = UserDefaults.standard.data(forKey: recentStationsKey) {
            do {
                let decoded = try JSONDecoder().decode([VTSearchStation].self, from: data)
                self.recentStations = decoded
                print("recentStations caricati: \(decoded.count) elementi")
            } catch {
                print("recentStations errore decodifica: \(error)")
            }
        } else {
            print("recentStations non trovati in UserDefaults")
        }

        if let data = UserDefaults.standard.data(forKey: favoritesKey), let decoded = try? JSONDecoder().decode([SavedTrain].self, from: data) { self.favoriteTrains = decoded }
        
        if let data = UserDefaults.standard.data(forKey: myStationsKey), let decoded = try? JSONDecoder().decode([Station].self, from: data) {
            self.myStations = decoded.map { st in
                if let rfi = st.rfiID, (rfi.hasPrefix("S") || rfi.hasPrefix("N")) {
                    return Station(name: st.name, rfiID: nil, vtID: st.vtID, lat: st.lat, lon: st.lon)
                }
                return st
            }
        } else {
            self.myStations = []
            saveFavorites()
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
        
        if let data = UserDefaults.standard.data(forKey: selectedSuburbanLinesKey), let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.selectedSuburbanLines = decoded
        } else {
            self.selectedSuburbanLines = ["S5", "S6"]
        }
        
        if let data = UserDefaults.standard.data(forKey: hiddenSuburbanStationsKey), let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            self.hiddenSuburbanStations = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: selectedPassanteStationKey), let decoded = try? JSONDecoder().decode(Station.self, from: data) {
            self.selectedPassanteStation = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: smartRoutesKey), let decoded = try? JSONDecoder().decode([SuburbanRoute].self, from: data) {
            self.smartRoutes = decoded
        } else {
            self.smartRoutes = [
                SuburbanRoute(originName: "Magenta", destinationName: "Milano Bovisa")
            ]
        }
        if let homeDest = UserDefaults.standard.string(forKey: homeDestinationStationNameKey) {
            self.homeDestinationStationName = homeDest
        }
        if let savedName = UserDefaults.standard.string(forKey: userNameKey) {
            self.userName = savedName
        }
        if UserDefaults.standard.object(forKey: useSpecialPassanteViewKey) != nil {
            self.useSpecialPassanteView = UserDefaults.standard.bool(forKey: useSpecialPassanteViewKey)
        }
        if UserDefaults.standard.object(forKey: iCloudSyncEnabledKey) != nil {
            self.iCloudSyncEnabled = UserDefaults.standard.bool(forKey: iCloudSyncEnabledKey)
        } else {
            self.iCloudSyncEnabled = true
        }
        
        if UserDefaults.standard.object(forKey: remoteNotificationsEnabledKey) != nil {
            self.remoteNotificationsEnabled = UserDefaults.standard.bool(forKey: remoteNotificationsEnabledKey)
        }
        if UserDefaults.standard.object(forKey: notifyOnStationPassKey) != nil {
            self.notifyOnStationPass = UserDefaults.standard.bool(forKey: notifyOnStationPassKey)
        }
        if let storedRegion = UserDefaults.standard.string(forKey: strikeRegionKey) {
            self.strikeRegion = storedRegion
        } else {
            self.strikeRegion = "Tutte"
        }
        self.apnsToken = UserDefaults.standard.string(forKey: apnsTokenKey)
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
        if let encoded = try? JSONEncoder().encode(selectedSuburbanLines) {
            UserDefaults.standard.set(encoded, forKey: selectedSuburbanLinesKey)
        }
        if let encoded = try? JSONEncoder().encode(hiddenSuburbanStations) {
            UserDefaults.standard.set(encoded, forKey: hiddenSuburbanStationsKey)
        }
        if let encoded = try? JSONEncoder().encode(selectedPassanteStation) {
            UserDefaults.standard.set(encoded, forKey: selectedPassanteStationKey)
        }
        if let encoded = try? JSONEncoder().encode(smartRoutes) {
            UserDefaults.standard.set(encoded, forKey: smartRoutesKey)
        }
        if let encoded = try? JSONEncoder().encode(sectionOrder) {
            UserDefaults.standard.set(encoded, forKey: sectionOrderKey)
        }
        
        do {
            let encoded = try JSONEncoder().encode(recentTrains)
            UserDefaults.standard.set(encoded, forKey: recentTrainsKey)
            print("recentTrains salvati: \(recentTrains.count) elementi (\(encoded.count) bytes)")
        } catch {
            print("recentTrains errore codifica: \(error)")
        }
        
        do {
            let encoded = try JSONEncoder().encode(recentStations)
            UserDefaults.standard.set(encoded, forKey: recentStationsKey)
            print("recentStations salvati: \(recentStations.count) elementi (\(encoded.count) bytes)")
        } catch {
            print("recentStations errore codifica: \(error)")
        }
        
        UserDefaults.standard.synchronize()
        
        UserDefaults.standard.set(homeDestinationStationName, forKey: homeDestinationStationNameKey)
        UserDefaults.standard.set(userName, forKey: userNameKey)
        UserDefaults.standard.set(useSpecialPassanteView, forKey: useSpecialPassanteViewKey)
        UserDefaults.standard.set(iCloudSyncEnabled, forKey: iCloudSyncEnabledKey)
        
        UserDefaults.standard.set(remoteNotificationsEnabled, forKey: remoteNotificationsEnabledKey)
        UserDefaults.standard.set(notifyOnStationPass, forKey: notifyOnStationPassKey)
        UserDefaults.standard.set(strikeRegion, forKey: strikeRegionKey)
        UserDefaults.standard.set(apnsToken, forKey: apnsTokenKey)
        
        if iCloudSyncEnabled {
            let store = NSUbiquitousKeyValueStore.default
            if let encoded = try? JSONEncoder().encode(favoriteTrains) { store.set(encoded, forKey: favoritesKey) }
            if let encoded = try? JSONEncoder().encode(myStations) { store.set(encoded, forKey: myStationsKey) }
            if let encoded = try? JSONEncoder().encode(favoriteRoutes) { store.set(encoded, forKey: favoriteRoutesKey) }
            if let encoded = try? JSONEncoder().encode(savedTrips) { store.set(encoded, forKey: savedTripsKey) }
            if let encoded = try? JSONEncoder().encode(selectedSuburbanLines) { store.set(encoded, forKey: selectedSuburbanLinesKey) }
            if let encoded = try? JSONEncoder().encode(hiddenSuburbanStations) { store.set(encoded, forKey: hiddenSuburbanStationsKey) }
            if let encoded = try? JSONEncoder().encode(selectedPassanteStation) { store.set(encoded, forKey: selectedPassanteStationKey) }
            if let encoded = try? JSONEncoder().encode(smartRoutes) { store.set(encoded, forKey: smartRoutesKey) }
            if let encoded = try? JSONEncoder().encode(sectionOrder) { store.set(encoded, forKey: sectionOrderKey) }
            
            store.set(homeDestinationStationName, forKey: homeDestinationStationNameKey)
            store.set(userName, forKey: userNameKey)
            store.set(useSpecialPassanteView, forKey: useSpecialPassanteViewKey)
            store.set(iCloudSyncEnabled, forKey: iCloudSyncEnabledKey)
            store.set(remoteNotificationsEnabled, forKey: remoteNotificationsEnabledKey)
            store.set(notifyOnStationPass, forKey: notifyOnStationPassKey)
            store.set(strikeRegion, forKey: strikeRegionKey)
            
            store.synchronize()
        }
        
        if let groupDefaults = UserDefaults(suiteName: "group.carlo.InOrario") {
            groupDefaults.set(homeDestinationStationName, forKey: homeDestinationStationNameKey)
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
        recentStations.removeAll { $0.vtID == station.vtID }
        recentStations.insert(station, at: 0)
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
                if let rfi = st.rfiID, (rfi.hasPrefix("S") || rfi.hasPrefix("N")) {
                    return Station(name: st.name, rfiID: nil, vtID: st.vtID, lat: st.lat, lon: st.lon)
                }
                return st
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
        
        if shouldUpdate(selectedSuburbanLinesKey), let data = store.data(forKey: selectedSuburbanLinesKey), let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.selectedSuburbanLines = decoded
            UserDefaults.standard.set(data, forKey: selectedSuburbanLinesKey)
            didModify = true
        }
        
        if shouldUpdate(hiddenSuburbanStationsKey), let data = store.data(forKey: hiddenSuburbanStationsKey), let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            self.hiddenSuburbanStations = decoded
            UserDefaults.standard.set(data, forKey: hiddenSuburbanStationsKey)
            didModify = true
        }
        
        if shouldUpdate(selectedPassanteStationKey), let data = store.data(forKey: selectedPassanteStationKey), let decoded = try? JSONDecoder().decode(Station.self, from: data) {
            self.selectedPassanteStation = decoded
            UserDefaults.standard.set(data, forKey: selectedPassanteStationKey)
            didModify = true
        }
        
        if shouldUpdate(smartRoutesKey), let data = store.data(forKey: smartRoutesKey), let decoded = try? JSONDecoder().decode([SuburbanRoute].self, from: data) {
            self.smartRoutes = decoded
            UserDefaults.standard.set(data, forKey: smartRoutesKey)
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
        
        if shouldUpdate(useSpecialPassanteViewKey), store.object(forKey: useSpecialPassanteViewKey) != nil {
            let value = store.bool(forKey: useSpecialPassanteViewKey)
            self.useSpecialPassanteView = value
            UserDefaults.standard.set(value, forKey: useSpecialPassanteViewKey)
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
        
        if didModify {
            syncRemoteNotifications()
        }
    }
    
    func toggleSuburbanLine(_ id: String) {
        if selectedSuburbanLines.contains(id) {
            selectedSuburbanLines.removeAll { $0 == id }
        } else {
            selectedSuburbanLines.append(id)
        }
        saveFavorites()
    }
    
    func toggleHiddenStation(lineId: String, stationName: String) {
        var hiddenForLine = hiddenSuburbanStations[lineId] ?? []
        if hiddenForLine.contains(stationName) {
            hiddenForLine.removeAll { $0 == stationName }
        } else {
            hiddenForLine.append(stationName)
        }
        hiddenSuburbanStations[lineId] = hiddenForLine
        saveFavorites()
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
    
    
    func selectPassanteStation(_ station: Station) {
        self.selectedPassanteStation = station
        saveFavorites()
        Task {
            await fetchPassanteLive()
        }
    }
    
    func fetchPassanteLive() async {
        self.isLoadingPassanteBoard = true
        let trainsFetched = await fetchTrainsForStation(station: selectedPassanteStation)
        self.passanteTrains = trainsFetched
        self.isLoadingPassanteBoard = false
        
        await fetchTunnelHealth()
    }
    
    func fetchTunnelHealth() async {
        let repubblica = Station(name: "Repubblica", rfiID: "1719", vtID: "S01060", lat: 45.4795, lon: 9.1963)
        let trainsFetched = await fetchTrainsForStation(station: repubblica)
        
        let delays = trainsFetched.compactMap { t -> Int? in
            let delayStr = t.delay.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "'", with: "")
            if delayStr.lowercased().contains("orario") { return 0 }
            return Int(delayStr)
        }
        
        _ = trainsFetched.filter { $0.delay.lowercased().contains("soppresso") || $0.delay.lowercased().contains("cancellato") }.count
        
        if trainsFetched.isEmpty {
            return
        } else {
            let resolveLine: (Train) -> String = { train in
                let cat = train.category.uppercased()
                if cat != "S" && cat.hasPrefix("S") {
                    return cat
                }
                let dest = train.destination.lowercased()
                if dest.contains("saronno") || dest.contains("lodi") {
                    return "S1"
                } else if dest.contains("mariano") || dest.contains("seveso") || dest.contains("camnago") {
                    return "S2"
                } else if dest.contains("varese") || dest.contains("treviglio") || dest.contains("gallarate") {
                    return "S5"
                } else if dest.contains("novara") || dest.contains("pioltello") {
                    return "S6"
                } else if dest.contains("melegnano") || dest.contains("cormano") {
                    return "S12"
                } else if dest.contains("pavia") || dest.contains("bovisa") {
                    return "S13"
                }
                return cat
            }
            
            self.passanteTunnelTrains = trainsFetched
            let avgDelay = delays.isEmpty ? 0 : (delays.reduce(0, +) / delays.count)
            self.passanteTunnelAverageDelay = avgDelay
            
            let targetLines = self.selectedSuburbanLines.isEmpty ? ["S1", "S2", "S5", "S6", "S12", "S13"] : self.selectedSuburbanLines
            let trainsToQuery = trainsFetched.filter { train in
                let line = resolveLine(train)
                return targetLines.contains(line)
            }
            
            await withTaskGroup(of: (String, TrainStatus?).self) { group in
                for train in trainsToQuery {
                    group.addTask {
                        let result = await self.fetchLiveStops(for: train.number)
                        return (train.number, result.status)
                    }
                }
                var newStatuses: [String: TrainStatus] = [:]
                for await (number, status) in group {
                    if let s = status { newStatuses[number] = s }
                }
                await MainActor.run {
                    self.passanteLiveStatuses = newStatuses
                }
            }
            
            var lineCancellations: [String: Int] = [:]
            var lineDelays: [String: [Int]] = [:]
            
            for train in trainsFetched {
                let line = resolveLine(train)
                guard line.hasPrefix("S") else { continue }
                
                let isCancelled = train.delay.lowercased().contains("soppresso") || train.delay.lowercased().contains("cancellato")
                if isCancelled {
                    lineCancellations[line, default: 0] += 1
                } else {
                    let delayStr = train.delay.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "'", with: "")
                    let delayVal = delayStr.lowercased().contains("orario") ? 0 : (Int(delayStr) ?? 0)
                    lineDelays[line, default: []].append(delayVal)
                }
            }
            
            var criticalLines: [String] = []
            var delayedLines: [String] = []
            
            for line in ["S1", "S2", "S5", "S6", "S12", "S13"] {
                let cancellations = lineCancellations[line] ?? 0
                let delaysForLine = lineDelays[line] ?? []
                let avgDelayForLine = delaysForLine.isEmpty ? 0 : (delaysForLine.reduce(0, +) / delaysForLine.count)
                
                if cancellations > 0 || avgDelayForLine >= 8 {
                    criticalLines.append(line)
                } else if avgDelayForLine >= 3 {
                    delayedLines.append(line)
                }
            }
            
            if !criticalLines.isEmpty {
                let sorted = criticalLines.sorted(by: {
                    let n1 = Int($0.replacingOccurrences(of: "S", with: "")) ?? 0
                    let n2 = Int($1.replacingOccurrences(of: "S", with: "")) ?? 0
                    return n1 < n2
                })
                self.passanteTunnelHealthMessage = "Criticità su \(sorted.joined(separator: ", "))"
                self.passanteTunnelHealthColor = "#e30613"
            } else if !delayedLines.isEmpty {
                let sorted = delayedLines.sorted(by: {
                    let n1 = Int($0.replacingOccurrences(of: "S", with: "")) ?? 0
                    let n2 = Int($1.replacingOccurrences(of: "S", with: "")) ?? 0
                    return n1 < n2
                })
                self.passanteTunnelHealthMessage = "Rallentamenti su \(sorted.joined(separator: ", "))"
                self.passanteTunnelHealthColor = "#f39200"
            } else {
                self.passanteTunnelHealthMessage = "Circolazione Regolare"
                self.passanteTunnelHealthColor = "#009640"
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
        selectedSuburbanLines.contains { TrainManager.tunnelLineIDs.contains($0) }
    }
    
    var passanteStationsForUser: [Station] {
        let selectedLines = SuburbanData.shared.allLines.filter { selectedSuburbanLines.contains($0.id) }
        let source = selectedLines.isEmpty ? SuburbanData.shared.allLines : selectedLines
        var seen = Set<String>()
        return source.flatMap { $0.stations }.filter { seen.insert($0.name).inserted }
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
    
    nonisolated private func fetchTrainsForStation(station: Station) async -> [Train] {
        if let rfi = station.rfiID, !rfi.isEmpty {
            let scraped = await performRfiScraping(for: rfi, isDepartures: true)
            if !scraped.trains.isEmpty {
                return scraped.trains
            }
        }
        if let vt = station.vtID, !vt.isEmpty {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "Europe/Rome")
            f.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT'ZZZ"
            let dateStr = f.string(from: Date()).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            return await performVTFetch(for: vt, isDepartures: true, dateStr: dateStr)
        }
        return []
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
            if let token = apnsToken {
                registerTrainForPush(trainNumber: trainNumber, token: token)
            }
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
                favoriteTrains[index].departureTime = firstStop?.time
                if favoriteTrains[index].arrivalTime == nil {
                    favoriteTrains[index].arrivalTime = lastStop?.time
                }
                // Populate description with Origin - Destination if it's just the destination
                let origin = firstStop?.stationName ?? ""
                let destination = lastStop?.stationName ?? ""
                if !origin.isEmpty && !destination.isEmpty {
                    favoriteTrains[index].description = "\(origin) - \(destination)"
                }
                saveFavorites()
            }
        }
    }
    
    func syncRemoteNotifications() {
        print("[syncRemoteNotifications] Avvio sincronizzazione. Token: \(apnsToken ?? "nil"), remoteNotificationsEnabled: \(remoteNotificationsEnabled), preferiti: \(favoriteTrains.map { "\($0.number): \($0.notifyDelay ?? false)" })")
        
        if remoteNotificationsEnabled && apnsToken == nil {
            print("[syncRemoteNotifications] Notifiche abilitate e token nil. Richiedo registrazione token APNs ad Apple...")
            UIApplication.shared.registerForRemoteNotifications()
        }
        
        guard let token = apnsToken else {
            print("[syncRemoteNotifications] Esco: token è ancora nil.")
            return
        }
        
        if !remoteNotificationsEnabled {
            print("[syncRemoteNotifications] Notifiche globali disabilitate. Cancello tutte le registrazioni.")
            // Unregister all
            unregisterDeviceForStrikes(token: token)
            Task {
                for train in favoriteTrains {
                    unregisterTrainForPush(trainNumber: train.number, token: token)
                }
            }
            return
        }
        
        // Registra sempre il dispositivo generale per gli scioperi
        registerDeviceForStrikes(token: token)
        
        for train in favoriteTrains {
            if train.notifyDelay ?? false {
                registerTrainForPush(trainNumber: train.number, token: token)
            } else {
                unregisterTrainForPush(trainNumber: train.number, token: token)
            }
        }
    }
    
    func ignoreStrike(strikeId: String) {
        guard let token = apnsToken else { return }
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/notifications/ignore-strike") else { return }
        
        let payload: [String: Any] = [
            "token": token,
            "strike_id": strikeId
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Errore ignoreStrike: \(error.localizedDescription)")
                } else {
                    print("Sciopero \(strikeId) ignorato con successo per il token.")
                }
            }.resume()
        } catch {
            print("Errore JSON ignoreStrike: \(error)")
        }
    }
    
    func registerDeviceForStrikes(token: String) {
        guard remoteNotificationsEnabled else { return }
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/notifications/register") else { return }
            let region = hasSupport() ? strikeRegion : "Tutte"
        let payload: [String: Any] = [
            "token": token,
            "platform": "ios",
            "strike_region": region
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Errore registrazione dispositivo per scioperi: \(error.localizedDescription)")
                } else {
                    print("Registrato dispositivo per scioperi con regione: \(region)")
                }
            }.resume()
        } catch {
            print("Errore serializzazione payload registrazione dispositivo: \(error.localizedDescription)")
        }
    }
    
    func unregisterDeviceForStrikes(token: String) {
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/notifications/unregister") else { return }
        
        let payload: [String: Any] = [
            "token": token
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Errore disattivazione dispositivo generale: \(error.localizedDescription)")
                } else {
                    print("Dispositivo generale e notifiche scioperi disattivati con successo.")
                }
            }.resume()
        } catch {
            print("Errore serializzazione payload disattivazione dispositivo: \(error.localizedDescription)")
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
            notificationLimitError = "Le notifiche treni sono state disattivate per fare spazio alla Live Activity (Esclusività funzioni Base)."
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
            notificationLimitError = "La Live Activity è stata disattivata per fare spazio alle Notifiche Treni (Esclusività funzioni Base)."
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
            "platform_change_station_name": platformChangeStationName
        ]
        
        if let activeDays = trainPref?.activeDays {
            payload["active_days"] = activeDays
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("[registerTrainForPush] Errore invio registrazione push treno \(trainNumber): \(error.localizedDescription)")
                } else if let httpResponse = response as? HTTPURLResponse {
                    print("[registerTrainForPush] Risposta server per treno \(trainNumber): codice \(httpResponse.statusCode)")
                    if httpResponse.statusCode == 200 {
                        print("[registerTrainForPush] Registrato con successo treno \(trainNumber) per notifiche push")
                    } else if httpResponse.statusCode == 403 {
                        DispatchQueue.main.async {
                            if self.hasSupport() {
                                self.notificationLimitError = "Puoi monitorare al massimo \(limit) treni alla volta per il tuo livello."
                            } else {
                                self.notificationLimitError = "La gestione delle notifiche in tempo reale comporta costi di server continui per ciascun treno monitorato. Se trovi utile l'app, considera di sostenere lo sviluppo indipendente con un piccolo contributo: sbloccherai il monitoraggio fino a 10 treni contemporaneamente e le notifiche personalizzate per gli scioperi della tua regione."
                            }
                        }
                    }
                }
            }.resume()
        } catch {
            print("[registerTrainForPush] Errore serializzazione payload push treno \(trainNumber): \(error.localizedDescription)")
        }
    }
    
    func unregisterTrainForPush(trainNumber: String, token: String) {
        print("[unregisterTrainForPush] Tentativo di rimozione per treno \(trainNumber)...")
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/notifications/unregister") else { return }
        
        let payload: [String: Any] = [
            "token": token,
            "train_number": trainNumber
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("[unregisterTrainForPush] Errore invio cancellazione push treno \(trainNumber): \(error.localizedDescription)")
                } else if let httpResponse = response as? HTTPURLResponse {
                    print("[unregisterTrainForPush] Risposta server rimozione treno \(trainNumber): codice \(httpResponse.statusCode)")
                }
            }.resume()
        } catch {
            print("[unregisterTrainForPush] Errore serializzazione payload rimozione treno \(trainNumber): \(error.localizedDescription)")
        }
    }

    func registerLiveActivityToken(pushToken: Data, trainNumber: String, deviceToken: String) {
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/liveactivity/register") else { return }
        let tokenString = pushToken.map { String(format: "%02x", $0) }.joined()
        let payload: [String: Any] = [
            "token": deviceToken,
            "push_token": tokenString,
            "train_number": trainNumber
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: request) { _, response, error in
                if let error = error {
                    print("Errore registrazione LiveActivity token: \(error.localizedDescription)")
                } else if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    print("Token LiveActivity registrato per treno \(trainNumber)")
                }
            }.resume()
        } catch {
            print("Errore serializzazione LiveActivity payload: \(error.localizedDescription)")
        }
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    self.remoteNotificationsEnabled = true
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
        if !myStations.contains(where: { $0.vtID == vtID }) {
            let possibleRfiID = getRfiID(for: name)
            let newStation = Station(name: name.capitalized, rfiID: possibleRfiID, vtID: vtID, lat: nil, lon: nil)
            myStations.append(newStation)
            saveFavorites()
            Haptics.notify(.success)
        }
    }
    
    func removeMyStation(vtID: String) {
        myStations.removeAll { $0.vtID == vtID }
        saveFavorites()
        Haptics.notify(.warning)
    }
    
    func isMyStation(vtID: String) -> Bool {
        return myStations.contains { $0.vtID == vtID }
    }
    
    func searchTrains(query: String) async {
        guard query.count >= 2 else { self.searchResults = []; return }
        self.isSearching = true
        let urlString = "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/cercaNumeroTrenoTrenoAutocomplete/\(query)"
        guard let url = URL(string: urlString) else { self.isSearching = false; return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = String(data: data, encoding: .utf8) ?? ""
            let lines = result.components(separatedBy: .newlines).filter { !$0.isEmpty }
            self.searchResults = lines.compactMap { line in
                let parts = line.components(separatedBy: "|")
                guard parts.count > 0 else { return nil }
                let desc = parts[0].components(separatedBy: " - ")
                return SavedTrain(number: desc[0].trimmingCharacters(in: .whitespaces), description: desc.count > 1 ? desc[1].trimmingCharacters(in: .whitespaces) : desc[0])
            }
            self.isSearching = false
        } catch { self.isSearching = false }
    }
    
    private func isValidStationName(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.contains("bivio") || lower.contains("bivi ") || lower.contains("biv.") || lower.hasSuffix(" bivi") { return false }
        if lower.hasPrefix("pc ") || lower.contains(" pc ") || lower.hasSuffix(" pc") || lower.contains("p.c.") || lower.contains("/pc") { return false }
        if lower.hasPrefix("pm ") || lower.contains(" pm ") || lower.hasSuffix(" pm") || lower.contains("p.m.") || lower.contains("/pm") { return false }
        if lower.contains("posto di movimento") || lower.contains("posto di comunicazione") { return false }
        return true
    }
    
    func searchStations(query: String) async {
        guard query.count >= 2 else { self.searchStationResults = []; return }
        self.isSearching = true
        
        let lowerQ = query.lowercased()
        let hits = allRFIStations.filter { $0.name.lowercased().contains(lowerQ) && isValidStationName($0.name) }
        
        var results: [VTSearchStation] = []
        for r in hits {
            results.append(VTSearchStation(nomeLungo: r.name, nomeBreve: r.name, vtID: r.vtID ?? r.rfiID ?? ""))
        }
        
        results.sort { $0.nomeLungo < $1.nomeLungo }
        
        Task { @MainActor in
            self.searchStationResults = results
            self.isSearching = false
        }
    }
    
    func searchTravelLocations(query: String) async {
        guard query.count >= 2 else { self.searchTrenitaliaLocations = []; return }
        self.isSearching = true
        let safeQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://www.lefrecce.it/Channels.Website.BFF.WEB/website/locations/search?name=\(safeQuery)"
        guard let url = URL(string: urlString) else { self.isSearching = false; return }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = (try? JSONDecoder().decode([TrenitaliaLocation].self, from: data)) ?? []
            self.searchTrenitaliaLocations = decoded.filter { isValidStationName($0.name) }
            self.isSearching = false
        } catch { self.isSearching = false }
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
            let (data, _) = try await URLSession.shared.data(for: request)
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let solutions = json["solutions"] as? [[String: Any]] else {
                self.isSearchingSolutions = false
                return
            }
            
            var parsedSolutions: [TravelSolution] = []
            
            for item in solutions {
                guard let sol = item["solution"] as? [String: Any] else { continue }
                
                let origin = (sol["origin"] as? String) ?? ""
                let destination = (sol["destination"] as? String) ?? ""
                let duration = (sol["duration"] as? String) ?? ""
                
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
                        
                        if nCat.lowercased() == "urbano" || nNum.lowercased() == "urbano" || nCat.lowercased().contains("metro") {
                            nCat = "Trasporto Urbano"
                            nNum = "(Metro / Mezzi)"
                        } else if nodeOrigin.lowercased().hasPrefix("milano") && nodeDest.lowercased().hasPrefix("milano") && nodeOrigin != nodeDest && nNum.isEmpty {
                            nCat = "Trasporto Urbano"
                            nNum = "(Metro / Mezzi)"
                        }
                        
                        segments.append(TravelSegment(
                            origin: nodeOrigin,
                            destination: nodeDest,
                            departureTime: nDepStr,
                            arrivalTime: nArrStr,
                            trainNumber: nNum,
                            trainCategory: nCat
                        ))
                    }
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
            
            self.travelSolutions = parsedSolutions
            self.isSearchingSolutions = false
            
        } catch {
            self.isSearchingSolutions = false
        }
    }
    
    func searchRFIStationsLocally(query: String) {
        guard query.count >= 2 else { self.searchRFIStationResults = []; return }
        let lowerQuery = query.lowercased()
        self.searchRFIStationResults = self.allRFIStations.filter { $0.name.lowercased().contains(lowerQuery) && isValidStationName($0.name) }
    }
    
    
    nonisolated private func performVTFetch(for vtID: String, isDepartures: Bool, dateStr: String) async -> [Train] {
        let endpoint = isDepartures ? "partenze" : "arrivi"
        let urlString = "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/\(endpoint)/\(vtID)/\(dateStr)"
        guard let url = URL(string: urlString) else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            
            return jsonArray.compactMap { item in
                let num = String(item["numeroTreno"] as? Int ?? 0)
                var cat = (item["categoriaDescrizione"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                let dest = ((isDepartures ? item["destinazione"] : item["origine"]) as? String)?.capitalized ?? ""
                let timeVal = (isDepartures ? item["orarioPartenza"] : item["orarioArrivo"]) as? Int ?? 0
                let ritardo = item["ritardo"] as? Int ?? 0
                
                let binEff = (isDepartures ? item["binarioEffettivoPartenzaDescrizione"] : item["binarioEffettivoArrivoDescrizione"]) as? String
                let binProg = (isDepartures ? item["binarioProgrammatoPartenzaDescrizione"] : item["binarioProgrammatoArrivoDescrizione"]) as? String
                let platform = binEff ?? binProg ?? "--"
                
                let catUpper = cat.uppercased()
                if catUpper.contains("ALTA VELOCIT") { cat = "AV" }
                else if catUpper.contains("INTERCITY") { cat = "IC" }
                else if catUpper.contains("EUROCITY") { cat = "EC" }
                else if catUpper == "REGIONALE VELOCE" { cat = "RV" }
                else if catUpper == "REGIONALE" { cat = "REG" }
                else if catUpper == "SUBURBANO" { cat = "S" }
                
                if cat.uppercased() == "S" || cat.uppercased() == "REG" {
                    if num.hasPrefix("240") || num.hasPrefix("230") || num.hasPrefix("241") || num.hasPrefix("231") { cat = "S1" }
                    else if num.hasPrefix("242") || num.hasPrefix("232") {
                        let d = dest.lowercased()
                        if d.contains("melegnano") || d.contains("cormano") { cat = "S12" }
                        else { cat = "S2" }
                    }
                    else if num.hasPrefix("243") || num.hasPrefix("233") || num.hasPrefix("328") || num.hasPrefix("329") { cat = "S13" }
                    else if num.hasPrefix("245") || num.hasPrefix("235") { cat = "S5" }
                    else if num.hasPrefix("246") || num.hasPrefix("236") { cat = "S6" }
                    else if num.hasPrefix("256") || num.hasPrefix("257") || num.hasPrefix("247") || num.hasPrefix("237") { cat = "S12" }
                    else if num.hasPrefix("248") || num.hasPrefix("238") { cat = "S8" }
                    else if num.hasPrefix("249") || num.hasPrefix("239") { cat = "S9" }
                    else if num.hasPrefix("250") || num.hasPrefix("251") || num.hasPrefix("252") { cat = "S11" }
                    else {
                        let d = dest.lowercased()
                        if d.contains("saronno") || d.contains("lodi") { cat = "S1" }
                        else if d.contains("mariano") || d.contains("seveso") || d.contains("camnago") { cat = "S2" }
                        else if d.contains("varese") || d.contains("treviglio") || d.contains("gallarate") { cat = "S5" }
                        else if d.contains("novara") || d.contains("nov ") || d.contains("pioltello") || d.contains("piolt") || d.contains("magenta") { cat = "S6" }
                        else if d.contains("melegnano") || d.contains("cormano") { cat = "S12" }
                        else if d.contains("pavia") || d.contains("garbagnate") { cat = "S13" }
                    }
                }
                
                if timeVal > 0 {
                    let date = Date(timeIntervalSince1970: TimeInterval(timeVal/1000))
                    return Train(category: cat, number: num, destination: dest, time: SharedFormatters.time.string(from: date), delay: ritardo > 0 ? "+\(ritardo)'" : "In orario", platform: platform)
                }
                return nil
            }
        } catch {
            return []
        }
    }
    
    func fetchVTTrains(for vtID: String, isDepartures: Bool) async {
        self.isLoading = true
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        f.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT'ZZZ"
        let dateStr = f.string(from: Date()).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        
        let fetchedTrains = await performVTFetch(for: vtID, isDepartures: isDepartures, dateStr: dateStr)
        
        self.trains = fetchedTrains
        self.isLoading = false
    }
    
    nonisolated private func stripHTML(_ str: String) -> String {
        var text = "<td" + str
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression, range: nil)
        text = text.replacingOccurrences(of: "<td", with: " ", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&#39", with: "'")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    nonisolated private func performRfiScraping(for rfiID: String, isDepartures: Bool) async -> (trains: [Train], alerts: String?) {
        let urlString = "https://iechub.rfi.it/ArriviPartenze/ArrivalsDepartures/Monitor?placeId=\(rfiID)&arrivals=\(!(isDepartures))"
        guard let url = URL(string: urlString) else { return ([], nil) }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return ([], nil) }
            
            var stationAlerts: String? = nil
            if let range = html.range(of: "Avvisi") {
                let subHtml = String(html[range.lowerBound...])
                if let endRange = subHtml.range(of: "</div>") {
                    let alertRaw = String(subHtml[..<endRange.lowerBound])
                    var cleanAlert = self.stripHTML(alertRaw)
                        .replacingOccurrences(of: "Avvisi", with: "")
                        .replacingOccurrences(of: "<", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if cleanAlert.uppercased().contains("VIETATO APRIRE LE PORTE") {
                        cleanAlert = ""
                    }
                    
                    if !cleanAlert.isEmpty {
                        stationAlerts = cleanAlert
                    }
                }
            }
            
            var cleanHtml = html.replacingOccurrences(of: "<TR", with: "<tr", options: .caseInsensitive)
            cleanHtml = cleanHtml.replacingOccurrences(of: "<TD", with: "<td", options: .caseInsensitive)
            let rows = cleanHtml.components(separatedBy: "<tr")
            var scrapedTrains: [Train] = []
            for row in rows.dropFirst() {
                let cols = row.components(separatedBy: "<td")
                if cols.count >= 8 {
                    var cat = self.stripHTML(cols[2]).replacingOccurrences(of: "Categoria", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
                    if cat.isEmpty {
                        if let altRange = cols[2].range(of: "alt=\"([^\"]+)\"", options: .regularExpression) {
                            let match = String(cols[2][altRange])
                            let rawAlt = match.replacingOccurrences(of: "alt=\"", with: "")
                                              .replacingOccurrences(of: "\"", with: "")
                                              .replacingOccurrences(of: "Categoria", with: "", options: .caseInsensitive)
                            cat = self.stripHTML(rawAlt)
                        }
                    }
                    let num = self.stripHTML(cols[3])
                    let dest = self.stripHTML(cols[4])
                    let time = self.stripHTML(cols[5])
                    let delayRaw = self.stripHTML(cols[6])
                    let plat = self.stripHTML(cols[7])
                    
                    let catUpper = cat.uppercased()
                    if catUpper.contains("ALTA VELOCIT") { cat = "AV" }
                    else if catUpper.contains("INTERCITY") { cat = "IC" }
                    else if catUpper.contains("EUROCITY") { cat = "EC" }
                    else if catUpper == "REGIONALE VELOCE" { cat = "RV" }
                    else if catUpper == "REGIONALE" { cat = "REG" }
                    
                    if cat.isEmpty {
                        if num.hasPrefix("20") || num.hasPrefix("21") { cat = "RV" }
                        else if num.hasPrefix("24") || num.hasPrefix("10") { cat = "S" }
                        else { cat = "REG" }
                    }
                    
                    if cat.uppercased() == "S" || cat.uppercased() == "REG" {
                        if num.hasPrefix("240") || num.hasPrefix("230") || num.hasPrefix("241") || num.hasPrefix("231") { cat = "S1" }
                        else if num.hasPrefix("242") || num.hasPrefix("232") {
                            let d = dest.lowercased()
                            if d.contains("melegnano") || d.contains("cormano") { cat = "S12" }
                            else { cat = "S2" }
                        }
                        else if num.hasPrefix("243") || num.hasPrefix("233") || num.hasPrefix("328") || num.hasPrefix("329") { cat = "S13" }
                        else if num.hasPrefix("245") || num.hasPrefix("235") { cat = "S5" }
                        else if num.hasPrefix("246") || num.hasPrefix("236") { cat = "S6" }
                        else if num.hasPrefix("256") || num.hasPrefix("257") || num.hasPrefix("247") || num.hasPrefix("237") { cat = "S12" }
                        else if num.hasPrefix("248") || num.hasPrefix("238") { cat = "S8" }
                        else if num.hasPrefix("249") || num.hasPrefix("239") { cat = "S9" }
                        else if num.hasPrefix("250") || num.hasPrefix("251") || num.hasPrefix("252") { cat = "S11" }
                        else {
                            let d = dest.lowercased()
                            if d.contains("saronno") || d.contains("lodi") { cat = "S1" }
                            else if d.contains("mariano") || d.contains("seveso") || d.contains("camnago") { cat = "S2" }
                            else if d.contains("varese") || d.contains("treviglio") || d.contains("gallarate") { cat = "S5" }
                            else if d.contains("novara") || d.contains("nov ") || d.contains("pioltello") || d.contains("piolt") || d.contains("magenta") { cat = "S6" }
                            else if d.contains("melegnano") || d.contains("cormano") { cat = "S12" }
                            else if d.contains("pavia") || d.contains("garbagnate") { cat = "S13" }
                        }
                    }
                    if !num.isEmpty && time.contains(":") {
                        scrapedTrains.append(Train(category: cat, number: num, destination: dest.capitalized, time: time, delay: delayRaw.isEmpty ? "In orario" : "+\(delayRaw)'", platform: plat.isEmpty ? "--" : plat))
                    }
                }
            }
            return (scrapedTrains, stationAlerts)
        } catch {
            return ([], nil)
        }
    }
    
    func fetchTrains(for station: Station, isDepartures: Bool) async {
        self.isLoading = true
        self.stationAlerts = nil
        
        let rfiID = station.rfiID ?? ""
        let vtID = station.vtID ?? ""
        
        var scraperSuccess = false
        if !rfiID.isEmpty {
            let scraped = await performRfiScraping(for: rfiID, isDepartures: isDepartures)
            if let alerts = scraped.alerts {
                self.stationAlerts = alerts
            }
            if !scraped.trains.isEmpty {
                self.trains = scraped.trains
                scraperSuccess = true
            }
        }
        
        if !scraperSuccess && !vtID.isEmpty {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "Europe/Rome")
            f.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT'ZZZ"
            let dateStr = f.string(from: Date()).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            let vtTrains = await performVTFetch(for: vtID, isDepartures: isDepartures, dateStr: dateStr)
            self.trains = vtTrains
            scraperSuccess = true
        }
        
        if !scraperSuccess {
            self.trains = []
        }
        
        self.isLoading = false
    }
    
    
    nonisolated func fetchLiveStops(for trainNumber: String) async -> StopsResult {
        let cleanNumber = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchUrl = "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/cercaNumeroTrenoTrenoAutocomplete/\(cleanNumber)"
        
        guard let sUrl = URL(string: searchUrl) else {
            return await StopsResult(stops: [], status: TrainStatus(), errorMessage: "URL non valido.")
        }
        
        do {
            let (sData, _) = try await URLSession.shared.data(from: sUrl)
            let result = String(data: sData, encoding: .utf8) ?? ""
            
            if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return await StopsResult(stops: [], status: TrainStatus(), errorMessage: "Treno non tracciato o non ancora nel sistema.")
            }
            
            let lines = result.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            var targets = lines.filter { $0.contains("|\(cleanNumber)-") }
            if targets.isEmpty, let firstLine = lines.first {
                targets = [firstLine]
            }
            if targets.isEmpty {
                return await StopsResult(stops: [], status: TrainStatus(), errorMessage: "Dettagli del treno non trovati.")
            }
            
            let results: [(String, [String: Any])] = await withTaskGroup(of: (String, [String: Any])?.self) { group in
                for targetLine in targets {
                    group.addTask {
                        let pipes = targetLine.components(separatedBy: "|")
                        guard pipes.count >= 2 else { return nil }
                        let subParts = pipes[1].components(separatedBy: "-")
                        guard subParts.count >= 2 else { return nil }
                        
                        let originID = subParts[1]
                        let timestamp = subParts.count >= 3 ? subParts[2] : ""
                        
                        var stopsUrl = "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/andamentoTreno/\(originID)/\(cleanNumber)"
                        if !timestamp.isEmpty { stopsUrl += "/\(timestamp)" }
                        
                        guard let stUrl = URL(string: stopsUrl) else { return nil }
                        var request = URLRequest(url: stUrl)
                        request.timeoutInterval = 10.0
                        
                        do {
                            let (stData, response) = try await URLSession.shared.data(for: request)
                            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, !stData.isEmpty else { return nil }
                            guard let json = try JSONSerialization.jsonObject(with: stData) as? [String: Any] else { return nil }
                            return (targetLine, json)
                        } catch {
                            return nil
                        }
                    }
                }
                
                var collected = [(String, [String: Any])]()
                for await res in group {
                    if let r = res {
                        collected.append(r)
                    }
                }
                return collected
            }
            
            guard !results.isEmpty else {
                return await StopsResult(stops: [], status: TrainStatus(), errorMessage: "Dati in aggiornamento o temporaneamente non disponibili.")
            }
            
            let nowTs = Date().timeIntervalSince1970 * 1000.0
            var bestJson: [String: Any]? = nil
            var bestScore: Double = -1.0
            
            for (targetLine, json) in results {
                let pipes = targetLine.components(separatedBy: "|")
                let subParts = pipes.count >= 2 ? pipes[1].components(separatedBy: "-") : []
                let tsStr = subParts.count >= 3 ? subParts[2] : ""
                let trainTs = Double(tsStr) ?? nowTs
                
                let deltaDays = abs(nowTs - trainTs) / (1000.0 * 60 * 60 * 24)
                let isDeparted = !(json["nonPartito"] as? Bool ?? true)
                let isArrived = (json["arrivato"] as? Bool) ?? false
                
                let baseScore = (isDeparted && !isArrived) ? 10000.0 : 1000.0
                let score = baseScore - (deltaDays * 100.0)
                
                if score > bestScore {
                    bestScore = score
                    bestJson = json
                }
            }
            
            let json = bestJson ?? results[0].1
            
            var status = await TrainStatus()
            status.isDeparted = !(json["nonPartito"] as? Bool ?? true)
            status.isArrived = (json["arrivato"] as? Bool) ?? false
            status.lastStation = (json["stazioneUltimoRilevamento"] as? String) ?? "--"
            status.lastTime = (json["compOraUltimoRilevamento"] as? String) ?? (json["oraUltimoRilevamento"] as? String) ?? "--:--"
            
            if let ritardi = json["compRitardo"] as? [String], !ritardi.isEmpty { status.statusMessage = ritardi[0] }
            else { status.statusMessage = status.isDeparted ? "In viaggio" : "In attesa di partenza" }
            if let provv = json["provvedimento"] as? Int, provv != 0 { status.cancellationNote = "TRENO CANCELLATO O DEVIATO"; status.statusMessage = "Soppresso" }
            
            let globalDelay = (json["ritardo"] as? Int) ?? 0
            
            if let fermate = json["fermate"] as? [[String: Any]] {
                let mappedStops = fermate.map { f -> Stop in
                    let name = (f["stazione"] as? String) ?? "Sconosciuta"
                    let tProg = (f["programmata"] as? Int) ?? 0
                    let tEff = (f["effettiva"] as? Int) ?? 0
                    
                    let stopSpecificDelay = (f["ritardo"] as? Int) ?? 0
                    let effectiveDelay = stopSpecificDelay > 0 ? stopSpecificDelay : globalDelay
                    
                    let d = Date(timeIntervalSince1970: TimeInterval(tProg/1000))
                    let actT = tEff > 0 ? SharedFormatters.time.string(from: Date(timeIntervalSince1970: TimeInterval(tEff/1000))) : nil
                    
                    var estT: String? = nil
                    if actT == nil && effectiveDelay >= 4 {
                        if let futureDate = Calendar.current.date(byAdding: .minute, value: effectiveDelay, to: d) {
                            estT = SharedFormatters.time.string(from: futureDate)
                        }
                    }
                    
                    return Stop(stationName: name.capitalized,
                                time: SharedFormatters.time.string(from: d),
                                actualTime: actT,
                                delay: effectiveDelay,
                                estimatedTime: estT)
                }
                return StopsResult(stops: mappedStops, status: status, errorMessage: nil)
            }
            return StopsResult(stops: [], status: status, errorMessage: "Nessuna fermata trovata.")
        } catch is CancellationError {
            return await StopsResult(stops: [], status: TrainStatus(), errorMessage: nil)
        } catch {
            return await StopsResult(stops: [], status: TrainStatus(), errorMessage: "Errore di rete o blocco di sicurezza (controlla i permessi ATS nel file Info.plist).")
        }
    }
    
    func fetchStops(for train: Train, isRefresh: Bool = false) async {
        if !isRefresh {
            self.selectedTrainStops = []
            self.currentTrainStatus = TrainStatus()
            self.isStopsLoading = true
            self.stopErrorMessage = nil
        }
        
        let cleanNumber = train.number.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await fetchLiveStops(for: cleanNumber)
        
        if !isRefresh || result.errorMessage == nil {
            self.selectedTrainStops = result.stops
            self.currentTrainStatus = result.status
            self.stopErrorMessage = result.errorMessage
        }
        
        if !isRefresh {
            self.isStopsLoading = false
        }
        
        if result.errorMessage == nil {
            let globalDelay = result.status.statusMessage.contains("Soppresso") ? 0 : (result.stops.last?.delay ?? 0)
            let delayStr = globalDelay > 0 ? "+\(globalDelay)'" : "In orario"
            let updatedState = TrainLiveActivityAttributes.ContentState(
                delay: delayStr,
                statusMessage: result.status.statusMessage,
                lastStation: result.status.lastStation
            )
            
            for activity in Activity<TrainLiveActivityAttributes>.activities {
                if activity.attributes.trainNumber == cleanNumber {
                    await activity.update(ActivityContent(state: updatedState, staleDate: nil))
                }
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
    
    func syncLiveActivities() {
        let active = Activity<TrainLiveActivityAttributes>.activities.map { $0.attributes.trainNumber }
        self.activeLiveActivities = Set(active)
        
        // Sincronizza i token push correnti di tutte le Live Activities
        Task {
            if let deviceToken = self.apnsToken, !deviceToken.isEmpty {
                for activity in Activity<TrainLiveActivityAttributes>.activities {
                    if let pushToken = activity.pushToken {
                        self.registerLiveActivityToken(pushToken: pushToken, trainNumber: activity.attributes.trainNumber, deviceToken: deviceToken)
                    }
                }
            }
        }
    }
    
    func observeAllLiveActivityPushTokens() {
        // Ascolta la creazione di NUOVE Live Activities
        Task {
            for await activity in Activity<TrainLiveActivityAttributes>.activityUpdates {
                Task {
                    for await tokenData in activity.pushTokenUpdates {
                        if let deviceToken = self.apnsToken, !deviceToken.isEmpty {
                            self.registerLiveActivityToken(pushToken: tokenData, trainNumber: activity.attributes.trainNumber, deviceToken: deviceToken)
                        }
                    }
                }
            }
        }
        
        // Ascolta gli aggiornamenti dei token per le Live Activities GIÀ ESISTENTI (es. riapertura app)
        for activity in Activity<TrainLiveActivityAttributes>.activities {
            Task {
                for await tokenData in activity.pushTokenUpdates {
                    if let deviceToken = self.apnsToken, !deviceToken.isEmpty {
                        self.registerLiveActivityToken(pushToken: tokenData, trainNumber: activity.attributes.trainNumber, deviceToken: deviceToken)
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
        if saved.number.hasPrefix("20") || saved.number.hasPrefix("21") { cat = "RV" }
        else if saved.number.hasPrefix("24") || saved.number.hasPrefix("10") { cat = "S" }
        else if saved.number.hasPrefix("9") { cat = "FR" }
        return Train(category: cat, number: saved.number, destination: saved.description.capitalized, time: "--:--", delay: "In orario", platform: "--")
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
    
    private let productIDs = ["tip.colazionee"]
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
        var hasColazionee = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == "tip.colazionee" {
                    hasColazionee = true
                }
            }
        }
        UserDefaults.standard.set(hasColazionee, forKey: "tip.colazionee")
        if let groupDefaults = UserDefaults(suiteName: "group.carlo.InOrario") {
            groupDefaults.set(hasColazionee, forKey: "tip.colazionee")
        }
        NotificationCenter.default.post(name: NSNotification.Name("PurchasesUpdated"), object: nil)
    }
    
    func fetchProducts() async {
        DispatchQueue.main.async { self.isLoadingProducts = true }
        await updatePurchases()
        do {
            let storeProducts = try await Product.products(for: productIDs)
            DispatchQueue.main.async {
                self.products = storeProducts.sorted(by: { $0.price < $1.price })
                self.isLoadingProducts = false
            }
        } catch {
            print("Errore nel caricamento dei prodotti da StoreKit: \(error)")
            DispatchQueue.main.async {
                self.isLoadingProducts = false
            }
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
        let isColazionee = transaction.productID == "tip.colazionee"
        
        if isColazionee {
            UserDefaults.standard.set(true, forKey: "tip.colazionee")
        }
        
        if let groupDefaults = UserDefaults(suiteName: "group.carlo.InOrario") {
            if isColazionee {
                groupDefaults.set(true, forKey: "tip.colazionee")
            }
        }
        NotificationCenter.default.post(name: NSNotification.Name("PurchasesUpdated"), object: nil)
    }
    
    func resetState() {
        purchaseState = .idle
    }
}
