import SwiftUI
import Combine
import Foundation
import CoreLocation
import ActivityKit


struct NewsItem: Codable, Identifiable {
    let id = UUID()
    let title: String
    let content: String
    let isUrgent: Bool
    let category: String?
    let date: String?
    
    enum CodingKeys: String, CodingKey {
        case title, content, isUrgent, category, date
    }
}

struct SharedFormatters {
    nonisolated static var time: DateFormatter {
        if let formatter = Thread.current.threadDictionary["timeFormatter"] as? DateFormatter {
            return formatter
        }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        Thread.current.threadDictionary["timeFormatter"] = f
        return f
    }
    
    nonisolated static func formatDestination(_ name: String) -> String {
        var dest = name
        
        if dest == "Milano Centrale" {
            return dest
        }
        
        dest = dest.replacingOccurrences(of: "Milano Porta Garibaldi Passante", with: "Milano P. Garibaldi")
        dest = dest.replacingOccurrences(of: "Milano Porta Garibaldi", with: "Milano P. Garibaldi")
        dest = dest.replacingOccurrences(of: "Porta Garibaldi Passante", with: "Milano P. Garibaldi")
        dest = dest.replacingOccurrences(of: "Porta Garibaldi", with: "Milano P. Garibaldi")
        
        if dest == "Milano Porta Venezia" || dest == "Porta Venezia" || dest == "Venezia" {
            dest = "P. Venezia"
        } else {
            dest = dest.replacingOccurrences(of: "Milano Porta Venezia", with: "P. Venezia")
            dest = dest.replacingOccurrences(of: "Porta Venezia", with: "P. Venezia")
        }
        
        if dest == "Milano Porta Vittoria" || dest == "Porta Vittoria" || dest == "Vittoria" {
            dest = "P. Vittoria"
        } else {
            dest = dest.replacingOccurrences(of: "Milano Porta Vittoria", with: "P. Vittoria")
            dest = dest.replacingOccurrences(of: "Porta Vittoria", with: "P. Vittoria")
        }
        
        dest = dest.replacingOccurrences(of: "Milano Repubblica", with: "Repubblica")
        
        dest = dest.replacingOccurrences(of: "Milano Dateo", with: "Dateo")
        
        dest = dest.replacingOccurrences(of: "Milano Lancetti", with: "Lancetti")
        
        if dest.contains("Porta ") && !dest.contains("Milano P. ") && !dest.contains("P. ") {
            dest = dest.replacingOccurrences(of: "Porta ", with: "P. ")
        }
        
        return dest
    }
}

enum DayType: String, Codable {
    case feriali, sabato, festivo
    static var current: DayType {
        let day = Calendar.current.component(.weekday, from: Date())
        if day == 1 { return .festivo }
        if day == 7 { return .sabato }
        return .feriali
    }
}

struct MetroDepartureItem: Codable, Hashable {
    let time: String
    let destination: String
}

struct MetroDeparturesResponse: Codable {
    let departures: [MetroDepartureItem]
}

struct MetroDeparture: Codable, Hashable {
    let min: Int
    let color: String
}

struct FormattedDeparture: Hashable {
    let timeString: String
    let destinationName: String?
}

enum MetroDisplayMode {
    case exact([FormattedDeparture])
    case frequency(String)
    case closed
}

struct FullSchedule: Codable {
    let feriali: [Int: [MetroDeparture]]
    let sabato: [Int: [MetroDeparture]]
    let festivo: [Int: [MetroDeparture]]
    let frequenze: [String: String]
    let lastSyncDate: Date?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        func parseDict(key: String) -> [Int: [MetroDeparture]] {
            var result = [Int: [MetroDeparture]]()
            if let subContainer = try? container.nestedContainer(keyedBy: DynamicKey.self, forKey: DynamicKey(stringValue: key)!) {
                for k in subContainer.allKeys {
                    if let hour = Int(k.stringValue), let mins = try? subContainer.decode([MetroDeparture].self, forKey: k) {
                        result[hour] = mins
                    }
                }
            }
            return result
        }
        self.feriali = parseDict(key: "feriali")
        self.sabato = parseDict(key: "sabato")
        self.festivo = parseDict(key: "festivo")
        self.frequenze = (try? container.decode([String: String].self, forKey: DynamicKey(stringValue: "frequenze")!)) ?? [:]
        self.lastSyncDate = try? container.decode(Date.self, forKey: DynamicKey(stringValue: "lastSyncDate")!)
    }
    
    init(feriali: [Int: [MetroDeparture]], sabato: [Int: [MetroDeparture]], festivo: [Int: [MetroDeparture]], frequenze: [String: String], lastSyncDate: Date?) {
        self.feriali = feriali
        self.sabato = sabato
        self.festivo = festivo
        self.frequenze = frequenze
        self.lastSyncDate = lastSyncDate
    }
}

struct DynamicKey: CodingKey {
    var stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int?
    init?(intValue: Int) { return nil }
}

struct MetroLine: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let colorName: String
    var color: Color {
        switch colorName {
        case "red": return .red
        case "green": return .green
        case "purple": return .purple
        case "yellow": return .yellow
        case "blue": return .blue
        case "orange": return .orange
        default: return .gray
        }
    }
    let pdfID: String?
    var direction: Int = 0
    var customFrequencies: [DayType: String]? = nil
    var destinations: [String: String]? = nil

    var directionLabel: String {
        switch colorName {
        case "red":
            return direction == 0 ? "Sesto FS" : "Rho Fiera / Bisceglie"
        case "green":
            return direction == 0 ? "Cologno / Gessate" : "Abbiategrasso / Assago"
        case "yellow":
            return direction == 0 ? "San Donato" : "Comasina"
        case "blue":
            return direction == 0 ? "San Cristoforo" : "Linate"
        case "purple":
            return direction == 0 ? "Bignami" : "San Siro"
        default:
            return name
        }
    }
}

struct SavedTrain: Codable, Identifiable, Equatable {
    var id: String { number }
    let number: String
    var description: String
    
    var notifyDelay: Bool? = false
    var notifyStationPass: Bool? = false
    var stationPassName: String? = nil
    var notifyDeparture: Bool? = false
    var departureTime: String? = nil
    var arrivalTime: String? = nil
    
    var activeDays: [Int]? = nil
    var lastNotifiedPlatform: String? = nil
    var notifyPlatformChange: Bool? = false
    var platformChangeStationName: String? = nil
}

struct VTSearchStation: Codable, Identifiable {
    var id: String { vtID }
    let nomeLungo: String
    let nomeBreve: String
    let vtID: String
    
    enum CodingKeys: String, CodingKey {
        case nomeLungo
        case nomeBreve
        case vtID = "id"
    }
}

struct TrenitaliaLocation: Codable, Identifiable {
    var id: Int
    let name: String
    let displayName: String
}

struct RFIStation: Codable, Identifiable, Hashable {
    var id: String { rfiID ?? vtID ?? name }
    let name: String
    let rfiID: String?
    let vtID: String?
    let lat: Double?
    let lon: Double?
    
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = lat, let lon = lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case rfiID = "id"
        case vtID
        case lat
        case lon
    }
}

struct Train: Identifiable, Sendable {
    let id: String
    let category: String
    let number: String
    let destination: String
    let time: String
    let delay: String
    let platform: String
    
    nonisolated init(category: String, number: String, destination: String, time: String, delay: String, platform: String) {
        self.category = category
        self.number = number
        self.destination = Train.cleanStationName(destination)
        self.time = time
        self.delay = delay
        self.platform = platform
        self.id = "\(category)_\(number)_\(time)_\(self.destination)"
    }
    
    var estimatedArrivalTime: String {
        guard let baseDate = SharedFormatters.time.date(from: time) else { return time }
        let delayMinutes = Int(delay.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "'", with: "")) ?? 0
        if let newDate = Calendar.current.date(byAdding: .minute, value: delayMinutes, to: baseDate) {
            return SharedFormatters.time.string(from: newDate)
        }
        return time
    }
    
    nonisolated static func cleanStationName(_ name: String) -> String {
        var clean = name
        
        let replacements: [(String, String)] = [
            ("Milano Bovisa Politecnico", "Bovisa"),
            ("Milano Bovisa", "Bovisa"),
            ("Milano Porta Garibaldi", "Porta Garibaldi"),
            ("Milano Lancetti", "Lancetti"),
            ("Milano Rogoredo", "Rogoredo"),
            ("Milano Forlanini", "Forlanini"),
            ("Milano Porta Venezia", "Porta Venezia"),
            ("Milano Repubblica", "Repubblica"),
            ("Milano Dateo", "Dateo"),
            ("Milano Porta Vittoria", "Porta Vittoria"),
            ("Milano Villapizzone", "Villapizzone"),
            ("Milano Cadorna", "Cadorna"),
            ("Milano Centrale", "Centrale"),
            ("Milano Greco Pirelli", "Greco Pirelli"),
            ("Milano Scalo Romana", "Scalo Romana"),
            ("Milano Porta Romana", "Scalo Romana"),
            ("Milano San Cristoforo", "San Cristoforo"),
            ("Milano Lambrate", "Lambrate"),
            ("Milano Certosa", "Certosa"),
            ("Milano Lodi T.i.b.b.", "Lodi T.I.B.B.")
        ]
        
        for (target, replacement) in replacements {
            if clean.localizedCaseInsensitiveContains(target) {
                clean = clean.replacingOccurrences(of: target, with: replacement, options: .caseInsensitive)
            }
        }
        
        if clean.hasPrefix("Milano ") {
            clean = String(clean.dropFirst(7))
        } else if clean.hasPrefix("Milano") {
            clean = String(clean.dropFirst(6))
        }
        
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TrainStatus: Codable, Sendable {
    var lastStation: String = "--"
    var lastTime: String = "--"
    var statusMessage: String = "In attesa di dati..."
    var isDeparted: Bool = false
    var cancellationNote: String? = nil
    var isArrived: Bool = false
}

struct Stop: Identifiable, Sendable {
    let id = UUID()
    let stationName: String
    let time: String
    let actualTime: String?
    let delay: Int
    let estimatedTime: String?
    let plannedPlatform: String?
    let actualPlatform: String?
}

struct Station: Identifiable, Codable, Hashable {
    var id = UUID()
    let name: String
    let rfiID: String?
    let vtID: String?
    let lat: Double?
    let lon: Double?
    
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = lat, let lon = lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Station, rhs: Station) -> Bool { lhs.id == rhs.id }
    
    func matches(_ other: Station) -> Bool {
        if let r1 = self.rfiID, let r2 = other.rfiID, !r1.isEmpty, !r2.isEmpty {
            if r1 == r2 { return true }
        }
        if let v1 = self.vtID, let v2 = other.vtID, !v1.isEmpty, !v2.isEmpty {
            if v1 == v2 { return true }
        }
        let n1 = self.name.lowercased()
            .replacingOccurrences(of: "milano ", with: "")
            .replacingOccurrences(of: " passante", with: "")
            .replacingOccurrences(of: " sotterranea", with: "")
            .replacingOccurrences(of: " politecnico", with: "")
            .replacingOccurrences(of: "p. garibaldi", with: "porta garibaldi")
            .replacingOccurrences(of: "p.garibaldi", with: "porta garibaldi")
            .replacingOccurrences(of: "porta garibaldi passante", with: "porta garibaldi")
            .replacingOccurrences(of: "p. garibaldi passante", with: "porta garibaldi")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let n2 = other.name.lowercased()
            .replacingOccurrences(of: "milano ", with: "")
            .replacingOccurrences(of: " passante", with: "")
            .replacingOccurrences(of: " sotterranea", with: "")
            .replacingOccurrences(of: " politecnico", with: "")
            .replacingOccurrences(of: "p. garibaldi", with: "porta garibaldi")
            .replacingOccurrences(of: "p.garibaldi", with: "porta garibaldi")
            .replacingOccurrences(of: "porta garibaldi passante", with: "porta garibaldi")
            .replacingOccurrences(of: "p. garibaldi passante", with: "porta garibaldi")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if n1 == n2 { return true }
        if n1.count > 3 && n2.count > 3 {
            if n1.contains(n2) || n2.contains(n1) { return true }
        }
        return false
    }
    
    var metroLines: [MetroLine] {
        let upperName = self.name.uppercased()
        if upperName.contains("RHO FIERA") {
            return [
                MetroLine(name: "M1 Sesto", colorName: "red", pdfID: "RHO FIERAMILANO", direction: 0)
            ]
        } else if upperName.contains("GARIBALDI") {
            return [
                MetroLine(name: "M2 Nord", colorName: "green", pdfID: "GARIBALDI FS", direction: 0),
                MetroLine(name: "M2 Sud", colorName: "green", pdfID: "GARIBALDI FS", direction: 1),
                MetroLine(name: "M5 Bignami", colorName: "purple", pdfID: "GARIBALDI FS", direction: 0),
                MetroLine(name: "M5 San Siro", colorName: "purple", pdfID: "GARIBALDI FS", direction: 1)
            ]
        } else if upperName.contains("CENTRALE") {
            return [
                MetroLine(name: "M2 Nord", colorName: "green", pdfID: "CENTRALE FS", direction: 0),
                MetroLine(name: "M2 Sud", colorName: "green", pdfID: "CENTRALE FS", direction: 1),
                MetroLine(name: "M3 S. Donato", colorName: "yellow", pdfID: "CENTRALE FS", direction: 0),
                MetroLine(name: "M3 Comasina", colorName: "yellow", pdfID: "CENTRALE FS", direction: 1)
            ]
        } else if upperName.contains("REPUBBLICA") {
            return [
                MetroLine(name: "M3 S. Donato", colorName: "yellow", pdfID: "REPUBBLICA", direction: 0),
                MetroLine(name: "M3 Comasina", colorName: "yellow", pdfID: "REPUBBLICA", direction: 1)
            ]
        } else if upperName.contains("VENEZIA") {
            return [
                MetroLine(name: "M1 Sesto", colorName: "red", pdfID: "P.TA VENEZIA", direction: 0),
                MetroLine(name: "M1 Rho/Bisc.", colorName: "red", pdfID: "P.TA VENEZIA", direction: 1)
            ]
        } else if upperName.contains("DATEO") {
            return [
                MetroLine(name: "M4 S. Cristoforo", colorName: "blue", pdfID: "DATEO", direction: 0),
                MetroLine(name: "M4 Linate", colorName: "blue", pdfID: "DATEO", direction: 1)
            ]
        } else if upperName.contains("FORLANINI") {
            return [
                MetroLine(name: "M4 S. Cristoforo", colorName: "blue", pdfID: "STAZIONE FORLANINI", direction: 0),
                MetroLine(name: "M4 Linate", colorName: "blue", pdfID: "STAZIONE FORLANINI", direction: 1)
            ]
        } else if upperName.contains("SESTO S") || upperName.contains("SESTO SAN GIOVANNI") {
            return [
                MetroLine(name: "M1 Rho/Bisc.", colorName: "red", pdfID: "SESTO 1 MAGGIO FS", direction: 1)
            ]
        } else if upperName.contains("CADORNA") {
            return [
                MetroLine(name: "M1 Sesto", colorName: "red", pdfID: "CADORNA FN M1", direction: 0),
                MetroLine(name: "M1 Rho/Bisc.", colorName: "red", pdfID: "CADORNA FN M1", direction: 1),
                MetroLine(name: "M2 Nord", colorName: "green", pdfID: "CADORNA FN M2", direction: 0),
                MetroLine(name: "M2 Sud", colorName: "green", pdfID: "CADORNA FN M2", direction: 1)
            ]
        } else if upperName.contains("LAMBRATE") {
            return [
                MetroLine(name: "M2 Nord", colorName: "green", pdfID: "LAMBRATE FS", direction: 0),
                MetroLine(name: "M2 Sud", colorName: "green", pdfID: "LAMBRATE FS", direction: 1)
            ]
        } else if upperName.contains("GENOVA") {
            return [
                MetroLine(name: "M2 Nord", colorName: "green", pdfID: "PORTA GENOVA FS", direction: 0),
                MetroLine(name: "M2 Sud", colorName: "green", pdfID: "PORTA GENOVA FS", direction: 1)
            ]
        } else if upperName.contains("ROMOLO") {
            return [
                MetroLine(name: "M2 Nord", colorName: "green", pdfID: "ROMOLO", direction: 0),
                MetroLine(name: "M2 Sud", colorName: "green", pdfID: "ROMOLO", direction: 1)
            ]
        } else if upperName.contains("AFFORI") {
            return [
                MetroLine(name: "M3 S. Donato", colorName: "yellow", pdfID: "AFFORI FN", direction: 0),
                MetroLine(name: "M3 Comasina", colorName: "yellow", pdfID: "AFFORI FN", direction: 1)
            ]
        } else if upperName.contains("ROMANA") {
            return [
                MetroLine(name: "M3 S. Donato", colorName: "yellow", pdfID: "PORTA ROMANA", direction: 0),
                MetroLine(name: "M3 Comasina", colorName: "yellow", pdfID: "PORTA ROMANA", direction: 1)
            ]
        } else if upperName.contains("ROGOREDO") {
            return [
                MetroLine(name: "M3 S. Donato", colorName: "yellow", pdfID: "ROGOREDO FS", direction: 0),
                MetroLine(name: "M3 Comasina", colorName: "yellow", pdfID: "ROGOREDO FS", direction: 1)
            ]
        } else if upperName.contains("CRISTOFORO") {
            return [
                MetroLine(name: "M4 S. Cristoforo", colorName: "blue", pdfID: "SAN CRISTOFORO FS", direction: 0),
                MetroLine(name: "M4 Linate", colorName: "blue", pdfID: "SAN CRISTOFORO FS", direction: 1)
            ]
        } else if upperName.contains("DOMODOSSOLA") {
            return [
                MetroLine(name: "M5 Bignami", colorName: "purple", pdfID: "DOMODOSSOLA FN", direction: 0),
                MetroLine(name: "M5 San Siro", colorName: "purple", pdfID: "DOMODOSSOLA FN", direction: 1)
            ]
        }
        return []
    }
}

enum AppSection: String, Codable, CaseIterable {
    case nearby = "Stazione Vicina"
    case myStations = "Le Mie Stazioni"
    case favoriteTrains = "I miei Treni"
    case passante = "Linee Suburbane"
}

struct SuburbanLine: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let hexColor: String
    let stations: [Station]
    
    var color: Color {
        Color(hex: hexColor)
    }
}

struct SuburbanRoute: Codable, Identifiable, Equatable {
    var id: String { "\(originName)-\(destinationName)" }
    let originName: String
    let destinationName: String
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct SuburbanData {
    static let shared = SuburbanData()
    
    let allLines: [SuburbanLine]
    
    private init() {
        let bovisa = Station(name: "Milano Bovisa", rfiID: nil, vtID: "S01642", lat: 45.5025, lon: 9.1592)
        let certosa = Station(name: "Certosa", rfiID: "1708", vtID: "S01640", lat: 45.5085, lon: 9.1272)
        let villapizzone = Station(name: "Villapizzone", rfiID: "3099", vtID: "S01639", lat: 45.4998, lon: 9.1465)
        let lancetti = Station(name: "Lancetti", rfiID: "1713", vtID: "S01643", lat: 45.4925, lon: 9.1751)
        let garibaldiPassante = Station(name: "P. Garibaldi Passante", rfiID: "1714", vtID: "S01647", lat: 45.4844, lon: 9.1887)
        let repubblica = Station(name: "Repubblica", rfiID: "1719", vtID: "S01648", lat: 45.4795, lon: 9.1963)
        let venezia = Station(name: "Porta Venezia", rfiID: "1723", vtID: "S01649", lat: 45.4746, lon: 9.2052)
        let dateo = Station(name: "Dateo", rfiID: "3468", vtID: "S01650", lat: 45.4682, lon: 9.2158)
        let vittoria = Station(name: "Porta Vittoria", rfiID: "1718", vtID: "S01633", lat: 45.4613, lon: 9.2227)
        let rogoredo = Station(name: "Milano Rogoredo", rfiID: "1720", vtID: "S01820", lat: 45.4333, lon: 9.2389)
        let forlanini = Station(name: "Forlanini", rfiID: "3169", vtID: "S01492", lat: 45.4625, lon: 9.2368)
        

        
        let saronno = Station(name: "Saronno", rfiID: nil, vtID: "S01933", lat: 45.6264, lon: 9.0336)
        let greco = Station(name: "Milano Greco Pirelli", rfiID: "1711", vtID: "S01326", lat: 45.5129, lon: 9.2141)

        
        let garibaldiSup = Station(name: "Milano P. Garibaldi", rfiID: "1715", vtID: "S01058", lat: 45.4844, lon: 9.1887)
        let rhoFiera = Station(name: "Rho Fiera", rfiID: "3098", vtID: "S01026", lat: 45.5215, lon: 9.0883)
        
        let novara = Station(name: "Novara", rfiID: "1917", vtID: "S00248", lat: 45.4524, lon: 8.6253)
        let trecate = Station(name: "Trecate", rfiID: "2909", vtID: "S00252", lat: 45.4374, lon: 8.7428)
        let magenta = Station(name: "Magenta", rfiID: "1618", vtID: "S01040", lat: 45.4641, lon: 8.8845)
        let corbetta = Station(name: "Corbetta-S.Stefano Ticino", rfiID: "1174", vtID: "S01041", lat: 45.4716, lon: 8.9189)
        let vittuone = Station(name: "Vittuone-Arluno", rfiID: "3119", vtID: "S01042", lat: 45.4921, lon: 8.9568)
        let pregnana = Station(name: "Pregnana Milanese", rfiID: "381", vtID: "S01058", lat: 45.5036, lon: 9.0069)
        let rho = Station(name: "Rho", rfiID: "2345", vtID: "S01037", lat: 45.5262, lon: 9.0402)
        let segrate = Station(name: "Segrate", rfiID: "3507", vtID: "S01715", lat: 45.4712, lon: 9.2974)
        let pioltello = Station(name: "Pioltello-Limito", rfiID: "2147", vtID: "S01703", lat: 45.4801, lon: 9.3245)
        
        let varese = Station(name: "Varese", rfiID: "2994", vtID: "S01205", lat: 45.8176, lon: 8.8329)
        let gazzada = Station(name: "Gazzada-Schianno-Morazzone", rfiID: "1413", vtID: "S01207", lat: 45.7821, lon: 8.8251)
        let castronno = Station(name: "Castronno", rfiID: "1029", vtID: "S01208", lat: 45.7483, lon: 8.8105)
        let albizzate = Station(name: "Albizzate-Solbiate Arno", rfiID: "405", vtID: "S01209", lat: 45.7196, lon: 8.8021)
        let cavaria = Station(name: "Cavaria-Oggiona-Jerago", rfiID: "1046", vtID: "S01210", lat: 45.6985, lon: 8.8183)
        let gallarate = Station(name: "Gallarate", rfiID: "1393", vtID: "S01030", lat: 45.6599, lon: 8.7963)
        let busto = Station(name: "Busto Arsizio", rfiID: "766", vtID: "S01031", lat: 45.6062, lon: 8.8612)
        let legnano = Station(name: "Legnano", rfiID: "1554", vtID: "S01033", lat: 45.5925, lon: 8.9189)
        let canegrate = Station(name: "Canegrate", rfiID: "858", vtID: "S01034", lat: 45.5684, lon: 8.9321)
        let parabiago = Station(name: "Parabiago", rfiID: "2033", vtID: "S01035", lat: 45.5562, lon: 8.9483)
        let vanzago = Station(name: "Vanzago-Pogliano", rfiID: "2987", vtID: "S01036", lat: 45.5262, lon: 8.9951)
        let melzo = Station(name: "Melzo", rfiID: "1690", vtID: "S01705", lat: 45.4983, lon: 9.4212)
        let pozzuolo = Station(name: "Pozzuolo Martesana", rfiID: "380", vtID: "S01722", lat: 45.5065, lon: 9.4583)
        let trecella = Station(name: "Trecella", rfiID: "2910", vtID: "S01706", lat: 45.5121, lon: 9.4896)
        let cassano = Station(name: "Cassano d'Adda", rfiID: "951", vtID: "S01707", lat: 45.5242, lon: 9.5165)
        let treviglio = Station(name: "Treviglio", rfiID: "2919", vtID: "S01708", lat: 45.5201, lon: 9.5932)
        
        let caronno = Station(name: "Caronno Pertusella", rfiID: nil, vtID: "S01076", lat: 45.5983, lon: 9.0432)
        let cesate = Station(name: "Cesate", rfiID: nil, vtID: "S01075", lat: 45.5812, lon: 9.0621)
        let garbagnateM = Station(name: "Garbagnate Milanese", rfiID: nil, vtID: "S01074", lat: 45.5684, lon: 9.0763)
        let garbagnateP = Station(name: "Garbagnate Parco delle Groane", rfiID: nil, vtID: "S01073", lat: 45.5562, lon: 9.0883)
        let bollateN = Station(name: "Bollate Nord", rfiID: nil, vtID: "S01072", lat: 45.5451, lon: 9.1021)
        let bollateC = Station(name: "Bollate Centro", rfiID: nil, vtID: "S01071", lat: 45.5342, lon: 9.1162)
        let novate = Station(name: "Novate Milanese", rfiID: nil, vtID: "S01070", lat: 45.5262, lon: 9.1301)
        let quartoOggiaro = Station(name: "Milano Quarto Oggiaro", rfiID: nil, vtID: "S01069", lat: 45.5121, lon: 9.1412)
        let sanDonato = Station(name: "San Donato Milanese", rfiID: "2487", vtID: "S01624", lat: 45.4183, lon: 9.2562)
        let borgolombardo = Station(name: "Borgolombardo", rfiID: "710", vtID: "S01830", lat: 45.4062, lon: 9.2683)
        let sanGiuliano = Station(name: "San Giuliano Milanese", rfiID: "2520", vtID: "S01821", lat: 45.3983, lon: 9.2812)
        let melegnano = Station(name: "Melegnano", rfiID: "1688", vtID: "S01822", lat: 45.3592, lon: 9.3235)
        let tavazzano = Station(name: "Tavazzano", rfiID: "2820", vtID: "S01824", lat: 45.3262, lon: 9.3783)
        let lodi = Station(name: "Lodi", rfiID: "1584", vtID: "S01825", lat: 45.2796, lon: 9.4795)
        
        let mariano = Station(name: "Mariano Comense", rfiID: nil, vtID: "S01089", lat: 45.6983, lon: 9.1832)
        let cabiate = Station(name: "Cabiate", rfiID: nil, vtID: "S01088", lat: 45.6812, lon: 9.1721)
        let meda = Station(name: "Meda", rfiID: nil, vtID: "S01087", lat: 45.6684, lon: 9.1563)
        let seveso = Station(name: "Seveso", rfiID: nil, vtID: "S01925", lat: 45.6421, lon: 9.1412)
        let cesano = Station(name: "Cesano Maderno", rfiID: nil, vtID: "S01086", lat: 45.6262, lon: 9.1501)
        let bovisio = Station(name: "Bovisio Masciago-Mombello", rfiID: nil, vtID: "S01085", lat: 45.6062, lon: 9.1521)
        let varedo = Station(name: "Varedo", rfiID: nil, vtID: "S01084", lat: 45.5983, lon: 9.1583)
        let palazzolo = Station(name: "Palazzolo Milanese", rfiID: nil, vtID: "S01083", lat: 45.5862, lon: 9.1621)
        let paderno = Station(name: "Paderno Dugnano", rfiID: nil, vtID: "S01082", lat: 45.5712, lon: 9.1683)
        let cormano = Station(name: "Cormano-Cusano Milanino", rfiID: nil, vtID: "S01109", lat: 45.5451, lon: 9.1783)
        let bruzzano = Station(name: "Milano Bruzzano", rfiID: nil, vtID: "S01079", lat: 45.5262, lon: 9.1762)
        
        let locate = Station(name: "Locate Triulzi", rfiID: "1583", vtID: "S01801", lat: 45.3583, lon: 9.2182)
        let pieve = Station(name: "Pieve Emanuele", rfiID: "1749", vtID: "S01104", lat: 45.3421, lon: 9.2062)
        let villamaggiore = Station(name: "Villamaggiore", rfiID: "3092", vtID: "S01802", lat: 45.3212, lon: 9.2021)
        let certosaPavia = Station(name: "Certosa di Pavia", rfiID: "1069", vtID: "S01803", lat: 45.2562, lon: 9.1583)
        let pavia = Station(name: "Pavia", rfiID: "2046", vtID: "S01860", lat: 45.1868, lon: 9.1625)
        

        let superficieS11 = [greco, garibaldiSup, villapizzone, certosa, rhoFiera]
        
        let lineS1Stations = [saronno, caronno, cesate, garbagnateM, garbagnateP, bollateN, bollateC, novate, quartoOggiaro, bovisa, lancetti, garibaldiPassante, repubblica, venezia, dateo, vittoria, rogoredo, sanDonato, borgolombardo, sanGiuliano, melegnano, tavazzano, lodi]
        let lineS2Stations = [mariano, cabiate, meda, seveso, cesano, bovisio, varedo, palazzolo, paderno, cormano, bruzzano, bovisa, lancetti, garibaldiPassante, repubblica, venezia, dateo, vittoria, rogoredo]
        let lineS5Stations = [varese, gazzada, castronno, albizzate, cavaria, gallarate, busto, legnano, canegrate, parabiago, vanzago, rho, rhoFiera, certosa, villapizzone, lancetti, garibaldiPassante, repubblica, venezia, dateo, vittoria, forlanini, segrate, pioltello, melzo, pozzuolo, trecella, cassano, treviglio]
        let lineS6Stations = [novara, trecate, magenta, corbetta, vittuone, pregnana, rho, rhoFiera, certosa, villapizzone, lancetti, garibaldiPassante, repubblica, venezia, dateo, vittoria, forlanini, segrate, pioltello]
        let lineS12Stations = [cormano, bruzzano, bovisa, lancetti, garibaldiPassante, repubblica, venezia, dateo, vittoria, rogoredo, sanDonato, borgolombardo, sanGiuliano, melegnano]
        let lineS13Stations = [bovisa, lancetti, garibaldiPassante, repubblica, venezia, dateo, vittoria, rogoredo, locate, pieve, villamaggiore, certosaPavia, pavia]
        
        self.allLines = [
            SuburbanLine(id: "S1", name: "S1 Saronno - Lodi", hexColor: "#e30613", stations: lineS1Stations),
            SuburbanLine(id: "S2", name: "S2 Mariano - Rogoredo", hexColor: "#009640", stations: lineS2Stations),
            SuburbanLine(id: "S5", name: "S5 Varese - Treviglio", hexColor: "#f39200", stations: lineS5Stations),
            SuburbanLine(id: "S6", name: "S6 Novara - Pioltello", hexColor: "#ffd60a", stations: lineS6Stations),
            SuburbanLine(id: "S11", name: "S11 Chiasso - Rho", hexColor: "#8a8bbf", stations: superficieS11),
            SuburbanLine(id: "S12", name: "S12 Cormano - Melegnano", hexColor: "#005a2b", stations: lineS12Stations),
            SuburbanLine(id: "S13", name: "S13 Bovisa - Pavia", hexColor: "#a37a3e", stations: lineS13Stations),
        ]
    }
}

struct TravelSegment: Identifiable, Sendable {
    let id = UUID()
    var origin: String
    var destination: String
    let departureTime: String
    let arrivalTime: String
    var trainNumber: String
    var trainCategory: String
}

struct TravelSolution: Identifiable, Sendable {
    let id = UUID()
    let trainNumber: String
    let category: String
    let departureTime: String
    let arrivalTime: String
    let origin: String
    let destination: String
    let duration: String
    var segments: [TravelSegment]
}

struct FavoriteRoute: Codable, Identifiable, Equatable {
    var id: String { "\(originID)-\(destinationID)" }
    let originName: String
    let originID: String
    let destinationName: String
    let destinationID: String
}

struct SavedTripSegment: Codable, Equatable {
    let origin: String
    let destination: String
    let departureTime: String
    let arrivalTime: String
    let trainNumber: String
    let trainCategory: String
}

struct SavedTrip: Codable, Identifiable, Equatable {
    let id: String
    let origin: String
    let destination: String
    let departureTime: String
    let arrivalTime: String
    let duration: String
    let segments: [SavedTripSegment]
    
    var asTravelSolution: TravelSolution {
        let mappedSegments = segments.map { TravelSegment(origin: $0.origin, destination: $0.destination, departureTime: $0.departureTime, arrivalTime: $0.arrivalTime, trainNumber: $0.trainNumber, trainCategory: $0.trainCategory) }
        return TravelSolution(trainNumber: "", category: "Viaggio", departureTime: departureTime, arrivalTime: arrivalTime, origin: origin, destination: destination, duration: duration, segments: mappedSegments)
    }
}
