import SwiftUI
import Combine
import Foundation
import CoreLocation
import ActivityKit
import StoreKit
import CoreSpotlight
import UniformTypeIdentifiers

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
    @Published var apnsToken: String? = nil
    @Published var notificationLimitError: String? = nil
    
    private let remoteNotificationsEnabledKey = "remoteNotificationsEnabled_v1"
    private let notifyOnStationPassKey = "notifyOnStationPass_v1"
    private let strikeRegionKey = "strikeRegion_v1"
    private let strikeNotificationsEnabledKey = "strikeNotificationsEnabled_v1"
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
    private var stationCache: [String: (timestamp: Date, trains: [Train], alerts: String?)] = [:]
    
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
        
        isInitializing = false
        
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

        if let data = UserDefaults.standard.data(forKey: favoritesKey), let decoded = try? JSONDecoder().decode([SavedTrain].self, from: data) {
            self.favoriteTrains = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: myStationsKey), let decoded = try? JSONDecoder().decode([Station].self, from: data) {
            self.myStations = decoded.map { st in
                if let rfi = st.rfiID, (rfi.hasPrefix("S") || rfi.hasPrefix("N")) {
                    return Station(name: st.name, rfiID: nil, vtID: st.vtID, lat: st.lat, lon: st.lon)
                }
                return st
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
        
        indexSpotlightItems()
        
        UserDefaults.standard.synchronize()
        
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
            
            store.synchronize()
        }
        
        if let groupDefaults = UserDefaults(suiteName: "group.carlo.InOrario") {
            groupDefaults.set(homeDestinationStationName, forKey: homeDestinationStationNameKey)
        }
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
        let station = VTSearchStation(nomeLungo: name, nomeBreve: name, vtID: vtID)
        viewedRecentStations.removeAll { $0.vtID == station.vtID }
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
        guard UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") else { return }
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
                if train.notifyDelay ?? false {
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
        
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/notifications/sync") else { return }
        
        let payload: [String: Any] = [
            "token": token,
            "platform": "ios",
            "strike_region": strikeRegion,
            "strike_enabled": strikeEnabled,
            "trains": trainsPayload,
            "device_model": getDeviceModelName(),
            "os_version": UIDevice.current.systemVersion,
            "ai_engine": hasSupport() ? (AIFeatureManager.shared.preferLocalAI ? "local" : "cloud") : (AIFeatureManager.shared.isLocalModelInstalled ? "local" : "none"),
            "has_support": hasSupport()
        ]
        
        Task {
            do {
                let (_, response) = try await NetworkService.shared.post(url: url, payload: payload)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    print("[syncRemoteNotifications] Sincronizzazione completata con successo sul server.")
                } else {
                    print("[syncRemoteNotifications] Risposta server non 200 per sincronizzazione")
                }
            } catch {
                print("[syncRemoteNotifications] Errore nell'invio della sincronizzazione: \(error.localizedDescription)")
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
                                self.notificationLimitError = "La gestione delle notifiche in tempo reale comporta costi di server continui per ciascun treno monitorato. Se trovi utile l'app, considera di sostenere lo sviluppo indipendente con un piccolo contributo: sbloccherai il monitoraggio fino a 10 treni contemporaneamente e le notifiche personalizzate per gli scioperi della tua regione."
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
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/liveactivity/register") else { return }
        let tokenString = pushToken.map { String(format: "%02x", $0) }.joined()
        let payload: [String: Any] = [
            "token": deviceToken,
            "push_token": tokenString,
            "train_number": trainNumber
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
    
    func addMyStation(_ station: Station) {
        if !myStations.contains(where: { $0.name == station.name }) {
            myStations.append(station)
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
        myStations.removeAll { $0.name == station.name }
        saveFavorites()
        Haptics.notify(.warning)
    }
    
    func isMyStation(vtID: String) -> Bool {
        return myStations.contains { $0.vtID == vtID }
    }
    
    func isMyStation(_ station: Station) -> Bool {
        return myStations.contains { $0.name == station.name }
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
        
        let lowerQ = normalizeStationName(query)
        let hits = allRFIStations.filter { normalizeStationName($0.name).contains(lowerQ) && isValidStationName($0.name) }
        
        var results: [VTSearchStation] = []
        var seenIDs = Set<String>()
        for r in hits {
            let vtID = r.vtID ?? r.rfiID ?? ""
            let key = vtID.isEmpty ? r.name : vtID
            if !seenIDs.contains(key) {
                seenIDs.insert(key)
                results.append(VTSearchStation(nomeLungo: r.name, nomeBreve: r.name, vtID: vtID))
            }
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
                
                let isCancelled = (item["cancellato"] as? Bool ?? false) || (item["provvedimento"] as? Int ?? 0) == 1
                let delayStr = isCancelled ? "Cancellato" : (ritardo > 0 ? "+\(ritardo)'" : "In orario")
                
                if timeVal > 0 {
                    let date = Date(timeIntervalSince1970: TimeInterval(timeVal/1000))
                    return Train(category: cat, number: num, destination: dest, time: SharedFormatters.time.string(from: date), delay: delayStr, platform: platform)
                }
                return nil
            }
        } catch {
            return []
        }
    }
    
    func fetchVTTrains(for vtID: String, isDepartures: Bool, force: Bool = false) async {
        let stationKey = "\(vtID)_\(isDepartures)"
        
        // Check cache (TTL 15 seconds)
        if !force, let cached = stationCache[stationKey], Date().timeIntervalSince(cached.timestamp) < 60.0 {
            self.trains = cached.trains
            self.stationAlerts = cached.alerts
            self.lastFetchedStationKey = stationKey
            self.isLoading = false
            return
        }
        
        if self.lastFetchedStationKey != stationKey {
            self.trains = []
            self.lastFetchedStationKey = stationKey
        }
        self.isLoading = true
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        f.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT'ZZZ"
        let dateStr = f.string(from: Date()).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        
        let fetchedTrains = await performVTFetch(for: vtID, isDepartures: isDepartures, dateStr: dateStr)
        
        self.trains = fetchedTrains
        self.stationCache[stationKey] = (Date(), fetchedTrains, nil)
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
    
    func fetchTrains(for station: Station, isDepartures: Bool, force: Bool = false) async {
        let stationKey = "\(station.vtID ?? station.rfiID ?? station.name)_\(isDepartures)"
        
        // Check cache (TTL 60 seconds)
        if !force, let cached = stationCache[stationKey], Date().timeIntervalSince(cached.timestamp) < 60.0 {
            self.trains = cached.trains
            self.stationAlerts = cached.alerts
            self.lastFetchedStationKey = stationKey
            self.isLoading = false
            return
        }
        
        if self.lastFetchedStationKey != stationKey {
            self.trains = []
            self.lastFetchedStationKey = stationKey
        }
        self.isLoading = true
        self.stationAlerts = nil
        
        let rfiID = station.rfiID ?? ""
        let vtID = station.vtID ?? ""
        
        if !rfiID.isEmpty {
            // Stazione RFI: scraping principale
            let rfiResult = await performRfiScraping(for: rfiID, isDepartures: isDepartures)
            if let alerts = rfiResult.alerts { self.stationAlerts = alerts }
            
            if !rfiResult.trains.isEmpty {
                // Controlla se ci sono treni nei prossimi 30 minuti prima di chiamare VT
                let hasUpcomingTrains = rfiResult.trains.contains { trainIsWithinNextMinutes($0, minutes: 45) }
                
                if hasUpcomingTrains && !vtID.isEmpty {
                    // Almeno un treno imminente → vale la pena arricchire con VT
                    let vtDateStr = makeVTDateString()
                    let vtTrains = await performVTFetch(for: vtID, isDepartures: isDepartures, dateStr: vtDateStr)
                    self.trains = vtTrains.isEmpty
                        ? rfiResult.trains
                        : mergeVTDelays(rfiTrains: rfiResult.trains, vtTrains: vtTrains)
                } else {
                    // Nessun treno imminente o nessun vtID: usa RFI as-is, risparmia la chiamata VT
                    self.trains = rfiResult.trains
                }
            } else if !vtID.isEmpty {
                // RFI fallisce → fallback VT puro
                let vtTrains = await performVTFetch(for: vtID, isDepartures: isDepartures, dateStr: makeVTDateString())
                self.trains = vtTrains
            } else {
                self.trains = []
            }
        } else if !vtID.isEmpty {
            // Stazione senza tabellone RFI (es. Ferrovie Nord): usa solo VT, nessun merge
            let vtTrains = await performVTFetch(for: vtID, isDepartures: isDepartures, dateStr: makeVTDateString())
            self.trains = vtTrains
        } else {
            self.trains = []
        }
        
        // Cache successful results
        self.stationCache[stationKey] = (Date(), self.trains, self.stationAlerts)
        self.isLoading = false
    }
    
    /// Restituisce true se l'orario programmato del treno cade entro i prossimi `minutes` minuti
    /// (o fino a 5 minuti fa, per coprire treni già partiti di poco).
    nonisolated private func trainIsWithinNextMinutes(_ train: Train, minutes: Int) -> Bool {
        // train.time è in formato "HH:mm"
        let parts = train.time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return false }
        
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        
        guard var trainDate = calendar.date(from: components) else { return false }
        
        // Gestione mezzanotte: se il treno sembra molto nel passato, è probabilmente domani
        let diff = trainDate.timeIntervalSince(now)
        if diff < -43200 { trainDate = calendar.date(byAdding: .day, value: 1, to: trainDate) ?? trainDate }
        else if diff > 43200 { trainDate = calendar.date(byAdding: .day, value: -1, to: trainDate) ?? trainDate }
        
        let windowStart = calendar.date(byAdding: .minute, value: -5, to: now)!
        let windowEnd   = calendar.date(byAdding: .minute, value: minutes, to: now)!
        return trainDate >= windowStart && trainDate <= windowEnd
    }
    
    /// Costruisce la stringa data/ora nel formato richiesto da ViaggiaTreno.
    nonisolated private func makeVTDateString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        f.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT'ZZZ"
        let str = f.string(from: Date()).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return str.replacingOccurrences(of: "+", with: "%2B")
    }
    
    /// Combina i treni RFI con i ritardi più precisi di ViaggiaTreno.
    /// - Struttura (numero, destinazione, orario, binario): sempre da RFI
    /// - Ritardo VT applicato SOLO ai treni nei prossimi 30 minuti
    /// - Cancellazioni/soppressioni: RFI ha sempre priorità
    /// - Stazioni FNM (rfiID vuoto): questa funzione NON viene mai chiamata per loro
    nonisolated private func mergeVTDelays(rfiTrains: [Train], vtTrains: [Train]) -> [Train] {
        // Indice VT per numero treno — O(1) lookup
        let vtByNumber: [String: Train] = Dictionary(
            vtTrains.map { ($0.number, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        
        // Soglia oltre la quale la discrepanza è sospetta e non ci fidiamo di VT
        let discrepancyThreshold = 15
        
        return rfiTrains.map { rfi in
            // Treni oltre la finestra dei 45 minuti: non toccare, risparmia il merge
            guard trainIsWithinNextMinutes(rfi, minutes: 45) else { return rfi }
            
            let rfiDelayLower = rfi.delay.lowercased()
            
            // 1. Cancellazione/soppressione da RFI ha sempre la priorità assoluta
            if rfiDelayLower.contains("cancellat") || rfiDelayLower.contains("soppress") {
                return rfi
            }
            
            // 2. Se VT non conosce il treno → tieni RFI com'è
            guard let vt = vtByNumber[rfi.number] else { return rfi }
            
            let vtDelayLower = vt.delay.lowercased()
            
            // 3. Se VT dice cancellato/soppresso → non fidarsi (RFI è più affidabile sulle cancellazioni)
            if vtDelayLower.contains("cancellat") || vtDelayLower.contains("soppress") {
                return rfi
            }
            
            // Converti i due ritardi in minuti per il confronto numerico
            let rfiMin = parseDelayMinutes(rfi.delay)
            let vtMin  = parseDelayMinutes(vt.delay)
            let diff   = abs(vtMin - rfiMin)
            
            // 4. Discrepanza enorme (> 15 min): VT probabilmente ha un omonimo o dati vecchi
            //    → mantieni il ritardo RFI e segnala incertezza con il badge "?"
            if diff > discrepancyThreshold {
                return Train(
                    category: rfi.category, number: rfi.number,
                    destination: rfi.destination, time: rfi.time,
                    delay: rfi.delay, platform: rfi.platform,
                    isDelayUncertain: true
                )
            }
            
            // 5. Caso normale: sostituisci il ritardo RFI con quello più preciso di VT
            return Train(
                category: rfi.category, number: rfi.number,
                destination: rfi.destination, time: rfi.time,
                delay: vt.delay, platform: rfi.platform,
                isDelayUncertain: false
            )
        }
    }
    
    /// Parsa una stringa di ritardo (es. "+7'", "In orario", "0'") in minuti interi.
    nonisolated private func parseDelayMinutes(_ delay: String) -> Int {
        let cleaned = delay
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespaces)
        if cleaned.lowercased().contains("orario") { return 0 }
        return Int(cleaned) ?? 0
    }
    
    nonisolated func fetchLiveStops(for trainNumber: String, destination: String? = nil) async -> StopsResult {
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
            var bestScore: Double = -999999.0
            
            for (targetLine, json) in results {
                let pipes = targetLine.components(separatedBy: "|")
                let subParts = pipes.count >= 2 ? pipes[1].components(separatedBy: "-") : []
                let tsStr = subParts.count >= 3 ? subParts[2] : ""
                let trainTs = Double(tsStr) ?? nowTs
                
                let deltaDays = abs(nowTs - trainTs) / (1000.0 * 60 * 60 * 24)
                let isDeparted = !(json["nonPartito"] as? Bool ?? true)
                let isArrived = (json["arrivato"] as? Bool) ?? false
                
                let baseScore = (isDeparted && !isArrived) ? 10000.0 : 1000.0
                var score = baseScore - (deltaDays * 100.0)
                
                if let dest = destination, !dest.isEmpty {
                    let targetUpper = targetLine.uppercased()
                    let destUpper = dest.uppercased()
                    
                    let cleanDest = destUpper.replacingOccurrences(of: "MILANO P. ", with: "MILANO ")
                                             .replacingOccurrences(of: "MILANO ", with: "")
                    let cleanTarget = targetUpper.replacingOccurrences(of: "MILANO P. ", with: "MILANO ")
                                                 .replacingOccurrences(of: "MILANO ", with: "")
                    
                    if cleanTarget.contains(cleanDest) || cleanDest.contains(cleanTarget) {
                        score += 50000.0
                    } else {
                        let words = cleanDest.components(separatedBy: " ").filter { $0.count > 3 }
                        for word in words {
                            if cleanTarget.contains(word) {
                                score += 10000.0
                            }
                        }
                    }
                }
                
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
                    if actT == nil && effectiveDelay >= 3 {
                        if let futureDate = Calendar.current.date(byAdding: .minute, value: effectiveDelay, to: d) {
                            estT = SharedFormatters.time.string(from: futureDate)
                        }
                    }
                    
                    let progArr = f["binarioProgrammatoArrivoDescrizione"] as? String
                    let progPart = f["binarioProgrammatoPartenzaDescrizione"] as? String
                    let effArr = f["binarioEffettivoArrivoDescrizione"] as? String
                    let effPart = f["binarioEffettivoPartenzaDescrizione"] as? String
                    
                    let plannedPlatform = (progPart ?? progArr)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let actualPlatform = (effPart ?? effArr)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    return Stop(stationName: name.capitalized,
                                time: SharedFormatters.time.string(from: d),
                                actualTime: actT,
                                delay: effectiveDelay,
                                estimatedTime: estT,
                                plannedPlatform: plannedPlatform,
                                actualPlatform: actualPlatform)
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
        let result = await fetchLiveStops(for: cleanNumber, destination: train.destination)
        
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
                print("Errore decodifica comfort reports: \(error)")
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
                
                Task {
                    for await state in activity.activityStateUpdates {
                        if state == .ended || state == .dismissed {
                            if let deviceToken = self.apnsToken, !deviceToken.isEmpty {
                                self.unregisterTrainForPush(trainNumber: activity.attributes.trainNumber, token: deviceToken)
                            }
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
            
            Task {
                for await state in activity.activityStateUpdates {
                    if state == .ended || state == .dismissed {
                        if let deviceToken = self.apnsToken, !deviceToken.isEmpty {
                            self.unregisterTrainForPush(trainNumber: activity.attributes.trainNumber, token: deviceToken)
                        }
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
    // MARK: - Hybrid AI / Fetching News
    
    func fetchStrikesAndNews(forceRefresh: Bool = false) async -> [NewsItem] {
        let strikeRegion = self.strikeRegion
        let isPremium = hasSupport()
        let smartSummaryEnabled = UserDefaults.standard.object(forKey: "ai_smartSummaryEnabled") as? Bool ?? true
        
        let lastFetch = UserDefaults.standard.double(forKey: "cachedNewsTimestamp")
        let now = Date().timeIntervalSince1970
        let cacheAge = now - lastFetch
        
        // Carica la cache se non è richiesto un aggiornamento forzato ed è più recente di 5 minuti (300s)
        if !forceRefresh, cacheAge < 300.0, let cached = loadCache() {
            return filterExpiredStrikes(cached)
        }
        
        var result: [NewsItem]
        let aiManager = AIFeatureManager.shared
        // SOLO gli utenti premium usano il Cloud backend
        if isPremium && !aiManager.preferLocalAI {
            let regionParam = strikeRegion.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Tutte"
            async let backendTask = fetchFromBackend(regionParam: regionParam)
            async let trenitaliaTask = LocalScrapingService.shared.scrapeTrenitalia(region: strikeRegion)
            let backendItems = await backendTask
            let localItems = await trenitaliaTask
            result = backendItems + localItems.filter { $0.category == "realtime" }
            
            saveCache(items: result)
        } else if (aiManager.isAppleIntelligenceAvailable || (aiManager.isHardwareCompatible && aiManager.isLocalModelInstalled)) && smartSummaryEnabled {
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
        
        result.sort { a, b in
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
        
        return filterExpiredStrikes(result)
    }
    
    private func filterExpiredStrikes(_ items: [NewsItem]) -> [NewsItem] {
        let fmt1 = DateFormatter()
        fmt1.dateFormat = "dd/MM/yyyy"
        fmt1.locale = Locale(identifier: "it_IT")
        
        let fmt2 = DateFormatter()
        fmt2.dateFormat = "yyyy-MM-dd"
        fmt2.locale = Locale(identifier: "it_IT")
        
        let today = Calendar.current.startOfDay(for: Date())
        
        return items.filter { item in
            guard item.category == "sciopero", let dateStr = item.date else {
                return true // InfoLavori o altri item rimangono sempre
            }
            if item.isUrgent { return true }
            if let date = fmt1.date(from: dateStr) ?? fmt2.date(from: dateStr) {
                let strikeDay = Calendar.current.startOfDay(for: date)
                return strikeDay >= today
            }
            return true
        }
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
            print("Errore fetch dal backend: \(error)")
            return []
        }
    }
    
    func saveCache(items: [NewsItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "cachedStrikesAndNews")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "cachedNewsTimestamp")
        }
    }
    
    func getCachedStrikesAndNews() -> [NewsItem] {
        if let cached = loadCache() {
            return filterExpiredStrikes(cached)
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
            let (data, _) = try await URLSession.shared.data(from: url)
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
