import CoreLocation
import Foundation
import SwiftUI
import Combine

// MARK: - Personal Railway Lines Models

enum PersonalLineKind: String, Codable, CaseIterable, Sendable {
    case suburban = "Suburbana"
    case regional = "Regionale"
    case highSpeed = "Alta Velocità"
    case intercity = "Intercity"
    case international = "Internazionale"
    case airport = "Aeroportuale"
    case personalCorridor = "Direttrice Personale"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        switch raw {
        case PersonalLineKind.suburban.rawValue:
            self = .suburban
        case PersonalLineKind.regional.rawValue, "Regionale / Diretta":
            self = .regional
        case PersonalLineKind.highSpeed.rawValue:
            self = .highSpeed
        case PersonalLineKind.intercity.rawValue:
            self = .intercity
        case PersonalLineKind.international.rawValue:
            self = .international
        case PersonalLineKind.airport.rawValue:
            self = .airport
        case PersonalLineKind.personalCorridor.rawValue:
            self = .personalCorridor
        default:
            self = .regional
        }
    }

    var sortRank: Int {
        switch self {
        case .suburban: return 0
        case .regional: return 1
        case .highSpeed: return 2
        case .intercity: return 3
        case .international: return 4
        case .airport: return 5
        case .personalCorridor: return 6
        }
    }
}

enum RailwayBranchPosition: String, Codable, Equatable, Hashable, Sendable {
    case after
    case before
}

struct RailwayLineBranch: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String { "\(junctionStation)|\(label)|\(stations.joined(separator: ","))" }
    let junctionStation: String
    let label: String
    let stations: [String]
    var position: RailwayBranchPosition? = nil
    var isDashed: Bool? = nil

    var effectivePosition: RailwayBranchPosition { position ?? .after }
    var effectiveIsDashed: Bool { isDashed ?? false }
}

struct PersonalRailwayLine: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    var code: String
    var name: String
    var subtitle: String
    var kind: PersonalLineKind
    var region: String? = nil
    var hexColor: String
    var stations: [String]
    var probeStations: [String]
    var categoryPrefixes: [String]
    var usesPassanteTunnel: Bool
    var isAutoSuggested: Bool
    var branches: [RailwayLineBranch]? = nil

    var effectiveRegion: String {
        let trimmed = region?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Italia" : trimmed
    }

    var color: Color {
        Color(hex: hexColor)
    }

    var badgeTextColor: Color {
        Self.isLightHexColor(hexColor) ? .black : .white
    }

    var primaryCorridorLabel: String {
        guard let first = stations.first, let last = stations.last, first != last else {
            return stations.first ?? name
        }
        return "\(first.compactStationName) ↔ \(last.compactStationName)"
    }

    nonisolated static func isLightHexColor(_ hex: String) -> Bool {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return false }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.72
    }
}

struct SuggestedRailwayLine: Identifiable, Equatable, Sendable {
    var id: String { line.id }
    let line: PersonalRailwayLine
    let reason: String
}

enum LineHealthStatus: Equatable, Sendable {
    case regular
    case warning(avgDelayMinutes: Int)
    case disrupted(reason: String)
    case noDataYet(reason: String)

    var title: String {
        switch self {
        case .regular:
            return "Circolazione regolare"
        case .warning(let avg):
            return avg > 0 ? "Rallentamenti (+\(avg) min)" : "Possibili rallentamenti"
        case .disrupted(let reason):
            return reason
        case .noDataYet:
            return "In attesa di rilevamenti"
        }
    }

    var semanticKind: SemanticStatusKind {
        switch self {
        case .regular: return .regular
        case .warning: return .warning
        case .disrupted: return .disrupted
        case .noDataYet: return .neutral
        }
    }
}

struct LineActiveTrain: Identifiable, Equatable, Sendable {
    var id: String { "\(train.number)_\(matchedStation ?? "")_\(train.time)" }
    let train: Train
    let matchedStation: String?
    let liveLastStation: String?
    let delayMinutes: Int
    let isCancelled: Bool
    let isPassanteTunnel: Bool
}

struct LineLiveSnapshot: Equatable, Sendable {
    let lineID: String
    let health: LineHealthStatus
    let activeTrains: [LineActiveTrain]
    let upcomingDepartures: [LineActiveTrain]
    let stationPositions: [String: [LineActiveTrain]]
    let alertMessages: [String]
    let fetchedAt: Date
}

struct LineNearbyDepartures: Equatable, Sendable {
    let lineID: String
    let stationKey: String
    let stationName: String
    let directionBadges: [String]
    let departures: [Train]
    let fetchedAt: Date
}

// MARK: - Catalog & Matcher

enum RailwayLineCatalog {
    private final class BundleToken {}

    static let curatedCatalog: [PersonalRailwayLine] = {
        let candidateBundles = [Bundle.main, Bundle(for: BundleToken.self)]
        for bundle in candidateBundles {
            if let url = bundle.url(forResource: "railway_lines_italy", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([PersonalRailwayLine].self, from: data),
               !decoded.isEmpty {
                return decoded
            }
        }
        return SuburbanData.shared.allLines.map { sub in
            let stationNames = sub.stations.map(\.formattedName)
            return PersonalRailwayLine(
                id: sub.id,
                code: sub.id,
                name: sub.name,
                subtitle: "Linea Suburbana",
                kind: .suburban,
                region: "Lombardia",
                hexColor: sub.hexColor,
                stations: stationNames,
                probeStations: [stationNames.first, stationNames.last].compactMap { $0 },
                categoryPrefixes: [sub.id],
                usesPassanteTunnel: sub.id != "S11",
                isAutoSuggested: false
            )
        }
    }()

    nonisolated static func normalizeStationToken(_ raw: String) -> String {
        var base = raw.lowercased()
            .replacingOccurrences(of: "(passante)", with: "")
        if base.contains("/"), !base.contains("/av") {
            base = base.split(separator: "/", maxSplits: 1).first.map(String.init) ?? base
        }
        return base
            .replacingOccurrences(of: "milano p.", with: "milano porta")
            .replacingOccurrences(of: "p.ta ", with: "porta ")
            .replacingOccurrences(of: "p. ", with: "porta ")
            .replacingOccurrences(of: "s. ", with: "san ")
            .replacingOccurrences(of: "s.", with: "san ")
            .replacingOccurrences(of: "c.le", with: "centrale")
            .replacingOccurrences(of: "smn", with: "santa maria novella")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "'", with: "")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    nonisolated static func stationsLikelyMatch(_ a: String, _ b: String) -> Bool {
        let na = normalizeStationToken(a)
        let nb = normalizeStationToken(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        if na == nb { return true }
        if na.count >= 4, nb.count >= 4 {
            return na.contains(nb) || nb.contains(na)
        }
        return false
    }

    nonisolated static func shortStationAbbreviation(_ name: String) -> String {
        let lower = name.lowercased()
        let known: [(String, String)] = [
            ("novara", "NOV"), ("pioltello", "PIOLT"), ("treviglio", "TREV"),
            ("varese", "VAR"), ("gallarate", "GALL"), ("saronno", "SAR"),
            ("lodi", "LODI"), ("mariano", "MAR"), ("seveso", "SEV"),
            ("pavia", "PAV"), ("bovisa", "BOV"), ("rogoredo", "ROG"),
            ("melegnano", "MEL"), ("cadorna", "CAD"), ("garibaldi", "GAR"),
            ("certosa di pavia", "CRT PV"), ("certosa", "CRT"), ("rho", "RHO"),
            ("centrale", "MI C."), ("torino porta nuova", "TO PN"),
            ("torino porta susa", "TO PS"), ("bologna", "BO C."),
            ("firenze", "FI SMN"), ("roma termini", "RM TER"),
            ("roma tiburtina", "RM TIB"), ("napoli centrale", "NA C."),
            ("salerno", "SA"), ("venezia", "VE SL"), ("verona", "VR PN"),
            ("padova", "PD"), ("bergamo", "BG"), ("brescia", "BS"),
            ("genova piazza principe", "GE PP"), ("genova brignole", "GE BR"),
            ("como lago", "CO LAGO"), ("como", "COMO"), ("chiasso", "CHIAS"),
            ("lecco", "LECCO"), ("sondrio", "SOND"), ("tirano", "TIR"),
            ("cremona", "CR"), ("mantova", "MN"), ("piacenza", "PC"),
            ("domodossola", "DOMO"), ("albairate", "ALB"), ("camnago", "CAMN"),
            ("malpensa", "MXP"), ("fiumicino", "FCO"), ("porto ceresio", "CERES"),
            ("laveno", "LAV"), ("mortara", "MORT"), ("asso", "ASSO"),
            ("edolo", "EDOLO"), ("alessandria", "AL"), ("trieste", "TS"),
            ("bolzano", "BZ"), ("brennero", "BREN"), ("ancona", "AN"),
            ("pescara", "PE"), ("bari", "BA"), ("lecce", "LE"),
            ("pisa", "PI"), ("ventimiglia", "XXM"), ("cuneo", "CN"),
            ("formia", "FORM"), ("cassino", "CASS"), ("civitavecchia", "CIVIT")
        ]
        for (needle, code) in known where lower.contains(needle) {
            return code
        }
        let cleaned = name.compactStationName
            .replacingOccurrences(of: "Milano ", with: "")
            .replacingOccurrences(of: "Torino ", with: "")
            .replacingOccurrences(of: "Roma ", with: "")
            .replacingOccurrences(of: "Napoli ", with: "")
        return String(cleaned.prefix(5)).uppercased()
    }

    static func buildCorridorLine(
        origin: String,
        destination: String,
        stopsHint: [String] = []
    ) -> PersonalRailwayLine {
        let cleanOrigin = origin.formattedStationName
        let cleanDest = destination.formattedStationName
        let normA = normalizeStationToken(cleanOrigin)
        let normB = normalizeStationToken(cleanDest)
        let orderedPair = [normA, normB].sorted()
        let id = "CORRIDOR:\(orderedPair[0])->\(orderedPair[1])"

        let shortOrigin = cleanOrigin
            .replacingOccurrences(of: "Milano ", with: "MI ")
            .prefix(8)
        let shortDest = cleanDest
            .replacingOccurrences(of: "Milano ", with: "MI ")
            .prefix(8)
        let code = "\(shortOrigin.trimmingCharacters(in: .whitespaces))–\(shortDest.trimmingCharacters(in: .whitespaces))"

        var stations = stopsHint.map { $0.formattedStationName }
        if stations.isEmpty {
            stations = [cleanOrigin, cleanDest]
        } else {
            if !stations.contains(where: { stationsLikelyMatch($0, cleanOrigin) }) {
                stations.insert(cleanOrigin, at: 0)
            }
            if !stations.contains(where: { stationsLikelyMatch($0, cleanDest) }) {
                stations.append(cleanDest)
            }
        }

        return PersonalRailwayLine(
            id: id,
            code: String(code.prefix(12)),
            name: "\(cleanOrigin) – \(cleanDest)",
            subtitle: "Direttrice personale dalle tue tratte",
            kind: .personalCorridor,
            region: "Personale",
            hexColor: "#2563EB",
            stations: stations,
            probeStations: [cleanOrigin, cleanDest],
            categoryPrefixes: ["R", "REG", "RE", "RV", "S", "IC"],
            usesPassanteTunnel: false,
            isAutoSuggested: true
        )
    }

    static func findBestCatalogLine(matchingStationA a: String, stationB b: String, category: String? = nil) -> PersonalRailwayLine? {
        let cleanCat = category?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let catTokens = Set(cleanCat.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let isExplicitAV = ["FR", "FA", "ITA", "NTV", "AV", "FRECCIAROSSA", "FRECCIARGENTO", "ITALO"].contains {
            cleanCat == $0 || catTokens.contains($0)
        }
        let isExplicitIC = ["IC", "ICN", "FB", "INTERCITY", "FRECCIABIANCA"].contains {
            cleanCat == $0 || catTokens.contains($0)
        }
        let isExplicitInternational = ["EC", "RJ", "EN", "TGV", "EUROCITY", "RAILJET", "EURONIGHT"].contains {
            cleanCat == $0 || catTokens.contains($0)
        }

        let matchingLines = curatedCatalog.filter { line in
            let hasA = line.stations.contains { stationsLikelyMatch($0, a) }
            let hasB = line.stations.contains { stationsLikelyMatch($0, b) }
            return hasA && hasB
        }

        if !cleanCat.isEmpty, !isExplicitAV, !isExplicitIC, !isExplicitInternational {
            if let codeAndRouteMatch = matchingLines.first(where: {
                $0.code.uppercased() == cleanCat || $0.id.uppercased() == cleanCat
            }) {
                return codeAndRouteMatch
            }
            if let directSub = curatedCatalog.first(where: { $0.code.uppercased() == cleanCat || $0.id.uppercased() == cleanCat }) {
                if matchingLines.isEmpty {
                    return directSub
                }
            }
        }

        guard !matchingLines.isEmpty else { return nil }

        if isExplicitAV {
            return matchingLines.first(where: { $0.kind == .highSpeed }) ?? matchingLines.first
        }
        if isExplicitIC {
            return matchingLines.first(where: { $0.kind == .intercity }) ?? matchingLines.first
        }
        if isExplicitInternational {
            return matchingLines.first(where: { $0.kind == .international })
                ?? matchingLines.first(where: { $0.categoryPrefixes.contains(cleanCat) })
                ?? matchingLines.first
        }

        return matchingLines.first(where: {
            $0.kind == .suburban || $0.kind == .regional || $0.kind == .airport
        }) ?? matchingLines.first
    }
}

// MARK: - PersonalLinesManager

@MainActor
final class PersonalLinesManager: ObservableObject {
    @Published var savedLines: [PersonalRailwayLine] = []
    @Published var suggestedLines: [SuggestedRailwayLine] = []
    @Published var hiddenStationsByLine: [String: Set<String>] = [:]
    @Published var snapshots: [String: LineLiveSnapshot] = [:]
    @Published var refreshingLineIDs: Set<String> = []
    @Published var nearbyDeparturesByLine: [String: LineNearbyDepartures] = [:]
    @Published var loadingNearbyLineIDs: Set<String> = []

    private let savedLinesKey = "personalSavedRailwayLines_v1"
    private let hiddenStationsKey = "personalLinesHiddenStations_v1"
    private let seededPassanteSyncKey = "personalLinesSeededPassanteSync_v1"
    private var resolvedStationsCache: [String: [Station]] = [:]

    init() {
        loadPersistence()
    }

    // MARK: - Persistence & Migration

    private func loadPersistence() {
        if let data = UserDefaults.standard.data(forKey: savedLinesKey),
           let decoded = try? JSONDecoder().decode([PersonalRailwayLine].self, from: data) {
            let catalogByID = Dictionary(uniqueKeysWithValues: RailwayLineCatalog.curatedCatalog.map { ($0.id, $0) })
            var didMigrate = false
            let migrated: [PersonalRailwayLine] = decoded.map { stored in
                guard let latest = catalogByID[stored.id] else { return stored }
                if stored.code != latest.code
                    || stored.name != latest.name
                    || stored.subtitle != latest.subtitle
                    || stored.kind != latest.kind
                    || stored.region != latest.region
                    || stored.categoryPrefixes != latest.categoryPrefixes
                    || stored.stations != latest.stations
                    || stored.usesPassanteTunnel != latest.usesPassanteTunnel
                    || stored.branches != latest.branches {
                    didMigrate = true
                    return latest
                }
                return stored
            }
            self.savedLines = migrated
            if didMigrate {
                savePersistence()
            }
        }

        if let data = UserDefaults.standard.data(forKey: hiddenStationsKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            self.hiddenStationsByLine = decoded.mapValues { Set($0) }
        }
    }

    private func savePersistence() {
        if let data = try? JSONEncoder().encode(savedLines) {
            UserDefaults.standard.set(data, forKey: savedLinesKey)
        }
        let encodedHidden = hiddenStationsByLine.mapValues { Array($0) }
        if let data = try? JSONEncoder().encode(encodedHidden) {
            UserDefaults.standard.set(data, forKey: hiddenStationsKey)
        }
    }

    // MARK: - Sync & Suggestions

    func syncFromExistingUserState(
        trainManager: TrainManager,
        passanteManager: PassanteManager,
        usageTracker: UsageTracker,
        commuteManager: SupporterCommuteManager
    ) {
        let hasSeededPassante = UserDefaults.standard.bool(forKey: seededPassanteSyncKey)
        if !hasSeededPassante || savedLines.isEmpty {
            for lineID in passanteManager.selectedSuburbanLines {
                if let catalogLine = RailwayLineCatalog.curatedCatalog.first(where: { $0.id == lineID }),
                   !savedLines.contains(where: { $0.id == catalogLine.id }) {
                    savedLines.append(catalogLine)
                }
            }
            UserDefaults.standard.set(true, forKey: seededPassanteSyncKey)
            savePersistence()
        } else {
            var changed = false
            for lineID in passanteManager.selectedSuburbanLines {
                if !savedLines.contains(where: { $0.id == lineID }),
                   let catalogLine = RailwayLineCatalog.curatedCatalog.first(where: { $0.id == lineID }) {
                    savedLines.append(catalogLine)
                    changed = true
                }
            }
            if changed { savePersistence() }
        }

        rebuildSuggestions(
            trainManager: trainManager,
            passanteManager: passanteManager,
            usageTracker: usageTracker,
            commuteManager: commuteManager
        )
    }

    func rebuildSuggestions(
        trainManager: TrainManager,
        passanteManager: PassanteManager,
        usageTracker: UsageTracker,
        commuteManager: SupporterCommuteManager
    ) {
        var candidates: [String: SuggestedRailwayLine] = [:]

        func register(_ line: PersonalRailwayLine, reason: String) {
            guard !isLineSaved(id: line.id) else { return }
            if candidates[line.id] == nil {
                var copy = line
                copy.isAutoSuggested = true
                candidates[line.id] = SuggestedRailwayLine(line: copy, reason: reason)
            }
        }

        // 1. From Favorite Trains
        for saved in trainManager.favoriteTrains {
            let cat = saved.resolvedCategoryCode()
            if let direct = RailwayLineCatalog.curatedCatalog.first(where: { $0.id.uppercased() == cat.uppercased() }) {
                register(direct, reason: "Dal tuo treno \(saved.fullTypeAndNumberTitle)")
                continue
            }
            let endpoints = saved.parsedEndpoints
            if let origin = endpoints.origin,
               let match = RailwayLineCatalog.findBestCatalogLine(matchingStationA: origin, stationB: endpoints.destination, category: cat) {
                register(match, reason: "Dal tuo treno \(saved.number)")
            } else if let origin = endpoints.origin {
                let stops = trainManager.liveTrainSnapshots[saved.number]?.stops.map(\.stationName) ?? []
                let corridor = RailwayLineCatalog.buildCorridorLine(origin: origin, destination: endpoints.destination, stopsHint: stops)
                register(corridor, reason: "Direttrice del treno \(saved.number)")
            }
        }

        // 2. From Favorite Routes
        for route in trainManager.favoriteRoutes {
            if let match = RailwayLineCatalog.findBestCatalogLine(matchingStationA: route.effectiveOriginName, stationB: route.effectiveDestinationName) {
                register(match, reason: "Dalla tratta \(route.effectiveOriginName.compactStationName) → \(route.effectiveDestinationName.compactStationName)")
            } else {
                let corridor = RailwayLineCatalog.buildCorridorLine(origin: route.effectiveOriginName, destination: route.effectiveDestinationName)
                register(corridor, reason: "Direttrice dalla tua tratta abituale")
            }
        }

        // 3. From Smart Passante Routes
        for smart in trainManager.smartRoutes {
            if let line = RailwayLineCatalog.findBestCatalogLine(matchingStationA: smart.originName, stationB: smart.destinationName) {
                register(line, reason: "Dalla tua tratta \(smart.originName) → \(smart.destinationName)")
            }
        }

        // 4. From Saved Trips
        for trip in trainManager.savedTrips {
            let firstCat = trip.segments.first?.trainCategory
            if let match = RailwayLineCatalog.findBestCatalogLine(matchingStationA: trip.origin, stationB: trip.destination, category: firstCat) {
                register(match, reason: "Dal tuo viaggio \(trip.origin.compactStationName) → \(trip.destination.compactStationName)")
            }
        }

        // 5. From Commute Casa <-> Lavoro
        for origin in commuteManager.origins {
            for dest in commuteManager.destinations where !RailwayLineCatalog.stationsLikelyMatch(origin, dest) {
                if let match = RailwayLineCatalog.findBestCatalogLine(matchingStationA: origin, stationB: dest) {
                    register(match, reason: "Coerente col tuo tragitto abituale")
                } else {
                    let corridor = RailwayLineCatalog.buildCorridorLine(origin: origin, destination: dest)
                    register(corridor, reason: "Direttrice del tuo tragitto abituale")
                }
            }
        }

        // 6. From UsageTracker frequently traveled routes
        var usageCounts: [String: (origin: String, dest: String, count: Int)] = [:]
        for routeUsage in usageTracker.routeUsages {
            let key = "\(RailwayLineCatalog.normalizeStationToken(routeUsage.originName))->\(RailwayLineCatalog.normalizeStationToken(routeUsage.destName))"
            var entry = usageCounts[key] ?? (routeUsage.originName, routeUsage.destName, 0)
            entry.count += 1
            usageCounts[key] = entry
        }
        for (_, item) in usageCounts where item.count >= 2 {
            if let match = RailwayLineCatalog.findBestCatalogLine(matchingStationA: item.origin, stationB: item.dest) {
                register(match, reason: "Usata spesso nelle tue ricerche")
            }
        }

        // 7. From My Stations pair matching catalog corridors
        if trainManager.myStations.count >= 2 {
            let names = trainManager.myStations.map(\.formattedName)
            for line in RailwayLineCatalog.curatedCatalog {
                let hits = names.filter { st in line.stations.contains { RailwayLineCatalog.stationsLikelyMatch($0, st) } }
                if hits.count >= 2 {
                    register(line, reason: "Collega le tue stazioni \(hits[0].compactStationName) e \(hits[1].compactStationName)")
                }
            }
        }

        let sorted = candidates.values.sorted { lhs, rhs in
            if lhs.line.kind.sortRank != rhs.line.kind.sortRank {
                return lhs.line.kind.sortRank < rhs.line.kind.sortRank
            }
            return lhs.line.name < rhs.line.name
        }
        self.suggestedLines = Array(sorted.prefix(6))
    }

    // MARK: - CRUD

    func isLineSaved(id: String) -> Bool {
        savedLines.contains(where: { $0.id == id })
    }

    func addLine(_ line: PersonalRailwayLine, passanteManager: PassanteManager? = nil) {
        guard !isLineSaved(id: line.id) else { return }
        var stored = line
        stored.isAutoSuggested = false
        savedLines.append(stored)
        suggestedLines.removeAll { $0.id == line.id }
        if line.usesPassanteTunnel,
           let passanteManager,
           SuburbanData.shared.allLines.contains(where: { $0.id == line.id }),
           !passanteManager.selectedSuburbanLines.contains(line.id) {
            passanteManager.toggleSuburbanLine(line.id)
        }
        savePersistence()
        Haptics.notify(.success)
    }

    func removeLine(id: String, passanteManager: PassanteManager? = nil) {
        savedLines.removeAll { $0.id == id }
        nearbyDeparturesByLine.removeValue(forKey: id)
        if let passanteManager, passanteManager.selectedSuburbanLines.contains(id) {
            passanteManager.toggleSuburbanLine(id)
        }
        savePersistence()
    }

    func moveSavedLines(from source: IndexSet, to destination: Int) {
        savedLines.move(fromOffsets: source, toOffset: destination)
        savePersistence()
    }

    func toggleStationVisibility(lineID: String, stationName: String, passanteManager: PassanteManager? = nil) {
        var set = hiddenStationsByLine[lineID] ?? []
        if set.contains(stationName) {
            set.remove(stationName)
        } else {
            set.insert(stationName)
        }
        hiddenStationsByLine[lineID] = set
        if let passanteManager,
           SuburbanData.shared.allLines.contains(where: { $0.id == lineID }) {
            passanteManager.toggleHiddenStation(lineId: lineID, stationName: stationName)
        }
        savePersistence()
    }

    func isStationHidden(lineID: String, stationName: String) -> Bool {
        hiddenStationsByLine[lineID]?.contains(stationName) ?? false
    }

    func visibleStations(for line: PersonalRailwayLine, passanteManager: PassanteManager? = nil) -> [String] {
        var hidden = hiddenStationsByLine[line.id] ?? []
        if let passanteManager,
           let passanteHidden = passanteManager.hiddenSuburbanStations[line.id] {
            hidden.formUnion(passanteHidden)
        }
        let filtered = line.stations.filter { !hidden.contains($0) }
        return filtered.isEmpty ? line.stations : filtered
    }

    func resolvedStations(for line: PersonalRailwayLine, trainManager: TrainManager) -> [Station] {
        let cacheKey = "\(line.id)|\(line.stations.joined(separator: "|"))"
        if let cached = resolvedStationsCache[cacheKey] {
            return cached
        }
        let passanteSub = line.usesPassanteTunnel
            ? SuburbanData.shared.allLines.first(where: { $0.id == line.id })
            : nil
        let resolved = line.stations.map { rawName in
            if let passanteMatch = passanteSub?.stations.first(where: {
                $0.name.caseInsensitiveCompare(rawName) == .orderedSame
                || $0.formattedName.caseInsensitiveCompare(rawName) == .orderedSame
            }) {
                return passanteMatch
            }
            return trainManager.resolveStation(name: rawName, fallbackVtID: nil, fallbackRfiID: nil)
        }
        resolvedStationsCache[cacheKey] = resolved
        return resolved
    }

    func visibleResolvedStations(
        for line: PersonalRailwayLine,
        trainManager: TrainManager,
        passanteManager: PassanteManager? = nil
    ) -> [Station] {
        let all = resolvedStations(for: line, trainManager: trainManager)
        var hidden = hiddenStationsByLine[line.id] ?? []
        if let passanteManager,
           let passanteHidden = passanteManager.hiddenSuburbanStations[line.id] {
            hidden.formUnion(passanteHidden)
        }
        let filtered = all.filter { st in
            !hidden.contains(where: { RailwayLineCatalog.stationsLikelyMatch($0, st.name) || RailwayLineCatalog.stationsLikelyMatch($0, st.formattedName) })
        }
        return filtered.isEmpty ? all : filtered
    }

    func nearestStation(
        on line: PersonalRailwayLine,
        visibleStations: [Station],
        activeNearby: Station?,
        userLocation: CLLocation?,
        maxDistanceMeters: Double = 10_000
    ) -> Station? {
        if let activeNearby,
           let matched = visibleStations.first(where: {
               $0.matches(activeNearby)
               || RailwayLineCatalog.stationsLikelyMatch($0.name, activeNearby.name)
               || RailwayLineCatalog.stationsLikelyMatch($0.formattedName, activeNearby.formattedName)
           }) {
            return matched
        }

        guard let userLocation else { return nil }
        var best: (station: Station, distance: CLLocationDistance)? = nil
        for station in visibleStations {
            guard let lat = station.lat, let lon = station.lon else { continue }
            let d = userLocation.distance(from: CLLocation(latitude: lat, longitude: lon))
            if d <= maxDistanceMeters, best == nil || d < best!.distance {
                best = (station, d)
            }
        }
        return best?.station
    }

    // MARK: - Pertinent News & RFI Works

    func relevantNews(for line: PersonalRailwayLine, from allNews: [NewsItem]) -> [NewsItem] {
        allNews.filter { item in
            item.isRelevantToUser(stationNames: line.stations, lineCodes: [line.code])
        }
    }

    // MARK: - Lazy On-Demand Nearby Departures (1 request only when expanded or opened)

    func refreshNearbyDepartures(
        for line: PersonalRailwayLine,
        station: Station,
        visibleStations: [Station],
        trainManager: TrainManager,
        passanteManager: PassanteManager,
        force: Bool = false
    ) async {
        let stationKey = TrainManager.canonicalStationKey(for: station)
        if !force,
           let cached = nearbyDeparturesByLine[line.id],
           cached.stationKey == stationKey,
           Date().timeIntervalSince(cached.fetchedAt) < 180 {
            return
        }
        if loadingNearbyLineIDs.contains(line.id) && !force { return }

        loadingNearbyLineIDs.insert(line.id)
        defer { loadingNearbyLineIDs.remove(line.id) }

        let rawTrains: [Train]
        if line.usesPassanteTunnel && passanteManager.selectedPassanteStation.matches(station) {
            if force || passanteManager.passanteTrains.isEmpty {
                _ = await passanteManager.fetchPassanteLive(manager: trainManager, includePositions: false, force: force)
            }
            rawTrains = passanteManager.passanteTrains
        } else {
            let board = await StationRepository.shared.getStationBoard(station: station, isDepartures: true, force: force)
            rawTrains = board.trains
        }

        let filtered = rawTrains.filter { train in
            Self.matchesLineTrain(train, boardStation: station.formattedName, line: line)
        }

        let badges = Self.computeDirectionBadges(
            trains: filtered,
            nearbyStation: station,
            visibleStations: visibleStations,
            line: line
        )

        nearbyDeparturesByLine[line.id] = LineNearbyDepartures(
            lineID: line.id,
            stationKey: stationKey,
            stationName: station.formattedName,
            directionBadges: badges,
            departures: Array(filtered.prefix(8)),
            fetchedAt: Date()
        )
    }

    nonisolated static func computeDirectionBadges(
        trains: [Train],
        nearbyStation: Station,
        visibleStations: [Station],
        line: PersonalRailwayLine,
        now: Date = Date()
    ) -> [String] {
        let nearbyIdx = visibleStations.firstIndex {
            $0.matches(nearbyStation) || RailwayLineCatalog.stationsLikelyMatch($0.formattedName, nearbyStation.formattedName)
        }

        var bucketBest: [String: (label: String, mins: Int)] = [:]
        let calendar = Calendar.current

        for train in trains {
            let lowerDelay = train.delay.lowercased()
            if lowerDelay.contains("soppresso") || lowerDelay.contains("cancellat") { continue }
            guard let mins = countdownMinutes(for: train, calendar: calendar, now: now), mins >= 0 else { continue }

            let destIdx = visibleStations.firstIndex {
                RailwayLineCatalog.stationsLikelyMatch($0.formattedName, train.destination)
                || RailwayLineCatalog.stationsLikelyMatch($0.name, train.destination)
            }

            let bucket: String
            if let nIdx = nearbyIdx, let dIdx = destIdx, dIdx != nIdx {
                bucket = dIdx < nIdx ? "START" : "END"
            } else {
                bucket = RailwayLineCatalog.normalizeStationToken(train.destination)
            }

            let shortDest = RailwayLineCatalog.shortStationAbbreviation(train.destination)
            let timeStr = mins == 0 ? "ora" : "\(mins)m"
            let text = "\(shortDest) \(timeStr)"

            if bucketBest[bucket] == nil || mins < bucketBest[bucket]!.mins {
                bucketBest[bucket] = (text, mins)
            }
        }

        return bucketBest.values
            .sorted { $0.mins < $1.mins }
            .prefix(2)
            .map(\.label)
    }

    nonisolated static func countdownMinutes(
        for train: Train,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Int? {
        let parts = train.time.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        let delayMinutes = TrainManager.parseDelayMinutes(from: train.delay) ?? 0

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let baseDate = calendar.date(from: components),
              var targetDate = calendar.date(byAdding: .minute, value: delayMinutes, to: baseDate) else {
            return nil
        }

        let diff = targetDate.timeIntervalSince(now)
        if diff < -43_200, let next = calendar.date(byAdding: .day, value: 1, to: targetDate) {
            targetDate = next
        } else if diff > 43_200, let prev = calendar.date(byAdding: .day, value: -1, to: targetDate) {
            targetDate = prev
        }

        return Int(round(targetDate.timeIntervalSince(now) / 60.0))
    }

    // MARK: - Live Snapshot Evaluation (retained for explicit refreshes & tests)

    func refreshAllSavedLinesIfNeeded(
        trainManager: TrainManager,
        passanteManager: PassanteManager,
        force: Bool = false
    ) async {
        if savedLines.contains(where: { $0.usesPassanteTunnel }) {
            await passanteManager.fetchPassanteLive(manager: trainManager, includePositions: false, force: force)
        }
        for line in savedLines {
            if !force, let snap = snapshots[line.id], Date().timeIntervalSince(snap.fetchedAt) < 45 {
                continue
            }
            await refreshSnapshot(for: line, trainManager: trainManager, passanteManager: passanteManager, force: force)
        }
    }

    func refreshSnapshot(
        for line: PersonalRailwayLine,
        trainManager: TrainManager,
        passanteManager: PassanteManager,
        force: Bool = false
    ) async {
        if refreshingLineIDs.contains(line.id) && !force { return }
        refreshingLineIDs.insert(line.id)
        defer { refreshingLineIDs.remove(line.id) }

        if line.usesPassanteTunnel && passanteManager.selectedSuburbanLines.contains(line.id) {
            await passanteManager.fetchPassanteLive(manager: trainManager, includePositions: false, force: force)
            snapshots[line.id] = evaluateSuburbanSnapshot(line: line, passanteManager: passanteManager)
            return
        }

        var collected: [LineActiveTrain] = []
        var seenNumbers: Set<String> = []
        var alerts: [String] = []

        let probes = Array((line.probeStations.isEmpty ? Array(line.stations.prefix(2)) : line.probeStations).prefix(2))
        for stationName in probes {
            let station = trainManager.resolveStation(name: stationName, fallbackVtID: nil, fallbackRfiID: nil)
            let board = await StationRepository.shared.getStationBoard(station: station, isDepartures: true, force: force)
            if let alert = board.alerts?.trimmingCharacters(in: .whitespacesAndNewlines), !alert.isEmpty {
                alerts.append(alert)
            }
            for train in board.trains {
                guard !seenNumbers.contains(train.number) else { continue }
                guard Self.matchesLineTrain(train, boardStation: stationName, line: line) else { continue }
                seenNumbers.insert(train.number)

                let delayMins = TrainManager.parseDelayMinutes(from: train.delay) ?? 0
                let isCancelled = train.delay.localizedCaseInsensitiveContains("soppresso")
                    || train.delay.localizedCaseInsensitiveContains("cancellat")
                let liveLast = trainManager.liveTrainSnapshots[train.number]?.lastStation
                    ?? passanteManager.passanteLiveStatuses[train.number]?.lastStation.nilIfDash

                collected.append(
                    LineActiveTrain(
                        train: train,
                        matchedStation: stationName,
                        liveLastStation: liveLast,
                        delayMinutes: delayMins,
                        isCancelled: isCancelled,
                        isPassanteTunnel: false
                    )
                )
            }
        }

        snapshots[line.id] = buildSnapshot(line: line, trains: collected, alerts: alerts)
    }

    private func evaluateSuburbanSnapshot(line: PersonalRailwayLine, passanteManager: PassanteManager) -> LineLiveSnapshot {
        let matchingTunnel = passanteManager.passanteTunnelTrains.filter {
            passanteManager.isTrain($0, belongingToLine: line.code)
        }
        let matchingBoard = passanteManager.passanteTrains.filter {
            passanteManager.isTrain($0, belongingToLine: line.code)
        }

        var combined: [LineActiveTrain] = []
        var seen: Set<String> = []

        for train in matchingTunnel + matchingBoard {
            guard !seen.contains(train.number) else { continue }
            seen.insert(train.number)
            let isTunnel = matchingTunnel.contains(where: { $0.number == train.number })
            let status = passanteManager.passanteLiveStatuses[train.number]
            let liveLast = status?.lastStation.nilIfDash
            let delayMins = TrainManager.parseDelayMinutes(from: train.delay) ?? 0
            let isCancelled = train.delay.localizedCaseInsensitiveContains("soppresso")
                || train.delay.localizedCaseInsensitiveContains("cancellat")
                || (status?.cancellationNote != nil)

            combined.append(
                LineActiveTrain(
                    train: train,
                    matchedStation: passanteManager.selectedPassanteStation.formattedName,
                    liveLastStation: liveLast,
                    delayMinutes: delayMins,
                    isCancelled: isCancelled,
                    isPassanteTunnel: isTunnel
                )
            )
        }

        return buildSnapshot(line: line, trains: combined, alerts: passanteManager.passanteSelectedLinesAlerts)
    }

    private func buildSnapshot(
        line: PersonalRailwayLine,
        trains: [LineActiveTrain],
        alerts: [String]
    ) -> LineLiveSnapshot {
        let cancelled = trains.filter(\.isCancelled)
        let activeDelays = trains.filter { !$0.isCancelled }.map(\.delayMinutes)
        let avgDelay = activeDelays.isEmpty ? 0 : (activeDelays.reduce(0, +) / activeDelays.count)
        let maxDelay = activeDelays.max() ?? 0
        let distinctAlerts = Array(Set(alerts))

        let health: LineHealthStatus
        if trains.isEmpty && distinctAlerts.isEmpty {
            health = .noDataYet(reason: "Nessun treno attivo rilevato ora")
        } else if !cancelled.isEmpty || maxDelay >= 20 {
            let reason = !cancelled.isEmpty
                ? "\(cancelled.count) tren\(cancelled.count == 1 ? "o soppresso" : "i soppressi")"
                : "Ritardi fino a +\(maxDelay) min"
            health = .disrupted(reason: reason)
        } else if avgDelay >= 5 || !distinctAlerts.isEmpty || activeDelays.contains(where: { $0 >= 10 }) {
            health = .warning(avgDelayMinutes: avgDelay)
        } else {
            health = .regular
        }

        var positions: [String: [LineActiveTrain]] = [:]
        for item in trains {
            guard let liveStation = item.liveLastStation else { continue }
            if let matchedNode = line.stations.first(where: { RailwayLineCatalog.stationsLikelyMatch($0, liveStation) }) {
                positions[matchedNode, default: []].append(item)
            }
        }

        return LineLiveSnapshot(
            lineID: line.id,
            health: health,
            activeTrains: trains,
            upcomingDepartures: Array(trains.prefix(8)),
            stationPositions: positions,
            alertMessages: distinctAlerts,
            fetchedAt: Date()
        )
    }

    nonisolated static func matchesLineTrain(_ train: Train, boardStation: String, line: PersonalRailwayLine) -> Bool {
        let rawCat = train.category.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCat = cleanTrainCategory(train.category).uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let catTokens = Set(rawCat.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))

        let isPureAVTrain = ["FR", "FA", "ITA", "NTV", "AV", "ES", "FRECCIAROSSA", "FRECCIARGENTO", "ITALO"].contains {
            cleanCat == $0 || catTokens.contains($0) || rawCat.contains("FRECCIAROSSA") || rawCat.contains("ITALO")
        }
        let isIntercityTrain = ["IC", "ICN", "FB", "INTERCITY", "FRECCIABIANCA"].contains {
            cleanCat == $0 || catTokens.contains($0)
        }
        let isInternationalTrain = ["EC", "RJ", "EN", "TGV", "EUROCITY", "RAILJET", "EURONIGHT"].contains {
            cleanCat == $0 || catTokens.contains($0)
        }
        let isSuburbanTrainCode: Bool = {
            guard cleanCat.hasPrefix("S"), cleanCat.count >= 2 else { return false }
            return cleanCat.dropFirst().allSatisfy(\.isNumber)
        }()
        let boardOnLine = line.stations.contains { RailwayLineCatalog.stationsLikelyMatch($0, boardStation) }

        func matchesPrefix(_ prefixList: [String]) -> Bool {
            prefixList.contains {
                let p = $0.uppercased()
                return cleanCat == p || rawCat == p || catTokens.contains(p)
            }
        }

        switch line.kind {
        case .highSpeed:
            guard isPureAVTrain else { return false }
        case .intercity:
            guard isIntercityTrain || matchesPrefix(line.categoryPrefixes) else { return false }
            if isPureAVTrain || isSuburbanTrainCode { return false }
        case .international:
            guard matchesPrefix(line.categoryPrefixes) else { return false }
        case .regional:
            let allowsAV = line.categoryPrefixes.contains(where: { ["FR", "FA", "ITA", "NTV", "AV"].contains($0.uppercased()) })
            let allowsIC = line.categoryPrefixes.contains(where: { ["IC", "ICN", "FB"].contains($0.uppercased()) })
            let allowsIntl = line.categoryPrefixes.contains(where: { ["EC", "RJ", "EN", "TGV"].contains($0.uppercased()) })
            if isPureAVTrain && !allowsAV { return false }
            if isIntercityTrain && !allowsIC { return false }
            if isInternationalTrain && !allowsIntl { return false }
            if isSuburbanTrainCode && !line.categoryPrefixes.contains(where: { $0.uppercased() == cleanCat || $0.uppercased() == "S" }) {
                return false
            }
        case .suburban:
            if isPureAVTrain || isIntercityTrain || isInternationalTrain { return false }
            if (cleanCat == line.code.uppercased() || catTokens.contains(line.code.uppercased())) && boardOnLine {
                return true
            }
            if isSuburbanTrainCode && cleanCat != line.code.uppercased() {
                return false
            }
        case .airport:
            break
        case .personalCorridor:
            break
        }

        let destMatches = line.stations.contains { RailwayLineCatalog.stationsLikelyMatch($0, train.destination) }
        let originMatches = train.origin.map { orig in
            line.stations.contains { RailwayLineCatalog.stationsLikelyMatch($0, orig) }
        } ?? false

        if !destMatches && !originMatches {
            return false
        }
        if line.id == "MXP" {
            let isMxpEndpoint = RailwayLineCatalog.stationsLikelyMatch(train.destination, "Malpensa")
                || (train.origin.map { RailwayLineCatalog.stationsLikelyMatch($0, "Malpensa") } ?? false)
            return isMxpEndpoint
        }
        if line.id == "LEO" {
            let isFcoEndpoint = RailwayLineCatalog.stationsLikelyMatch(train.destination, "Fiumicino")
                || (train.origin.map { RailwayLineCatalog.stationsLikelyMatch($0, "Fiumicino") } ?? false)
            return isFcoEndpoint
        }
        return boardOnLine && (destMatches || originMatches)
    }
}

private extension String {
    var nilIfDash: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "--" {
            return nil
        }
        return trimmed
    }
}
