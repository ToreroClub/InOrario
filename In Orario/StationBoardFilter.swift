import Foundation
import Combine

// MARK: - Filter Models

enum CommuteTargetFilter: String, Sendable, Equatable, Hashable {
    case home
    case work

    nonisolated var displayTitle: String {
        switch self {
        case .home: return String(localized: "Casa")
        case .work: return String(localized: "Lavoro")
        }
    }

    nonisolated var actionTitle: String {
        switch self {
        case .home: return String(localized: "Portami a Casa")
        case .work: return String(localized: "Portami al Lavoro")
        }
    }

    nonisolated var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .work: return "briefcase.fill"
        }
    }
}

enum TrainCategoryGroup: String, CaseIterable, Identifiable, Sendable, Hashable {
    case highSpeed
    case intercity
    case regional
    case suburban
    case airport
    case other

    nonisolated var id: String { rawValue }

    nonisolated var displayTitle: String {
        switch self {
        case .highSpeed: return String(localized: "Alta Velocità")
        case .intercity: return String(localized: "Intercity")
        case .regional: return String(localized: "Regionali")
        case .suburban: return String(localized: "Suburbani")
        case .airport: return String(localized: "Malpensa Express")
        case .other: return String(localized: "Altri")
        }
    }

    nonisolated var shortLabel: String {
        switch self {
        case .highSpeed: return String(localized: "Alta Vel.")
        case .intercity: return String(localized: "Intercity")
        case .regional: return String(localized: "Regionali")
        case .suburban: return String(localized: "Suburbani")
        case .airport: return String(localized: "MXP")
        case .other: return String(localized: "Altri")
        }
    }

    nonisolated static func suburbanLineCode(for train: Train) -> String? {
        let up = train.category.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = up.range(of: #"\bS\d{1,2}\b"#, options: .regularExpression) {
            return String(up[range])
        }
        return nil
    }

    nonisolated static func classify(_ train: Train) -> TrainCategoryGroup {
        if train.isItalo {
            return .highSpeed
        }
        let up = train.category.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if up.contains("ITALO") || up.contains("NTV") || up == "ITA" ||
           up == "FR" || up == "FA" || up == "FB" || up == "AV" ||
           up.contains("FRECCIA") || up.contains("ALTA VELOCIT") {
            return .highSpeed
        }
        if up == "IC" || up == "ICN" || up == "EC" || up.contains("INTERCITY") || up.contains("EUROCITY") {
            return .intercity
        }
        if up == "MXP" || up.contains("MALPENSA") {
            return .airport
        }
        if suburbanLineCode(for: train) != nil || up == "S" || up == "SUB" || up.contains("SUBURBAN") {
            return .suburban
        }
        if up == "REG" || up == "RV" || up == "R" || up == "RE" ||
           up.range(of: #"^RE\d*$"#, options: .regularExpression) != nil ||
           up.contains("REGIONALE") {
            return .regional
        }
        return .other
    }
}

struct CommuteTrainMatch: Sendable, Equatable {
    enum MatchSource: String, Sendable {
        case directTerminus
        case suburbanTopology
        case lefrecce
        case italo
        case viaggiaTreno
    }

    let trainNumber: String
    let matchedTargetStation: String
    let estimatedArrivalTime: String?
    let source: MatchSource

    nonisolated init(
        trainNumber: String,
        matchedTargetStation: String,
        estimatedArrivalTime: String? = nil,
        source: MatchSource
    ) {
        self.trainNumber = trainNumber
        self.matchedTargetStation = matchedTargetStation
        self.estimatedArrivalTime = estimatedArrivalTime
        self.source = source
    }
}

struct StationBoardFilterState: Equatable, Sendable {
    var commuteTarget: CommuteTargetFilter? = nil
    var selectedCategories: Set<TrainCategoryGroup> = []
    var selectedSuburbanLines: Set<String> = []
    var hideCancelled: Bool = false
    var onlyWithPlatform: Bool = false
    var onlyOnTime: Bool = false
    var onlyFavorites: Bool = false

    nonisolated init() {}

    nonisolated var isActive: Bool {
        commuteTarget != nil ||
        !selectedCategories.isEmpty ||
        !selectedSuburbanLines.isEmpty ||
        hideCancelled ||
        onlyWithPlatform ||
        onlyOnTime ||
        onlyFavorites
    }

    nonisolated var activeFilterCount: Int {
        var count = 0
        if commuteTarget != nil { count += 1 }
        count += selectedCategories.count
        count += selectedSuburbanLines.count
        if hideCancelled { count += 1 }
        if onlyWithPlatform { count += 1 }
        if onlyOnTime { count += 1 }
        if onlyFavorites { count += 1 }
        return count
    }

    nonisolated mutating func reset() {
        commuteTarget = nil
        selectedCategories = []
        selectedSuburbanLines = []
        hideCancelled = false
        onlyWithPlatform = false
        onlyOnTime = false
        onlyFavorites = false
    }

    nonisolated static func isTrainCancelled(_ train: Train) -> Bool {
        let low = train.delay.lowercased()
        return low.contains("cancellat") || low.contains("soppress")
    }

    nonisolated static func isTrainOnTime(_ train: Train) -> Bool {
        guard !isTrainCancelled(train) else { return false }
        let low = train.delay.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if low.isEmpty || low.contains("in orario") || low == "0'" {
            return true
        }
        let digits = low.filter { $0.isNumber }
        if let mins = Int(digits), !low.contains("+") && mins == 0 {
            return true
        }
        return false
    }

    nonisolated static func hasValidPlatform(_ train: Train) -> Bool {
        let plat = train.platform.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return !plat.isEmpty && plat != "--" && plat != "-" && plat != "N/D" && plat != "ND" && plat != "?"
    }

    nonisolated func commuteMatch(for train: Train, in matches: [String: CommuteTrainMatch]?) -> CommuteTrainMatch? {
        guard let matches else { return nil }
        let cleanNum = StationNameMatcher.cleanTrainDigits(train.number)
        return matches[cleanNum] ?? matches[train.number.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    nonisolated func apply(
        to trains: [Train],
        favoriteTrainNumbers: Set<String>,
        commuteMatches: [String: CommuteTrainMatch]?,
        isAlreadyAtTargetStation: Bool = false
    ) -> [Train] {
        guard isActive else { return trains }

        return trains.filter { train in
            if commuteTarget != nil && !isAlreadyAtTargetStation, let matches = commuteMatches {
                if commuteMatch(for: train, in: matches) == nil {
                    return false
                }
            }

            if !selectedCategories.isEmpty || !selectedSuburbanLines.isEmpty {
                let cat = TrainCategoryGroup.classify(train)
                let subLine = TrainCategoryGroup.suburbanLineCode(for: train)

                if !selectedSuburbanLines.isEmpty {
                    let matchesSubLine = subLine.map { selectedSuburbanLines.contains($0) } ?? false
                    let matchesOtherCategory = selectedCategories.contains(cat) && cat != .suburban
                    if !matchesSubLine && !matchesOtherCategory {
                        return false
                    }
                } else if !selectedCategories.contains(cat) {
                    return false
                }
            }

            if hideCancelled && Self.isTrainCancelled(train) {
                return false
            }

            if onlyWithPlatform && !Self.hasValidPlatform(train) {
                return false
            }

            if onlyOnTime && !Self.isTrainOnTime(train) {
                return false
            }

            if onlyFavorites {
                let cleanNum = StationNameMatcher.cleanTrainDigits(train.number)
                if !favoriteTrainNumbers.contains(train.number) && !favoriteTrainNumbers.contains(cleanNum) {
                    return false
                }
            }

            return true
        }
    }
}

// MARK: - Station Name Matcher

enum StationNameMatcher {
    nonisolated static func cleanTrainDigits(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.replacingOccurrences(
            of: #"^(?:s\d{1,2}|re\d{1,2}|r\d{1,2}|mxp|rv|fr|fa|fb|ic|icn|ec|reg|sub|treno)\b[\s\-]*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let digits = stripped.filter { $0.isNumber }
        if !digits.isEmpty {
            return digits
        }
        let fallbackDigits = trimmed.filter { $0.isNumber }
        return fallbackDigits.isEmpty ? trimmed : fallbackDigits
    }

    nonisolated static func isMilanoGaribaldi(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("garibaldi") &&
               !lower.contains("pavia") &&
               !lower.contains("casalecchio") &&
               !lower.contains("napoli")
    }

    nonisolated static func canonicalKey(_ raw: String) -> String {
        var str = raw
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "it_IT"))
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "'", with: " ")

        str = str.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if str.isEmpty { return "" }

        if isMilanoGaribaldi(str) {
            return "milano porta garibaldi"
        }

        let tokenNoise = ["passante", "superficie", "sotterranea", "sotterraneo", "sott", "fs", "f s", "politecnico"]
        var words = str.split(separator: " ").map(String.init)
        words.removeAll { tokenNoise.contains($0) }
        str = words.joined(separator: " ")

        // Espansione sicura di C.le -> Centrale (es. Bologna C.le -> Bologna Centrale)
        str = str.replacingOccurrences(of: #"\bc\s+le\b"#, with: "centrale", options: .regularExpression)

        // Gestione mirata di "Nord" solo per stazioni milanesi FNM fisicamente coincidenti
        // (mantenendo distinti Varese vs Varese Nord, Novara vs Novara Nord, Busto Arsizio vs Busto Arsizio Nord)
        let milanFNMStations = ["cadorna", "bovisa", "domodossola", "affori", "bruzzano", "quarto oggiaro"]
        for st in milanFNMStations {
            if str == "milano nord \(st)" || str == "milano \(st) nord" || str == "nord \(st)" {
                str = "milano \(st)"
                break
            }
        }

        let directAliases: [String: String] = [
            "p venezia": "milano porta venezia",
            "porta venezia": "milano porta venezia",
            "milano p venezia": "milano porta venezia",
            "p vittoria": "milano porta vittoria",
            "porta vittoria": "milano porta vittoria",
            "milano p vittoria": "milano porta vittoria",
            "p romana": "milano porta romana",
            "porta romana": "milano porta romana",
            "milano p romana": "milano porta romana",
            "s cristoforo": "milano san cristoforo",
            "san cristoforo": "milano san cristoforo",
            "milano s cristoforo": "milano san cristoforo",
            "greco p": "milano greco pirelli",
            "greco pirelli": "milano greco pirelli",
            "milano greco p": "milano greco pirelli",
            "repubblica": "milano repubblica",
            "dateo": "milano dateo",
            "lancetti": "milano lancetti",
            "villapizzone": "milano villapizzone",
            "certosa": "milano certosa",
            "forlanini": "milano forlanini",
            "bovisa": "milano bovisa",
            "rogoredo": "milano rogoredo",
            "lambrate": "milano lambrate",
            "cadorna": "milano cadorna",
            "m centrale": "milano centrale",
            "milano cle": "milano centrale",
            "rho fiera milano": "rho fiera",
            "milano expo rho": "rho fiera",
            "expo rho": "rho fiera",
            "firenze s m n": "firenze santa maria novella",
            "firenze smn": "firenze santa maria novella",
            "firenze s m novella": "firenze santa maria novella",
            "firenze santa maria novella": "firenze santa maria novella",
            "venezia s l": "venezia santa lucia",
            "venezia sl": "venezia santa lucia",
            "venezia s lucia": "venezia santa lucia",
            "venezia santa lucia": "venezia santa lucia",
            "torino p n": "torino porta nuova",
            "torino pn": "torino porta nuova",
            "torino p nuova": "torino porta nuova",
            "torino porta nuova": "torino porta nuova",
            "torino p s": "torino porta susa",
            "torino ps": "torino porta susa",
            "torino p susa": "torino porta susa",
            "torino porta di susa": "torino porta susa",
            "torino porta susa": "torino porta susa",
            "verona p n": "verona porta nuova",
            "verona pn": "verona porta nuova",
            "verona p nuova": "verona porta nuova",
            "verona porta nuova": "verona porta nuova",
            "genova p p": "genova piazza principe",
            "genova pp": "genova piazza principe",
            "genova p principe": "genova piazza principe",
            "genova piazza principe": "genova piazza principe",
            "napoli p g": "napoli piazza garibaldi",
            "napoli p garibaldi": "napoli piazza garibaldi",
            "napoli piazza garibaldi": "napoli piazza garibaldi",
            "roma term": "roma termini",
            "roma termini": "roma termini",
            "bologna centrale av": "bologna centrale",
            "bologna centrale": "bologna centrale",
            "reggio emilia av mediopadana": "reggio emilia av mediopadana",
            "reggio emilia mediopadana": "reggio emilia av mediopadana",
            "mediopadana r emilia": "reggio emilia av mediopadana",
            "corbetta s stefano ticino": "corbetta santo stefano ticino",
            "corbetta s stefano": "corbetta santo stefano ticino"
        ]
        if let mapped = directAliases[str] {
            str = mapped
        } else {
            str = str.replacingOccurrences(of: #"\bp\s+ta\b"#, with: "porta", options: .regularExpression)
            str = str.replacingOccurrences(of: #"\bp\s+(?=[a-z])"#, with: "porta ", options: .regularExpression)
        }

        // Normalizza San / Santo / Santa / Sant' -> "s" per uniformare es. Roma S. Pietro == Roma San Pietro
        str = str.replacingOccurrences(of: #"\b(?:santa|santo|sant|san)\b"#, with: "s", options: .regularExpression)
        return str.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    nonisolated static func isSameStation(_ s1: String, _ s2: String) -> Bool {
        let t1 = s1.trimmingCharacters(in: .whitespacesAndNewlines)
        let t2 = s2.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t1.isEmpty, !t2.isEmpty else { return false }

        if t1.localizedCaseInsensitiveCompare(t2) == .orderedSame {
            return true
        }
        if isMilanoGaribaldi(t1) && isMilanoGaribaldi(t2) {
            return true
        }

        let c1 = canonicalKey(t1)
        let c2 = canonicalKey(t2)
        guard !c1.isEmpty, !c2.isEmpty else { return false }
        if c1 == c2 {
            return true
        }

        // Evita falsi positivi tra stazioni omonime di città diverse (es. Milano Certosa vs Certosa di Pavia)
        if (c1 == "milano certosa" && c2.contains("pavia")) || (c2 == "milano certosa" && c1.contains("pavia")) {
            return false
        }

        let stripped1 = c1.hasPrefix("milano ") ? String(c1.dropFirst(7)) : c1
        let stripped2 = c2.hasPrefix("milano ") ? String(c2.dropFirst(7)) : c2
        if c1.hasPrefix("milano ") && c2.hasPrefix("milano ") && stripped1 == stripped2 {
            return true
        }

        return false
    }

    nonisolated static func matchesLefrecceLocation(_ loc: TrenitaliaLocation, targetStationName: String) -> Bool {
        let nUp = loc.name.uppercased()
        let dUp = loc.displayName.uppercased()
        if nUp.contains("TUTTE LE STAZIONI") || dUp.contains("TUTTE LE STAZIONI") {
            return false
        }
        return isSameStation(loc.name, targetStationName) || isSameStation(loc.displayName, targetStationName)
    }

    nonisolated static func stopsContainOrderedRoute(
        stops: [Stop],
        originStationName: String,
        targetStations: [String]
    ) -> (targetStation: String, arrivalTime: String?)? {
        guard !stops.isEmpty, !targetStations.isEmpty else { return nil }
        guard let originIdx = stops.firstIndex(where: { !$0.isSuppressed && isSameStation($0.stationName, originStationName) }) else {
            return nil
        }

        let remainingStops = stops.dropFirst(originIdx + 1)
        for stop in remainingStops {
            guard !stop.isSuppressed else { continue }
            if let matchedTarget = targetStations.first(where: { isSameStation(stop.stationName, $0) }) {
                let rawTime = stop.actualTime ?? stop.estimatedTime ?? stop.time
                let cleanTime = rawTime.trimmingCharacters(in: .whitespacesAndNewlines)
                return (matchedTarget, cleanTime.isEmpty || cleanTime == "--:--" ? nil : cleanTime)
            }
        }
        return nil
    }
}

// MARK: - Universal Commute Matcher Actor

actor StationCommuteMatcher {
    static let shared = StationCommuteMatcher()

    private struct CacheEntry {
        let timestamp: Date
        let matches: [String: CommuteTrainMatch]
    }

    private var cache: [String: CacheEntry] = [:]
    private var locationIDCache: [String: [Int]] = [:]
    private let cacheTTL: TimeInterval = 12 * 60 // 12 minuti

    private init() {}

    func clearCache() {
        cache.removeAll()
    }

    nonisolated static func delayMinutes(for train: Train) -> Int {
        let low = train.delay.lowercased()
        if low.contains("orario") || low.contains("cancellat") || low.contains("soppress") {
            return 0
        }
        let digits = train.delay.filter { $0.isNumber }
        return Int(digits) ?? 0
    }

    nonisolated static func minutesFromHHMM(_ hhmm: String?) -> Int? {
        guard let raw = hhmm?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.contains(":") else { return nil }
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else {
            return nil
        }
        return h * 60 + m
    }

    nonisolated static func arrivalSortKey(arrivalHHmm: String?, referenceMinutes: Int) -> Int {
        guard let arrMin = minutesFromHHMM(arrivalHHmm) else {
            return Int.max / 2
        }
        var delta = arrMin - referenceMinutes
        if delta < -120 {
            delta += 1440
        }
        return delta
    }

    nonisolated static func shouldPreferCandidate(
        _ candidate: CommuteTrainMatch,
        candidateTargetIndex: Int,
        over existing: CommuteTrainMatch,
        existingTargetIndex: Int,
        referenceMinutes: Int
    ) -> Bool {
        let candKey = arrivalSortKey(arrivalHHmm: candidate.estimatedArrivalTime, referenceMinutes: referenceMinutes)
        let existKey = arrivalSortKey(arrivalHHmm: existing.estimatedArrivalTime, referenceMinutes: referenceMinutes)
        if candKey != existKey {
            return candKey < existKey
        }
        return candidateTargetIndex < existingTargetIndex
    }

    func resolveMatchingTrains(
        currentStationName: String,
        boardTrains: [Train],
        targetStations: [String],
        force: Bool = false
    ) async -> [String: CommuteTrainMatch] {
        let cleanTargets = targetStations
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleanTargets.isEmpty, !boardTrains.isEmpty else { return [:] }

        let targetIndexMap: [String: Int] = {
            var map: [String: Int] = [:]
            for (idx, t) in cleanTargets.enumerated() {
                let key = StationNameMatcher.canonicalKey(t)
                if map[key] == nil { map[key] = idx }
            }
            return map
        }()

        var referenceMinutesByTrain: [String: Int] = [:]
        for tr in boardTrains {
            let cleanNum = StationNameMatcher.cleanTrainDigits(tr.number)
            if let depMin = Self.minutesFromHHMM(tr.time) {
                referenceMinutesByTrain[cleanNum] = depMin
            }
        }
        let fallbackNowComps = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let fallbackNowMinutes = (fallbackNowComps.hour ?? 0) * 60 + (fallbackNowComps.minute ?? 0)

        func insertDeterministic(
            _ candidate: CommuteTrainMatch,
            into dict: inout [String: CommuteTrainMatch]
        ) {
            let num = candidate.trainNumber
            guard let existing = dict[num] else {
                dict[num] = candidate
                return
            }
            let candIdx = targetIndexMap[StationNameMatcher.canonicalKey(candidate.matchedTargetStation)] ?? Int.max
            let existIdx = targetIndexMap[StationNameMatcher.canonicalKey(existing.matchedTargetStation)] ?? Int.max
            let refMin = referenceMinutesByTrain[num] ?? fallbackNowMinutes
            if Self.shouldPreferCandidate(
                candidate,
                candidateTargetIndex: candIdx,
                over: existing,
                existingTargetIndex: existIdx,
                referenceMinutes: refMin
            ) {
                dict[num] = candidate
            }
        }

        let cacheKey = "\(StationNameMatcher.canonicalKey(currentStationName))|\(cleanTargets.map { StationNameMatcher.canonicalKey($0) }.sorted().joined(separator: ","))"
        if !force, let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            let instantOnly = Self.computeStage0Matches(
                boardTrains: boardTrains,
                targetStations: cleanTargets
            )
            var merged = cached.matches
            for (_, m) in instantOnly where merged[m.trainNumber] == nil {
                merged[m.trainNumber] = m
            }
            return merged
        }

        // Stadio 0: Solo capolinea esatto (nessuna inferenza offline sulle fermate intermedie)
        var resolved = Self.computeStage0Matches(
            boardTrains: boardTrains,
            targetStations: cleanTargets
        )

        // Stadio 1: Query diretta LeFrecce (noChanges: true) in parallelo per ciascuna stazione target
        let lfResult = await queryLefrecceDirectMatches(
            currentStationName: currentStationName,
            targetStations: cleanTargets
        )
        for match in lfResult.matches {
            insertDeterministic(match, into: &resolved)
        }

        guard !Task.isCancelled else { return resolved }

        // Stadio 2: Eventuali treni Italo sul tabellone non ancora coperti
        let italoCandidates = boardTrains.filter { train in
            train.isItalo && resolved[StationNameMatcher.cleanTrainDigits(train.number)] == nil
        }
        if !italoCandidates.isEmpty {
            let italoMatches = await checkItaloCandidates(
                italoCandidates,
                currentStationName: currentStationName,
                targetStations: cleanTargets
            )
            for match in italoMatches {
                insertDeterministic(match, into: &resolved)
            }
        }

        guard !Task.isCancelled else { return resolved }

        // Stadio 3: Fallback ViaggiaTreno per stazioni non coperte da LeFrecce, target non risolti o treni con ritardo >= 45'
        let nonItaloUnmatched = boardTrains.filter { train in
            !train.isItalo && resolved[StationNameMatcher.cleanTrainDigits(train.number)] == nil
        }

        if !nonItaloUnmatched.isEmpty {
            if !lfResult.hadDepID || !lfResult.hadCoverage || lfResult.matches.isEmpty {
                let vtMatches = await checkViaggiaTrenoFallback(
                    Array(nonItaloUnmatched.prefix(24)),
                    currentStationName: currentStationName,
                    targetStations: cleanTargets
                )
                for match in vtMatches {
                    insertDeterministic(match, into: &resolved)
                }
            } else {
                if !lfResult.unresolvedTargets.isEmpty {
                    let vtUnresolved = await checkViaggiaTrenoFallback(
                        Array(nonItaloUnmatched.prefix(24)),
                        currentStationName: currentStationName,
                        targetStations: lfResult.unresolvedTargets
                    )
                    for match in vtUnresolved {
                        insertDeterministic(match, into: &resolved)
                    }
                }
                let highDelayUnmatched = nonItaloUnmatched.filter { Self.delayMinutes(for: $0) >= 45 }
                if !highDelayUnmatched.isEmpty {
                    let vtDelayed = await checkViaggiaTrenoFallback(
                        Array(highDelayUnmatched.prefix(12)),
                        currentStationName: currentStationName,
                        targetStations: cleanTargets
                    )
                    for match in vtDelayed {
                        insertDeterministic(match, into: &resolved)
                    }
                }
            }
        }

        if !Task.isCancelled {
            cache[cacheKey] = CacheEntry(timestamp: Date(), matches: resolved)
        }
        return resolved
    }

    nonisolated static func computeStage0Matches(
        boardTrains: [Train],
        targetStations: [String]
    ) -> [String: CommuteTrainMatch] {
        var result: [String: CommuteTrainMatch] = [:]

        for train in boardTrains {
            let cleanNum = StationNameMatcher.cleanTrainDigits(train.number)
            guard !cleanNum.isEmpty else { continue }

            // 0A: Capolinea coincide esattamente con una delle stazioni target
            if let directTarget = targetStations.first(where: { StationNameMatcher.isSameStation(train.destination, $0) }) {
                result[cleanNum] = CommuteTrainMatch(
                    trainNumber: cleanNum,
                    matchedTargetStation: directTarget,
                    estimatedArrivalTime: nil,
                    source: .directTerminus
                )
            }
        }

        return result
    }

    // MARK: - Stage 1: LeFrecce Direct Solutions

    private func resolveLefrecceLocationIDs(for stationName: String) async -> [Int] {
        let key = StationNameMatcher.canonicalKey(stationName)
        if let cached = locationIDCache[key], !cached.isEmpty {
            return cached
        }
        if StationNameMatcher.isMilanoGaribaldi(stationName) {
            let ids = [830001645, 830001662] // Superficie + Passante
            locationIDCache[key] = ids
            return ids
        }

        var queries = [stationName.trimmingCharacters(in: .whitespacesAndNewlines)]
        let canonical = StationNameMatcher.canonicalKey(stationName)
        if !canonical.isEmpty && canonical.lowercased() != queries[0].lowercased() {
            queries.append(canonical.capitalized)
        }
        if stationName.contains("-") || stationName.contains("/") {
            let spaced = stationName
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "/", with: " ")
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            if !spaced.isEmpty && !queries.contains(spaced) {
                queries.append(spaced)
            }
        }
        let upper = stationName.uppercased()
        if upper.contains("CADORNA") && !upper.contains("NORD") {
            queries.insert("Milano Nord Cadorna", at: 0)
        }

        for q in queries where !q.isEmpty {
            guard let safeQuery = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://www.lefrecce.it/Channels.Website.BFF.WEB/website/locations/search?name=\(safeQuery)") else {
                continue
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 7.0
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")

            if let (data, _) = try? await NetworkService.shared.get(request: request),
               let decoded = try? JSONDecoder().decode([TrenitaliaLocation].self, from: data),
               let matchedLoc = decoded.first(where: { StationNameMatcher.matchesLefrecceLocation($0, targetStationName: stationName) }) {
                let ids = [matchedLoc.id]
                locationIDCache[key] = ids
                return ids
            }
        }
        return []
    }

    private struct LefrecceQueryResult {
        let matches: [CommuteTrainMatch]
        let hadCoverage: Bool
        let hadDepID: Bool
        let unresolvedTargets: [String]
    }

    private func queryLefrecceDirectMatches(
        currentStationName: String,
        targetStations: [String]
    ) async -> LefrecceQueryResult {
        let depIDs = await resolveLefrecceLocationIDs(for: currentStationName)
        guard !depIDs.isEmpty else {
            return LefrecceQueryResult(matches: [], hadCoverage: false, hadDepID: false, unresolvedTargets: targetStations)
        }

        // Finestra -90 min per includere treni con ritardi importanti ancora sul tabellone
        let lookbackDate = Date().addingTimeInterval(-90 * 60)
        let isoFmt = DateFormatter()
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        isoFmt.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        isoFmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.000ZZZZZ"
        let depTimeStr = isoFmt.string(from: lookbackDate)

        // Risolvi gli ID delle stazioni target in parallelo
        var resolvedTargets: [(targetName: String, arrIDs: [Int])] = []
        await withTaskGroup(of: (String, [Int]).self) { group in
            for target in targetStations {
                group.addTask {
                    let ids = await self.resolveLefrecceLocationIDs(for: target)
                    return (target, ids)
                }
            }
            for await res in group {
                resolvedTargets.append(res)
            }
        }

        var unresolvedTargets: [String] = []
        var targetPairs: [(targetName: String, depID: Int, arrID: Int)] = []
        for entry in resolvedTargets {
            if entry.arrIDs.isEmpty {
                unresolvedTargets.append(entry.targetName)
            } else {
                for dID in depIDs {
                    for aID in entry.arrIDs where dID != aID {
                        targetPairs.append((entry.targetName, dID, aID))
                    }
                }
            }
        }

        guard !targetPairs.isEmpty else {
            return LefrecceQueryResult(matches: [], hadCoverage: false, hadDepID: true, unresolvedTargets: unresolvedTargets)
        }

        var allMatches: [CommuteTrainMatch] = []
        var anyHTTP200 = false

        await withTaskGroup(of: ([CommuteTrainMatch], Bool).self) { group in
            for pair in targetPairs {
                group.addTask {
                    await self.fetchSingleLefreccePair(
                        depID: pair.depID,
                        arrID: pair.arrID,
                        depTimeStr: depTimeStr,
                        currentStationName: currentStationName,
                        targetStationName: pair.targetName
                    )
                }
            }
            for await (pairMatches, ok) in group {
                if ok { anyHTTP200 = true }
                allMatches.append(contentsOf: pairMatches)
            }
        }

        return LefrecceQueryResult(
            matches: allMatches,
            hadCoverage: anyHTTP200,
            hadDepID: true,
            unresolvedTargets: unresolvedTargets
        )
    }

    private func fetchSingleLefreccePair(
        depID: Int,
        arrID: Int,
        depTimeStr: String,
        currentStationName: String,
        targetStationName: String
    ) async -> ([CommuteTrainMatch], Bool) {
        guard let url = URL(string: "https://www.lefrecce.it/Channels.Website.BFF.WEB/website/ticket/solutions") else {
            return ([], false)
        }
        let payload: [String: Any] = [
            "departureLocationId": depID,
            "arrivalLocationId": arrID,
            "departureTime": depTimeStr,
            "adults": 1,
            "children": 0,
            "criteria": [
                "frecceOnly": false,
                "regionalOnly": false,
                "noChanges": true,
                "order": "DEPARTURE_DATE",
                "offset": 0,
                "limit": 30
            ],
            "advancedSearchRequest": [
                "bestFare": false
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await NetworkService.shared.post(request: request)
            let is200 = (response as? HTTPURLResponse)?.statusCode == 200
            let parsed = Self.parseDirectLefrecceMatches(
                from: data,
                currentStationName: currentStationName,
                targetStationName: targetStationName
            )
            return (parsed, is200)
        } catch {
            return ([], false)
        }
    }

    nonisolated static func parseDirectLefrecceMatches(
        from data: Data,
        currentStationName: String,
        targetStationName: String
    ) -> [CommuteTrainMatch] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let solutions = json["solutions"] as? [[String: Any]] else {
            return []
        }

        let isoFmt = DateFormatter()
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        isoFmt.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        isoFmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.000ZZZZZ"

        var results: [CommuteTrainMatch] = []
        for item in solutions {
            guard let sol = item["solution"] as? [String: Any] else { continue }

            var arrHHmm: String? = nil
            if let at = sol["arrivalTime"] as? String, let d = isoFmt.date(from: at) {
                arrHHmm = SharedFormatters.time.string(from: d)
            }

            if let nodes = sol["nodes"] as? [[String: Any]] {
                // Scarta qualsiasi soluzione che contenga nodi multipli, trasporti urbani, bus o tratte a piedi
                guard nodes.count == 1, let railNode = nodes.first,
                      let tr = railNode["train"] as? [String: Any] else {
                    continue
                }
                let acronym = (tr["acronym"] as? String)?.uppercased() ?? ""
                let cat = (tr["trainCategory"] as? String)?.lowercased() ?? ""
                let denom = (tr["denomination"] as? String)?.lowercased() ?? ""
                let isUrb = (tr["urban"] as? Bool) ?? false
                if isUrb || acronym == "UB" || acronym == "WK" ||
                   ((cat.contains("urban") || denom.contains("urban") || cat.contains("metro") || cat.contains("walk")) && !cat.contains("suburbano")) {
                    continue
                }

                let nodeOrigin = (railNode["origin"] as? String) ?? (sol["origin"] as? String) ?? ""
                let nodeDest = (railNode["destination"] as? String) ?? (sol["destination"] as? String) ?? ""
                guard StationNameMatcher.isSameStation(nodeOrigin, currentStationName),
                      StationNameMatcher.isSameStation(nodeDest, targetStationName) else {
                    continue
                }

                if arrHHmm == nil, let at = railNode["arrivalTime"] as? String, let d = isoFmt.date(from: at) {
                    arrHHmm = SharedFormatters.time.string(from: d)
                }
                let rawName = (tr["name"] as? String) ?? (tr["description"] as? String) ?? ""
                let cleanNum = StationNameMatcher.cleanTrainDigits(rawName)
                guard !cleanNum.isEmpty else { continue }
                results.append(CommuteTrainMatch(
                    trainNumber: cleanNum,
                    matchedTargetStation: targetStationName,
                    estimatedArrivalTime: arrHHmm,
                    source: .lefrecce
                ))
            } else if let trains = sol["trains"] as? [[String: Any]], trains.count == 1, let firstTrain = trains.first {
                let solOrigin = (sol["origin"] as? String) ?? ""
                let solDest = (sol["destination"] as? String) ?? ""
                guard StationNameMatcher.isSameStation(solOrigin, currentStationName),
                      StationNameMatcher.isSameStation(solDest, targetStationName) else {
                    continue
                }
                let rawName = (firstTrain["name"] as? String) ?? (firstTrain["description"] as? String) ?? ""
                let cleanNum = StationNameMatcher.cleanTrainDigits(rawName)
                guard !cleanNum.isEmpty else { continue }
                results.append(CommuteTrainMatch(
                    trainNumber: cleanNum,
                    matchedTargetStation: targetStationName,
                    estimatedArrivalTime: arrHHmm,
                    source: .lefrecce
                ))
            }
        }
        return results
    }

    // MARK: - Stage 2: Italo Stops Verification

    private func checkItaloCandidates(
        _ trains: [Train],
        currentStationName: String,
        targetStations: [String]
    ) async -> [CommuteTrainMatch] {
        var matches: [CommuteTrainMatch] = []
        await withTaskGroup(of: CommuteTrainMatch?.self) { group in
            for train in trains {
                group.addTask {
                    let cleanNum = StationNameMatcher.cleanTrainDigits(train.number)
                    let stopsRes = await ItaloTrackingProvider.shared.getLiveStops(for: cleanNum)
                    guard let hit = StationNameMatcher.stopsContainOrderedRoute(
                        stops: stopsRes.stops,
                        originStationName: currentStationName,
                        targetStations: targetStations
                    ) else {
                        return nil
                    }
                    return CommuteTrainMatch(
                        trainNumber: cleanNum,
                        matchedTargetStation: hit.targetStation,
                        estimatedArrivalTime: hit.arrivalTime,
                        source: .italo
                    )
                }
            }
            for await match in group {
                if let match {
                    matches.append(match)
                }
            }
        }
        return matches
    }

    // MARK: - Stage 3: ViaggiaTreno Fallback (es. FerrovieNord / stazioni locali)

    private func checkViaggiaTrenoFallback(
        _ trains: [Train],
        currentStationName: String,
        targetStations: [String]
    ) async -> [CommuteTrainMatch] {
        var matches: [CommuteTrainMatch] = []
        let maxConcurrency = 6
        var iterator = trains.makeIterator()

        await withTaskGroup(of: CommuteTrainMatch?.self) { group in
            func enqueueNext() {
                guard let train = iterator.next() else { return }
                group.addTask {
                    let cleanNum = StationNameMatcher.cleanTrainDigits(train.number)
                    let stopsRes = await TrainRepository.shared.getLiveStops(
                        for: cleanNum,
                        category: train.category,
                        destination: train.destination,
                        origin: currentStationName,
                        scheduledTime: train.time
                    )
                    guard let hit = StationNameMatcher.stopsContainOrderedRoute(
                        stops: stopsRes.stops,
                        originStationName: currentStationName,
                        targetStations: targetStations
                    ) else {
                        return nil
                    }
                    return CommuteTrainMatch(
                        trainNumber: cleanNum,
                        matchedTargetStation: hit.targetStation,
                        estimatedArrivalTime: hit.arrivalTime,
                        source: .viaggiaTreno
                    )
                }
            }

            for _ in 0..<maxConcurrency {
                enqueueNext()
            }
            for await match in group {
                if let match {
                    matches.append(match)
                }
                enqueueNext()
            }
        }
        return matches
    }
}

// MARK: - Temporary Session Persistence (15 min sliding TTL)

struct PersistedStationFilterSession: Codable {
    var commuteTargetRaw: String?
    var selectedCategoryRaws: [String]
    var suburbanLinesByStation: [String: [String]]
    var hideCancelled: Bool
    var onlyWithPlatform: Bool
    var onlyOnTime: Bool
    var onlyFavorites: Bool
    var lastUpdatedAt: TimeInterval
}

@MainActor
final class StationBoardFilterStore {
    static let shared = StationBoardFilterStore()
    static let sessionTTL: TimeInterval = 15 * 60 // 15 minuti

    private let defaults: UserDefaults
    private let storageKey = "station_board_filter_session_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }

    func loadState(for stationName: String, hasSupport: Bool, now: Date = Date()) -> StationBoardFilterState {
        guard let data = defaults.data(forKey: storageKey),
              var session = try? JSONDecoder().decode(PersistedStationFilterSession.self, from: data) else {
            return StationBoardFilterState()
        }

        if now.timeIntervalSince1970 - session.lastUpdatedAt > Self.sessionTTL {
            clear()
            return StationBoardFilterState()
        }

        var state = StationBoardFilterState()
        if hasSupport, let raw = session.commuteTargetRaw {
            state.commuteTarget = CommuteTargetFilter(rawValue: raw)
        }
        state.selectedCategories = Set(session.selectedCategoryRaws.compactMap(TrainCategoryGroup.init(rawValue:)))
        let stKey = StationNameMatcher.canonicalKey(stationName)
        if !stKey.isEmpty {
            state.selectedSuburbanLines = Set(session.suburbanLinesByStation[stKey] ?? [])
        }
        state.hideCancelled = session.hideCancelled
        state.onlyWithPlatform = session.onlyWithPlatform
        state.onlyOnTime = session.onlyOnTime
        state.onlyFavorites = session.onlyFavorites

        // Finestra scorrevole: rinnova timestamp all'apertura di una stazione
        session.lastUpdatedAt = now.timeIntervalSince1970
        if let encoded = try? JSONEncoder().encode(session) {
            defaults.set(encoded, forKey: storageKey)
        }
        return state
    }

    func saveState(_ state: StationBoardFilterState, for stationName: String, now: Date = Date()) {
        var session: PersistedStationFilterSession
        if let data = defaults.data(forKey: storageKey),
           let existing = try? JSONDecoder().decode(PersistedStationFilterSession.self, from: data),
           now.timeIntervalSince1970 - existing.lastUpdatedAt <= Self.sessionTTL {
            session = existing
        } else {
            session = PersistedStationFilterSession(
                commuteTargetRaw: nil,
                selectedCategoryRaws: [],
                suburbanLinesByStation: [:],
                hideCancelled: false,
                onlyWithPlatform: false,
                onlyOnTime: false,
                onlyFavorites: false,
                lastUpdatedAt: now.timeIntervalSince1970
            )
        }

        session.commuteTargetRaw = state.commuteTarget?.rawValue
        session.selectedCategoryRaws = state.selectedCategories.map(\.rawValue).sorted()
        session.hideCancelled = state.hideCancelled
        session.onlyWithPlatform = state.onlyWithPlatform
        session.onlyOnTime = state.onlyOnTime
        session.onlyFavorites = state.onlyFavorites

        let stKey = StationNameMatcher.canonicalKey(stationName)
        if !stKey.isEmpty {
            if state.selectedSuburbanLines.isEmpty {
                session.suburbanLinesByStation.removeValue(forKey: stKey)
            } else {
                session.suburbanLinesByStation[stKey] = state.selectedSuburbanLines.sorted()
            }
        }

        let hasAnyGlobal = session.commuteTargetRaw != nil ||
            !session.selectedCategoryRaws.isEmpty ||
            session.hideCancelled ||
            session.onlyWithPlatform ||
            session.onlyOnTime ||
            session.onlyFavorites

        if !hasAnyGlobal && session.suburbanLinesByStation.isEmpty {
            clear()
            return
        }

        session.lastUpdatedAt = now.timeIntervalSince1970
        if let encoded = try? JSONEncoder().encode(session) {
            defaults.set(encoded, forKey: storageKey)
        }
    }
}

// MARK: - View Filter Controller

@MainActor
final class StationBoardFilterController: ObservableObject {
    @Published var filterState = StationBoardFilterState()
    @Published var commuteMatches: [String: CommuteTrainMatch]? = nil
    @Published var isResolvingCommute: Bool = false
    @Published var isAlreadyAtTargetStation: Bool = false

    private let store: StationBoardFilterStore
    private var resolveTask: Task<Void, Never>? = nil
    private var lastResolvedBoardSignature: String = ""
    private var restoredStationKey: String? = nil

    init(store: StationBoardFilterStore = .shared) {
        self.store = store
    }

    func restorePersistedFilters(
        for stationName: String,
        boardTrains: [Train],
        commuteManager: SupporterCommuteManager,
        hasSupport: Bool
    ) {
        let stKey = StationNameMatcher.canonicalKey(stationName)
        guard restoredStationKey != stKey else { return }
        restoredStationKey = stKey

        let restored = store.loadState(for: stationName, hasSupport: hasSupport)
        filterState = restored

        if let target = restored.commuteTarget {
            let targetStations = (target == .home) ? commuteManager.origins : commuteManager.destinations
            resolveCommute(
                target: target,
                currentStationName: stationName,
                boardTrains: boardTrains,
                targetStations: targetStations,
                force: false
            )
        }
    }

    func persistCurrentFilters(for stationName: String) {
        guard restoredStationKey != nil else { return }
        store.saveState(filterState, for: stationName)
    }

    func clearCommuteTarget(for stationName: String? = nil) {
        resolveTask?.cancel()
        resolveTask = nil
        filterState.commuteTarget = nil
        commuteMatches = nil
        isResolvingCommute = false
        isAlreadyAtTargetStation = false
        lastResolvedBoardSignature = ""
        if let stationName {
            store.saveState(filterState, for: stationName)
        }
    }

    func resetAll(for stationName: String? = nil) {
        resolveTask?.cancel()
        resolveTask = nil
        filterState.reset()
        commuteMatches = nil
        isResolvingCommute = false
        isAlreadyAtTargetStation = false
        lastResolvedBoardSignature = ""
        if let stationName {
            store.saveState(filterState, for: stationName)
        }
    }

    func toggleCommuteTarget(
        _ target: CommuteTargetFilter,
        currentStationName: String,
        boardTrains: [Train],
        targetStations: [String]
    ) {
        if filterState.commuteTarget == target {
            clearCommuteTarget(for: currentStationName)
            return
        }

        filterState.commuteTarget = target
        store.saveState(filterState, for: currentStationName)
        resolveCommute(
            target: target,
            currentStationName: currentStationName,
            boardTrains: boardTrains,
            targetStations: targetStations,
            force: false
        )
    }

    func refreshCommuteIfNeeded(
        currentStationName: String,
        boardTrains: [Train],
        commuteManager: SupporterCommuteManager,
        force: Bool = false
    ) {
        guard let target = filterState.commuteTarget else { return }
        let targetStations = (target == .home) ? commuteManager.origins : commuteManager.destinations
        let sig = "\(target.rawValue)|\(StationNameMatcher.canonicalKey(currentStationName))|\(boardTrains.map(\.number).joined(separator: ","))|\(targetStations.joined(separator: ","))"
        if !force && sig == lastResolvedBoardSignature && (commuteMatches != nil || isAlreadyAtTargetStation) {
            return
        }
        resolveCommute(
            target: target,
            currentStationName: currentStationName,
            boardTrains: boardTrains,
            targetStations: targetStations,
            force: force
        )
    }

    private func resolveCommute(
        target: CommuteTargetFilter,
        currentStationName: String,
        boardTrains: [Train],
        targetStations: [String],
        force: Bool
    ) {
        resolveTask?.cancel()

        let cleanTargets = targetStations
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if cleanTargets.contains(where: { StationNameMatcher.isSameStation(currentStationName, $0) }) {
            isAlreadyAtTargetStation = true
            isResolvingCommute = false
            commuteMatches = nil
            return
        }

        isAlreadyAtTargetStation = false
        guard !cleanTargets.isEmpty else {
            isResolvingCommute = false
            commuteMatches = [:]
            return
        }

        guard !boardTrains.isEmpty else {
            isResolvingCommute = false
            commuteMatches = nil
            return
        }

        // Applica subito Stage 0A (capolinea esatto) così i diretti al capolinea compaiono senza attesa
        let instant = StationCommuteMatcher.computeStage0Matches(
            boardTrains: boardTrains,
            targetStations: cleanTargets
        )
        commuteMatches = instant.isEmpty ? nil : instant
        isResolvingCommute = true

        let sig = "\(target.rawValue)|\(StationNameMatcher.canonicalKey(currentStationName))|\(boardTrains.map(\.number).joined(separator: ","))|\(cleanTargets.joined(separator: ","))"
        resolveTask = Task { [weak self] in
            let matches = await StationCommuteMatcher.shared.resolveMatchingTrains(
                currentStationName: currentStationName,
                boardTrains: boardTrains,
                targetStations: cleanTargets,
                force: force
            )
            guard let self, !Task.isCancelled else { return }
            self.commuteMatches = matches
            self.isResolvingCommute = false
            self.lastResolvedBoardSignature = sig
        }
    }
}

// MARK: - Commute Arrival Row Formatter

enum CommuteArrivalFormatter {
    nonisolated static let maxTextCharacters = 30

    nonisolated static func nonSpaceCount(_ text: String) -> Int {
        text.filter { !$0.isWhitespace }.count
    }

    nonisolated static func abbreviatePorta(_ station: String) -> String {
        station.replacingOccurrences(
            of: #"\bPorta\b"#,
            with: "P.",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    nonisolated static func abbreviateMilano(_ station: String) -> String {
        station.replacingOccurrences(
            of: #"\bMilano\b"#,
            with: "Mi.",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    nonisolated static func formatLine(station: String, arrivalTime: String?) -> String {
        if let arr = arrivalTime?.trimmingCharacters(in: .whitespacesAndNewlines), !arr.isEmpty {
            return String(format: String(localized: "Arrivo a %@ alle %@"), station, arr)
        }
        return String(format: String(localized: "Ferma a %@"), station)
    }

    @MainActor
    static func displayCandidates(stationName: String, arrivalTime: String?) -> [String] {
        let baseStation = stationName.formattedStationName
        let fullText = formatLine(station: baseStation, arrivalTime: arrivalTime)
        let portaStation = abbreviatePorta(baseStation)
        let portaText = formatLine(station: portaStation, arrivalTime: arrivalTime)
        let milanoStation = abbreviateMilano(portaStation)
        let milanoText = formatLine(station: milanoStation, arrivalTime: arrivalTime)

        func deduplicated(_ items: [String]) -> [String] {
            var seen = Set<String>()
            return items.filter { seen.insert($0).inserted }
        }

        if nonSpaceCount(fullText) <= maxTextCharacters {
            return deduplicated([fullText, portaText, milanoText])
        }
        if portaText != fullText {
            return deduplicated([portaText, milanoText])
        }
        return milanoText != fullText ? [milanoText] : [fullText]
    }
}
