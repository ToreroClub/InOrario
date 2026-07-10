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
    
    private let visitsKey = "smartVisits_v1"
    private let trainsKey = "smartTrains_v1"
    private let routesKey = "smartRoutes_v1"
    private let maxEntries = 300
    
    init() {
        load()
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
    
    func clearHistory() {
        stationVisits = []
        trainChecks = []
        routeUsages = []
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
    
    func suggestionsForNow(location: CLLocationCoordinate2D? = nil, excludeStations: [String] = []) -> [SmartSuggestion] {
        guard smartSuggestionsEnabled else { return [] }
        let now = Date()
        let cal = Calendar.current
        let currentHour = cal.component(.hour, from: now)
        let currentWeekday = cal.component(.weekday, from: now)
        
        let timeDistance = { (h1: Int, h2: Int) -> Int in
            let diff = abs(h1 - h2)
            return min(diff, 24 - diff)
        }
        
        let isLocationMatch = { (lat: Double?, lon: Double?) -> Bool in
            guard let currentLoc = location, let targetLat = lat, let targetLon = lon else { return false }
            let l1 = CLLocation(latitude: currentLoc.latitude, longitude: currentLoc.longitude)
            let l2 = CLLocation(latitude: targetLat, longitude: targetLon)
            return l1.distance(from: l2) <= 1500
        }
        
        var suggestions: [SmartSuggestion] = []
        
        // 1. Analizza le stazioni:
        var stationScores: [String: (score: Int, lastVisit: StationVisit)] = [:]
        for visit in stationVisits {
            var score = 0
            
            let isSameWeekday = visit.weekday == currentWeekday
            let isSameTime = timeDistance(visit.hour, currentHour) <= 1
            let isNear = isLocationMatch(visit.lat, visit.lon)
            
            if isSameWeekday && isSameTime && isNear {
                score += 50
            } else if isSameTime && isNear {
                score += 30
            } else if isSameWeekday && isSameTime {
                score += 20
            } else if isSameTime {
                score += 5
            } else if isSameWeekday {
                score += 2
            }
            
            let daysAgo = cal.dateComponents([.day], from: visit.date, to: now).day ?? 0
            if daysAgo <= 7 { score += 3 }
            
            if visit.gpsConfirmed { 
                score += 8 
            }
            
            if daysAgo > 42 && score < 20 { continue }
            
            if score > 0 {
                if let existing = stationScores[visit.stationName] {
                    stationScores[visit.stationName] = (existing.score + score, existing.lastVisit.date > visit.date ? existing.lastVisit : visit)
                } else {
                    stationScores[visit.stationName] = (score, visit)
                }
            }
        }
        
        let lowerExcluded = excludeStations.map { $0.lowercased() }
        let stationCounts = Dictionary(grouping: stationVisits, by: { $0.stationName }).mapValues { $0.count }
        let topStations = stationScores.filter { name, info in
            let count = stationCounts[name] ?? 0
            return count >= 2 && info.score >= 15 && !lowerExcluded.contains(name.lowercased())
        }.sorted { $0.value.score > $1.value.score }.prefix(2)
        for (name, info) in topStations {
            let s = Station(name: name, rfiID: info.lastVisit.rfiID, vtID: info.lastVisit.vtID, lat: nil, lon: nil)
            suggestions.append(.station(s))
        }
        
        // 2. Analizza i treni:
        var trainScores: [String: (score: Int, lastCheck: TrainCheck)] = [:]
        for check in trainChecks {
            var score = 0
            
            let isSameWeekday = check.weekday == currentWeekday
            let isSameTime = timeDistance(check.hour, currentHour) <= 1
            let isNear = isLocationMatch(check.lat, check.lon)
            
            if isSameWeekday && isSameTime && isNear {
                score += 50
            } else if isSameTime && isNear {
                score += 30
            } else if isSameWeekday && isSameTime {
                score += 20
            } else if isSameTime {
                score += 5
            } else if isSameWeekday {
                score += 2
            }
            
            let daysAgo = cal.dateComponents([.day], from: check.date, to: now).day ?? 0
            if daysAgo <= 7 { score += 3 }
            
            if daysAgo > 42 && score < 20 { continue }
            
            if score > 0 {
                if let existing = trainScores[check.trainNumber] {
                    trainScores[check.trainNumber] = (existing.score + score, existing.lastCheck.date > check.date ? existing.lastCheck : check)
                } else {
                    trainScores[check.trainNumber] = (score, check)
                }
            }
        }
        
        let trainCounts = Dictionary(grouping: trainChecks, by: { $0.trainNumber }).mapValues { $0.count }
        let topTrains = trainScores.filter { number, info in
            let count = trainCounts[number] ?? 0
            return count >= 2 && info.score >= 15
        }.sorted { $0.value.score > $1.value.score }.prefix(1)
        for (number, info) in topTrains {
            let t = Train(category: info.lastCheck.category, number: number, destination: info.lastCheck.destination, time: "--:--", delay: "In orario", platform: "--")
            suggestions.append(.train(t))
        }
        
        // 3. Analizza le rotte:
        var routeScores: [String: (score: Int, lastRoute: RouteUsage)] = [:]
        for route in routeUsages {
            var score = 0
            
            let isSameWeekday = route.weekday == currentWeekday
            let isSameTime = timeDistance(route.hour, currentHour) <= 1
            let isNear = isLocationMatch(route.lat, route.lon)
            
            if isSameWeekday && isSameTime && isNear {
                score += 50
            } else if isSameTime && isNear {
                score += 30
            } else if isSameWeekday && isSameTime {
                score += 20
            } else if isSameTime {
                score += 5
            } else if isSameWeekday {
                score += 2
            }
            
            let daysAgo = cal.dateComponents([.day], from: route.date, to: now).day ?? 0
            if daysAgo <= 7 { score += 3 }
            
            if daysAgo > 42 && score < 20 { continue }
            
            if score > 0 {
                let key = "\(route.originID)-\(route.destID)"
                if let existing = routeScores[key] {
                    routeScores[key] = (existing.score + score, existing.lastRoute.date > route.date ? existing.lastRoute : route)
                } else {
                    routeScores[key] = (score, route)
                }
            }
        }
        
        let routeCounts = Dictionary(grouping: routeUsages, by: { "\($0.originID)-\($0.destID)" }).mapValues { $0.count }
        let topRoutes = routeScores.filter { key, info in
            let count = routeCounts[key] ?? 0
            return count >= 2 && info.score >= 15
        }.sorted { $0.value.score > $1.value.score }.prefix(1)
        for (_, info) in topRoutes {
            let r = FavoriteRoute(originName: info.lastRoute.originName, originID: info.lastRoute.originID, destinationName: info.lastRoute.destName, destinationID: info.lastRoute.destID)
            suggestions.append(.route(r))
        }
        
        return suggestions
    }
}
