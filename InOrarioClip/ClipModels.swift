import SwiftUI
import Foundation
import CoreLocation
import Combine

// MARK: - Haptics

public struct Haptics {
    public static func play(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    public static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
    public static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}

// MARK: - Train Model (Exact from In Orario)

public struct Train: Identifiable, Sendable, Equatable, Codable {
    public let id: String
    public let category: String
    public let number: String
    public let destination: String
    public let time: String
    public let delay: String
    public let platform: String
    public let isDelayUncertain: Bool
    public let origin: String?
    
    public var isItalo: Bool {
        isItaloTrain(category: category, number: number)
    }
    
    public init(
        category: String,
        number: String,
        destination: String,
        time: String,
        delay: String,
        platform: String,
        isDelayUncertain: Bool = false,
        origin: String? = nil
    ) {
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
        self.origin = origin
        self.id = "\(self.category)_\(number)_\(time)_\(destination)"
    }
    
    public static func cleanStationName(_ name: String) -> String {
        var clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let replacements: [(String, String)] = [
            ("Torino Porta di Susa", "Torino Porta Susa"),
            ("Milano Expo Rho", "Rho Fiera"),
            ("Expo Rho", "Rho Fiera"),
            ("Mediopadana R.Emilia", "Reggio Emilia AV Mediopadana")
        ]
        
        for (target, replacement) in replacements {
            if clean.localizedCaseInsensitiveContains(target) {
                clean = clean.replacingOccurrences(of: target, with: replacement, options: .caseInsensitive)
            }
        }
        
        if clean.hasPrefix("MILANO ") {
            let rest = String(clean.dropFirst(7))
            let lowerRest = rest.lowercased()
            if lowerRest != "centrale" && lowerRest != "p. garibaldi" && lowerRest != "porta garibaldi" {
                clean = rest
            }
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Station Model (Exact from In Orario)

public struct Station: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public let name: String
    public let rfiID: String?
    public let vtID: String?
    public let lat: Double?
    public let lon: Double?
    
    public init(id: UUID = UUID(), name: String, rfiID: String?, vtID: String?, lat: Double? = nil, lon: Double? = nil) {
        self.id = id
        self.name = name
        self.rfiID = rfiID
        self.vtID = vtID
        self.lat = lat
        self.lon = lon
    }
    
    public var coordinate: CLLocationCoordinate2D? {
        guard let lat = lat, let lon = lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    public var formattedName: String {
        let lower = name.lowercased()
        if lower.contains("garibaldi") {
            if rfiID == "1714" || vtID == "S01647" || lower.contains("sotterranea") || lower.contains("passante") {
                return "Milano Porta Garibaldi (Passante)"
            } else {
                return "Milano Porta Garibaldi"
            }
        }
        if lower.contains("centrale") {
            if lower.contains("milano") { return "Milano Centrale" }
            if lower.contains("napoli") { return "Napoli Centrale" }
            if lower.contains("bologna") { return "Bologna Centrale" }
        }
        if lower.contains("termini") { return "Roma Termini" }
        if lower.contains("tiburtina") { return "Roma Tiburtina" }
        
        let words = name.split(separator: " ")
        let capitalized = words.map { word -> String in
            let w = String(word).lowercased()
            if ["fs", "av", "smn", "p.ta", "c.le"].contains(w) { return w.uppercased() }
            return w.prefix(1).uppercased() + w.dropFirst()
        }
        return capitalized.joined(separator: " ")
    }
}

// MARK: - Stop & TrainStatus Models (Exact from In Orario)

public struct Stop: Identifiable, Sendable {
    public let id = UUID()
    public let stationName: String
    public let time: String
    public let actualTime: String?
    public let delay: Int
    public let estimatedTime: String?
    public let plannedPlatform: String?
    public let actualPlatform: String?
    
    public init(
        stationName: String,
        time: String,
        actualTime: String? = nil,
        delay: Int = 0,
        estimatedTime: String? = nil,
        plannedPlatform: String? = nil,
        actualPlatform: String? = nil
    ) {
        self.stationName = stationName
        self.time = time
        self.actualTime = actualTime
        self.delay = delay
        self.estimatedTime = estimatedTime
        self.plannedPlatform = plannedPlatform
        self.actualPlatform = actualPlatform
    }
}

public struct TrainStatus: Codable, Sendable {
    public var lastStation: String = "--"
    public var lastTime: String = "--"
    public var statusMessage: String = "In attesa di dati..."
    public var isDeparted: Bool = false
    public var cancellationNote: String? = nil
    public var isArrived: Bool = false
    
    public init(
        lastStation: String = "--",
        lastTime: String = "--",
        statusMessage: String = "In attesa di dati...",
        isDeparted: Bool = false,
        cancellationNote: String? = nil,
        isArrived: Bool = false
    ) {
        self.lastStation = lastStation
        self.lastTime = lastTime
        self.statusMessage = statusMessage
        self.isDeparted = isDeparted
        self.cancellationNote = cancellationNote
        self.isArrived = isArrived
    }
}

public struct StopsResult: Sendable {
    public let stops: [Stop]
    public let status: TrainStatus
    public let errorMessage: String?
    
    public init(stops: [Stop], status: TrainStatus, errorMessage: String? = nil) {
        self.stops = stops
        self.status = status
        self.errorMessage = errorMessage
    }
}

public struct StationBoardResult: Sendable {
    public let trains: [Train]
    public let alerts: String?
    
    public init(trains: [Train], alerts: String? = nil) {
        self.trains = trains
        self.alerts = alerts
    }
}

// MARK: - RFIStation

public struct RFIStation: Codable, Identifiable, Hashable, Sendable {
    public var id: String { rfiID ?? vtID ?? name }
    public let name: String
    public let rfiID: String?
    public let vtID: String?
    public let lat: Double?
    public let lon: Double?
    
    public init(name: String, rfiID: String?, vtID: String?, lat: Double? = nil, lon: Double? = nil) {
        self.name = name
        self.rfiID = rfiID
        self.vtID = vtID
        self.lat = lat
        self.lon = lon
    }
    
    public var coordinate: CLLocationCoordinate2D? {
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

// MARK: - Category Helpers (Exact from In Orario)

public nonisolated func cleanTrainCategory(_ category: String) -> String {
    let trimmed = category
        .replacingOccurrences(of: "Categoria", with: "", options: .caseInsensitive)
        .replacingOccurrences(of: "Category", with: "", options: .caseInsensitive)
        .replacingOccurrences(of: "Treno", with: "", options: .caseInsensitive)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let up = trimmed.uppercased()
    
    // Suburbani: S1 .. S19 (es. "S5 TRENORD", "SUBURBANO S5", "S6")
    if let match = up.range(of: #"\bS\d{1,2}\b"#, options: .regularExpression) {
        return String(up[match])
    }
    if up.contains("FAST REGIONAL") || up.contains("REGIONALE VELOCE") || up.contains("REG. VEL.") || up == "RV" {
        return "RV"
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
    if up.contains("EUROCITY") || up == "EC" {
        return "EC"
    }
    return trimmed.replacingOccurrences(of: "TRENORD", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Identifica in modo deterministico se un treno è operato da Italo (NTV).
/// Verifica la categoria (NTV, ITA, ITALO) o la numerazione ufficiale (serie RFI 99xx, 89xx, 81xx a 4 cifre riservate a Italo).
public nonisolated func isItaloTrain(category: String? = nil, number: String? = nil) -> Bool {
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

public func fullCategoryName(_ c: String, dest: String) -> String {
    let cat = c.uppercased()
    if cat.contains("ITALO") || cat.contains("NTV") || cat == "ITA" { return "Italo" }
    if cat.contains("FR") { return "Frecciarossa" }
    if cat.contains("RV") { return "Regionale Veloce" }
    if cat.contains("AV") || cat.contains("ALTA VELOCIT") { return "Alta Velocità" }
    if cat.contains("IC") { return "Intercity" }
    if cat.contains("EC") { return "Eurocity" }
    if cat.contains("S6") || (cat == "S" && (dest.lowercased().contains("novara") || dest.lowercased().contains("treviglio"))) { return "Suburbano" }
    if cat.hasPrefix("S") && cat.count <= 3 { return "Suburbano" }
    if cat == "REG" { return "Regionale" }
    return "Treno"
}

public func categoryColor(_ cat: String) -> Color {
    let c = cat.uppercased()
    if c.contains("ITALO") || c.contains("NTV") { return Color(red: 0.65, green: 0.05, blue: 0.12) }
    if c.contains("FR") || c == "AV" { return .red }
    if c == "IC" || c == "EC" { return .gray }
    if c.contains("S") { return Color(red: 0.0, green: 0.6, blue: 0.2) } // Suburbano Green
    if c.contains("RV") || c.contains("RE") { return .blue }
    return .gray
}

// MARK: - App Store Helper

@MainActor
public func openInOrarioAppStore() {
    guard let url = URL(string: "https://apps.apple.com/it/app/in-orario/id6773419855") else { return }
    UIApplication.shared.open(url)
}

// MARK: - Recent Trains Manager

@MainActor
public final class ClipRecentTrainsManager: ObservableObject {
    public static let shared = ClipRecentTrainsManager()
    
    @Published public private(set) var recentTrains: [Train] = []
    private let storageKey = "clip_recent_trains_v1"
    
    private init() {
        loadRecents()
    }
    
    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            recentTrains = try JSONDecoder().decode([Train].self, from: data)
        } catch {
            print("ClipRecentTrainsManager decode error: \(error)")
        }
    }
    
    public func addTrain(_ train: Train) {
        recentTrains.removeAll { $0.number == train.number }
        recentTrains.insert(train, at: 0)
        if recentTrains.count > 15 {
            recentTrains = Array(recentTrains.prefix(15))
        }
        save()
    }
    
    public func clear() {
        recentTrains.removeAll()
        save()
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(recentTrains)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("ClipRecentTrainsManager encode error: \(error)")
        }
    }
}

// MARK: - SharedFormatters (Exact from In Orario)

public struct SharedFormatters {
    public static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter
    }()
    
    public nonisolated static func formatDestination(_ name: String) -> String {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.isEmpty { return name }
        
        if lower == "milano centrale" || lower == "centrale" || lower == "cle" {
            return "Milano Centrale"
        }
        if lower.contains("garibaldi") {
            return "Milano P. Garibaldi"
        }
        if lower == "torino porta nuova" || lower == "torino p. nuova" || lower == "torino p.nuova" {
            return "Torino P. Nuova"
        }
        if lower == "roma termini" {
            return "Roma Termini"
        }
        if lower == "bologna centrale" {
            return "Bologna Centrale"
        }
        if lower == "napoli centrale" {
            return "Napoli Centrale"
        }
        if lower == "firenze s.m.n." || lower.contains("firenze santa maria") {
            return "Firenze S.M.N."
        }
        if lower == "venezia s. lucia" || lower.contains("santa lucia") {
            return "Venezia S. Lucia"
        }
        
        let words = name.split(separator: " ")
        let cap = words.map { w -> String in
            let low = String(w).lowercased()
            if ["p.", "s.", "c.le", "av", "fs"].contains(low) { return low.uppercased() }
            return low.prefix(1).uppercased() + low.dropFirst()
        }
        return cap.joined(separator: " ")
    }
}

extension String {
    public var formattedStationName: String {
        SharedFormatters.formatDestination(self)
    }
}

