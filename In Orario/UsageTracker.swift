import Foundation
import SwiftUI
import Combine
import CoreLocation

struct StationVisit: Codable, Identifiable {
    var id: String { "\(stationName)-\(date.timeIntervalSince1970)" }
    let stationName: String
    let vtID: String?
    let rfiID: String?
    var date: Date
    let weekday: Int
    let hour: Int
    let gpsConfirmed: Bool
    var lat: Double?
    var lon: Double?
    var viewCount: Int? = 1
}

struct TrainCheck: Codable, Identifiable {
    var id: String { "\(trainNumber)-\(date.timeIntervalSince1970)" }
    let trainNumber: String
    let category: String
    let destination: String
    var date: Date
    let weekday: Int
    let hour: Int
    var lat: Double?
    var lon: Double?
    var viewCount: Int? = 1
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
        
        if let existingIndex = stationVisits.firstIndex(where: {
            $0.stationName.lowercased() == name.lowercased() &&
            cal.isDate($0.date, inSameDayAs: now) &&
            abs(cal.component(.hour, from: $0.date) - hour) < 3
        }) {
            var item = stationVisits[existingIndex]
            item.viewCount = (item.viewCount ?? 1) + 1
            item.date = now
            stationVisits.remove(at: existingIndex)
            stationVisits.insert(item, at: 0)
        } else {
            let visit = StationVisit(
                stationName: name,
                vtID: vtID,
                rfiID: rfiID,
                date: now,
                weekday: weekday,
                hour: hour,
                gpsConfirmed: gpsNear,
                lat: location?.latitude,
                lon: location?.longitude,
                viewCount: 1
            )
            stationVisits.insert(visit, at: 0)
        }
        
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
        
        if let existingIndex = trainChecks.firstIndex(where: {
            $0.trainNumber == number &&
            cal.isDate($0.date, inSameDayAs: now) &&
            abs(cal.component(.hour, from: $0.date) - hour) < 3
        }) {
            var item = trainChecks[existingIndex]
            item.viewCount = (item.viewCount ?? 1) + 1
            item.date = now
            trainChecks.remove(at: existingIndex)
            trainChecks.insert(item, at: 0)
        } else {
            let check = TrainCheck(
                trainNumber: number,
                category: category,
                destination: destination,
                date: now,
                weekday: weekday,
                hour: hour,
                lat: location?.latitude,
                lon: location?.longitude,
                viewCount: 1
            )
            trainChecks.insert(check, at: 0)
        }
        
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
        favoriteTrains: [SavedTrain] = [],
        favoriteStations: [Station] = []
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
            
            // Bonus per stazioni preferite e anzianità
            let favMatch = favoriteStations.first {
                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame ||
                ($0.vtID != nil && latestVisit.vtID != nil && $0.vtID == latestVisit.vtID)
            }
            if let fav = favMatch {
                let daysSaved = favoriteSeniorityDays(addedDate: fav.addedDate)
                totalScore += (daysSaved >= 30 ? 25 : (daysSaved >= 14 ? 15 : 8))
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
            
            let favMatch = favoriteTrains.first(where: { $0.number == number })
            if let fav = favMatch {
                let daysSaved = favoriteSeniorityDays(addedDate: fav.addedDate)
                totalScore += (daysSaved >= 30 ? 25 : (daysSaved >= 14 ? 15 : 8))
            }
            
            guard totalScore >= 18 else { continue }
            let cat = latestCheck.category.isEmpty ? "Treno" : latestCheck.category
            let dest = !latestCheck.destination.isEmpty ? latestCheck.destination : (favMatch?.description ?? "")
            let time = favMatch?.departureTime ?? "--:--"
            let t = Train(category: cat, number: number, destination: dest, time: time, delay: "In orario", platform: "--")
            
            if bestTrainCandidate == nil || totalScore > bestTrainCandidate!.score {
                bestTrainCandidate = (t, totalScore)
            }
        }
        
        // 2b. Treni preferiti in partenza imminente (tra -10 min e +75 min) con ponderazione anzianità
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
                let daysSaved = favoriteSeniorityDays(addedDate: fav.addedDate)
                let seniorityBonus = daysSaved >= 30 ? 20 : (daysSaved >= 14 ? 12 : 5)
                let score = 60 - abs(diff) / 2 + seniorityBonus
                
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
    
    func learnedHabitsByTimeSlot(
        favoriteTrains: [SavedTrain] = [],
        favoriteStations: [Station] = []
    ) -> [TimeSlotHabit] {
        let cal = Calendar.current
        
        // 3 fasce orarie: Mattina (05:00-12:00), Pomeriggio (12:00-19:00), Sera (19:00-01:00)
        let slotsConfig: [(title: String, range: String, icon: String, color: Color, matches: (Int) -> Bool)] = [
            ("Mattina", "05:00 - 12:00", "sun.and.horizon.fill", .orange, { $0 >= 5 && $0 < 12 }),
            ("Pomeriggio", "12:00 - 19:00", "sun.max.fill", .yellow, { $0 >= 12 && $0 < 19 }),
            ("Sera", "19:00 - 01:00", "sunset.fill", .indigo, { $0 >= 19 || $0 == 0 })
        ]
        
        let favTrains: [SavedTrain] = {
            if !favoriteTrains.isEmpty { return favoriteTrains }
            if let data = UserDefaults.standard.data(forKey: "savedFavoriteTrains_v3"),
               let decoded = try? JSONDecoder().decode([SavedTrain].self, from: data) {
                return decoded
            }
            if let defaults = UserDefaults(suiteName: "group.carlo.InOrario"),
               let data = defaults.data(forKey: "savedFavoriteTrains_v3"),
               let decoded = try? JSONDecoder().decode([SavedTrain].self, from: data) {
                return decoded
            }
            return []
        }()
        
        let favStations: [Station] = {
            if !favoriteStations.isEmpty { return favoriteStations }
            if let data = UserDefaults.standard.data(forKey: "savedMyStations_v3"),
               let decoded = try? JSONDecoder().decode([Station].self, from: data) {
                return decoded
            }
            if let defaults = UserDefaults(suiteName: "group.carlo.InOrario"),
               let data = defaults.data(forKey: "savedMyStations_v3"),
               let decoded = try? JSONDecoder().decode([Station].self, from: data) {
                return decoded
            }
            return []
        }()
        
        return slotsConfig.map { cfg in
            // 1. Stazioni più consultate e preferite nella fascia oraria
            let filteredVisits = stationVisits.filter {
                cfg.matches($0.hour) && !isStationIgnored($0.stationName)
            }
            let stationGroups = Dictionary(grouping: filteredVisits, by: { $0.stationName.trimmingCharacters(in: .whitespacesAndNewlines).capitalized })
            
            var stationMap: [String: LearnedStationHabit] = [:]
            
            for (name, visits) in stationGroups {
                guard let firstVisit = visits.first else { continue }
                let total = visits.reduce(0) { $0 + ($1.viewCount ?? 1) }
                let days = Set(visits.map { cal.startOfDay(for: $0.date) }).count
                let favMatch = favStations.first {
                    $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame ||
                    ($0.vtID != nil && firstVisit.vtID != nil && $0.vtID == firstVisit.vtID)
                }
                let isFav = favMatch != nil
                let daysSaved = isFav ? favoriteSeniorityDays(addedDate: favMatch?.addedDate) : 0
                
                let viewPoints = min(total, 30) * 2
                let dayPoints = days * 8
                let favPoints = isFav ? (35 + min(daysSaved, 30)) : 0
                let totalScore = viewPoints + dayPoints + favPoints
                
                let strength = calculateHabitStrength(score: totalScore, isFavorite: isFav, daysSaved: daysSaved, distinctDays: days)
                let desc = stationHabitCountDescription(isFavorite: isFav, daysSaved: daysSaved, totalViews: total, distinctDays: max(1, days))
                
                stationMap[name] = LearnedStationHabit(
                    name: name,
                    totalViews: total,
                    distinctDays: max(1, days),
                    isFavorite: isFav,
                    habitStrength: strength,
                    countDescription: desc,
                    score: totalScore
                )
            }
            
            // Includi stazioni preferite dell'utente
            for fav in favStations {
                if isStationIgnored(fav.name) { continue }
                let capName = fav.name.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
                if stationMap[capName] == nil {
                    let daysSaved = favoriteSeniorityDays(addedDate: fav.addedDate)
                    let totalScore = 35 + min(daysSaved, 30)
                    let strength = calculateHabitStrength(score: totalScore, isFavorite: true, daysSaved: daysSaved, distinctDays: 1)
                    let desc = stationHabitCountDescription(isFavorite: true, daysSaved: daysSaved, totalViews: 0, distinctDays: 1, trainContext: "Stazione preferita")
                    stationMap[capName] = LearnedStationHabit(
                        name: capName,
                        totalViews: 0,
                        distinctDays: 1,
                        isFavorite: true,
                        habitStrength: strength,
                        countDescription: desc,
                        score: totalScore
                    )
                }
            }
            
            let sortedStations = stationMap.values.sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                if $0.isFavorite != $1.isFavorite {
                    return $0.isFavorite && !$1.isFavorite
                }
                return $0.distinctDays > $1.distinctDays
            }
            
            // 2. Treni consultati e abituali nella fascia oraria
            let filteredChecks = trainChecks.filter {
                cfg.matches($0.hour) && !isTrainIgnored($0.trainNumber)
            }
            let checkGroups = Dictionary(grouping: filteredChecks, by: { $0.trainNumber })
            
            var trainsMap: [String: LearnedTrainHabit] = [:]
            
            // Includi i check registrati
            for (num, checks) in checkGroups {
                guard let first = checks.first else { continue }
                let total = checks.reduce(0) { $0 + ($1.viewCount ?? 1) }
                let days = Set(checks.map { cal.startOfDay(for: $0.date) }).count
                let favMatch = favTrains.first { $0.number == num }
                let isFav = favMatch != nil
                let daysSaved = isFav ? favoriteSeniorityDays(addedDate: favMatch?.addedDate) : 0
                
                let cat = resolveTrainCategory(number: num, categoryDesc: first.category, destination: first.destination)
                let dest = favMatch?.description.isEmpty == false ? favMatch!.description : first.destination
                
                let viewPoints = min(total, 30) * 2
                let dayPoints = days * 8
                let favPoints = isFav ? (35 + min(daysSaved, 30)) : 0
                let totalScore = viewPoints + dayPoints + favPoints
                
                let strength = calculateHabitStrength(score: totalScore, isFavorite: isFav, daysSaved: daysSaved, distinctDays: days)
                let desc = trainHabitCountDescription(isFavorite: isFav, daysSaved: daysSaved, totalViews: total, distinctDays: max(1, days))
                
                trainsMap[num] = LearnedTrainHabit(
                    number: num,
                    category: cat,
                    destination: dest,
                    departureTime: favMatch?.departureTime,
                    totalViews: total,
                    distinctDays: max(1, days),
                    isFavorite: isFav,
                    habitStrength: strength,
                    countDescription: desc,
                    score: totalScore
                )
            }
            
            // Includi i treni preferiti con orario programmato in questa fascia oraria
            for fav in favTrains {
                if isTrainIgnored(fav.number) { continue }
                
                var matchesSlot = false
                if let dep = fav.departureTime?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let h = Int(dep.components(separatedBy: ":").first ?? "") {
                    matchesSlot = cfg.matches(h)
                }
                
                if matchesSlot {
                    let daysSaved = favoriteSeniorityDays(addedDate: fav.addedDate)
                    if let existing = trainsMap[fav.number] {
                        let favPoints = 35 + min(daysSaved, 30)
                        let newScore = existing.score + favPoints
                        let strength = calculateHabitStrength(score: newScore, isFavorite: true, daysSaved: daysSaved, distinctDays: existing.distinctDays)
                        let desc = trainHabitCountDescription(isFavorite: true, daysSaved: daysSaved, totalViews: existing.totalViews, distinctDays: existing.distinctDays)
                        
                        trainsMap[fav.number] = LearnedTrainHabit(
                            number: existing.number,
                            category: existing.category,
                            destination: fav.description.isEmpty ? existing.destination : fav.description,
                            departureTime: fav.departureTime ?? existing.departureTime,
                            totalViews: existing.totalViews,
                            distinctDays: existing.distinctDays,
                            isFavorite: true,
                            habitStrength: strength,
                            countDescription: desc,
                            score: newScore
                        )
                    } else {
                        let cat = resolveTrainCategory(number: fav.number, categoryDesc: nil, destination: fav.description)
                        let totalScore = 40 + min(daysSaved, 30)
                        let strength = calculateHabitStrength(score: totalScore, isFavorite: true, daysSaved: daysSaved, distinctDays: 1)
                        let desc = trainHabitCountDescription(isFavorite: true, daysSaved: daysSaved, totalViews: 0, distinctDays: 1)
                        
                        trainsMap[fav.number] = LearnedTrainHabit(
                            number: fav.number,
                            category: cat,
                            destination: fav.description,
                            departureTime: fav.departureTime,
                            totalViews: 0,
                            distinctDays: 1,
                            isFavorite: true,
                            habitStrength: strength,
                            countDescription: desc,
                            score: totalScore
                        )
                    }
                }
            }
            
            let sortedTrains = trainsMap.values.sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                if $0.isFavorite != $1.isFavorite {
                    return $0.isFavorite && !$1.isFavorite
                }
                return $0.distinctDays > $1.distinctDays
            }
            
            return TimeSlotHabit(
                title: cfg.title,
                timeRange: cfg.range,
                icon: cfg.icon,
                color: cfg.color,
                stations: Array(sortedStations.prefix(5)),
                trains: Array(sortedTrains.prefix(5))
            )
        }
    }
}

// MARK: - Learned Habits Models & Helpers

func favoriteSeniorityDays(addedDate: Date?) -> Int {
    guard let date = addedDate else {
        // Se non specificata, è un preferito storico esistente salvato prima dell'aggiornamento (> 35 giorni)
        return 35
    }
    let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    return max(0, days)
}

func habitSeniorityDescription(daysSaved: Int, isFavorite: Bool) -> String {
    guard isFavorite else { return "" }
    if daysSaved >= 30 {
        return "Preferito da oltre 1 mese"
    } else if daysSaved >= 14 {
        let weeks = daysSaved / 7
        return "Preferito da \(weeks) settiman\(weeks == 1 ? "a" : "e")"
    } else if daysSaved >= 2 {
        return "Preferito da \(daysSaved) giorni"
    } else {
        return "Aggiunto di recente"
    }
}

func calculateHabitStrength(score: Int, isFavorite: Bool, daysSaved: Int, distinctDays: Int) -> String {
    if isFavorite && daysSaved >= 30 {
        return "Abitudine consolidata"
    } else if distinctDays >= 4 || (isFavorite && daysSaved >= 14) || score >= 50 {
        return "Abitudine frequente"
    } else if isFavorite {
        return "Nuovo preferito"
    } else if distinctDays >= 2 || score >= 25 {
        return "Consultato spesso"
    } else {
        return "Consultazione recente"
    }
}

func trainHabitCountDescription(
    isFavorite: Bool,
    daysSaved: Int,
    totalViews: Int,
    distinctDays: Int
) -> String {
    if isFavorite {
        let seniority = habitSeniorityDescription(daysSaved: daysSaved, isFavorite: true)
        if totalViews > 1 && distinctDays > 1 {
            return "\(seniority) • \(totalViews) consultazioni in \(distinctDays) giorni"
        } else if totalViews >= 1 {
            return "\(seniority) • \(totalViews) consultazione"
        } else {
            return "\(seniority) • Treno abituale programmato"
        }
    } else {
        if distinctDays > 1 {
            return "\(totalViews) consultazioni in \(distinctDays) giorni"
        } else if totalViews == 1 {
            return "1 consultazione"
        } else {
            return "\(totalViews) consultazioni"
        }
    }
}

func stationHabitCountDescription(
    isFavorite: Bool,
    daysSaved: Int,
    totalViews: Int,
    distinctDays: Int,
    trainContext: String? = nil
) -> String {
    if isFavorite {
        let seniority = habitSeniorityDescription(daysSaved: daysSaved, isFavorite: true)
        if totalViews > 1 && distinctDays > 1 {
            return "\(seniority) • \(totalViews) aperture in \(distinctDays) giorni"
        } else if totalViews >= 1 {
            return "\(seniority) • \(totalViews) apertura"
        } else if let ctx = trainContext {
            return "\(seniority) • \(ctx)"
        } else {
            return "\(seniority) • Stazione preferita"
        }
    } else {
        if distinctDays > 1 {
            return "\(totalViews) aperture in \(distinctDays) giorni"
        } else if totalViews == 1 {
            return "1 apertura recente"
        } else {
            return "\(totalViews) aperture"
        }
    }
}

func resolveTrainCategory(number: String, categoryDesc: String?, destination: String?) -> String {
    let cleanNum = number.trimmingCharacters(in: .whitespacesAndNewlines)
    var cat = categoryDesc?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let catUpper = cat.uppercased()
    let destLower = (destination ?? "").lowercased()
    
    if catUpper.contains("FRECCIAROSSA") || catUpper == "FR" { return "FR" }
    if catUpper.contains("FRECCIARGENTO") || catUpper == "FA" { return "FA" }
    if catUpper.contains("FRECCIABIANCA") || catUpper == "FB" { return "FB" }
    if catUpper.contains("ITALO") { return "ITALO" }
    if catUpper.contains("ALTA VELOCIT") || catUpper == "AV" { return "AV" }
    if catUpper.contains("INTERCITY NOTTE") || catUpper == "ICN" { return "ICN" }
    if catUpper.contains("INTERCITY") || catUpper == "IC" { return "IC" }
    if catUpper.contains("EUROCITY") || catUpper == "EC" { return "EC" }
    if catUpper.contains("EURONIGHT") || catUpper == "EN" { return "EN" }
    if catUpper.contains("MALPENSA") || catUpper == "XP" || catUpper == "MXP" { return "XP" }
    if catUpper == "REGIONALE VELOCE" || catUpper == "RV" { return "RV" }
    if catUpper == "REGIOEXPRESS" || catUpper == "RE" { return "RE" }
    if catUpper == "SUBURBANO" || catUpper == "S" { cat = "S" }
    if catUpper == "REGIONALE" || catUpper == "REG" { cat = "REG" }
    
    if cat == "S" || cat == "REG" || cat.isEmpty {
        if cleanNum.hasPrefix("240") || cleanNum.hasPrefix("230") || cleanNum.hasPrefix("241") || cleanNum.hasPrefix("231") { return "S1" }
        if cleanNum.hasPrefix("242") || cleanNum.hasPrefix("232") {
            if destLower.contains("melegnano") || destLower.contains("cormano") { return "S12" }
            return "S2"
        }
        if cleanNum.hasPrefix("243") || cleanNum.hasPrefix("233") || cleanNum.hasPrefix("328") || cleanNum.hasPrefix("329") { return "S13" }
        if cleanNum.hasPrefix("245") || cleanNum.hasPrefix("235") { return "S5" }
        if cleanNum.hasPrefix("246") || cleanNum.hasPrefix("236") { return "S6" }
        if cleanNum.hasPrefix("256") || cleanNum.hasPrefix("257") || cleanNum.hasPrefix("247") || cleanNum.hasPrefix("237") { return "S12" }
        if cleanNum.hasPrefix("248") || cleanNum.hasPrefix("238") { return "S8" }
        if cleanNum.hasPrefix("249") || cleanNum.hasPrefix("239") { return "S9" }
        if cleanNum.hasPrefix("250") || cleanNum.hasPrefix("251") || cleanNum.hasPrefix("252") { return "S11" }
        if cleanNum.hasPrefix("253") || cleanNum.hasPrefix("254") || cleanNum.hasPrefix("255") { return "S7" }
        if cleanNum.hasPrefix("244") || cleanNum.hasPrefix("234") { return "S4" }
    }
    
    return cat.isEmpty ? "REG" : cat
}

func habitCategoryColor(for cat: String) -> Color {
    let c = cat.uppercased()
    if c.contains("FR") || c.contains("ITA") || c == "AV" { return .red }
    if c == "IC" || c == "EC" || c == "ICN" || c == "EN" { return Color(white: 0.4) }
    if c.contains("S") { return Color(red: 0.0, green: 0.6, blue: 0.2) }
    if c.contains("RV") || c.contains("RE") { return .blue }
    if c.contains("XP") || c.contains("MXP") { return Color(red: 0.75, green: 0.10, blue: 0.25) }
    return Color(red: 0.2, green: 0.45, blue: 0.85)
}

struct LearnedStationHabit: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let totalViews: Int
    let distinctDays: Int
    let isFavorite: Bool
    let habitStrength: String
    let countDescription: String
    let score: Int
}

struct LearnedTrainHabit: Identifiable, Equatable {
    var id: String { number }
    let number: String
    let category: String
    let destination: String
    let departureTime: String?
    let totalViews: Int
    let distinctDays: Int
    let isFavorite: Bool
    let habitStrength: String
    let countDescription: String
    let score: Int
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

