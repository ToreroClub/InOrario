import SwiftUI
import Combine
import Foundation
import CoreLocation
import ActivityKit


struct NewsItem: Codable, Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let content: String
    let isUrgent: Bool
    let category: String?
    let date: String?
    let regions: [String]?
    
    init(title: String, content: String, isUrgent: Bool, category: String? = nil, date: String? = nil, regions: [String]? = nil) {
        self.title = title
        self.content = content
        self.isUrgent = isUrgent
        self.category = category
        self.date = date
        self.regions = regions
    }
    
    enum CodingKeys: String, CodingKey {
        case title, content, isUrgent, category, date, regions
    }
}

extension NewsItem {
    private nonisolated static let dateRegex: NSRegularExpression? = try? NSRegularExpression(pattern: #"(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?"#)
    
    var sortableDate: Date {
        if let dateStr = date, !dateStr.isEmpty {
            // YYYY-MM-DD
            if let d = SharedFormatters.dateISO.date(from: dateStr) { return d }
            
            // DD/MM/YYYY
            if let d = SharedFormatters.dateIT.date(from: dateStr) { return d }
            
            // DD/MM
            if let d = SharedFormatters.dateShort.date(from: dateStr) {
                let calendar = Calendar.current
                let currentYear = calendar.component(.year, from: Date())
                var components = calendar.dateComponents([.month, .day], from: d)
                components.year = currentYear
                if let fullDate = calendar.date(from: components) { return fullDate }
            }
        }
        
        // Estrazione data DD/MM dal titolo (es. "Sciopero ... 08/09")
        if let regex = Self.dateRegex {
            let nsTitle = title as NSString
            if let match = regex.firstMatch(in: title, options: [], range: NSRange(location: 0, length: nsTitle.length)) {
                let dayStr = nsTitle.substring(with: match.range(at: 1))
                let monthStr = nsTitle.substring(with: match.range(at: 2))
                var yearStr = String(Calendar.current.component(.year, from: Date()))
                if match.range(at: 3).location != NSNotFound {
                    yearStr = nsTitle.substring(with: match.range(at: 3))
                    if yearStr.count == 2 { yearStr = "20" + yearStr }
                }
                if let d = SharedFormatters.dateIT.date(from: "\(dayStr)/\(monthStr)/\(yearStr)") {
                    return d
                }
            }
        }
        
        return Date.distantFuture
    }
}

struct SharedFormatters {
    nonisolated static var time: DateFormatter {
        if let formatter = Thread.current.threadDictionary["timeFormatter"] as? DateFormatter {
            return formatter
        }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        Thread.current.threadDictionary["timeFormatter"] = f
        return f
    }
    
    nonisolated static var dateISO: DateFormatter {
        if let formatter = Thread.current.threadDictionary["dateISOFormatter"] as? DateFormatter {
            return formatter
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "it_IT")
        Thread.current.threadDictionary["dateISOFormatter"] = f
        return f
    }
    
    nonisolated static var dateIT: DateFormatter {
        if let formatter = Thread.current.threadDictionary["dateITFormatter"] as? DateFormatter {
            return formatter
        }
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        f.locale = Locale(identifier: "it_IT")
        Thread.current.threadDictionary["dateITFormatter"] = f
        return f
    }
    
    nonisolated static var dateShort: DateFormatter {
        if let formatter = Thread.current.threadDictionary["dateShortFormatter"] as? DateFormatter {
            return formatter
        }
        let f = DateFormatter()
        f.dateFormat = "dd/MM"
        f.locale = Locale(identifier: "it_IT")
        Thread.current.threadDictionary["dateShortFormatter"] = f
        return f
    }
    
    nonisolated static func formatDestination(_ name: String) -> String {
        let normalized = name.normalizedForDisplay
        let lower = normalized.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.isEmpty { return normalized }
        
        if lower == "milano centrale" || lower == "centrale" || lower == "m. centrale" || lower == "m.centrale" || lower == "milano cle" || lower == "m. cle" || lower == "cle" {
            return "Milano Centrale"
        }
        
        if lower == "milano porta garibaldi" || lower == "milano p. garibaldi" || lower == "milano p.garibaldi" || lower == "porta garibaldi" || lower == "p. garibaldi" || lower == "p.garibaldi" || lower.contains("garibaldi passante") || lower == "garibaldi" {
            return "Milano P. Garibaldi"
        }
        
        if lower == "milano porta venezia" || lower == "porta venezia" || lower == "p.ta venezia" || lower == "p. venezia" || lower == "p.venezia" || lower == "milano p. venezia" || lower == "milano p.venezia" || lower == "milano p.ta venezia" {
            return "Milano P. Venezia"
        }
        
        if lower == "milano porta vittoria" || lower == "porta vittoria" || lower == "p.ta vittoria" || lower == "p. vittoria" || lower == "p.vittoria" || lower == "milano p. vittoria" || lower == "milano p.vittoria" || lower == "milano p.ta vittoria" {
            return "Milano P. Vittoria"
        }
        
        var dest = name
        dest = dest.replacingOccurrences(of: "Milano Repubblica", with: "Milano Repubblica")
        dest = dest.replacingOccurrences(of: "Milano Dateo", with: "Milano Dateo")
        dest = dest.replacingOccurrences(of: "Milano Lancetti", with: "Milano Lancetti")
        
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
    let city: String
    var customFrequencies: [DayType: String]? = nil
    var destinations: [String: String]? = nil

    init(name: String, colorName: String, pdfID: String?, direction: Int = 0, city: String = "milano", customFrequencies: [DayType: String]? = nil, destinations: [String: String]? = nil) {
        self.name = name
        self.colorName = colorName
        self.pdfID = pdfID
        self.direction = direction
        self.city = city
        self.customFrequencies = customFrequencies
        self.destinations = destinations
    }

    var directionLabel: String {
        if city == "roma" {
            switch name {
            case "MA Battistini", "MA Anagnina":
                return direction == 0 ? "Battistini" : "Anagnina"
            case "MB Rebibbia/Jonio", "MB Laurentina", "MB Rebibbia":
                return direction == 0 ? "Rebibbia / Jonio" : "Laurentina"
            default: return name
            }
        } else if city == "napoli" {
            return direction == 0 ? "Piscinola" : "Garibaldi"
        } else if city == "torino" {
            return direction == 0 ? "Fermi" : "Bengasi"
        } else {
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
    var notifyScheduledTime: Bool? = false
    var scheduledNotificationTime: String? = nil
    
    var lastDelayText: String? = nil
    var lastDelayColorName: String? = nil
    var showInWidget: Bool? = true
    var addedDate: Date? = nil
    var category: String? = nil
    var lastViewedAt: Date? = nil
    
    func resolvedCategoryCode() -> String {
        resolveTrainCategory(number: number, rawCategory: category, description: description)
    }
    
    var fullTypeAndNumberTitle: String {
        let catCode = resolvedCategoryCode()
        let typeLabel = descriptiveTrainTypeLabel(category: catCode)
        return "\(typeLabel) \(number)"
    }
    
    var parsedEndpoints: (origin: String?, destination: String) {
        let separators = [" - ", " → ", " ➔ "]
        for sep in separators where description.contains(sep) {
            let parts = description
                .components(separatedBy: sep)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count >= 2 {
                return (parts.first!.formattedStationName, parts.last!.formattedStationName)
            }
        }
        return (nil, description.formattedStationName)
    }
    
    var formattedTimeRange: (departure: String, arrival: String?)? {
        guard let dep = departureTime?.trimmingCharacters(in: .whitespacesAndNewlines),
              !dep.isEmpty, dep != "--:--" else {
            return nil
        }
        let arr = arrivalTime?.trimmingCharacters(in: .whitespacesAndNewlines)
        let validArr = (arr?.isEmpty == false && arr != "--:--") ? arr : nil
        return (dep, validArr)
    }
}

struct VTSearchStation: Codable, Identifiable {
    var id: String { vtID }
    let nomeLungo: String
    let nomeBreve: String
    let vtID: String
    var lastViewedAt: Date? = nil
    
    enum CodingKeys: String, CodingKey {
        case nomeLungo
        case nomeBreve
        case vtID = "id"
        case lastViewedAt
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

nonisolated func cleanTrainCategory(_ category: String) -> String {
    let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
    let up = trimmed.uppercased()
    
    // Suburbani: S1 .. S19 (es. "S5 TRENORD", "SUBURBANO S5", "S6")
    if let match = up.range(of: #"\bS\d{1,2}\b"#, options: .regularExpression) {
        return String(up[match])
    }
    if up.contains("FAST REGIONAL") || up.contains("REGIONALE VELOCE") || up == "RV" {
        return "RV"
    }
    if up.contains("REGIOEXPRESS") || up.contains("REGIO EXPRESS") || up == "RE" {
        return "RE"
    }
    if up.contains("REGIONALE") || up == "REG" || up == "R" {
        return "REG"
    }
    if up.contains("FRECCIAROSSA") || up == "FR" {
        return "FR"
    }
    if up.contains("FRECCIARGENTO") || up == "FA" {
        return "FA"
    }
    if up.contains("FRECCIABIANCA") || up == "FB" {
        return "FB"
    }
    if up.contains("ALTA VELOCIT") || up == "AV" {
        return "AV"
    }
    if up.contains("INTERCITY NOTTE") || up == "ICN" {
        return "ICN"
    }
    if up.contains("INTERCITY") || up == "IC" {
        return "IC"
    }
    if up.contains("ITALO") || up.contains("NTV") || up == "ITA" {
        return "Italo"
    }
    if up.contains("MALPENSA EXPRESS") || up == "MXP" {
        return "MXP"
    }
    if up.contains("EURONIGHT") || up == "EN" {
        return "EN"
    }
    if up.contains("EUROCITY") || up == "EC" {
        return "EC"
    }
    if up.contains("SUBURBANO") || up == "S" {
        return "S"
    }
    if up.contains("METRO") {
        return trimmed
    }
    return trimmed.replacingOccurrences(of: "TRENORD", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Identifica in modo deterministico se un treno è operato da Italo (NTV).
/// Verifica la categoria (NTV, ITA, ITALO) o la numerazione ufficiale (serie RFI 99xx, 89xx, 81xx a 4 cifre riservate a Italo).
nonisolated func isItaloTrain(category: String? = nil, number: String? = nil) -> Bool {
    if let cat = category {
        let clean = cleanTrainCategory(cat).uppercased()
        if clean.contains("ITALO") || clean.contains("NTV") || clean == "ITA" {
            return true
        }
    }
    if let num = number {
        let cleanNum = num.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanNum.count == 4 && (cleanNum.hasPrefix("99") || cleanNum.hasPrefix("89") || cleanNum.hasPrefix("81")) {
            return true
        }
    }
    return false
}

private nonisolated func inferSuburbanLine(number: String, description: String) -> String? {
    let num = number.trimmingCharacters(in: .whitespacesAndNewlines)
    let desc = description.lowercased()
    if num.hasPrefix("240") || num.hasPrefix("230") || num.hasPrefix("241") || num.hasPrefix("231") { return "S1" }
    if num.hasPrefix("242") || num.hasPrefix("232") {
        if desc.contains("melegnano") || desc.contains("cormano") { return "S12" }
        return "S2"
    }
    if num.hasPrefix("243") || num.hasPrefix("233") || num.hasPrefix("328") || num.hasPrefix("329") { return "S13" }
    if num.hasPrefix("245") || num.hasPrefix("235") { return "S5" }
    if num.hasPrefix("246") || num.hasPrefix("236") { return "S6" }
    if num.hasPrefix("256") || num.hasPrefix("257") || num.hasPrefix("247") || num.hasPrefix("237") { return "S12" }
    if num.hasPrefix("248") || num.hasPrefix("238") { return "S8" }
    if num.hasPrefix("249") || num.hasPrefix("239") { return "S9" }
    if num.hasPrefix("250") || num.hasPrefix("251") || num.hasPrefix("252") { return "S11" }
    if desc.contains("varese") || desc.contains("treviglio") || desc.contains("gallarate") { return "S5" }
    if desc.contains("novara") || desc.contains("pioltello") || desc.contains("magenta") { return "S6" }
    if desc.contains("saronno") || desc.contains("lodi") { return "S1" }
    if desc.contains("mariano") || desc.contains("seveso") || desc.contains("camnago") { return "S2" }
    if desc.contains("pavia") || desc.contains("garbagnate") { return "S13" }
    return nil
}

nonisolated func resolveTrainCategory(number: String, rawCategory: String? = nil, description: String = "") -> String {
    let cleanNum = number.trimmingCharacters(in: .whitespacesAndNewlines)
    if isItaloTrain(category: rawCategory, number: cleanNum) || description.localizedCaseInsensitiveContains("Italo") {
        return "Italo"
    }
    
    let raw = rawCategory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let cleaned = raw.isEmpty ? "" : cleanTrainCategory(raw)
    let up = cleaned.uppercased()
    
    if !up.isEmpty && up != "TRENO" {
        if up.range(of: #"^S\d{1,2}$"#, options: .regularExpression) != nil {
            return up
        }
        if ["FR", "FA", "FB", "AV", "IC", "ICN", "EC", "EN", "MXP", "RV", "RE"].contains(up) {
            return up
        }
        if up == "S" {
            if let subLine = inferSuburbanLine(number: cleanNum, description: description) {
                return subLine
            }
            if cleanNum.hasPrefix("10") {
                return "REG"
            }
            return "S"
        }
        if up == "REG" || up == "R" {
            if let subLine = inferSuburbanLine(number: cleanNum, description: description),
               cleanNum.hasPrefix("23") || cleanNum.hasPrefix("24") || cleanNum.hasPrefix("25") || cleanNum.hasPrefix("328") || cleanNum.hasPrefix("329") {
                return subLine
            }
            return "REG"
        }
        return cleaned
    }
    
    if (cleanNum.hasPrefix("23") || cleanNum.hasPrefix("24") || cleanNum.hasPrefix("25") || cleanNum.hasPrefix("328") || cleanNum.hasPrefix("329")),
       let subLine = inferSuburbanLine(number: cleanNum, description: description) {
        return subLine
    }
    if cleanNum.hasPrefix("20") || cleanNum.hasPrefix("21") {
        return "RV"
    }
    if cleanNum.hasPrefix("9") {
        return "FR"
    }
    return "REG"
}

nonisolated func descriptiveTrainTypeLabel(category: String) -> String {
    let cleaned = cleanTrainCategory(category)
    let up = cleaned.uppercased()
    if up.range(of: #"^S\d{1,2}$"#, options: .regularExpression) != nil {
        return "Suburbano \(up)"
    }
    switch up {
    case "S": return "Suburbano"
    case "REG", "R": return "Regionale"
    case "RV": return "Regionale Veloce"
    case "RE": return "RegioExpress"
    case "FR": return "Frecciarossa"
    case "FA": return "Frecciargento"
    case "FB": return "Frecciabianca"
    case "AV": return "Alta Velocità"
    case "IC": return "Intercity"
    case "ICN": return "Intercity Notte"
    case "EC": return "Eurocity"
    case "EN": return "Euronight"
    case "MXP": return "Malpensa Express"
    case "ITALO": return "Italo"
    default:
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.caseInsensitiveCompare("Treno") == .orderedSame {
            return "Treno"
        }
        return cleaned.isEmpty ? trimmed : cleaned
    }
}

struct Train: Identifiable, Sendable, Equatable {
    let id: String
    let category: String
    let number: String
    let destination: String
    let time: String
    let delay: String
    let platform: String
    /// True quando la discrepanza tra ritardo RFI e VT supera la soglia (15 min):
    /// il dato VT non è attendibile in quel caso, si usa RFI ma si segnala con un badge "?".
    let isDelayUncertain: Bool
    let origin: String?
    
    var isItalo: Bool {
        isItaloTrain(category: category, number: number)
    }
    
    nonisolated init(category: String, number: String, destination: String, time: String, delay: String, platform: String, isDelayUncertain: Bool = false, origin: String? = nil) {
        let cleaned = cleanTrainCategory(category)
        let resolvedCat: String
        if isItaloTrain(category: cleaned, number: number) {
            resolvedCat = "Italo"
        } else {
            resolvedCat = cleaned.isEmpty ? category : cleaned
        }
        self.category = resolvedCat
        self.number = number
        self.destination = Train.cleanStationName(destination)
        self.time = time
        self.delay = delay
        self.platform = platform
        self.isDelayUncertain = isDelayUncertain
        self.origin = origin.map { Train.cleanStationName($0) }
        self.id = "\(self.category)_\(number)_\(time)_\(self.destination)"
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
            ("Torino Porta di Susa", "Torino Porta Susa"),
            ("Milano Expo Rho", "Rho Fiera"),
            ("Expo Rho", "Rho Fiera"),
            ("Mediopadana R.Emilia", "Reggio Emilia AV Mediopadana"),
            ("Milano Bovisa Politecnico", "Milano Bovisa"),
            ("Milano Bovisa", "Milano Bovisa"),
            ("Milano Porta Garibaldi", "Milano P. Garibaldi"),
            ("Milano Lancetti", "Milano Lancetti"),
            ("Milano Rogoredo", "Milano Rogoredo"),
            ("Milano Forlanini", "Milano Forlanini"),
            ("Milano Porta Venezia", "Milano P. Venezia"),
            ("Milano Repubblica", "Milano Repubblica"),
            ("Milano Dateo", "Milano Dateo"),
            ("Milano Porta Vittoria", "Milano P. Vittoria"),
            ("Milano Villapizzone", "Milano Villapizzone"),
            ("Milano Cadorna", "Milano Cadorna"),
            ("Milano Greco Pirelli", "Milano Greco P."),
            ("Milano Scalo Romana", "Milano S. Romana"),
            ("Milano Porta Romana", "Milano P. Romana"),
            ("Milano San Cristoforo", "Milano S. Cristoforo"),
            ("Milano Lambrate", "Milano Lambrate"),
            ("Milano Certosa", "Milano Certosa"),
            ("Milano Lodi T.i.b.b.", "Milano Lodi T.I.B.B.")
        ]
        
        for (target, replacement) in replacements {
            if clean.localizedCaseInsensitiveContains(target) {
                clean = clean.replacingOccurrences(of: target, with: replacement, options: .caseInsensitive)
            }
        }
        
        if clean.hasPrefix("Milano ") {
            let rest = String(clean.dropFirst(7))
            let lowerRest = rest.lowercased()
            if lowerRest == "centrale" || lowerRest == "p. garibaldi" || lowerRest == "porta garibaldi" {
                // Keep "Milano "
            } else {
                clean = rest
            }
        } else if clean.hasPrefix("Milano") {
            let rest = String(clean.dropFirst(6))
            let lowerRest = rest.lowercased()
            if lowerRest == "centrale" || lowerRest == "p. garibaldi" || lowerRest == "porta garibaldi" {
                // Keep "Milano"
            } else {
                clean = rest
            }
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
    var detectedCategory: String? = nil
    
    nonisolated init(
        lastStation: String = "--",
        lastTime: String = "--",
        statusMessage: String = "In attesa di dati...",
        isDeparted: Bool = false,
        cancellationNote: String? = nil,
        isArrived: Bool = false,
        detectedCategory: String? = nil
    ) {
        self.lastStation = lastStation
        self.lastTime = lastTime
        self.statusMessage = statusMessage
        self.isDeparted = isDeparted
        self.cancellationNote = cancellationNote
        self.isArrived = isArrived
        self.detectedCategory = detectedCategory
    }
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
    var isSuppressed: Bool = false
}

struct Station: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    let name: String
    let rfiID: String?
    let vtID: String?
    let lat: Double?
    let lon: Double?
    var addedDate: Date? = nil
    
    enum CodingKeys: String, CodingKey {
        case id, name, rfiID, vtID, lat, lon, addedDate
    }
    
    init(id: UUID = UUID(), name: String, rfiID: String? = nil, vtID: String? = nil, lat: Double? = nil, lon: Double? = nil, addedDate: Date? = nil) {
        self.id = id
        self.name = name
        self.rfiID = rfiID
        self.vtID = vtID
        self.lat = lat
        self.lon = lon
        self.addedDate = addedDate
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.rfiID = try? container.decodeIfPresent(String.self, forKey: .rfiID)
        self.vtID = try? container.decodeIfPresent(String.self, forKey: .vtID)
        self.lat = try? container.decodeIfPresent(Double.self, forKey: .lat)
        self.lon = try? container.decodeIfPresent(Double.self, forKey: .lon)
        self.addedDate = try? container.decodeIfPresent(Date.self, forKey: .addedDate)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(rfiID, forKey: .rfiID)
        try container.encodeIfPresent(vtID, forKey: .vtID)
        try container.encodeIfPresent(lat, forKey: .lat)
        try container.encodeIfPresent(lon, forKey: .lon)
        try container.encodeIfPresent(addedDate, forKey: .addedDate)
    }
    
    var formattedName: String {
        let lower = name.lowercased()
        let isGaribaldi = lower.contains("garibaldi") && !lower.contains("pavia") && !lower.contains("casalecchio") && !lower.contains("napoli")
        if isGaribaldi {
            let isSotterranea = rfiID == "1714" || vtID == "S01647" || lower.contains("sotterranea") || lower.contains("passante")
            if isSotterranea {
                return "Milano Porta Garibaldi (Passante)"
            } else {
                return "Milano Porta Garibaldi"
            }
        }
        
        let passanteMilanRFI: [String: String] = [
            "1719": "Milano Repubblica",
            "1723": "Milano Porta Venezia",
            "3468": "Milano Dateo",
            "1718": "Milano Porta Vittoria",
            "1713": "Milano Lancetti",
            "3099": "Milano Villapizzone",
            "1708": "Milano Certosa",
            "3169": "Milano Forlanini"
        ]
        if let rfi = rfiID, let fullName = passanteMilanRFI[rfi] {
            return fullName
        }
        
        return name.formattedStationName
    }
    
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = lat, let lon = lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Station, rhs: Station) -> Bool { lhs.id == rhs.id }
    
    private static let passanteExactAliases: [String: String] = [
        "repubblica": "milanorepubblica",
        "dateo": "milanodateo",
        "lancetti": "milanolancetti",
        "villapizzone": "milanovillapizzone",
        "forlanini": "milanoforlanini",
        "bovisa": "milanobovisa",
        "bovisapolitecnico": "milanobovisa",
        "milanobovisapolitecnico": "milanobovisa",
        "certosa": "milanocertosa",
        "portavenezia": "milanoportavenezia",
        "portavittoria": "milanoportavittoria",
        "rogoredo": "milanorogoredo",
        "lambrate": "milanolambrate",
        "romolo": "milanoromolo",
        "affori": "milanoaffori",
        "cadorna": "milanocadorna",
        "milanonordcadorna": "milanocadorna",
        "milanofncadorna": "milanocadorna",
        "cadornafn": "milanocadorna",
        "portagenova": "milanoportagenova",
        "bruzzano": "milanobruzzano",
        "milanobruzzanoparconord": "milanobruzzano",
        "quartooggiaro": "milanoquartooggiaro",
        "grecopirelli": "milanogrecopirelli",
        "tibaldi": "milanotibaldiuniversitabocconi"
    ]

    private static func canonicalMatchKey(_ rawName: String) -> String {
        var s = rawName.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "it_IT"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: " passante", with: "")
            .replacingOccurrences(of: " sotterranea", with: "")
            .replacingOccurrences(of: " superficie", with: "")
            .replacingOccurrences(of: "p.za ", with: "piazza")
            .replacingOccurrences(of: "p.za", with: "piazza")
            .replacingOccurrences(of: "p.ta ", with: "porta")
            .replacingOccurrences(of: "p.ta", with: "porta")
            .replacingOccurrences(of: "p. ", with: "porta")
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
        let compact = String(s.filter { $0.isLetter || $0.isNumber })
        return Self.passanteExactAliases[compact] ?? compact
    }

    func matches(_ other: Station) -> Bool {
        let lower1 = self.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let lower2 = other.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let r1 = (self.rfiID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let r2 = (other.rfiID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let v1 = (self.vtID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let v2 = (other.vtID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        let isGari1 = (lower1.contains("garibaldi") && !lower1.contains("pavia") && !lower1.contains("casalecchio") && !lower1.contains("napoli"))
            || r1 == "1714" || r1 == "1715" || v1 == "S01645" || v1 == "S01647"
        let isGari2 = (lower2.contains("garibaldi") && !lower2.contains("pavia") && !lower2.contains("casalecchio") && !lower2.contains("napoli"))
            || r2 == "1714" || r2 == "1715" || v2 == "S01645" || v2 == "S01647"
        if isGari1 || isGari2 {
            guard isGari1 && isGari2 else { return false }
            let isSott1 = r1 == "1714" || v1 == "S01647" || lower1.contains("sotterranea") || lower1.contains("passante")
            let isSott2 = r2 == "1714" || v2 == "S01647" || lower2.contains("sotterranea") || lower2.contains("passante")
            return isSott1 == isSott2
        }

        if !r1.isEmpty && !r2.isEmpty {
            return r1 == r2
        }
        if v1.hasPrefix("S") && v2.hasPrefix("S") {
            return v1 == v2
        }
        if !v1.isEmpty && !v2.isEmpty && v1 == v2 {
            return true
        }

        let key1 = Self.canonicalMatchKey(self.name)
        let key2 = Self.canonicalMatchKey(other.name)
        return !key1.isEmpty && key1 == key2
    }
    
    private enum MetroHub {
        case milanoRhoFiera
        case milanoPortaGaribaldi
        case milanoCentrale
        case milanoRepubblica
        case milanoPortaVenezia
        case milanoDateo
        case milanoForlanini
        case milanoSestoSanGiovanni
        case milanoCadorna
        case milanoLambrate
        case milanoPortaGenova
        case milanoRomolo
        case milanoAffori
        case milanoPortaRomana
        case milanoRogoredo
        case milanoSanCristoforo
        case milanoDomodossola
        case napoliGaribaldi
        case napoliCavour
        case torinoPortaNuova
        case torinoPortaSusa
        case torinoLingotto
        case romaTermini
        case romaTiburtina
        case romaOstiense
        case romaValleAurelia

        var lines: [MetroLine] {
            switch self {
            case .milanoRhoFiera:
                return [
                    MetroLine(name: "M1 Sesto", colorName: "red", pdfID: "RHO FIERAMILANO", direction: 0)
                ]
            case .milanoPortaGaribaldi:
                return [
                    MetroLine(name: "M2 Nord", colorName: "green", pdfID: "GARIBALDI FS", direction: 0),
                    MetroLine(name: "M2 Sud", colorName: "green", pdfID: "GARIBALDI FS", direction: 1),
                    MetroLine(name: "M5 Bignami", colorName: "purple", pdfID: "GARIBALDI FS", direction: 0),
                    MetroLine(name: "M5 San Siro", colorName: "purple", pdfID: "GARIBALDI FS", direction: 1)
                ]
            case .milanoCentrale:
                return [
                    MetroLine(name: "M2 Nord", colorName: "green", pdfID: "CENTRALE FS", direction: 0),
                    MetroLine(name: "M2 Sud", colorName: "green", pdfID: "CENTRALE FS", direction: 1),
                    MetroLine(name: "M3 S. Donato", colorName: "yellow", pdfID: "CENTRALE FS", direction: 0),
                    MetroLine(name: "M3 Comasina", colorName: "yellow", pdfID: "CENTRALE FS", direction: 1)
                ]
            case .milanoRepubblica:
                return [
                    MetroLine(name: "M3 S. Donato", colorName: "yellow", pdfID: "REPUBBLICA", direction: 0),
                    MetroLine(name: "M3 Comasina", colorName: "yellow", pdfID: "REPUBBLICA", direction: 1)
                ]
            case .milanoPortaVenezia:
                return [
                    MetroLine(name: "M1 Sesto", colorName: "red", pdfID: "P.TA VENEZIA", direction: 0),
                    MetroLine(name: "M1 Rho/Bisc.", colorName: "red", pdfID: "P.TA VENEZIA", direction: 1)
                ]
            case .milanoDateo:
                return [
                    MetroLine(name: "M4 S. Cristoforo", colorName: "blue", pdfID: "DATEO", direction: 0),
                    MetroLine(name: "M4 Linate", colorName: "blue", pdfID: "DATEO", direction: 1)
                ]
            case .milanoForlanini:
                return [
                    MetroLine(name: "M4 S. Cristoforo", colorName: "blue", pdfID: "STAZIONE FORLANINI", direction: 0),
                    MetroLine(name: "M4 Linate", colorName: "blue", pdfID: "STAZIONE FORLANINI", direction: 1)
                ]
            case .milanoSestoSanGiovanni:
                return [
                    MetroLine(name: "M1 Rho/Bisc.", colorName: "red", pdfID: "SESTO 1 MAGGIO FS", direction: 1)
                ]
            case .milanoCadorna:
                return [
                    MetroLine(name: "M1 Sesto", colorName: "red", pdfID: "CADORNA FN M1", direction: 0),
                    MetroLine(name: "M1 Rho/Bisc.", colorName: "red", pdfID: "CADORNA FN M1", direction: 1),
                    MetroLine(name: "M2 Nord", colorName: "green", pdfID: "CADORNA FN M2", direction: 0),
                    MetroLine(name: "M2 Sud", colorName: "green", pdfID: "CADORNA FN M2", direction: 1)
                ]
            case .milanoLambrate:
                return [
                    MetroLine(name: "M2 Nord", colorName: "green", pdfID: "LAMBRATE FS", direction: 0),
                    MetroLine(name: "M2 Sud", colorName: "green", pdfID: "LAMBRATE FS", direction: 1)
                ]
            case .milanoPortaGenova:
                return [
                    MetroLine(name: "M2 Nord", colorName: "green", pdfID: "PORTA GENOVA FS", direction: 0),
                    MetroLine(name: "M2 Sud", colorName: "green", pdfID: "PORTA GENOVA FS", direction: 1)
                ]
            case .milanoRomolo:
                return [
                    MetroLine(name: "M2 Nord", colorName: "green", pdfID: "ROMOLO", direction: 0),
                    MetroLine(name: "M2 Sud", colorName: "green", pdfID: "ROMOLO", direction: 1)
                ]
            case .milanoAffori:
                return [
                    MetroLine(name: "M3 S. Donato", colorName: "yellow", pdfID: "AFFORI FN", direction: 0),
                    MetroLine(name: "M3 Comasina", colorName: "yellow", pdfID: "AFFORI FN", direction: 1)
                ]
            case .milanoPortaRomana:
                return [
                    MetroLine(name: "M3 S. Donato", colorName: "yellow", pdfID: "LODI T.I.B.B.", direction: 0),
                    MetroLine(name: "M3 Comasina", colorName: "yellow", pdfID: "LODI T.I.B.B.", direction: 1)
                ]
            case .milanoRogoredo:
                return [
                    MetroLine(name: "M3 S. Donato", colorName: "yellow", pdfID: "ROGOREDO FS", direction: 0),
                    MetroLine(name: "M3 Comasina", colorName: "yellow", pdfID: "ROGOREDO FS", direction: 1)
                ]
            case .milanoSanCristoforo:
                return [
                    MetroLine(name: "M4 Linate", colorName: "blue", pdfID: "SAN CRISTOFORO", direction: 1)
                ]
            case .milanoDomodossola:
                return [
                    MetroLine(name: "M5 Bignami", colorName: "purple", pdfID: "DOMODOSSOLA FN", direction: 0),
                    MetroLine(name: "M5 San Siro", colorName: "purple", pdfID: "DOMODOSSOLA FN", direction: 1)
                ]
            case .napoliGaribaldi:
                return [
                    MetroLine(name: "L1 Piscinola", colorName: "yellow", pdfID: "PIAZZA GARIBALDI", direction: 0, city: "napoli"),
                    MetroLine(name: "L1 Garibaldi", colorName: "yellow", pdfID: "PIAZZA GARIBALDI", direction: 1, city: "napoli")
                ]
            case .napoliCavour:
                return [
                    MetroLine(name: "L1 Piscinola", colorName: "yellow", pdfID: "MUSEO", direction: 0, city: "napoli"),
                    MetroLine(name: "L1 Garibaldi", colorName: "yellow", pdfID: "MUSEO", direction: 1, city: "napoli")
                ]
            case .torinoPortaNuova:
                return [
                    MetroLine(name: "M1 Fermi", colorName: "yellow", pdfID: "METRO PORTA NUOVA", direction: 0, city: "torino"),
                    MetroLine(name: "M1 Bengasi", colorName: "yellow", pdfID: "METRO PORTA NUOVA", direction: 1, city: "torino")
                ]
            case .torinoPortaSusa:
                return [
                    MetroLine(name: "M1 Fermi", colorName: "yellow", pdfID: "METRO PORTA SUSA", direction: 0, city: "torino"),
                    MetroLine(name: "M1 Bengasi", colorName: "yellow", pdfID: "METRO PORTA SUSA", direction: 1, city: "torino")
                ]
            case .torinoLingotto:
                return [
                    MetroLine(name: "M1 Fermi", colorName: "yellow", pdfID: "METRO LINGOTTO", direction: 0, city: "torino"),
                    MetroLine(name: "M1 Bengasi", colorName: "yellow", pdfID: "METRO LINGOTTO", direction: 1, city: "torino")
                ]
            case .romaTermini:
                return [
                    MetroLine(name: "MA Battistini", colorName: "orange", pdfID: "Termini", direction: 0, city: "roma"),
                    MetroLine(name: "MA Anagnina", colorName: "orange", pdfID: "Termini", direction: 1, city: "roma"),
                    MetroLine(name: "MB Rebibbia/Jonio", colorName: "blue", pdfID: "Termini", direction: 0, city: "roma"),
                    MetroLine(name: "MB Laurentina", colorName: "blue", pdfID: "Termini", direction: 1, city: "roma")
                ]
            case .romaTiburtina:
                return [
                    MetroLine(name: "MB Rebibbia", colorName: "blue", pdfID: "Tiburtina F.s.", direction: 0, city: "roma"),
                    MetroLine(name: "MB Laurentina", colorName: "blue", pdfID: "Tiburtina F.s.", direction: 1, city: "roma")
                ]
            case .romaOstiense:
                return [
                    MetroLine(name: "MB Rebibbia/Jonio", colorName: "blue", pdfID: "Piramide", direction: 0, city: "roma"),
                    MetroLine(name: "MB Laurentina", colorName: "blue", pdfID: "Piramide", direction: 1, city: "roma")
                ]
            case .romaValleAurelia:
                return [
                    MetroLine(name: "MA Battistini", colorName: "orange", pdfID: "Valle Aurelia", direction: 0, city: "roma"),
                    MetroLine(name: "MA Anagnina", colorName: "orange", pdfID: "Valle Aurelia", direction: 1, city: "roma")
                ]
            }
        }
    }

    private static let metroHubByRfiID: [String: MetroHub] = [
        // Milano
        "3098": .milanoRhoFiera,
        "1715": .milanoPortaGaribaldi,
        "1714": .milanoPortaGaribaldi,
        "1728": .milanoCentrale,
        "1719": .milanoRepubblica,
        "1723": .milanoPortaVenezia,
        "3468": .milanoDateo,
        "3169": .milanoForlanini,
        "2716": .milanoSestoSanGiovanni,
        "1712": .milanoLambrate,
        "1716": .milanoPortaGenova,
        "58": .milanoRomolo,
        "1717": .milanoPortaRomana,
        "1720": .milanoRogoredo,
        "1721": .milanoSanCristoforo,
        // Napoli
        "1888": .napoliGaribaldi,
        "1880": .napoliGaribaldi,
        "1879": .napoliCavour,
        // Torino
        "2876": .torinoPortaNuova,
        "3163": .torinoPortaSusa,
        "2855": .torinoLingotto,
        // Roma
        "2416": .romaTermini,
        "2385": .romaTiburtina,
        "2379": .romaOstiense,
        "3429": .romaValleAurelia
    ]

    private static let metroHubByVtID: [String: MetroHub] = [
        // Milano
        "S01039": .milanoRhoFiera,
        "S01645": .milanoPortaGaribaldi,
        "S01647": .milanoPortaGaribaldi,
        "S01700": .milanoCentrale,
        "S01648": .milanoRepubblica,
        "S01649": .milanoPortaVenezia,
        "S01650": .milanoDateo,
        "S01492": .milanoForlanini,
        "S01325": .milanoSestoSanGiovanni,
        "S01066": .milanoCadorna,
        "S01701": .milanoLambrate,
        "S01631": .milanoPortaGenova,
        "S01032": .milanoRomolo,
        "S01078": .milanoAffori,
        "S01632": .milanoPortaRomana,
        "S01820": .milanoRogoredo,
        "S01630": .milanoSanCristoforo,
        "S01067": .milanoDomodossola,
        // Napoli
        "S09218": .napoliGaribaldi,
        "S09109": .napoliGaribaldi,
        "S09108": .napoliCavour,
        // Torino
        "S00219": .torinoPortaNuova,
        "S00035": .torinoPortaSusa,
        "S00452": .torinoLingotto,
        // Roma
        "S08409": .romaTermini,
        "S08217": .romaTiburtina,
        "S08406": .romaOstiense,
        "S08329": .romaValleAurelia
    ]

    private static let metroHubByExactNormalizedName: [String: MetroHub] = [
        // Milano — Rho Fiera
        "RHO FIERA": .milanoRhoFiera,
        "RHO FIERA MILANO": .milanoRhoFiera,
        "RHO FIERAMILANO": .milanoRhoFiera,
        "RHO FIERA EXPO": .milanoRhoFiera,
        "RHO FIERA EXPO MILANO": .milanoRhoFiera,
        "MILANO RHO FIERA": .milanoRhoFiera,

        // Milano — Porta Garibaldi (Superficie & Passante/Sotterranea)
        "MILANO PORTA GARIBALDI": .milanoPortaGaribaldi,
        "MILANO PORTA GARIBALDI SOTTERRANEA": .milanoPortaGaribaldi,
        "MILANO PORTA GARIBALDI PASSANTE": .milanoPortaGaribaldi,
        "MILANO PORTA GARIBALDI PASSANTE SOTTERRANEA": .milanoPortaGaribaldi,
        "MILANO P GARIBALDI": .milanoPortaGaribaldi,
        "MILANO P GARIBALDI SOTTERRANEA": .milanoPortaGaribaldi,
        "MILANO P GARIBALDI PASSANTE": .milanoPortaGaribaldi,
        "MILANO P TA GARIBALDI": .milanoPortaGaribaldi,
        "MILANO P TA GARIBALDI SOTTERRANEA": .milanoPortaGaribaldi,
        "MILANO P TA GARIBALDI PASSANTE": .milanoPortaGaribaldi,
        "PORTA GARIBALDI": .milanoPortaGaribaldi,
        "PORTA GARIBALDI PASSANTE": .milanoPortaGaribaldi,
        "PORTA GARIBALDI SOTTERRANEA": .milanoPortaGaribaldi,
        "P GARIBALDI PASSANTE": .milanoPortaGaribaldi,
        "P TA GARIBALDI PASSANTE": .milanoPortaGaribaldi,
        "GARIBALDI FS": .milanoPortaGaribaldi,

        // Milano — Centrale
        "MILANO CENTRALE": .milanoCentrale,
        "MILANO C LE": .milanoCentrale,
        "CENTRALE FS": .milanoCentrale,

        // Milano — Repubblica
        "MILANO REPUBBLICA": .milanoRepubblica,
        "REPUBBLICA": .milanoRepubblica,

        // Milano — Porta Venezia
        "MILANO PORTA VENEZIA": .milanoPortaVenezia,
        "MILANO P VENEZIA": .milanoPortaVenezia,
        "MILANO P TA VENEZIA": .milanoPortaVenezia,
        "PORTA VENEZIA": .milanoPortaVenezia,
        "P VENEZIA": .milanoPortaVenezia,
        "P TA VENEZIA": .milanoPortaVenezia,

        // Milano — Dateo
        "MILANO DATEO": .milanoDateo,
        "DATEO": .milanoDateo,

        // Milano — Forlanini
        "MILANO FORLANINI": .milanoForlanini,
        "FORLANINI": .milanoForlanini,
        "STAZIONE FORLANINI": .milanoForlanini,

        // Milano — Sesto San Giovanni
        "SESTO SAN GIOVANNI": .milanoSestoSanGiovanni,
        "SESTO S GIOVANNI": .milanoSestoSanGiovanni,
        "MILANO SESTO SAN GIOVANNI": .milanoSestoSanGiovanni,
        "MILANO SESTO S GIOVANNI": .milanoSestoSanGiovanni,
        "SESTO 1 MAGGIO FS": .milanoSestoSanGiovanni,

        // Milano — Cadorna
        "MILANO CADORNA": .milanoCadorna,
        "MILANO NORD CADORNA": .milanoCadorna,
        "MILANO FN CADORNA": .milanoCadorna,
        "CADORNA FN": .milanoCadorna,

        // Milano — Lambrate
        "MILANO LAMBRATE": .milanoLambrate,
        "LAMBRATE FS": .milanoLambrate,

        // Milano — Porta Genova
        "MILANO PORTA GENOVA": .milanoPortaGenova,
        "MILANO P GENOVA": .milanoPortaGenova,
        "MILANO P TA GENOVA": .milanoPortaGenova,
        "PORTA GENOVA FS": .milanoPortaGenova,

        // Milano — Romolo
        "MILANO ROMOLO": .milanoRomolo,
        "ROMOLO": .milanoRomolo,

        // Milano — Affori
        "MILANO AFFORI": .milanoAffori,
        "MILANO NORD AFFORI": .milanoAffori,
        "AFFORI FN": .milanoAffori,

        // Milano — Porta Romana / Scalo Romana
        "MILANO PORTA ROMANA": .milanoPortaRomana,
        "MILANO P ROMANA": .milanoPortaRomana,
        "MILANO P TA ROMANA": .milanoPortaRomana,
        "MILANO SCALO ROMANA": .milanoPortaRomana,
        "PORTA ROMANA FS": .milanoPortaRomana,

        // Milano — Rogoredo
        "MILANO ROGOREDO": .milanoRogoredo,
        "ROGOREDO FS": .milanoRogoredo,

        // Milano — San Cristoforo
        "MILANO SAN CRISTOFORO": .milanoSanCristoforo,
        "MILANO S CRISTOFORO": .milanoSanCristoforo,

        // Milano — Domodossola
        "MILANO DOMODOSSOLA": .milanoDomodossola,
        "MILANO NORD DOMODOSSOLA": .milanoDomodossola,
        "DOMODOSSOLA FN": .milanoDomodossola,

        // Napoli
        "NAPOLI CENTRALE": .napoliGaribaldi,
        "NAPOLI C LE": .napoliGaribaldi,
        "NAPOLI PIAZZA GARIBALDI": .napoliGaribaldi,
        "NAPOLI P GARIBALDI": .napoliGaribaldi,
        "NAPOLI P ZA GARIBALDI": .napoliGaribaldi,
        "NAPOLI PIAZZA CAVOUR": .napoliCavour,
        "NAPOLI P CAVOUR": .napoliCavour,
        "NAPOLI P ZA CAVOUR": .napoliCavour,
        "NAPOLI CAVOUR": .napoliCavour,
        "NAPOLI MUSEO": .napoliCavour,

        // Torino
        "TORINO PORTA NUOVA": .torinoPortaNuova,
        "TORINO P NUOVA": .torinoPortaNuova,
        "TORINO P TA NUOVA": .torinoPortaNuova,
        "TORINO PORTA SUSA": .torinoPortaSusa,
        "TORINO P SUSA": .torinoPortaSusa,
        "TORINO P TA SUSA": .torinoPortaSusa,
        "TORINO LINGOTTO": .torinoLingotto,

        // Roma
        "ROMA TERMINI": .romaTermini,
        "ROMA TIBURTINA": .romaTiburtina,
        "ROMA OSTIENSE": .romaOstiense,
        "VALLE AURELIA": .romaValleAurelia,
        "ROMA VALLE AURELIA": .romaValleAurelia
    ]

    private static func normalizedMetroLookupName(_ raw: String) -> String {
        let folded = raw
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "it_IT"))
            .uppercased()
        let cleaned = folded.map { char -> Character in
            (char.isLetter || char.isNumber) ? char : " "
        }
        return String(cleaned)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    var metroLines: [MetroLine] {
        // 1. Match autorevole per rfiID / vtID: garantisce corrispondenza univoca alla stazione reale
        let cleanRfiID = (self.rfiID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanVtID = (self.vtID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if !cleanRfiID.isEmpty, let hub = Self.metroHubByRfiID[cleanRfiID] {
            return hub.lines
        }
        if !cleanVtID.isEmpty, let hub = Self.metroHubByVtID[cleanVtID] {
            return hub.lines
        }

        // Se la stazione possiede un codice RFI numerico o un codice ViaggiaTreno nazionale (S...)
        // che NON è presente nelle tabelle metro-interscambio, NON appartiene a nessuna stazione con metro.
        if !cleanRfiID.isEmpty && cleanRfiID.allSatisfy(\.isNumber) {
            return []
        }
        if cleanVtID.hasPrefix("S") {
            return []
        }

        // 2. Fallback rigoroso per nome normalizzato esatto (solo se priva di ID nazionali, es. fermate o codici N...)
        let normName = Self.normalizedMetroLookupName(self.name)
        if let hub = Self.metroHubByExactNormalizedName[normName] {
            return hub.lines
        }
        return []
    }
}

enum AppSection: String, Codable, CaseIterable {
    case nearby = "Stazione Vicina"
    case myStations = "Le Mie Stazioni"
    case favoriteTrains = "I miei Treni"
    case favoriteRoutes = "Le Mie Tratte Abituali"
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

        
        let garibaldiSup = Station(name: "Milano P. Garibaldi", rfiID: "1715", vtID: "S01645", lat: 45.4844, lon: 9.1887)
        let rhoFiera = Station(name: "Rho Fiera", rfiID: "3098", vtID: "S01039", lat: 45.5215, lon: 9.0883)
        
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
    var departureTime: String
    var arrivalTime: String
    var trainNumber: String
    var trainCategory: String
    var travelMinutes: Int? = nil
    var urbanHeadsign: String? = nil
    var isStationWalk: Bool = false
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

struct FavoriteRoute: Codable, Identifiable, Equatable, Hashable {
    var id: String { "\(originID)-\(destinationID)" }
    let originName: String
    let originID: String
    let destinationName: String
    let destinationID: String
    var lastViewedAt: Date? = nil
}

enum TravelSolutionsSource: Equatable {
    case none
    case searchView
    case favoriteRoute
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
    var lastViewedAt: Date? = nil
    
    static func from(solution: TravelSolution, lastViewedAt: Date? = nil) -> SavedTrip {
        let tripId = "\(solution.origin)-\(solution.destination)-\(solution.departureTime)"
        let segs = solution.segments.map {
            SavedTripSegment(
                origin: $0.origin,
                destination: $0.destination,
                departureTime: $0.departureTime,
                arrivalTime: $0.arrivalTime,
                trainNumber: $0.trainNumber,
                trainCategory: $0.trainCategory
            )
        }
        return SavedTrip(
            id: tripId,
            origin: solution.origin,
            destination: solution.destination,
            departureTime: solution.departureTime,
            arrivalTime: solution.arrivalTime,
            duration: solution.duration,
            segments: segs,
            lastViewedAt: lastViewedAt
        )
    }
    
    var compactTrainsSummary: String {
        let formatted = segments.compactMap { seg -> String? in
            let cat = seg.trainCategory.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let num = seg.trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // IMPORTANTE: 'suburbano' deve essere controllato PRIMA di 'urbano',
            // altrimenti la parola 'suburbano' contiene la sottostringa 'urbano' e viene scambiata per mezzo urbano!
            var prefix = ""
            if cat.contains("suburbano") || cat == "s" {
                prefix = "S"
            } else if cat.contains("regionale veloce") || cat == "rv" {
                prefix = "RV"
            } else if cat.contains("regioexpress") || cat == "re" {
                prefix = "RE"
            } else if cat.contains("regionale") || cat == "r" || cat == "reg" {
                prefix = "R"
            } else if cat.contains("frecciarossa") || cat == "fr" {
                prefix = "FR"
            } else if cat.contains("frecciargento") || cat == "fa" {
                prefix = "FA"
            } else if cat.contains("frecciabianca") || cat == "fb" {
                prefix = "FB"
            } else if cat.contains("frecce") {
                prefix = "FR"
            } else if cat.contains("alta velocit") || cat == "av" {
                prefix = "AV"
            } else if cat.contains("intercity notte") || cat == "icn" {
                prefix = "ICN"
            } else if cat.contains("intercity") || cat == "ic" {
                prefix = "IC"
            } else if cat.contains("eurocity") || cat == "ec" {
                prefix = "EC"
            } else if cat.contains("euronight") || cat == "en" {
                prefix = "EN"
            } else if cat.contains("malpensa") || cat == "mxp" {
                prefix = "MXP"
            } else if cat.contains("italo") {
                prefix = "Italo"
            } else if cat.contains("urbano") || cat.contains("metro") || num.lowercased().contains("urbano") || num.lowercased().contains("metro") {
                return "Urb"
            } else if !seg.trainCategory.isEmpty && seg.trainCategory != "Treno" {
                prefix = String(seg.trainCategory.prefix(3)).uppercased()
            }
            
            if num.isEmpty {
                return prefix.isEmpty ? nil : prefix
            }
            if !prefix.isEmpty && num.uppercased().hasPrefix(prefix.uppercased()) {
                return num
            }
            return "\(prefix)\(num)"
        }
        
        if formatted.isEmpty { return "" }
        return formatted.joined(separator: " + ")
    }
    
    var asTravelSolution: TravelSolution {
        let mappedSegments = segments.map { TravelSegment(origin: $0.origin, destination: $0.destination, departureTime: $0.departureTime, arrivalTime: $0.arrivalTime, trainNumber: $0.trainNumber, trainCategory: $0.trainCategory) }
        return TravelSolution(trainNumber: "", category: "Viaggio", departureTime: departureTime, arrivalTime: arrivalTime, origin: origin, destination: destination, duration: duration, segments: mappedSegments)
    }
}

struct HistoryTimeSection<Item: Identifiable>: Identifiable {
    let id: String
    let title: String
    let items: [Item]
}

private struct HistoryBucketMeta<Item> {
    let id: String
    let title: String
    let tier: Int
    let subRank: Int
    var items: [Item]
}

func groupHistoryByTime<Item: Identifiable>(
    _ items: [Item],
    dateFor: (Item) -> Date?,
    now: Date = Date()
) -> [HistoryTimeSection<Item>] {
    guard !items.isEmpty else { return [] }
    let calendar = Calendar.current
    let startOfToday = calendar.startOfDay(for: now)
    let currentYear = calendar.component(.year, from: now)
    let itLocale = Locale(identifier: "it_IT")

    let weekdayFormatter = DateFormatter()
    weekdayFormatter.locale = itLocale
    weekdayFormatter.dateFormat = "EEEE"

    let sameYearMonthFormatter = DateFormatter()
    sameYearMonthFormatter.locale = itLocale
    sameYearMonthFormatter.dateFormat = "MMMM"

    let otherYearMonthFormatter = DateFormatter()
    otherYearMonthFormatter.locale = itLocale
    otherYearMonthFormatter.dateFormat = "MMMM yyyy"

    var buckets: [String: HistoryBucketMeta<Item>] = [:]

    for item in items {
        let id: String
        let title: String
        let tier: Int
        let subRank: Int

        if let date = dateFor(item) {
            if calendar.isDateInToday(date) {
                let hour = calendar.component(.hour, from: date)
                tier = 0
                switch hour {
                case 18...23:
                    id = "today_evening"
                    title = "Oggi · Sera"
                    subRank = 3
                case 12...17:
                    id = "today_afternoon"
                    title = "Oggi · Pomeriggio"
                    subRank = 2
                case 5...11:
                    id = "today_morning"
                    title = "Oggi · Mattina"
                    subRank = 1
                default:
                    id = "today_night"
                    title = "Oggi · Notte"
                    subRank = 0
                }
            } else if calendar.isDateInYesterday(date) {
                id = "yesterday"
                title = "Ieri"
                tier = 1
                subRank = 0
            } else {
                let startOfDate = calendar.startOfDay(for: date)
                let daysAgo = max(0, calendar.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? 0)
                if daysAgo <= 6 {
                    id = "day_\(daysAgo)"
                    title = weekdayFormatter.string(from: date).capitalized(with: itLocale)
                    tier = 2
                    subRank = -daysAgo
                } else if daysAgo <= 13 {
                    id = "week_1"
                    title = "Settimana scorsa"
                    tier = 3
                    subRank = 3
                } else if daysAgo <= 20 {
                    id = "week_2"
                    title = "2 settimane fa"
                    tier = 3
                    subRank = 2
                } else if daysAgo <= 27 {
                    id = "week_3"
                    title = "3 settimane fa"
                    tier = 3
                    subRank = 1
                } else {
                    let year = calendar.component(.year, from: date)
                    let month = calendar.component(.month, from: date)
                    id = "month_\(year)_\(month)"
                    let rawMonth = (year == currentYear)
                        ? sameYearMonthFormatter.string(from: date)
                        : otherYearMonthFormatter.string(from: date)
                    title = rawMonth.capitalized(with: itLocale)
                    tier = 4
                    subRank = year * 12 + month
                }
            }
        } else {
            id = "legacy"
            title = "Precedenti"
            tier = 5
            subRank = 0
        }

        if var existing = buckets[id] {
            existing.items.append(item)
            buckets[id] = existing
        } else {
            buckets[id] = HistoryBucketMeta(id: id, title: title, tier: tier, subRank: subRank, items: [item])
        }
    }

    return buckets.values
        .sorted { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            return lhs.subRank > rhs.subRank
        }
        .map { HistoryTimeSection(id: $0.id, title: $0.title, items: $0.items) }
}

extension String {
    var normalizedForDisplay: String {
        var str = self.precomposedStringWithCanonicalMapping
        str = str.replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#39", with: "'")
            .replacingOccurrences(of: "&39;", with: "'")
            .replacingOccurrences(of: "&39", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
        if str.contains("Ã") || str.contains("©") || str.contains("¨") || str.contains("¬") || str.contains("³") {
            if let data = str.data(using: .isoLatin1), let utf8Str = String(data: data, encoding: .utf8) {
                str = utf8Str
            }
        }
        return str
    }
    
    var formattedStationName: String {
        var str = self.normalizedForDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.isEmpty { return str }
        
        let lower = str.lowercased()
        
        let isGaribaldi = lower.contains("garibaldi") && !lower.contains("pavia") && !lower.contains("casalecchio") && !lower.contains("napoli")
        if isGaribaldi {
            let isSotterranea = lower.contains("sotterranea") || lower.contains("passante")
            return isSotterranea ? "Milano Porta Garibaldi (Passante)" : "Milano Porta Garibaldi"
        }
        if lower == "milano centrale" || lower == "m.centrale" || lower == "m. centrale" || lower == "centrale" {
            return "Milano Centrale"
        }
        
        // 1. Sostituzioni di vocali accentate terminanti con apostrofo tipiche delle banche dati RFI/ViaggiaTreno
        let accentDict: [String: String] = [
            "FORLI'": "Forlì", "BIANZE'": "Bianzè", "CANTU'": "Cantù",
            "CEFALU'": "Cefalù", "SANTHIA'": "Santhià", "CIRIE'": "Ciriè",
            "CUORGNE'": "Cuorgnè", "CITTA'": "Città", "LIBERTA'": "Libertà",
            "UNIVERSITA'": "Università", "TRINITA'": "Trinità", "ROSA'": "Rosà",
            "ARQUA'": "Arquà", "ANNA'": "Annà", "DONA'": "Donà",
            "FAE'": "Faè", "FAGARE'": "Fagarè", "MAGRE'": "Magrè",
            "MOMME'": "Mommè", "CALDE'": "Caldè", "CARPANE'": "Carpanè",
            "PRE'": "Pré", "ALI'": "Alì", "SECLI'": "Seclì",
            "CANICATTI'": "Canicattì", "MUGGIO'": "Muggiò", "CALO'": "Calò",
            "REMONDO'": "Remondò", "GAMBOLO'": "Gambolò", "CIRO'": "Cirò",
            "NARDO'": "Nardò", "AGRO'": "Agrò", "NICOLO'": "Nicolò",
            "VIGGIU'": "Viggiù", "GU'": "Gù", "DOLCE'": "Dolcè",
            "SCORZE'": "Scorzè"
        ]
        
        for (pattern, replacement) in accentDict {
            if let regex = try? NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: pattern), options: .caseInsensitive) {
                str = regex.stringByReplacingMatches(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count), withTemplate: replacement)
            }
        }
        
        // Conversione generica di vocale + apostrofo per qualsiasi altra stazione (escluse elisioni d', dell', all', sull', l', ca', de', sant', castell')
        if let genericRegex = try? NSRegularExpression(pattern: "\\b(?!(?:d|dell|all|sull|l|ca|de|sant|castell)'\\b)([a-zA-Z]+?)([aeiouAEIOU])'\\b", options: []) {
            let nsStr = str as NSString
            let matches = genericRegex.matches(in: str, options: [], range: NSRange(location: 0, length: nsStr.length))
            for match in matches.reversed() {
                let wordRange = match.range(at: 1)
                let vowelRange = match.range(at: 2)
                let wordPart = nsStr.substring(with: wordRange)
                let vowelPart = nsStr.substring(with: vowelRange).lowercased()
                let acc: String
                switch vowelPart {
                case "a": acc = "à"
                case "e": acc = "è"
                case "i": acc = "ì"
                case "o": acc = "ò"
                case "u": acc = "ù"
                default: acc = vowelPart
                }
                let fullReplacement = wordPart + acc
                str = (str as NSString).replacingCharacters(in: match.range, with: fullReplacement)
            }
        }
        
        // 2. Abbreviazioni comuni
        str = str
            .replacingOccurrences(of: "p.ta ", with: "Porta ", options: .caseInsensitive)
            .replacingOccurrences(of: "p. ", with: "Porta ", options: .caseInsensitive)
            .replacingOccurrences(of: "staz.ne ", with: "Stazione ", options: .caseInsensitive)
            
        if let sRegex = try? NSRegularExpression(pattern: "\\bS\\.(?=[a-zA-Z])", options: .caseInsensitive) {
            str = sRegex.stringByReplacingMatches(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count), withTemplate: "S. ")
        }
        
        // 3. Formattazione intelligente maiuscole/minuscole ed elisioni italiane (d', dell', all', ecc.)
        let words = str.components(separatedBy: " ")
        var formattedWords: [String] = []
        
        for (i, w) in words.enumerated() {
            let subparts = w.components(separatedBy: "-")
            let formattedSubparts = subparts.map { sp -> String in
                if sp.isEmpty { return sp }
                if sp.contains("'") {
                    let parts = sp.components(separatedBy: "'")
                    let prefix = parts[0].lowercased()
                    let rest = parts.dropFirst().map { sub -> String in
                        guard !sub.isEmpty else { return "" }
                        return sub.prefix(1).uppercased() + sub.dropFirst().lowercased()
                    }
                    if prefix == "d" || prefix == "dell" || prefix == "all" || prefix == "sull" {
                        return prefix + "'" + rest.joined(separator: "'")
                    } else if prefix == "l" {
                        return (i == 0 ? "L'" : "l'") + rest.joined(separator: "'")
                    } else if prefix == "ca" {
                        return "Ca'" + rest.joined(separator: "'")
                    } else if prefix == "de" {
                        return "de'" + rest.joined(separator: "'")
                    } else if prefix == "sant" {
                        return "Sant'" + rest.joined(separator: "'")
                    } else if prefix == "castell" {
                        return "Castell'" + rest.joined(separator: "'")
                    } else {
                        return prefix.prefix(1).uppercased() + prefix.dropFirst().lowercased() + "'" + rest.joined(separator: "'")
                    }
                }
                
                let spLower = sp.lowercased()
                if i > 0 && ["di", "del", "della", "delle", "dei", "degli", "in", "per", "da", "su"].contains(spLower) {
                    return spLower
                }
                
                return sp.prefix(1).uppercased() + sp.dropFirst().lowercased()
            }
            formattedWords.append(formattedSubparts.joined(separator: "-"))
        }
        
        var result = formattedWords.joined(separator: " ")
        result = result
            .replacingOccurrences(of: " Fs", with: " FS")
            .replacingOccurrences(of: " Fn", with: " FN")
            .replacingOccurrences(of: " Passante", with: "")
        
        return result
    }
}

// MARK: - Metro Station Model

struct MetroStation: Identifiable, Codable, Equatable, Hashable {
    var id: String { primaryPdfID }
    let displayName: String
    let primaryPdfID: String   // used for MetroCache lookup
    let city: String
    let lines: [MetroLine]
    let latitude: Double
    let longitude: Double

    static func == (lhs: MetroStation, rhs: MetroStation) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var color: Color { lines.first?.color ?? .gray }

    // Codable support (MetroLine is not Codable, so we store identifiers)
    enum CodingKeys: String, CodingKey {
        case displayName, primaryPdfID, city, latitude, longitude, lineNames, lineColors, linePdfIDs, lineDirections
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(primaryPdfID, forKey: .primaryPdfID)
        try c.encode(city, forKey: .city)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(lines.map { $0.name }, forKey: .lineNames)
        try c.encode(lines.map { $0.colorName }, forKey: .lineColors)
        try c.encode(lines.map { $0.pdfID ?? "" }, forKey: .linePdfIDs)
        try c.encode(lines.map { $0.direction }, forKey: .lineDirections)
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decode(String.self, forKey: .displayName)
        primaryPdfID = try c.decode(String.self, forKey: .primaryPdfID)
        city = try c.decode(String.self, forKey: .city)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        let names = try c.decode([String].self, forKey: .lineNames)
        let colors = try c.decode([String].self, forKey: .lineColors)
        let pdfIDs = try c.decode([String].self, forKey: .linePdfIDs)
        let dirs = try c.decode([Int].self, forKey: .lineDirections)
        lines = zip(zip(names, colors), zip(pdfIDs, dirs)).map { outer in
            let ((name, color), (pdfID, dir)) = outer
            return MetroLine(name: name, colorName: color, pdfID: pdfID.isEmpty ? nil : pdfID, direction: dir)
        }
    }
    init(displayName: String, primaryPdfID: String, city: String = "milano", lines: [MetroLine], latitude: Double, longitude: Double) {
        self.displayName = displayName
        self.primaryPdfID = primaryPdfID
        self.city = city
        self.lines = lines
        self.latitude = latitude
        self.longitude = longitude
    }
}

extension MetroStation {
    var uniqueLines: [MetroLine] {
        var seen = Set<String>()
        var result = [MetroLine]()
        for line in lines {
            let prefix = String(line.name.prefix(2))
            if !seen.contains(prefix) {
                seen.insert(prefix)
                result.append(line)
            }
        }
        return result
    }

    func branchName(for linePrefix: String) -> String? {
        switch linePrefix {
        case "M1":
            let rhoFieraStations = ["Buonarroti", "Amendola", "Lotto", "QT8", "Lampugnano", "Uruguay", "Bonola", "San Leonardo", "Molino Dorino", "Pero", "Rho Fieramilano"]
            let bisceglieStations = ["Wagner", "De Angeli", "Gambara", "Bande Nere", "Primaticcio", "Inganni", "Bisceglie"]
            if rhoFieraStations.contains(displayName) {
                return "Rho"
            } else if bisceglieStations.contains(displayName) {
                return "Bisc."
            }
            return nil
        case "M2":
            let gessateStations = ["Vimodrone", "Cascina Burrona", "Cernusco Sul Naviglio", "Villa Fiorita", "Cassina De Pecchi", "Bussero", "Villa Pompea", "Gorgonzola", "Cascina Antonietta", "Gessate"]
            let colognoStations = ["Cologno Sud", "Cologno Centro", "Cologno Nord"]
            let assagoStations = ["Assago Milanofiori Nord", "Assago Milanofiori Forum"]
            let abbiategrassoStations = ["Abbiategrasso"]
            if gessateStations.contains(displayName) {
                return "Gessate"
            } else if colognoStations.contains(displayName) {
                return "Cologno"
            } else if assagoStations.contains(displayName) {
                return "Assago"
            } else if abbiategrassoStations.contains(displayName) {
                return "Abbiat."
            }
            return nil
        default:
            return nil
        }
    }

    func lineLabelWithBranch(_ linePrefix: String) -> String {
        if let branch = branchName(for: linePrefix) {
            return "\(linePrefix) \(branch)"
        }
        return linePrefix
    }
}



