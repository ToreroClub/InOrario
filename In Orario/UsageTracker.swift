import Foundation
import SwiftUI
import Combine
import CoreLocation

struct StationVisit: Codable, Identifiable {
    var id: String { "\(stationName)-\(date.timeIntervalSince1970)" }
    let stationName: String
    let vtID: String?
    let rfiID: String?
    let date: Date
    let weekday: Int
    let hour: Int
    let gpsConfirmed: Bool
    var lat: Double?
    var lon: Double?
}

struct TrainCheck: Codable, Identifiable {
    var id: String { "\(trainNumber)-\(date.timeIntervalSince1970)" }
    let trainNumber: String
    let category: String
    let destination: String
    let date: Date
    let weekday: Int
    let hour: Int
    var lat: Double?
    var lon: Double?
}

struct RouteUsage: Codable, Identifiable {
    var id: String { "\(originID)-\(destID)-\(date.timeIntervalSince1970)" }
    let originID: String
    let originName: String
    let destID: String
    let destName: String
    let date: Date
    let weekday: Int
    let hour: Int
    var lat: Double?
    var lon: Double?
}

enum SmartSuggestion: Identifiable {
    var id: String {
        switch self {
        case .station(let s): return "station-\(s.name)"
        case .train(let t): return "train-\(t.number)"
        case .route(let r): return "route-\(r.originID)-\(r.destinationID)"
        }
    }
    
    case station(Station)
    case train(Train)
    case route(FavoriteRoute)
}

@MainActor
class UsageTracker: ObservableObject {
    @AppStorage("smartSuggestionsEnabled") var smartSuggestionsEnabled = true
    
    @Published var stationVisits: [StationVisit] = [] {
        didSet { save() }
    }
    @Published var trainChecks: [TrainCheck] = [] {
        didSet { save() }
    }
    @Published var routeUsages: [RouteUsage] = [] {
        didSet { save() }
    }
    
    @Published var ignoredStationNames: Set<String> = [] {
        didSet { saveIgnored() }
    }
    @Published var ignoredTrainNumbers: Set<String> = [] {
        didSet { saveIgnored() }
    }
    @Published var ignoredRouteKeys: Set<String> = [] {
        didSet { saveIgnored() }
    }
    
    private let visitsKey = "smartVisits_v1"
    private let trainsKey = "smartTrains_v1"
    private let routesKey = "smartRoutes_v1"
    private let ignoredStationsKey = "smartIgnoredStations_v1"
    private let ignoredTrainsKey = "smartIgnoredTrains_v1"
    private let ignoredRoutesKey = "smartIgnoredRoutes_v1"
    private let maxEntries = 300
    
    init() {
        UserDefaults.standard.removeObject(forKey: "simulateSmartSuggestions")
        load()
        loadIgnored()
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(stationVisits) {
            UserDefaults.standard.set(data, forKey: visitsKey)
        }
        if let data = try? JSONEncoder().encode(trainChecks) {
            UserDefaults.standard.set(data, forKey: trainsKey)
        }
        if let data = try? JSONEncoder().encode(routeUsages) {
            UserDefaults.standard.set(data, forKey: routesKey)
        }
    }
    
    func saveIgnored() {
        UserDefaults.standard.set(Array(ignoredStationNames), forKey: ignoredStationsKey)
        UserDefaults.standard.set(Array(ignoredTrainNumbers), forKey: ignoredTrainsKey)
        UserDefaults.standard.set(Array(ignoredRouteKeys), forKey: ignoredRoutesKey)
    }
    
    func load() {
        if let data = UserDefaults.standard.data(forKey: visitsKey),
           let decoded = try? JSONDecoder().decode([StationVisit].self, from: data) {
            stationVisits = decoded
        }
        if let data = UserDefaults.standard.data(forKey: trainsKey),
           let decoded = try? JSONDecoder().decode([TrainCheck].self, from: data) {
            trainChecks = decoded
        }
        if let data = UserDefaults.standard.data(forKey: routesKey),
           let decoded = try? JSONDecoder().decode([RouteUsage].self, from: data) {
            routeUsages = decoded
        }
    }
    
    func loadIgnored() {
        if let stations = UserDefaults.standard.stringArray(forKey: ignoredStationsKey) {
            ignoredStationNames = Set(stations)
        }
        if let trains = UserDefaults.standard.stringArray(forKey: ignoredTrainsKey) {
            ignoredTrainNumbers = Set(trains)
        }
        if let routes = UserDefaults.standard.stringArray(forKey: ignoredRoutesKey) {
            ignoredRouteKeys = Set(routes)
        }
    }
    
    func clearHistory() {
        stationVisits = []
        trainChecks = []
        routeUsages = []
    }
    
    func ignoreSuggestion(_ suggestion: SmartSuggestion) {
        switch suggestion {
        case .station(let station):
            ignoreStation(station.name)
        case .train(let train):
            ignoreTrain(train.number)
        case .route(let route):
            ignoreRoute("\(route.originID)-\(route.destinationID)")
        }
    }
    
    func ignoreStation(_ name: String) {
        ignoredStationNames.insert(name.lowercased())
        stationVisits.removeAll { $0.stationName.lowercased() == name.lowercased() }
    }
    
    func ignoreTrain(_ number: String) {
        ignoredTrainNumbers.insert(number)
        trainChecks.removeAll { $0.trainNumber == number }
    }
    
    func ignoreRoute(_ key: String) {
        ignoredRouteKeys.insert(key)
        routeUsages.removeAll { "\($0.originID)-\($0.destID)" == key }
    }
    
    func unignoreAll() {
        ignoredStationNames.removeAll()
        ignoredTrainNumbers.removeAll()
        ignoredRouteKeys.removeAll()
    }
    
    func isStationIgnored(_ name: String) -> Bool {
        return ignoredStationNames.contains(name.lowercased())
    }
    
    func isTrainIgnored(_ number: String) -> Bool {
        return ignoredTrainNumbers.contains(number)
    }
    
    func isRouteIgnored(_ key: String) -> Bool {
        return ignoredRouteKeys.contains(key)
    }
    
    func recordStationVisit(name: String, vtID: String?, rfiID: String?, gpsNear: Bool, location: CLLocationCoordinate2D? = nil) {
        guard smartSuggestionsEnabled else { return }
        let now = Date()
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        let hour = cal.component(.hour, from: now)
        
        let visit = StationVisit(stationName: name, vtID: vtID, rfiID: rfiID, date: now, weekday: weekday, hour: hour, gpsConfirmed: gpsNear, lat: location?.latitude, lon: location?.longitude)
        
        stationVisits.removeAll { $0.stationName == name && cal.isDate($0.date, inSameDayAs: now) && abs(cal.component(.hour, from: $0.date) - hour) < 2 }
        stationVisits.insert(visit, at: 0)
        
        if stationVisits.count > maxEntries {
            stationVisits = Array(stationVisits.prefix(maxEntries))
        }
    }
    
    func recordTrainCheck(number: String, category: String, destination: String, location: CLLocationCoordinate2D? = nil) {
        guard smartSuggestionsEnabled else { return }
        let now = Date()
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        let hour = cal.component(.hour, from: now)
        
        let check = TrainCheck(trainNumber: number, category: category, destination: destination, date: now, weekday: weekday, hour: hour, lat: location?.latitude, lon: location?.longitude)
        
        trainChecks.removeAll { $0.trainNumber == number && cal.isDate($0.date, inSameDayAs: now) && abs(cal.component(.hour, from: $0.date) - hour) < 2 }
        trainChecks.insert(check, at: 0)
        
        if trainChecks.count > maxEntries {
            trainChecks = Array(trainChecks.prefix(maxEntries))
        }
    }
    
    func recordRouteSearch(originID: String, originName: String, destID: String, destName: String, location: CLLocationCoordinate2D? = nil) {
        guard smartSuggestionsEnabled else { return }
        let now = Date()
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        let hour = cal.component(.hour, from: now)
        
        let route = RouteUsage(originID: originID, originName: originName, destID: destID, destName: destName, date: now, weekday: weekday, hour: hour, lat: location?.latitude, lon: location?.longitude)
        
        routeUsages.removeAll { $0.originID == originID && $0.destID == destID && cal.isDate($0.date, inSameDayAs: now) && abs(cal.component(.hour, from: $0.date) - hour) < 2 }
        routeUsages.insert(route, at: 0)
        
        if routeUsages.count > maxEntries {
            routeUsages = Array(routeUsages.prefix(maxEntries))
        }
    }
    
    func suggestionsForNow(
        location: CLLocationCoordinate2D? = nil,
        excludeStations: [String] = [],
        excludeTrainNumbers: [String] = [],
        favoriteTrains: [SavedTrain] = []
    ) -> [SmartSuggestion] {
        guard smartSuggestionsEnabled else { return [] }

        let now = Date()
        let cal = Calendar.current
        let currentHour = cal.component(.hour, from: now)
        let currentMinute = cal.component(.minute, from: now)
        let currentWeekday = cal.component(.weekday, from: now)
        let isTodayWeekend = (currentWeekday == 1 || currentWeekday == 7)
        
        let timeDistance = { (h1: Int, h2: Int) -> Int in
            let diff = abs(h1 - h2)
            return min(diff, 24 - diff)
        }
        
        let isLocationMatch = { (lat: Double?, lon: Double?) -> Bool in
            guard let currentLoc = location, let targetLat = lat, let targetLon = lon else { return false }
            let l1 = CLLocation(latitude: currentLoc.latitude, longitude: currentLoc.longitude)
            let l2 = CLLocation(latitude: targetLat, longitude: targetLon)
            return l1.distance(from: l2) <= 1000
        }
        
        var scoredCandidates: [(suggestion: SmartSuggestion, score: Int)] = []
        
        // 1. Analizza le stazioni (solo abitudini consolidate: >= 3 giorni distinti, >= 2 nella fascia oraria attuale)
        let lowerExcludedStations = Set(excludeStations.map { $0.lowercased() })
        let recentStationVisits = stationVisits.filter {
            (cal.dateComponents([.day], from: $0.date, to: now).day ?? 999) <= 35
        }
        let visitsByName = Dictionary(grouping: recentStationVisits, by: { $0.stationName })
        
        var bestStationCandidate: (station: Station, score: Int)? = nil
        
        for (name, visits) in visitsByName {
            if isStationIgnored(name) || lowerExcludedStations.contains(name.lowercased()) { continue }
            
            let count = visits.count
            let distinctDays = Set(visits.map { cal.startOfDay(for: $0.date) }).count
            let windowVisits = visits.filter { timeDistance($0.hour, currentHour) <= 2 }
            guard (distinctDays >= 2 && !windowVisits.isEmpty) || windowVisits.count >= 2 || count >= 3 else { continue }
            
            var totalScore = 0
            var latestVisit = visits[0]
            
            for visit in (windowVisits.isEmpty ? visits : windowVisits) {
                if visit.date > latestVisit.date { latestVisit = visit }
                var visitScore = 0
                let hDist = timeDistance(visit.hour, currentHour)
                let isSameWeekday = visit.weekday == currentWeekday
                let isWeekendVisit = (visit.weekday == 1 || visit.weekday == 7)
                let isNear = isLocationMatch(visit.lat, visit.lon)
                
                if hDist == 0 { visitScore += 15 }
                else if hDist == 1 { visitScore += 10 }
                else if hDist == 2 { visitScore += 5 }
                
                if isSameWeekday { visitScore += 8 }
                else if isTodayWeekend == isWeekendVisit { visitScore += 4 }
                
                if isNear { visitScore += 10 }
                if visit.gpsConfirmed { visitScore += 4 }
                
                let daysAgo = cal.dateComponents([.day], from: visit.date, to: now).day ?? 0
                if daysAgo <= 7 { visitScore += 4 }
                else if daysAgo <= 14 { visitScore += 2 }
                
                totalScore += visitScore
            }
            
            guard totalScore >= 18 else { continue }
            let stationObj = Station(name: name, rfiID: latestVisit.rfiID, vtID: latestVisit.vtID, lat: nil, lon: nil)
            if bestStationCandidate == nil || totalScore > bestStationCandidate!.score {
                bestStationCandidate = (stationObj, totalScore)
            }
        }
        
        if let bestStation = bestStationCandidate {
            scoredCandidates.append((.station(bestStation.station), bestStation.score))
        }
        
        // 2. Analizza i treni
        let excludedTrains = Set(excludeTrainNumbers)
        let recentTrainChecks = trainChecks.filter {
            (cal.dateComponents([.day], from: $0.date, to: now).day ?? 999) <= 35
        }
        let checksByNumber = Dictionary(grouping: recentTrainChecks, by: { $0.trainNumber })
        
        var bestTrainCandidate: (train: Train, score: Int)? = nil
        
        // 2a. Treni da storico consultazioni
        for (number, checks) in checksByNumber {
            if isTrainIgnored(number) || excludedTrains.contains(number) { continue }
            
            let count = checks.count
            let distinctDays = Set(checks.map { cal.startOfDay(for: $0.date) }).count
            let windowChecks = checks.filter { timeDistance($0.hour, currentHour) <= 2 }
            guard (distinctDays >= 2 && !windowChecks.isEmpty) || windowChecks.count >= 2 || count >= 3 else { continue }
            
            var totalScore = 0
            var latestCheck = checks[0]
            
            for check in (windowChecks.isEmpty ? checks : windowChecks) {
                if check.date > latestCheck.date { latestCheck = check }
                var checkScore = 0
                let hDist = timeDistance(check.hour, currentHour)
                let isSameWeekday = check.weekday == currentWeekday
                let isWeekendCheck = (check.weekday == 1 || check.weekday == 7)
                let isNear = isLocationMatch(check.lat, check.lon)
                
                if hDist == 0 { checkScore += 15 }
                else if hDist == 1 { checkScore += 10 }
                else if hDist == 2 { checkScore += 5 }
                
                if isSameWeekday { checkScore += 8 }
                else if isTodayWeekend == isWeekendCheck { checkScore += 4 }
                
                if isNear { checkScore += 10 }
                
                let daysAgo = cal.dateComponents([.day], from: check.date, to: now).day ?? 0
                if daysAgo <= 7 { checkScore += 4 }
                else if daysAgo <= 14 { checkScore += 2 }
                
                totalScore += checkScore
            }
            
            guard totalScore >= 18 else { continue }
            let favMatch = favoriteTrains.first(where: { $0.number == number })
            let cat = latestCheck.category.isEmpty ? "Treno" : latestCheck.category
            let dest = !latestCheck.destination.isEmpty ? latestCheck.destination : (favMatch?.description ?? "")
            let time = favMatch?.departureTime ?? "--:--"
            let t = Train(category: cat, number: number, destination: dest, time: time, delay: "In orario", platform: "--")
            
            if bestTrainCandidate == nil || totalScore > bestTrainCandidate!.score {
                bestTrainCandidate = (t, totalScore)
            }
        }
        
        // 2b. Treni preferiti in partenza imminente (tra -10 min e +75 min)
        let currentTotalMinutes = currentHour * 60 + currentMinute
        for fav in favoriteTrains {
            if isTrainIgnored(fav.number) { continue }
            guard let depTime = fav.departureTime else { continue }
            let parts = depTime.components(separatedBy: ":")
            guard parts.count == 2,
                  let h = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let m = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { continue }
            
            let favMinutes = h * 60 + m
            let diff = favMinutes - currentTotalMinutes
            if diff >= -10 && diff <= 75 {
                let score = 60 - abs(diff) / 2
                let lastCheck = checksByNumber[fav.number]?.first
                let cat = lastCheck?.category ?? "Treno"
                let dest = lastCheck?.destination ?? fav.description
                let t = Train(category: cat, number: fav.number, destination: dest, time: depTime, delay: "In orario", platform: "--")
                if bestTrainCandidate == nil || score > bestTrainCandidate!.score {
                    bestTrainCandidate = (t, score)
                }
            }
        }
        
        if let bestTrain = bestTrainCandidate {
            scoredCandidates.append((.train(bestTrain.train), bestTrain.score))
        }
        
        // 3. Analizza le tratte (solo abitudini consolidate: >= 3 giorni distinti, >= 2 in questa fascia oraria)
        let recentRouteUsages = routeUsages.filter {
            (cal.dateComponents([.day], from: $0.date, to: now).day ?? 999) <= 35
        }
        let routesByKey = Dictionary(grouping: recentRouteUsages, by: { "\($0.originID)-\($0.destID)" })
        var bestRouteCandidate: (route: FavoriteRoute, score: Int)? = nil
        
        for (key, usages) in routesByKey {
            if isRouteIgnored(key) { continue }
            
            let distinctDays = Set(usages.map { cal.startOfDay(for: $0.date) }).count
            guard distinctDays >= 3 else { continue }
            
            let windowUsages = usages.filter { timeDistance($0.hour, currentHour) <= 2 }
            let distinctWindowDays = Set(windowUsages.map { cal.startOfDay(for: $0.date) }).count
            guard distinctWindowDays >= 2 else { continue }
            
            var totalScore = 0
            var latestUsage = usages[0]
            
            for usage in windowUsages {
                if usage.date > latestUsage.date { latestUsage = usage }
                var uScore = 0
                let hDist = timeDistance(usage.hour, currentHour)
                let isSameWeekday = usage.weekday == currentWeekday
                let isNear = isLocationMatch(usage.lat, usage.lon)
                
                if hDist == 0 { uScore += 15 }
                else if hDist == 1 { uScore += 10 }
                else { uScore += 5 }
                
                if isSameWeekday { uScore += 8 }
                if isNear { uScore += 10 }
                
                let daysAgo = cal.dateComponents([.day], from: usage.date, to: now).day ?? 0
                if daysAgo <= 7 { uScore += 4 }
                
                totalScore += uScore
            }
            
            guard totalScore >= 30 else { continue }
            let r = FavoriteRoute(
                originName: latestUsage.originName,
                originID: latestUsage.originID,
                destinationName: latestUsage.destName,
                destinationID: latestUsage.destID
            )
            if bestRouteCandidate == nil || totalScore > bestRouteCandidate!.score {
                bestRouteCandidate = (r, totalScore)
            }
        }
        
        if let bestRoute = bestRouteCandidate {
            scoredCandidates.append((.route(bestRoute.route), bestRoute.score))
        }
        
        // Restituisce al massimo i 2 suggerimenti più forti in assoluto
        return scoredCandidates
            .sorted { $0.score > $1.score }
            .prefix(2)
            .map { $0.suggestion }
    }
    
    // MARK: - Learned Habits by Time Slot
    
    func learnedHabitsByTimeSlot() -> [TimeSlotHabit] {
        let slotsConfig: [(title: String, range: String, icon: String, color: Color, hours: Range<Int>)] = [
            ("Mattina", "06:00 - 12:00", "sun.and.horizon.fill", .orange, 6..<12),
            ("Pomeriggio", "12:00 - 18:00", "sun.max.fill", .yellow, 12..<18),
            ("Sera", "18:00 - 24:00", "sunset.fill", .indigo, 18..<24),
            ("Notte", "00:00 - 06:00", "moon.stars.fill", .purple, 0..<6)
        ]
        
        return slotsConfig.map { cfg in
            let filteredVisits = stationVisits.filter {
                cfg.hours.contains($0.hour) && !isStationIgnored($0.stationName)
            }
            let stationCounts = Dictionary(grouping: filteredVisits, by: { $0.stationName.capitalized })
                .map { name, visits in LearnedStationHabit(name: name, count: visits.count) }
                .sorted { $0.count > $1.count }
            
            let filteredTrains = trainChecks.filter {
                cfg.hours.contains($0.hour) && !isTrainIgnored($0.trainNumber)
            }
            let trainCounts = Dictionary(grouping: filteredTrains, by: { $0.trainNumber })
                .compactMap { number, checks -> LearnedTrainHabit? in
                    guard let first = checks.first else { return nil }
                    return LearnedTrainHabit(
                        number: number,
                        category: first.category,
                        destination: first.destination,
                        count: checks.count
                    )
                }
                .sorted { $0.count > $1.count }
            
            return TimeSlotHabit(
                title: cfg.title,
                timeRange: cfg.range,
                icon: cfg.icon,
                color: cfg.color,
                stations: Array(stationCounts.prefix(4)),
                trains: Array(trainCounts.prefix(4))
            )
        }
    }
}

// MARK: - Learned Habits Models

struct LearnedStationHabit: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let count: Int
}

struct LearnedTrainHabit: Identifiable, Equatable {
    var id: String { "\(category) \(number)" }
    let number: String
    let category: String
    let destination: String
    let count: Int
}

struct TimeSlotHabit: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let timeRange: String
    let icon: String
    let color: Color
    let stations: [LearnedStationHabit]
    let trains: [LearnedTrainHabit]
    
    var isEmpty: Bool {
        stations.isEmpty && trains.isEmpty
    }
}

