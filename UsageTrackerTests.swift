import Foundation
import CoreLocation

// Mock del Tracker per poterlo testare senza AppStorage o UI
class MockUsageTracker {
    var stationVisits: [StationVisit] = []
    
    struct StationVisit {
        let stationName: String
        let date: Date
        let weekday: Int
        let hour: Int
        let gpsConfirmed: Bool
        var lat: Double?
        var lon: Double?
    }
    
    func recordStationVisit(name: String, date: Date, gpsNear: Bool, lat: Double?, lon: Double?) {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let hour = cal.component(.hour, from: date)
        
        let visit = StationVisit(stationName: name, date: date, weekday: weekday, hour: hour, gpsConfirmed: gpsNear, lat: lat, lon: lon)
        stationVisits.append(visit)
    }
    
    func suggestionsForNow(currentTime: Date, currentLat: Double?, currentLon: Double?, excludeStations: [String] = []) -> [String] {
        let cal = Calendar.current
        let currentHour = cal.component(.hour, from: currentTime)
        let currentWeekday = cal.component(.weekday, from: currentTime)
        
        let timeDistance = { (h1: Int, h2: Int) -> Int in
            let diff = abs(h1 - h2)
            return min(diff, 24 - diff)
        }
        
        var stationScores: [String: Int] = [:]
        
        for visit in stationVisits {
            var score = 0
            
            let isSameWeekday = visit.weekday == currentWeekday
            let isSameTime = timeDistance(visit.hour, currentHour) <= 1
            
            // Ignoriamo la distanza GPS nel test per semplificare se currentLat è nil
            let isNear = currentLat != nil && visit.lat != nil ? true : false // mock semplificato
            
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
            
            let daysAgo = cal.dateComponents([.day], from: visit.date, to: currentTime).day ?? 0
            if daysAgo <= 7 { score += 3 }
            if visit.gpsConfirmed { score += 8 }
            
            if score > 0 {
                stationScores[visit.stationName, default: 0] += score
            }
        }
        
        let stationCounts = Dictionary(grouping: stationVisits, by: { $0.stationName }).mapValues { $0.count }
        
        let lowerExcluded = excludeStations.map { $0.lowercased() }
        let topStations = stationScores.filter { name, score in
            let count = stationCounts[name] ?? 0
            return count >= 2 && score >= 15 && !lowerExcluded.contains(name.lowercased())
        }.sorted { $0.value > $1.value }
        
        return topStations.map { "\($0.key) (Punteggio: \($0.value), Visite: \(stationCounts[$0.key] ?? 0))" }
    }
}

func testUsageTracker() {
    print("=== TEST USAGE TRACKER (SEZIONE 'PER TE') ===\n")
    
    let tracker = MockUsageTracker()
    let calendar = Calendar.current
    let now = Date()
    
    // CASO 1: L'utente cerca stazioni a caso in orari e giorni diversi
    print("Simulazione 1: Uso casuale dell'app (1 ricerca per stazione in orari sparsi)")
    tracker.recordStationVisit(name: "Milano Centrale", date: calendar.date(byAdding: .day, value: -1, to: now)!, gpsNear: false, lat: nil, lon: nil)
    tracker.recordStationVisit(name: "Magenta", date: calendar.date(byAdding: .hour, value: -6, to: now)!, gpsNear: false, lat: nil, lon: nil)
    tracker.recordStationVisit(name: "Torino Porta Nuova", date: calendar.date(byAdding: .day, value: -3, to: now)!, gpsNear: false, lat: nil, lon: nil)
    
    let suggestions1 = tracker.suggestionsForNow(currentTime: now, currentLat: nil, currentLon: nil)
    if suggestions1.isEmpty {
        print("✅ PASSED: 'Per Te' è vuoto. Punteggi troppo bassi o singole visite.\n")
    } else {
        print("❌ FAILED: 'Per Te' ha mostrato: \(suggestions1)\n")
    }
    
    // CASO 2: L'utente pendolare che cerca 'Magenta' tutti i giorni alla stessa ora
    print("Simulazione 2: Pendolare (Apre 'Magenta' sempre intorno allo stesso orario)")
    // Oggi è mercoledì ore 8:00
    var dateComponents = calendar.dateComponents([.year, .month, .day, .weekday], from: now)
    dateComponents.hour = 8
    dateComponents.minute = 0
    let testTime = calendar.date(from: dateComponents)!
    
    // Visita 1: Lunedì ore 8:15 (2 giorni fa)
    let visit1 = calendar.date(byAdding: .day, value: -2, to: testTime)!
    tracker.recordStationVisit(name: "Magenta", date: visit1, gpsNear: false, lat: nil, lon: nil)
    
    // Visita 2: Martedì ore 7:55 (1 giorno fa)
    let visit2 = calendar.date(byAdding: .day, value: -1, to: testTime)!
    tracker.recordStationVisit(name: "Magenta", date: visit2, gpsNear: false, lat: nil, lon: nil)
    
    let suggestions2 = tracker.suggestionsForNow(currentTime: testTime, currentLat: nil, currentLon: nil)
    if !suggestions2.isEmpty {
        print("✅ PASSED: 'Per Te' ora suggerisce: \(suggestions2.first!)")
        print("-> Il punteggio supera 15 perché ci sono 2 visite e l'orario coincide (+5 punti per l'orario simile, +3 per la recency, moltiplicato per 2 visite)!\n")
    } else {
        print("❌ FAILED: 'Per Te' è ancora vuoto.\n")
    }
    
    // CASO 3: Sezione preferiti espansa o compressa
    print("Simulazione 3: Comportamento basato sullo stato della sezione Preferiti ('Le mie stazioni')")
    let favoriteStations = ["Magenta"]
    
    // Sezione Espansa -> 'Magenta' deve essere esclusa
    let isMyStationsExpanded = true
    let excludeListExpanded = isMyStationsExpanded ? favoriteStations : []
    let suggestionsExpanded = tracker.suggestionsForNow(currentTime: testTime, currentLat: nil, currentLon: nil, excludeStations: excludeListExpanded)
    
    if suggestionsExpanded.isEmpty {
        print("✅ PASSED: Con sezione Preferiti ESPANSA, 'Magenta' è esclusa dai suggerimenti.")
    } else {
        print("❌ FAILED: 'Magenta' è stata mostrata anche se la sezione preferiti era espansa!")
    }
    
    // Sezione Compressa -> 'Magenta' deve essere inclusa
    let isMyStationsCollapsed = false
    let excludeListCollapsed = isMyStationsCollapsed ? favoriteStations : []
    let suggestionsCollapsed = tracker.suggestionsForNow(currentTime: testTime, currentLat: nil, currentLon: nil, excludeStations: excludeListCollapsed)
    
    if !suggestionsCollapsed.isEmpty && suggestionsCollapsed.first?.contains("Magenta") == true {
        print("✅ PASSED: Con sezione Preferiti COMPRESSA, 'Magenta' viene suggerita in 'Per Te'!")
    } else {
        print("❌ FAILED: 'Magenta' non è stata suggerita pur avendo la sezione preferiti compressa!")
    }
}

testUsageTracker()
