import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Smart Query Models

struct SmartTrainQuery: Codable, Equatable, Sendable {
    enum IntentKind: String, Codable, Sendable {
        case routeSolutions
        case trainAtTimeFromStation
        case stationBoard
        case trainStatus
        case unknown
    }

    let kind: IntentKind
    let originStation: String?
    let destinationStation: String?
    let targetDate: String?          // YYYY-MM-DD
    let targetTime: String?          // HH:mm
    let trainNumber: String?
    let isArrivals: Bool
    let confidence: Double
    let normalizedSummary: String?
    let clarification: String?
    var engineUsed: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case originStation = "origin_station"
        case destinationStation = "destination_station"
        case targetDate = "target_date"
        case targetTime = "target_time"
        case trainNumber = "train_number"
        case isArrivals = "is_arrivals"
        case confidence
        case normalizedSummary = "normalized_summary"
        case clarification
        case engineUsed = "engine_used"
    }

    init(
        kind: IntentKind,
        originStation: String? = nil,
        destinationStation: String? = nil,
        targetDate: String? = nil,
        targetTime: String? = nil,
        trainNumber: String? = nil,
        isArrivals: Bool = false,
        confidence: Double = 1.0,
        normalizedSummary: String? = nil,
        clarification: String? = nil,
        engineUsed: String? = nil
    ) {
        self.kind = kind
        self.originStation = originStation
        self.destinationStation = destinationStation
        self.targetDate = targetDate
        self.targetTime = targetTime
        self.trainNumber = trainNumber
        self.isArrivals = isArrivals
        self.confidence = confidence
        self.normalizedSummary = normalizedSummary
        self.clarification = clarification
        self.engineUsed = engineUsed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = (try? c.decode(String.self, forKey: .kind)) ?? "unknown"
        self.kind = IntentKind(rawValue: rawKind) ?? .unknown
        self.originStation = try? c.decodeIfPresent(String.self, forKey: .originStation)
        self.destinationStation = try? c.decodeIfPresent(String.self, forKey: .destinationStation)
        self.targetDate = try? c.decodeIfPresent(String.self, forKey: .targetDate)
        self.targetTime = try? c.decodeIfPresent(String.self, forKey: .targetTime)
        self.trainNumber = try? c.decodeIfPresent(String.self, forKey: .trainNumber)
        self.isArrivals = (try? c.decodeIfPresent(Bool.self, forKey: .isArrivals)) ?? false
        self.confidence = (try? c.decodeIfPresent(Double.self, forKey: .confidence)) ?? 0.0
        self.normalizedSummary = try? c.decodeIfPresent(String.self, forKey: .normalizedSummary)
        self.clarification = try? c.decodeIfPresent(String.self, forKey: .clarification)
        self.engineUsed = try? c.decodeIfPresent(String.self, forKey: .engineUsed)
    }

    /// Combina `targetDate` (YYYY-MM-DD) e `targetTime` (HH:mm) nel fuso orario `Europe/Rome`.
    func resolvedDate(now: Date = Date()) -> Date {
        var cal = Calendar(identifier: .gregorian)
        let romeTZ = TimeZone(identifier: "Europe/Rome") ?? .current
        cal.timeZone = romeTZ

        var baseComponents = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)

        if let dateStr = targetDate?.trimmingCharacters(in: .whitespacesAndNewlines),
           dateStr.count == 10 {
            let parts = dateStr.split(separator: "-")
            if parts.count == 3,
               let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) {
                baseComponents.year = y
                baseComponents.month = m
                baseComponents.day = d
            }
        }

        if let timeStr = targetTime?.trimmingCharacters(in: .whitespacesAndNewlines),
           timeStr.contains(":") {
            let parts = timeStr.split(separator: ":")
            if parts.count == 2,
               let hh = Int(parts[0]), let mm = Int(parts[1]),
               (0...23).contains(hh), (0...59).contains(mm) {
                baseComponents.hour = hh
                baseComponents.minute = mm
                baseComponents.second = 0

                // Se l'utente chiede solo un'ora senza data esplicita e l'ora è già passata di oltre 6 ore oggi, lascia oggi a meno che targetDate sia esplicita
            }
        } else if targetDate != nil, let baseToday = cal.dateComponents([.year, .month, .day], from: now).day,
                  baseComponents.day != baseToday {
            baseComponents.hour = 8
            baseComponents.minute = 0
            baseComponents.second = 0
        }

        return cal.date(from: baseComponents) ?? now
    }

    func displaySummary(fallbackQuery: String) -> String {
        if let clean = SmartQueryPostProcessor.cleanOptString(normalizedSummary),
           clean != "..." {
            return clean
        }
        switch kind {
        case .routeSolutions:
            if let orig = SmartQueryPostProcessor.cleanOptString(originStation),
               let dest = SmartQueryPostProcessor.cleanOptString(destinationStation) {
                return "\(orig.formattedStationName) → \(dest.formattedStationName)"
            }
            if let dest = SmartQueryPostProcessor.cleanOptString(destinationStation) {
                return "Percorso verso \(dest.formattedStationName)"
            }
        case .trainAtTimeFromStation:
            let orig = SmartQueryPostProcessor.cleanOptString(originStation)?.formattedStationName ?? "stazione"
            let t = SmartQueryPostProcessor.cleanOptString(targetTime) ?? "--:--"
            return "Treno delle \(t) da \(orig)"
        case .stationBoard:
            let st = (SmartQueryPostProcessor.cleanOptString(originStation) ?? SmartQueryPostProcessor.cleanOptString(destinationStation))?.formattedStationName ?? ""
            return "\(isArrivals ? "Arrivi" : "Partenze") \(st)".trimmingCharacters(in: .whitespaces)
        case .trainStatus:
            if let num = SmartQueryPostProcessor.cleanOptString(trainNumber) {
                return "Stato treno \(num)"
            }
        case .unknown:
            break
        }
        return fallbackQuery
    }
}

enum SmartQueryPostProcessor {
    private static let garbageValues: Set<String> = [
        "nessuna", "nessuno", "null", "none", "n/a", "na", "qui",
        "posizione", "la mia posizione", "posizione attuale",
        "stazione vicina", "stazione gps", "gps", "...",
        "non disponibile", "sconosciuta", "nessuna stazione", "vuota"
    ]

    private static let italianHourWords: [String: Int] = [
        "mezzanotte": 0, "una": 1, "due": 2, "tre": 3, "quattro": 4,
        "cinque": 5, "sei": 6, "sette": 7, "otto": 8, "nove": 9,
        "dieci": 10, "undici": 11, "dodici": 12, "mezzogiorno": 12,
        "tredici": 13, "quattordici": 14, "quindici": 15, "sedici": 16,
        "diciassette": 17, "diciotto": 18, "diciannove": 19, "venti": 20,
        "ventuno": 21, "ventidue": 22, "ventitre": 23, "ventitré": 23
    ]

    private static let italianWeekdayMap: [(pattern: String, calendarWeekday: Int)] = [
        (#"\bdomenica\b"#, 1),
        (#"\bluned[iì]\b"#, 2),
        (#"\bmarted[iì]\b"#, 3),
        (#"\bmercoled[iì]\b"#, 4),
        (#"\bgioved[iì]\b"#, 5),
        (#"\bvenerd[iì]\b"#, 6),
        (#"\bsabato\b"#, 7)
    ]

    static func cleanOptString(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if garbageValues.contains(trimmed.lowercased()) {
            return nil
        }
        return trimmed
    }

    static func relativeDateString(daysOffset: Int, from now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let target = cal.date(byAdding: .day, value: daysOffset, to: now) ?? now
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = cal.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: target)
    }

    static func extractTargetDate(from rawQuery: String, now: Date = Date()) -> String? {
        let lower = rawQuery.lowercased()
        if lower.contains("dopodomani") || lower.contains("dopo domani") {
            return relativeDateString(daysOffset: 2, from: now)
        }
        if lower.contains("domani") {
            return relativeDateString(daysOffset: 1, from: now)
        }
        if lower.contains("oggi") || lower.contains("stamattina") || lower.contains("stamane") || lower.contains("stasera") || lower.contains("stanotte") {
            return relativeDateString(daysOffset: 0, from: now)
        }

        // Data esplicita dd/mm o dd/mm/yyyy
        let nsRange = NSRange(rawQuery.startIndex..<rawQuery.endIndex, in: rawQuery)
        if let regex = try? NSRegularExpression(pattern: #"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#),
           let match = regex.firstMatch(in: rawQuery, range: nsRange),
           let rD = Range(match.range(at: 1), in: rawQuery),
           let rM = Range(match.range(at: 2), in: rawQuery),
           let day = Int(rawQuery[rD]), let month = Int(rawQuery[rM]),
           (1...31).contains(day), (1...12).contains(month) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
            var year = cal.component(.year, from: now)
            if match.range(at: 3).location != NSNotFound,
               let rY = Range(match.range(at: 3), in: rawQuery),
               let parsedY = Int(rawQuery[rY]) {
                year = parsedY < 100 ? (2000 + parsedY) : parsedY
            }
            if let dt = cal.date(from: DateComponents(year: year, month: month, day: day)) {
                let fmt = DateFormatter()
                fmt.locale = Locale(identifier: "en_US_POSIX")
                fmt.timeZone = cal.timeZone
                fmt.dateFormat = "yyyy-MM-dd"
                return fmt.string(from: dt)
            }
        }

        // Giorni della settimana in italiano (es. "lunedì", "venerdì prossimo")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let currentWeekday = cal.component(.weekday, from: now)
        for item in italianWeekdayMap {
            if lower.range(of: item.pattern, options: .regularExpression) != nil {
                var diff = (item.calendarWeekday - currentWeekday + 7) % 7
                if diff == 0 && (lower.contains("prossim") || lower.contains("settimana")) {
                    diff = 7
                }
                return relativeDateString(daysOffset: diff, from: now)
            }
        }
        return nil
    }

    private static func parseHourToken(_ rawToken: String) -> Int? {
        let cleaned = rawToken
            .lowercased()
            .replacingOccurrences(of: "l'", with: "")
            .replacingOccurrences(of: "l’", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Int(cleaned), (0...23).contains(n) {
            return n
        }
        return italianHourWords[cleaned]
    }

    private static func applyPartOfDayPM(_ hour: Int, in lowerQuery: String) -> Int {
        guard (1...11).contains(hour) else { return hour }
        let hasPMHint = lowerQuery.contains("pomeriggio") ||
            lowerQuery.contains("di sera") ||
            lowerQuery.contains("la sera") ||
            lowerQuery.contains("stasera") ||
            lowerQuery.contains("del pomeriggio")
        let hasAMHint = lowerQuery.contains("mattina") ||
            lowerQuery.contains("stamattina") ||
            lowerQuery.contains("di notte") ||
            lowerQuery.contains("stanotte")
        if hasPMHint && !hasAMHint {
            return hour + 12
        }
        return hour
    }

    static func extractExplicitTime(from rawQuery: String, now: Date = Date()) -> String? {
        let lower = rawQuery.lowercased().replacingOccurrences(of: "’", with: "'")
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)

        // 1. Formato HH:MM / HH.MM / HH,MM
        if let regexColon = try? NSRegularExpression(pattern: #"\b(\d{1,2})[:.,](\d{2})\b"#),
           let match = regexColon.firstMatch(in: lower, range: range),
           let rH = Range(match.range(at: 1), in: lower),
           let rM = Range(match.range(at: 2), in: lower),
           let rawH = Int(lower[rH]), let mm = Int(lower[rM]),
           (0...23).contains(rawH), (0...59).contains(mm) {
            let hh = applyPartOfDayPM(rawH, in: lower)
            return String(format: "%02d:%02d", hh, mm)
        }

        // 2. Parlato con preposizione + ora e minuti: "alle 18 e 19", "delle 18 19", "dalle 18 e 30", "alle 8 e 5"
        if let regexSpokenHM = try? NSRegularExpression(pattern: #"\b(?:(?:a\s+partire\s+)?(?:dalle|alle)(?:\s+ore)?|delle|verso\s+le|dopo\s+le|prima\s+delle|entro\s+le|intorno\s+alle|ore)\s+(\d{1,2})\s*(?:e\s+(\d{1,2})|(\d{2}))\b"#),
           let match = regexSpokenHM.firstMatch(in: lower, range: range),
           let rH = Range(match.range(at: 1), in: lower),
           let rawH = Int(lower[rH]), (0...23).contains(rawH) {
            let rM = match.range(at: 2).location != NSNotFound ? Range(match.range(at: 2), in: lower) : Range(match.range(at: 3), in: lower)
            if let rM, let mm = Int(lower[rM]), (0...59).contains(mm) {
                let hh = applyPartOfDayPM(rawH, in: lower)
                return String(format: "%02d:%02d", hh, mm)
            }
        }

        // 3. Parlato senza preposizione ma chiaramente HH e MM a due cifre: "18 e 19"
        if let regexBareSpokenHM = try? NSRegularExpression(pattern: #"\b(\d{1,2})\s+e\s+(\d{2})\b"#),
           let match = regexBareSpokenHM.firstMatch(in: lower, range: range),
           let rH = Range(match.range(at: 1), in: lower),
           let rM = Range(match.range(at: 2), in: lower),
           let rawH = Int(lower[rH]), let mm = Int(lower[rM]),
           (0...23).contains(rawH), (0...59).contains(mm) {
            let hh = applyPartOfDayPM(rawH, in: lower)
            return String(format: "%02d:%02d", hh, mm)
        }

        let hourWordPattern = #"(\d{1,2}|l'una|una|due|tre|quattro|cinque|sei|sette|otto|nove|dieci|undici|dodici|tredici|quattordici|quindici|sedici|diciassette|diciotto|diciannove|venti|ventuno|ventidue|ventitre|ventitré|mezzogiorno|mezzanotte)"#

        // 4. Frazioni dell'ora: "alle 8 meno un quarto" -> 07:45
        if let regexMenoQuarto = try? NSRegularExpression(pattern: #"\b(?:(?:a\s+partire\s+)?(?:dall'|dalle(?:\s+ore)?|all'|alle(?:\s+ore)?)|delle|verso\s+le|dopo\s+le|prima\s+delle|ore)\s*"# + hourWordPattern + #"\s+meno\s+(?:un\s+quarto|15|quindici)\b"#),
           let match = regexMenoQuarto.firstMatch(in: lower, range: range),
           let rH = Range(match.range(at: 1), in: lower),
           let rawH = parseHourToken(String(lower[rH])) {
            let adjH = applyPartOfDayPM(rawH, in: lower)
            return String(format: "%02d:45", (adjH + 23) % 24)
        }

        // 5. "alle 8 e mezza / e un quarto / e tre quarti"
        if let regexFraction = try? NSRegularExpression(pattern: #"\b(?:(?:a\s+partire\s+)?(?:dall'|dalle(?:\s+ore)?|all'|alle(?:\s+ore)?)|delle|verso\s+le|dopo\s+le|prima\s+delle|ore)\s*"# + hourWordPattern + #"\s+e\s+(mezz[ao]|un\s+quarto|quarto|tre\s+quarti)\b"#),
           let match = regexFraction.firstMatch(in: lower, range: range),
           let rH = Range(match.range(at: 1), in: lower),
           let rF = Range(match.range(at: 2), in: lower),
           let rawH = parseHourToken(String(lower[rH])) {
            let frac = String(lower[rF])
            let mm = frac.contains("mezz") ? 30 : (frac.contains("tre") ? 45 : 15)
            let hh = (rawH == 1 && !lower.contains("notte")) ? 13 : applyPartOfDayPM(rawH, in: lower)
            return String(format: "%02d:%02d", hh, mm)
        }

        // 6. Offset relativi ("tra mezz'ora", "fra 20 minuti", "tra un'ora")
        var romeCal = Calendar(identifier: .gregorian)
        romeCal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        if lower.range(of: #"\b(?:tra|fra)\s+(?:un\s+)?quarto\s+d'?ora\b"#, options: .regularExpression) != nil {
            let dt = romeCal.date(byAdding: .minute, value: 15, to: now) ?? now
            let c = romeCal.dateComponents([.hour, .minute], from: dt)
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
        if lower.range(of: #"\b(?:tra|fra)\s+mezz'?ora\b"#, options: .regularExpression) != nil {
            let dt = romeCal.date(byAdding: .minute, value: 30, to: now) ?? now
            let c = romeCal.dateComponents([.hour, .minute], from: dt)
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
        if lower.range(of: #"\b(?:tra|fra)\s+(?:un'?|una\s+)ora\s+e\s+mezz[ao]\b"#, options: .regularExpression) != nil {
            let dt = romeCal.date(byAdding: .minute, value: 90, to: now) ?? now
            let c = romeCal.dateComponents([.hour, .minute], from: dt)
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
        if lower.range(of: #"\b(?:tra|fra)\s+(?:un'?|una\s+)ora\b"#, options: .regularExpression) != nil {
            let dt = romeCal.date(byAdding: .minute, value: 60, to: now) ?? now
            let c = romeCal.dateComponents([.hour, .minute], from: dt)
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
        if let regexRelMin = try? NSRegularExpression(pattern: #"\b(?:tra|fra)\s+(\d{1,3})\s+minut[oi]\b"#),
           let match = regexRelMin.firstMatch(in: lower, range: range),
           let rM = Range(match.range(at: 1), in: lower),
           let mins = Int(lower[rM]) {
            let dt = romeCal.date(byAdding: .minute, value: mins, to: now) ?? now
            let c = romeCal.dateComponents([.hour, .minute], from: dt)
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
        if let regexRelHr = try? NSRegularExpression(pattern: #"\b(?:tra|fra)\s+(\d{1,2})\s+or[ea]\b"#),
           let match = regexRelHr.firstMatch(in: lower, range: range),
           let rH = Range(match.range(at: 1), in: lower),
           let hrs = Int(lower[rH]) {
            let dt = romeCal.date(byAdding: .hour, value: hrs, to: now) ?? now
            let c = romeCal.dateComponents([.hour, .minute], from: dt)
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }

        // 7. Idiomi ("mezzogiorno", "mezzanotte", "all'una")
        if lower.range(of: #"\bmezzogiorno\s+e\s+mezz[ao]\b"#, options: .regularExpression) != nil {
            return "12:30"
        }
        if lower.range(of: #"\bmezzogiorno\b"#, options: .regularExpression) != nil {
            return "12:00"
        }
        if lower.range(of: #"\bmezzanotte\s+e\s+mezz[ao]\b"#, options: .regularExpression) != nil {
            return "00:30"
        }
        if lower.range(of: #"\bmezzanotte\b"#, options: .regularExpression) != nil {
            return "00:00"
        }
        if lower.range(of: #"\b(?:a\s+partire\s+)?(?:all'|dall')\s*(?:1|una)\b"#, options: .regularExpression) != nil {
            return lower.contains("notte") ? "01:00" : "13:00"
        }

        // 8. Ora intera ("domani alle 12", "a partire dalle 18", "dalle 18", "alle 4 del pomeriggio", "verso le nove", "entro le 9")
        if let regexHour = try? NSRegularExpression(pattern: #"\b(?:(?:a\s+partire\s+)?(?:dalle|alle)(?:\s+ore)?|delle|verso\s+le|dopo\s+le|prima\s+delle|entro\s+le|intorno\s+alle|ore)\s+"# + hourWordPattern + #"\b"#),
           let match = regexHour.firstMatch(in: lower, range: range),
           let rH = Range(match.range(at: 1), in: lower),
           let rawH = parseHourToken(String(lower[rH])) {
            let hh = applyPartOfDayPM(rawH, in: lower)
            return String(format: "%02d:00", hh)
        }

        return nil
    }

    static func preprocessMessySpeech(_ raw: String) -> String {
        var s = raw
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }

        // 1. Ricomponi nomi stazione spezzati dal dettato vocale iOS
        let dictationJoins: [(String, String)] = [
            (#"\babbiate\s+grasso\b"#, "Abbiategrasso"),
            (#"\bdomo\s+d['’]?ossola\b"#, "Domodossola"),
            (#"\bca\s+dorna\b"#, "Cadorna"),
            (#"\brogo\s+redo\b"#, "Rogoredo"),
            (#"\bporta\s+mi\b"#, "portami"),
            (#"\bdopo\s+domani\b"#, "dopodomani")
        ]
        for (pat, rep) in dictationJoins {
            s = s.replacingOccurrences(of: pat, with: rep, options: [.regularExpression, .caseInsensitive])
        }

        // 2. Gestione autocorrezioni parlate ("a Milano Centrale anzi no Porta Garibaldi", "alle 18 anzi alle 19")
        let correctionTimePattern = #"(?:\b(?:alle|delle|verso\s+le|dopo\s+le|prima\s+delle|entro\s+le)\s+)?\d{1,2}(?:[:.,]\d{2}|\s+e\s+(?:\d{1,2}|mezz[ao]|un\s+quarto))?\s+(?:anzi\s+no|o\s+meglio|no\s+scusa|cio[eè]\s+volevo\s+dire|volevo\s+dire|anzi)\s+(?=(?:alle|delle|verso\s+le|dopo\s+le|prima\s+delle|entro\s+le)\s+\d)"#
        s = s.replacingOccurrences(of: correctionTimePattern, with: "", options: [.regularExpression, .caseInsensitive])

        let correctionWithNextPrepPattern = #"(?:\b(?:a|ad|al|all'|in|per|verso|da|dal|dalla|dall')\s+)(?:\S+\s+){1,4}?(?:anzi\s+no|o\s+meglio|no\s+scusa|cio[eè]\s+volevo\s+dire|volevo\s+dire|anzi)\s+(?=(?:a|ad|al|all'|in|per|verso|da|dal|dalla|dall')\b)"#
        s = s.replacingOccurrences(of: correctionWithNextPrepPattern, with: "", options: [.regularExpression, .caseInsensitive])

        let correctionKeepPrepPattern = #"(\b(?:a|ad|al|all'|in|per|verso|da|dal|dalla|dall')\s+)(?:\S+\s+){1,4}?(?:anzi\s+no|o\s+meglio|no\s+scusa|cio[eè]\s+volevo\s+dire|volevo\s+dire|anzi)\s+"#
        s = s.replacingOccurrences(of: correctionKeepPrepPattern, with: "$1", options: [.regularExpression, .caseInsensitive])

        // 3. Rimuovi esitazioni parlate e intercalari umani ovunque nella frase
        let hesitationPattern = #"\b(?:ehm+|uhm+|mmm+|allora|dunque|praticamente|diciamo|scusami|scusa|senti|guarda|ascolta|per\s+favore|per\s+piacere|grazie|tipo)\b"#
        s = s.replacingOccurrences(of: hesitationPattern, with: " ", options: [.regularExpression, .caseInsensitive])

        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isArrivalDeadlineQuery(_ rawQuery: String) -> Bool {
        let lower = rawQuery.lowercased().replacingOccurrences(of: "’", with: "'")
        return lower.range(
            of: #"\b(?:devo\s+essere|essere\s+(?:a|in|l[iì])|per\s+essere(?:\s+l[iì])?|voglio\s+essere|vorrei\s+arrivare|devo\s+arrivare|arrivare\s+(?:a|in|entro)|entro\s+le)\b"#,
            options: .regularExpression
        ) != nil
    }

    static func shiftTimeString(_ hhmm: String, byMinutes delta: Int) -> String {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else {
            return hhmm
        }
        var total = (h * 60 + m + delta) % 1440
        if total < 0 { total += 1440 }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func extractPartOfDayDefaultTime(from rawQuery: String, targetDateStr: String?, now: Date = Date()) -> String? {
        let lower = rawQuery.lowercased()
        var romeCal = Calendar(identifier: .gregorian)
        romeCal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let todayStr = relativeDateString(daysOffset: 0, from: now)
        let isToday = (targetDateStr == nil || targetDateStr == todayStr)
        let nowComps = romeCal.dateComponents([.hour, .minute], from: now)
        let nowMins = (nowComps.hour ?? 0) * 60 + (nowComps.minute ?? 0)
        let nowHHmm = String(format: "%02d:%02d", nowComps.hour ?? 0, nowComps.minute ?? 0)

        if lower.contains("tra poco") || lower.contains("a breve") {
            return nowHHmm
        }
        if lower.contains("mattina presto") || lower.contains("all'alba") {
            return "06:30"
        }
        if lower.contains("tarda mattinata") {
            return "11:00"
        }
        if lower.contains("dopo pranzo") || lower.contains("primo pomeriggio") {
            if isToday && nowMins >= 14 * 60 && nowMins < 16 * 60 { return nowHHmm }
            return "14:00"
        }
        if lower.contains("tardo pomeriggio") {
            if isToday && nowMins >= 17 * 60 + 30 && nowMins < 19 * 60 { return nowHHmm }
            return "17:30"
        }
        if lower.contains("ora di cena") || lower.contains("prima di cena") {
            return "19:30"
        }
        if lower.contains("dopo cena") {
            return "21:30"
        }
        if lower.contains("stamattina") || lower.contains("stamani") || lower.contains("mattina") {
            if isToday && nowMins >= 8 * 60 && nowMins < 12 * 60 {
                return nowHHmm
            }
            return "08:00"
        }
        if lower.contains("pomeriggio") {
            if isToday && nowMins >= 14 * 60 + 30 && nowMins < 19 * 60 {
                return nowHHmm
            }
            return "14:30"
        }
        if lower.contains("stasera") || lower.range(of: #"\b(?:di|la)\s+sera\b"#, options: .regularExpression) != nil {
            if isToday && nowMins >= 19 * 60 + 30 && nowMins < 23 * 60 {
                return nowHHmm
            }
            return "19:30"
        }
        if lower.contains("stanotte") || lower.range(of: #"\bdi\s+notte\b"#, options: .regularExpression) != nil {
            return "23:00"
        }
        return nil
    }

    static func cleanTrainDigits(_ raw: String?) -> String? {
        guard let cleaned = cleanOptString(raw) else { return nil }
        let stripped = cleaned.replacingOccurrences(
            of: #"^(?:s\d{1,2}|re\d{1,2}|r\d{1,2}|mxp|rv|fr|fa|fb|ic|ec|reg|sub|treno)\b[\s\-]*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let digits = stripped.filter { $0.isNumber }
        return digits.isEmpty ? nil : digits
    }

    static func stripTemporalAndFillerTokens(_ fragment: String) -> String {
        var s = fragment.replacingOccurrences(of: "’", with: "'")
        let patterns = [
            #"\b(?:dopo\s+domani|dopodomani|domani|oggi|stamattina|stamani|stasera|stanotte)\b"#,
            #"\b(?:mattina\s+presto|all'alba|tarda\s+mattinata|dopo\s+pranzo|primo\s+pomeriggio|tardo\s+pomeriggio|ora\s+di\s+cena|prima\s+di\s+cena|dopo\s+cena|tra\s+poco|a\s+breve)\b"#,
            #"\b(?:di|nel|nella|il|la)?\s*(?:pomeriggio|mattina|sera|notte)\b"#,
            #"\b(?:di\s+)?(?:luned[iì]|marted[iì]|mercoled[iì]|gioved[iì]|venerd[iì]|sabato|domenica)(?:\s+prossim[oa])?\b"#,
            #"\b\d{1,2}/\d{1,2}(?:/\d{2,4})?\b"#,
            #"\b(?:(?:a\s+partire\s+)?(?:dalle|alle)(?:\s+ore)?|delle|verso\s+le|dopo\s+le|prima\s+delle|entro\s+le|intorno\s+alle|ore)\s+(?:\d{1,2}|una|due|tre|quattro|cinque|sei|sette|otto|nove|dieci|undici|dodici|tredici|quattordici|quindici|sedici|diciassette|diciotto|diciannove|venti|ventuno|ventidue|ventitre|ventitré)(?:[:.,]\d{2}|\s+e\s+(?:\d{1,2}|mezz[ao]|un\s+quarto|tre\s+quarti)|\s+meno\s+(?:un\s+quarto|15|quindici))?\b"#,
            #"\b(?:a\s+partire\s+)?(?:all'|dall')\s*(?:1|una)(?:\s+e\s+(?:mezz[ao]|un\s+quarto|tre\s+quarti))?\b"#,
            #"\b\d{1,2}[:.]\d{2}\b"#,
            #"\b(?:a|verso|dopo|prima\s+di)?\s*(?:mezzogiorno|mezzanotte)(?:\s+e\s+mezz[ao])?\b"#,
            #"\b(?:tra|fra)\s+(?:un\s+quarto\s+d'?ora|mezz'?ora|un'?ora(?:\s+e\s+mezz[ao])?|\d{1,3}\s+(?:minut[oi]|or[ea]))\b"#,
            #"\b(?:a\s+partire\s+(?:da|dal|dalla|dall'|dalle)|per\s+favore|per\s+piacere|grazie|subito|adesso)\b"#
        ]
        for p in patterns {
            s = s.replacingOccurrences(of: p, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: #"[?!.,]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b(?:di|il|lo|la|per|alle|delle|dalle|entro|ora|a\s+partire)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func resolvePersonalPlace(
        _ rawCandidate: String?,
        otherEndpoint: String?,
        nearbyStation: String?,
        homeStations: [String],
        workStations: [String],
        favoriteStations: [String] = []
    ) -> (station: String?, missingPersonalPlace: String?) {
        guard let clean = cleanOptString(rawCandidate) else {
            return (nil, nil)
        }
        let low = clean.lowercased().replacingOccurrences(of: "’", with: "'")
        let otherLow = cleanOptString(otherEndpoint)?.lowercased()

        func pickCandidate(from list: [String]) -> String? {
            let unique = list.compactMap { cleanOptString($0) }
            guard !unique.isEmpty else { return nil }
            if let otherLow, !otherLow.isEmpty {
                if let diff = unique.first(where: {
                    let cLow = $0.lowercased()
                    return cLow != otherLow && !cLow.contains(otherLow) && !otherLow.contains(cLow)
                }) {
                    return diff
                }
            }
            return unique.first
        }

        let isHome = low == "casa" || low == "casa mia" || low == "a casa" || low == "da casa" ||
                     low == "verso casa" || low == "per casa" || low == "stazione di casa"
        if isHome {
            let pool = !homeStations.isEmpty ? homeStations : favoriteStations
            if let resolved = pickCandidate(from: pool) {
                return (resolved, nil)
            }
            return (nil, "casa")
        }

        let isWork = low == "lavoro" || low == "al lavoro" || low == "dal lavoro" ||
                     low == "ufficio" || low == "in ufficio" || low == "dall'ufficio" || low == "ufficio mio"
        if isWork {
            if let resolved = pickCandidate(from: workStations) {
                return (resolved, nil)
            }
            return (nil, "lavoro")
        }

        if low == "qui" || low == "da qui" || low == "posizione" || low == "mia posizione" || low == "stazione vicina" {
            if let nearby = cleanOptString(nearbyStation) {
                return (nearby, nil)
            }
            return (nil, "gps")
        }

        return (clean, nil)
    }

    static func refine(
        parsed: SmartTrainQuery,
        rawQuery: String,
        nearbyStation: String?,
        homeStations: [String] = [],
        workStations: [String] = [],
        favoriteStations: [String] = [],
        now: Date = Date()
    ) -> SmartTrainQuery {
        var kind = parsed.kind
        var orig = cleanOptString(parsed.originStation)
        var dest = cleanOptString(parsed.destinationStation)
        var targetDate = cleanOptString(parsed.targetDate)
        var targetTime = cleanOptString(parsed.targetTime)
        var clarification = cleanOptString(parsed.clarification)
        let trainNum = cleanTrainDigits(parsed.trainNumber)
        let lower = preprocessMessySpeech(rawQuery).lowercased().replacingOccurrences(of: "’", with: "'")
        let cleanRaw = preprocessMessySpeech(rawQuery)

        // 1. Forza orario esplicito dalla frase (es. "11:34", "18 e 19", "domani alle 12")
        if let explicitTime = extractExplicitTime(from: cleanRaw, now: now) {
            if parsed.engineUsed != "local_exact" && isArrivalDeadlineQuery(cleanRaw) {
                targetTime = shiftTimeString(explicitTime, byMinutes: -50)
            } else {
                targetTime = explicitTime
            }
        } else if let t = targetTime, let normT = extractExplicitTime(from: t, now: now) {
            targetTime = normT
        }

        // 2. Forza date relative / giorni settimana su fuso Europe/Rome
        if let extractedDate = extractTargetDate(from: cleanRaw, now: now) {
            targetDate = extractedDate
        }

        // 3. Controlla se la frase ha sintassi inversa ("portami a B da A", "treno per B da A", "torno a casa da A")
        let revPattern = #"(?:portami|accompagnami|voglio\s+andare|vorrei\s+andare|devo\s+andare|come\s+(?:arrivo|vado|faccio\s+a[d]?\s+andare)|torno|tornare|treno|treni|soluzioni?)\s+(?:a|ad|al|all'|in|verso|per)\s+(.+?)\s+(?:da|partendo\s+da|dal|dalla|dall')\s+(.+)$"#
        if let revRegex = try? NSRegularExpression(pattern: revPattern, options: .caseInsensitive) {
            let r = NSRange(cleanRaw.startIndex..<cleanRaw.endIndex, in: cleanRaw)
            if let match = revRegex.firstMatch(in: cleanRaw, range: r),
               let rDest = Range(match.range(at: 1), in: cleanRaw),
               let rOrig = Range(match.range(at: 2), in: cleanRaw) {
                let destCleaned = stripTemporalAndFillerTokens(String(cleanRaw[rDest]))
                let origCleaned = stripTemporalAndFillerTokens(String(cleanRaw[rOrig]))
                if !destCleaned.isEmpty && !origCleaned.isEmpty {
                    kind = .routeSolutions
                    dest = cleanOptString(destCleaned) ?? dest
                    orig = cleanOptString(origCleaned) ?? orig
                }
            }
        }

        // 4. Proteggi richieste GPS / solo destinazione ("portami a ...", "come arrivo a ...") senza "da ..."
        let hasFromPreposition = lower.range(of: #"\s+(?:da|dal|dalla|dall')\s+"#, options: .regularExpression) != nil
        let isDestinationOnlyRequest = (lower.contains("portami") || lower.contains("accompagnami") || lower.contains("come arrivo") || lower.contains("come vado") || lower.contains("andare a ") || lower.contains("andare al ") || lower.contains("andare in ")) && !hasFromPreposition
        if isDestinationOnlyRequest {
            kind = .routeSolutions
            if dest == nil {
                if let origCandidate = orig,
                   nearbyStation == nil || origCandidate.lowercased() != nearbyStation?.lowercased() {
                    dest = origCandidate
                    orig = nil
                } else {
                    let pattern = #"(?:portami|accompagnami|come\s+(?:faccio\s+a[d]?\s+andare|arrivo|vado)|voglio\s+andare|vorrei\s+andare|devo\s+andare|andare)\s+(?:a|ad|al|all'|in|verso|per)\s+(.+?)$"#
                    if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                        let r = NSRange(rawQuery.startIndex..<rawQuery.endIndex, in: rawQuery)
                        if let match = regex.firstMatch(in: rawQuery, range: r),
                           let rDest = Range(match.range(at: 1), in: rawQuery) {
                            let stripped = stripTemporalAndFillerTokens(String(rawQuery[rDest]))
                            dest = cleanOptString(stripped)
                        }
                    }
                }
            }
        }

        // 5. Risolvi luoghi personali ("casa", "lavoro", "ufficio", "qui") su entrambi i capi
        let resDest = resolvePersonalPlace(
            dest,
            otherEndpoint: orig,
            nearbyStation: nearbyStation,
            homeStations: homeStations,
            workStations: workStations,
            favoriteStations: favoriteStations
        )
        dest = resDest.station
        let resOrig = resolvePersonalPlace(
            orig,
            otherEndpoint: dest,
            nearbyStation: nearbyStation,
            homeStations: homeStations,
            workStations: workStations,
            favoriteStations: favoriteStations
        )
        orig = resOrig.station

        if resDest.missingPersonalPlace == "casa" || resOrig.missingPersonalPlace == "casa" {
            kind = .unknown
            clarification = "Per usare \"casa\" imposta la tua stazione di casa in Routine Pendolare o nella scheda Stazioni."
        } else if resDest.missingPersonalPlace == "lavoro" || resOrig.missingPersonalPlace == "lavoro" {
            kind = .unknown
            clarification = "Per usare \"lavoro\" imposta la tua stazione di lavoro in Routine Pendolare."
        }

        if isDestinationOnlyRequest && clarification == nil {
            if let cleanNearby = cleanOptString(nearbyStation) {
                if orig == nil || (dest != nil && orig!.lowercased() == dest!.lowercased()) {
                    orig = cleanNearby
                }
            } else if let origCheck = orig, let destCheck = dest, origCheck.lowercased() == destCheck.lowercased() {
                orig = nil
            }
        }

        // 6. Proteggi "treno delle HH:MM da <stazione>" senza destinazione
        if (lower.contains("treno delle") || lower.contains("treno dalle")) && lower.contains(" da ") && dest == nil {
            kind = .trainAtTimeFromStation
        }

        // 7. Se manca ancora un orario esplicito ma c'è "pomeriggio" / "stasera" / "stamattina", applica fascia realistica
        if targetTime == nil && (kind == .routeSolutions || kind == .trainAtTimeFromStation) {
            targetTime = extractPartOfDayDefaultTime(from: rawQuery, targetDateStr: targetDate, now: now)
        }

        // 8. Normalizza eventuali alias noti sugli endpoint (es. "Milano porta garibaldi" -> "Milano Porta Garibaldi")
        if let o = orig {
            orig = LocalExactQueryParser.applyKnownAlias(o)
        }
        if let d = dest {
            dest = LocalExactQueryParser.applyKnownAlias(d)
        }

        let draft = SmartTrainQuery(
            kind: kind,
            originStation: orig,
            destinationStation: dest,
            targetDate: targetDate,
            targetTime: targetTime,
            trainNumber: trainNum,
            isArrivals: parsed.isArrivals,
            confidence: (kind == .unknown ? min(parsed.confidence, 0.5) : max(parsed.confidence, 0.85)),
            normalizedSummary: cleanOptString(parsed.normalizedSummary),
            clarification: clarification,
            engineUsed: parsed.engineUsed
        )
        let summary = draft.displaySummary(fallbackQuery: rawQuery)
        return SmartTrainQuery(
            kind: draft.kind,
            originStation: draft.originStation,
            destinationStation: draft.destinationStation,
            targetDate: draft.targetDate,
            targetTime: draft.targetTime,
            trainNumber: draft.trainNumber,
            isArrivals: draft.isArrivals,
            confidence: draft.confidence,
            normalizedSummary: summary,
            clarification: draft.clarification,
            engineUsed: draft.engineUsed
        )
    }
}

enum SmartQueryEngineChoice: Equatable, Sendable {
    case geminiCloud
    case appleIntelligence
    case localExactOnly
}

enum SmartQueryEnginePolicy {
    static func resolve(hasSupport: Bool, hasAppleIntelligence: Bool) -> SmartQueryEngineChoice {
        if hasSupport { return .geminiCloud }
        if hasAppleIntelligence { return .appleIntelligence }
        return .localExactOnly
    }

    static func resolve(
        hasSupport: Bool,
        hasAppleIntelligence: Bool,
        aiModeChoice: AIFeatureManager.AIMode
    ) -> SmartQueryEngineChoice {
        switch aiModeChoice {
        case .local:
            if hasAppleIntelligence { return .appleIntelligence }
            return hasSupport ? .geminiCloud : .localExactOnly
        case .cloud:
            if hasSupport { return .geminiCloud }
            return hasAppleIntelligence ? .appleIntelligence : .localExactOnly
        case .none:
            return .localExactOnly
        }
    }
}

enum SmartQueryParseOutcome: Sendable {
    case parsed(SmartTrainQuery)
    case needsUpgrade(String)
    case clarification(String)
    case error(String)
}

enum SmartQueryExecutionResult: Sendable {
    case trainAtTime(train: Train?, station: Station, boardSample: [Train], requestedTime: String)
    case trainStatus(train: Train)
    case solutions(solutions: [TravelSolution], origin: String, destination: String, originID: String, destID: String, searchDate: Date)
    case stationBoard(station: Station, isArrivals: Bool)
    case message(String)

    var isSuccessfulForHistory: Bool {
        switch self {
        case .trainStatus, .stationBoard:
            return true
        case .solutions(let solutions, _, _, _, _, _):
            return !solutions.isEmpty
        case .trainAtTime(let train, _, let boardSample, _):
            return train != nil || !boardSample.isEmpty
        case .message:
            return false
        }
    }

    var telemetrySummary: String {
        switch self {
        case .solutions(let solutions, let origin, let destination, _, _, _):
            if solutions.isEmpty {
                return "Nessuna soluzione trovata (\(origin.formattedStationName) → \(destination.formattedStationName))"
            }
            return "\(solutions.count) soluzioni (\(origin.formattedStationName) → \(destination.formattedStationName))"
        case .trainAtTime(let train, let station, let sample, let requestedTime):
            let stName = station.name.formattedStationName
            if let t = train {
                return "Treno \(t.category) \(t.number) alle \(t.time) da \(stName)"
            }
            return "Treno delle \(requestedTime) da \(stName) non trovato (\(sample.count) vicini)"
        case .trainStatus(let train):
            return "Treno \(train.number) (\(train.destination.formattedStationName))"
        case .stationBoard(let station, let isArrivals):
            return "Tabellone \(isArrivals ? "Arrivi" : "Partenze") \(station.name.formattedStationName)"
        case .message(let text):
            return String(text.prefix(240))
        }
    }
}

struct SmartQueryParseReport: Sendable {
    let outcome: SmartQueryParseOutcome
    let parsedSnapshot: SmartTrainQuery?
    let engineUsed: String
}

// MARK: - Parser Deterministico Avanzato (Layer 1 Locale Addestrato)

enum LocalExactQueryParser {
    private static let stationAliasMap: [String: String] = [
        // Hub cittadini / Milano
        "milano": "Milano",
        "mi": "Milano",
        "centrale": "Milano Centrale",
        "milano centrale": "Milano Centrale",
        "milanocentrale": "Milano Centrale",
        "garibaldi": "Milano Porta Garibaldi",
        "porta garibaldi": "Milano Porta Garibaldi",
        "milano garibaldi": "Milano Porta Garibaldi",
        "milano p. garibaldi": "Milano Porta Garibaldi",
        "milano porta garibaldi": "Milano Porta Garibaldi",
        "garibbaldi": "Milano Porta Garibaldi",
        "porta garibbaldi": "Milano Porta Garibaldi",
        "cadorna": "Milano Nord Cadorna",
        "milano cadorna": "Milano Nord Cadorna",
        "milano nord cadorna": "Milano Nord Cadorna",
        "cadorno": "Milano Nord Cadorna",
        "ca dorna": "Milano Nord Cadorna",
        "lambrate": "Milano Lambrate",
        "milano lambrate": "Milano Lambrate",
        "rogoredo": "Milano Rogoredo",
        "milano rogoredo": "Milano Rogoredo",
        "rogo redo": "Milano Rogoredo",
        "repubblica": "Milano Repubblica",
        "milano repubblica": "Milano Repubblica",
        "porta venezia": "Milano Porta Venezia",
        "milano porta venezia": "Milano Porta Venezia",
        "dateo": "Milano Dateo",
        "milano dateo": "Milano Dateo",
        "porta vittoria": "Milano Porta Vittoria",
        "milano porta vittoria": "Milano Porta Vittoria",
        "lancetti": "Milano Lancetti",
        "milano lancetti": "Milano Lancetti",
        "bovisa": "Milano Bovisa Politecnico",
        "milano bovisa": "Milano Bovisa Politecnico",
        "milano bovisa politecnico": "Milano Bovisa Politecnico",
        "certosa": "Milano Certosa",
        "milano certosa": "Milano Certosa",
        "forlanini": "Milano Forlanini",
        "milano forlanini": "Milano Forlanini",
        "villapizzone": "Milano Villapizzone",
        "milano villapizzone": "Milano Villapizzone",
        "greco pirelli": "Milano Greco Pirelli",
        "milano greco pirelli": "Milano Greco Pirelli",
        "san cristoforo": "Milano San Cristoforo",
        "milano san cristoforo": "Milano San Cristoforo",
        "romolo": "Milano Romolo",
        "milano romolo": "Milano Romolo",
        "tibaldi": "Milano Tibaldi",
        "milano tibaldi": "Milano Tibaldi",
        // Linea S6 / Ovest / Piemonte / Lombardia
        "magenta": "Magenta",
        "maggenta": "Magenta",
        "corbetta": "Corbetta-S.Stefano Ticino",
        "corbeta": "Corbetta-S.Stefano Ticino",
        "santo stefano": "Corbetta-S.Stefano Ticino",
        "santo stefano ticino": "Corbetta-S.Stefano Ticino",
        "corbetta santo stefano": "Corbetta-S.Stefano Ticino",
        "vittuone": "Vittuone-Arluno",
        "vituone": "Vittuone-Arluno",
        "vittuone arluno": "Vittuone-Arluno",
        "pregnana": "Pregnana Milanese",
        "pregnana milanese": "Pregnana Milanese",
        "rho": "Rho",
        "ro": "Rho",
        "rho fiera": "Rho Fiera",
        "rho fiera milano": "Rho Fiera",
        "rho-fiera milano": "Rho Fiera",
        "ro fiera": "Rho Fiera",
        "trecate": "Trecate",
        "novara": "Novara",
        "domodossola": "Domodossola",
        "domo d'ossola": "Domodossola",
        "arona": "Arona",
        "stresa": "Stresa",
        "verbania": "Verbania-Pallanza",
        "gallarate": "Gallarate",
        "busto arsizio": "Busto Arsizio",
        "legnano": "Legnano",
        "parabiago": "Parabiago",
        "varese": "Varese",
        "como": "Como S. Giovanni",
        "como san giovanni": "Como S. Giovanni",
        "saronno": "Saronno",
        "malpensa": "Malpensa Aeroporto Terminal 1",
        "malpensa t1": "Malpensa Aeroporto Terminal 1",
        "malpensa t2": "Malpensa Aeroporto Terminal 2",
        "monza": "Monza",
        "sesto san giovanni": "Sesto S. Giovanni",
        "pioltello": "Pioltello-Limito",
        "pioltelo": "Pioltello-Limito",
        "pioltello limito": "Pioltello-Limito",
        "treviglio": "Treviglio",
        "bergamo": "Bergamo",
        "brescia": "Brescia",
        "pavia": "Pavia",
        "lodi": "Lodi",
        "cremona": "Cremona",
        "mantova": "Mantova",
        "lecco": "Lecco",
        "vercelli": "Vercelli",
        // Principali città italiane
        "torino": "Torino Porta Nuova",
        "torino porta nuova": "Torino Porta Nuova",
        "porta nuova": "Torino Porta Nuova",
        "torino porta susa": "Torino Porta Susa",
        "porta susa": "Torino Porta Susa",
        "roma": "Roma Termini",
        "roma termini": "Roma Termini",
        "termini": "Roma Termini",
        "roma tiburtina": "Roma Tiburtina",
        "tiburtina": "Roma Tiburtina",
        "bologna": "Bologna Centrale",
        "bologna centrale": "Bologna Centrale",
        "firenze": "Firenze Santa Maria Novella",
        "firenze smn": "Firenze Santa Maria Novella",
        "firenze santa maria novella": "Firenze Santa Maria Novella",
        "napoli": "Napoli Centrale",
        "napoli centrale": "Napoli Centrale",
        "venezia": "Venezia Santa Lucia",
        "venezia santa lucia": "Venezia Santa Lucia",
        "venezia mestre": "Venezia Mestre",
        "mestre": "Venezia Mestre",
        "genova": "Genova Piazza Principe",
        "genova piazza principe": "Genova Piazza Principe",
        "genova brignole": "Genova Brignole",
        "verona": "Verona Porta Nuova",
        "verona porta nuova": "Verona Porta Nuova",
        "padova": "Padova",
        "trieste": "Trieste Centrale",
        "parma": "Parma",
        "piacenza": "Piacenza",
        "reggio emilia": "Reggio Emilia",
        "modena": "Modena",
        "pisa": "Pisa Centrale",
        "bari": "Bari Centrale"
    ]

    static func parse(query raw: String, knownStations: [RFIStation]) -> SmartTrainQuery? {
        parse(
            query: raw,
            knownStations: knownStations,
            nearbyStation: nil,
            homeStations: [],
            workStations: [],
            favoriteStations: [],
            favoriteTrains: [],
            now: Date()
        )
    }

    static func parse(
        query raw: String,
        knownStations: [RFIStation],
        nearbyStation: String? = nil,
        homeStations: [String] = [],
        workStations: [String] = [],
        favoriteStations: [String] = [],
        favoriteTrains: [String] = [],
        now: Date = Date()
    ) -> SmartTrainQuery? {
        let preprocessed = SmartQueryPostProcessor.preprocessMessySpeech(raw)
        let trimmed = preprocessed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let targetDate = SmartQueryPostProcessor.extractTargetDate(from: trimmed, now: now)
        let explicitTime = SmartQueryPostProcessor.extractExplicitTime(from: trimmed, now: now)
        let isArrivalDeadline = explicitTime != nil && SmartQueryPostProcessor.isArrivalDeadlineQuery(trimmed)
        let adjustedExplicitTime = isArrivalDeadline
            ? explicitTime.map { SmartQueryPostProcessor.shiftTimeString($0, byMinutes: -50) }
            : explicitTime
        let targetTime = adjustedExplicitTime ?? SmartQueryPostProcessor.extractPartOfDayDefaultTime(from: trimmed, targetDateStr: targetDate, now: now)

        var working = trimmed
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r?!.,;:"))

        let fillerPrefixPattern = #"^(?:(?:ciao|ehi|hey|scusa|senti|per\s+favore|per\s+piacere|mi\s+dici|puoi\s+dirmi|dimmi|vorrei\s+sapere|sai\s+dirmi|mostrami|fammi\s+vedere|trovami|cercami|cerca|vedi)\s+)+"#
        if let fRegex = try? NSRegularExpression(pattern: fillerPrefixPattern, options: .caseInsensitive) {
            let r = NSRange(working.startIndex..<working.endIndex, in: working)
            working = fRegex.stringByReplacingMatches(in: working, range: r, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !working.isEmpty else { return nil }
        let structuralQuery = SmartQueryPostProcessor.stripTemporalAndFillerTokens(working)

        // 1. Stato treno (es. "24627", "s6 24627", "dov'è il treno 24627", "ritardo 2017")
        let trainPattern = #"^(?:(?:dov['’]?[eè]|dove\s+si\s+trova|stato(?:\s+del)?|che\s+ritardo\s+ha|ritardo(?:\s+del)?|binario(?:\s+del)?|fermate(?:\s+del)?|info(?:\s+sul)?|il|lo)\s+)*(?:(?:treno|frecciarossa|frecciargento|frecciabianca|italo|intercity|eurocity|regionale\s+veloce|regionale|suburbano|rv|reg|fr|fa|fb|ic|ec|s\d{1,2})\s+)*(?:il\s+)?(\d{2,6})(?:\s+(?:adesso|ora|oggi|in\s+ritardo))?$"#
        if let regex = try? NSRegularExpression(pattern: trainPattern, options: .caseInsensitive) {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            if let match = regex.firstMatch(in: working, range: range),
               let r1 = Range(match.range(at: 1), in: working) {
                let num = String(working[r1])
                return SmartTrainQuery(
                    kind: .trainStatus,
                    trainNumber: num,
                    confidence: 1.0,
                    normalizedSummary: "Stato treno \(num)",
                    engineUsed: "local_exact"
                )
            }
        }
        let lowerWorking = working.lowercased()
        if (lowerWorking == "il mio treno" || lowerWorking == "dov'è il mio treno" || lowerWorking == "dove è il mio treno" || lowerWorking == "mio treno"),
           let favTrain = favoriteTrains.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            let cleanNum = SmartQueryPostProcessor.cleanTrainDigits(favTrain) ?? favTrain
            return SmartTrainQuery(
                kind: .trainStatus,
                trainNumber: cleanNum,
                confidence: 0.94,
                normalizedSummary: "Stato treno \(cleanNum)",
                engineUsed: "local_exact"
            )
        }

        // Helper locale per risolvere endpoint (Casa/Lavoro/GPS oppure stazione reale)
        func resolveEndpoint(_ rawPart: String, otherEndpoint: String? = nil, exactOnly: Bool = false) -> (station: String?, missingPersonalPlace: String?) {
            var cleaned = SmartQueryPostProcessor.stripTemporalAndFillerTokens(rawPart)
            cleaned = cleaned.replacingOccurrences(of: #"^(?:la\s+)?stazione\s+(?:di\s+)?"#, with: "", options: [.regularExpression, .caseInsensitive])
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return (nil, nil) }

            let personal = SmartQueryPostProcessor.resolvePersonalPlace(
                cleaned,
                otherEndpoint: otherEndpoint,
                nearbyStation: nearbyStation,
                homeStations: homeStations,
                workStations: workStations,
                favoriteStations: favoriteStations
            )
            if personal.missingPersonalPlace != nil {
                return (nil, personal.missingPersonalPlace)
            }
            if let pSt = personal.station, pSt.lowercased() != cleaned.lowercased() {
                return (pSt, nil)
            }
            if let matched = exactOrClearStationName(cleaned, in: knownStations, exactOnly: exactOnly) {
                return (matched, nil)
            }
            return (nil, nil)
        }

        func buildMissingPlaceClarification(_ place: String) -> SmartTrainQuery {
            let msg: String
            switch place {
            case "casa":
                msg = "Per usare \"casa\" imposta la tua stazione di casa in Routine Pendolare o nella scheda Stazioni."
            case "lavoro":
                msg = "Per usare \"lavoro\" imposta la tua stazione di lavoro in Routine Pendolare."
            default:
                msg = "Attiva la posizione GPS oppure indica chiaramente la stazione di partenza."
            }
            return SmartTrainQuery(
                kind: .unknown,
                confidence: 0.4,
                clarification: msg,
                engineUsed: "local_exact"
            )
        }

        // Helper per testare un regex prima su structuralQuery (senza date/ore in mezzo) e poi su working
        func matchFirst(_ pattern: String) -> (source: String, match: NSTextCheckingResult)? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
            for candidate in [structuralQuery, working] where !candidate.isEmpty {
                let r = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
                if let m = regex.firstMatch(in: candidate, range: r) {
                    return (candidate, m)
                }
            }
            return nil
        }

        // 2. Sintassi inversa: "portami a <DEST> da <ORIG>", "treno per <DEST> da <ORIG>", "torno a casa da <ORIG>"
        let reversedRoutePattern = #"^(?:(?:portami|accompagnami|voglio\s+andare|vorrei\s+andare|devo\s+andare|devo\s+essere|essere|come\s+(?:arrivo|vado|faccio\s+a[d]?\s+andare)|torno|tornare|(?:(?:il|lo|un)\s+)?(?:(?:primo|prossimo)\s+)?treno(?:\s+(?:delle|alle|verso\s+le|dopo\s+le)\s+[\d:.e\s]+?)?|treni|soluzioni?)\s+)?(?:a|ad|al|all'|in|verso|per)\s+(.+?)\s+(?:da|partendo\s+da|dal|dalla|dall')\s+(.+)$"#
        if let hit = matchFirst(reversedRoutePattern),
           let rDest = Range(hit.match.range(at: 1), in: hit.source),
           let rOrig = Range(hit.match.range(at: 2), in: hit.source) {
            let rawDest = String(hit.source[rDest])
            let rawOrig = String(hit.source[rOrig])
            let origRes = resolveEndpoint(rawOrig)
            let destRes = resolveEndpoint(rawDest, otherEndpoint: origRes.station)
            if let missing = origRes.missingPersonalPlace ?? destRes.missingPersonalPlace {
                return buildMissingPlaceClarification(missing)
            }
            if let origMatched = origRes.station, let destMatched = destRes.station {
                return SmartTrainQuery(
                    kind: .routeSolutions,
                    originStation: origMatched,
                    destinationStation: destMatched,
                    targetDate: targetDate,
                    targetTime: targetTime,
                    confidence: 0.96,
                    normalizedSummary: "\(origMatched.formattedStationName) → \(destMatched.formattedStationName)",
                    engineUsed: "local_exact"
                )
            }
        }

        // 3. Tratta standard: "Treno delle 18:19 da Magenta a Milano", "domani mattina alle 8 da Magenta a Milano"
        let standardRoutePattern = #"^(?:(?:(?:il|lo|un)\s+)?(?:(?:primo|prossimo)\s+)?treno(?:\s+(?:delle|alle|verso\s+le|dopo\s+le)\s+[\d:.e\s]+?)?\s+|(?:voglio|vorrei|devo)\s+(?:andare|partire)\s+|parto\s+|partenza\s+|soluzioni\s+)?da\s+(.+?)\s+(?:a|ad|al|all'|per|verso|fino\s+a)\s+(.+)$"#
        if let hit = matchFirst(standardRoutePattern),
           let rOrig = Range(hit.match.range(at: 1), in: hit.source),
           let rDest = Range(hit.match.range(at: 2), in: hit.source) {
            let rawOrig = String(hit.source[rOrig])
            let rawDest = String(hit.source[rDest])
            let origRes = resolveEndpoint(rawOrig)
            let destRes = resolveEndpoint(rawDest, otherEndpoint: origRes.station)
            if let missing = origRes.missingPersonalPlace ?? destRes.missingPersonalPlace {
                return buildMissingPlaceClarification(missing)
            }
            if let origMatched = origRes.station, let destMatched = destRes.station {
                return SmartTrainQuery(
                    kind: .routeSolutions,
                    originStation: origMatched,
                    destinationStation: destMatched,
                    targetDate: targetDate,
                    targetTime: targetTime,
                    confidence: 0.96,
                    normalizedSummary: "\(origMatched.formattedStationName) → \(destMatched.formattedStationName)",
                    engineUsed: "local_exact"
                )
            }
        }

        // Con separatore "->" o "→"
        let arrowPattern = #"^(.+?)\s*(?:->|→)\s*(.+)$"#
        if let regex = try? NSRegularExpression(pattern: arrowPattern, options: .caseInsensitive) {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            if let match = regex.firstMatch(in: working, range: range),
               let rOrig = Range(match.range(at: 1), in: working),
               let rDest = Range(match.range(at: 2), in: working) {
                let origRes = resolveEndpoint(String(working[rOrig]))
                let destRes = resolveEndpoint(String(working[rDest]), otherEndpoint: origRes.station)
                if let missing = origRes.missingPersonalPlace ?? destRes.missingPersonalPlace {
                    return buildMissingPlaceClarification(missing)
                }
                if let origMatched = origRes.station, let destMatched = destRes.station {
                    return SmartTrainQuery(
                        kind: .routeSolutions,
                        originStation: origMatched,
                        destinationStation: destMatched,
                        targetDate: targetDate,
                        targetTime: targetTime,
                        confidence: 0.95,
                        normalizedSummary: "\(origMatched.formattedStationName) → \(destMatched.formattedStationName)",
                        engineUsed: "local_exact"
                    )
                }
            }
        }

        // 4. Solo destinazione (es. "portami a casa", "portami a Magenta oggi pomeriggio", "primo treno per Milano")
        let destOnlyPattern = #"^(?:portami|accompagnami|voglio\s+andare|vorrei\s+andare|devo\s+andare|come\s+(?:arrivo|vado|faccio\s+a[d]?\s+andare)|torno|tornare|che\s+treno\s+c'è|ci\s+sono\s+treni|(?:(?:il|lo|un)\s+)?(?:(?:primo|prossimo)\s+)?treno(?:\s+(?:delle|alle|verso\s+le|dopo\s+le)\s+[\d:.e\s]+?)?)\s+(?:a|ad|al|all'|in|verso|per)\s+(.+)$"#
        if let regex = try? NSRegularExpression(pattern: destOnlyPattern, options: .caseInsensitive) {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            if let match = regex.firstMatch(in: working, range: range),
               let rDest = Range(match.range(at: 1), in: working) {
                let destRes = resolveEndpoint(String(working[rDest]), otherEndpoint: nearbyStation)
                if let missing = destRes.missingPersonalPlace {
                    return buildMissingPlaceClarification(missing)
                }
                if let destMatched = destRes.station {
                    let origMatched = SmartQueryPostProcessor.cleanOptString(nearbyStation)
                    return SmartTrainQuery(
                        kind: .routeSolutions,
                        originStation: origMatched,
                        destinationStation: destMatched,
                        targetDate: targetDate,
                        targetTime: targetTime,
                        confidence: 0.92,
                        normalizedSummary: origMatched != nil ? "\(origMatched!.formattedStationName) → \(destMatched.formattedStationName)" : "Percorso verso \(destMatched.formattedStationName)",
                        engineUsed: "local_exact"
                    )
                }
            }
        }

        // 5. Orario esplicito da stazione senza destinazione ("treno delle 11:34 da Magenta", "treno da Magenta delle 18 e 19")
        let isCommuteLeaveWork = (lowerWorking.contains("lavoro") || lowerWorking.contains("ufficio")) && !homeStations.isEmpty
        if let explicitTime, !isCommuteLeaveWork {
            let stationAfterFromPattern = #"(?:da|dalla|dal|dall'|di|partenza\s+da)\s+(.+)$"#
            if let regex = try? NSRegularExpression(pattern: stationAfterFromPattern, options: .caseInsensitive) {
                let strippedWork = SmartQueryPostProcessor.stripTemporalAndFillerTokens(working)
                let range = NSRange(strippedWork.startIndex..<strippedWork.endIndex, in: strippedWork)
                if let match = regex.firstMatch(in: strippedWork, range: range),
                   let rSt = Range(match.range(at: 1), in: strippedWork) {
                    let origRes = resolveEndpoint(String(strippedWork[rSt]))
                    if let matchedStation = origRes.station {
                        return SmartTrainQuery(
                            kind: .trainAtTimeFromStation,
                            originStation: matchedStation,
                            targetDate: targetDate,
                            targetTime: explicitTime,
                            confidence: 0.94,
                            normalizedSummary: "Treno delle \(explicitTime) da \(matchedStation)",
                            engineUsed: "local_exact"
                        )
                    }
                }
            }
        }

        // 6. Tabellone stazione ("partenze Magenta", "arrivi Milano Centrale", "stazione di Magenta", "che treni partono da Magenta")
        let boardPattern = #"^(?:tabellone\s+|prossimi\s+treni\s+|che\s+treni\s+(?:partono|ci\s+sono)\s+|cosa\s+parte\s+)?(partenze|arrivi|in\s+partenza|in\s+arrivo|partono|arrivo)?(?:\s+(?:da|a|in|di|per|dalla))?\s*(.+)$"#
        if lowerWorking.contains("partenz") || lowerWorking.contains("arriv") || lowerWorking.contains("tabellone") || lowerWorking.hasPrefix("stazione ") || lowerWorking.hasPrefix("la stazione ") {
            if let regex = try? NSRegularExpression(pattern: boardPattern, options: .caseInsensitive) {
                let range = NSRange(working.startIndex..<working.endIndex, in: working)
                if let match = regex.firstMatch(in: working, range: range),
                   let rSt = Range(match.range(at: 2), in: working) {
                    let isArr = lowerWorking.contains("arriv")
                    let stRes = resolveEndpoint(String(working[rSt]))
                    if let matchedStation = stRes.station {
                        return SmartTrainQuery(
                            kind: .stationBoard,
                            originStation: matchedStation,
                            isArrivals: isArr,
                            confidence: 0.95,
                            normalizedSummary: "\(isArr ? "Arrivi" : "Partenze") \(matchedStation)",
                            engineUsed: "local_exact"
                        )
                    }
                }
            }
        }

        // 7. Controlla PRIMA se l'intera frase ripulita è una singola stazione esatta (es. "Milano Porta Garibaldi", "Magenta")
        let cleanFullRemainder = SmartQueryPostProcessor.stripTemporalAndFillerTokens(working)
        if !cleanFullRemainder.isEmpty {
            let singleRes = resolveEndpoint(cleanFullRemainder, exactOnly: true)
            if let singleStation = singleRes.station {
                return SmartTrainQuery(
                    kind: .stationBoard,
                    originStation: singleStation,
                    isArrivals: false,
                    confidence: 0.95,
                    normalizedSummary: "Tabellone \(singleStation)",
                    engineUsed: "local_exact"
                )
            }

            // 8. Coppia di stazioni senza preposizioni (es. "NOVARA Domodossola domani alle 12", "Magenta Milano alle 18:19")
            let words = cleanFullRemainder.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if words.count >= 2 && words.count <= 8 {
                var bestPair: (orig: String, dest: String, score: Int)? = nil
                for splitIdx in 1..<words.count {
                    let left = words[0..<splitIdx].joined(separator: " ")
                    let right = words[splitIdx..<words.count].joined(separator: " ")
                    let leftRes = resolveEndpoint(left, exactOnly: true)
                    if let origMatched = leftRes.station {
                        let rightRes = resolveEndpoint(right, otherEndpoint: origMatched, exactOnly: true)
                        if let destMatched = rightRes.station,
                           origMatched.lowercased() != destMatched.lowercased() {
                            let score = left.count + right.count
                            if bestPair == nil || score > bestPair!.score {
                                bestPair = (origMatched, destMatched, score)
                            }
                        }
                    }
                }
                if let bestPair {
                    return SmartTrainQuery(
                        kind: .routeSolutions,
                        originStation: bestPair.orig,
                        destinationStation: bestPair.dest,
                        targetDate: targetDate,
                        targetTime: targetTime,
                        confidence: 0.93,
                        normalizedSummary: "\(bestPair.orig.formattedStationName) → \(bestPair.dest.formattedStationName)",
                        engineUsed: "local_exact"
                    )
                }
            }
        }

        // 9. Stage 3 & 4: Motore a Slot & Finestra N-Gram per frasi disordinate, parlate o implicite
        if let slotGraphQuery = parseDisorderedWithSlotGraph(
            cleanedQuery: structuralQuery.isEmpty ? working : structuralQuery,
            rawLower: working.lowercased(),
            targetDate: targetDate,
            targetTime: targetTime,
            knownStations: knownStations,
            nearbyStation: nearbyStation,
            homeStations: homeStations,
            workStations: workStations,
            favoriteStations: favoriteStations
        ) {
            return slotGraphQuery
        }

        return nil
    }

    // MARK: - Stage 3 & 4: Slot-Filling & Fuzzy Token-Graph Parser (Disordered Speech)

    private struct MentionSpan {
        enum Role { case origin, destination, neutral }
        let startToken: Int
        let endToken: Int
        let resolvedName: String?
        let personalKind: String?      // "casa", "lavoro", "qui", nil
        let missingPersonal: String?   // "casa", "lavoro", "gps", nil
        let role: Role
    }

    private static let fuzzyStopWords: Set<String> = [
        "treno", "treni", "voglio", "vorrei", "domani", "dopodomani", "oggi", "questo", "questa",
        "quando", "andare", "parto", "partire", "arrivo", "arrivare", "torno", "tornare",
        "rientro", "scusa", "senti", "allora", "dunque", "alle", "delle", "dopo", "prima",
        "verso", "entro", "pranzo", "cena", "mattina", "pomeriggio", "sera", "notte",
        "lavoro", "ufficio", "casa", "stazione", "binario", "ritardo", "orario", "adesso",
        "subito", "presto", "mezza", "quarto", "portami", "che", "come", "dove", "quale"
    ]

    private static func tokenizeWithPrepositions(_ text: String) -> [String] {
        let prepared = text
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"(\b(?:dall|all|dell|nell|sull))'"#, with: "$1 ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"[?!,;:]+"#, with: " ", options: .regularExpression)
        return prepared.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func inferRoleFromContext(tokens: [String], beforeIndex idx: Int) -> MentionSpan.Role {
        guard idx > 0 else { return .neutral }
        let t1 = tokens[idx - 1].lowercased()
        let t2 = idx >= 2 ? "\(tokens[idx - 2].lowercased()) \(t1)" : ""
        let t3 = idx >= 3 ? "\(tokens[idx - 3].lowercased()) \(t2)" : ""

        let origin3: Set<String> = ["mi trovo a", "mi trovo al", "mi trovo in", "partendo da", "uscendo da", "partenza da"]
        let origin2: Set<String> = ["sono a", "sono ad", "sono al", "sono in", "parto da", "esco da", "vengo da", "parto dall", "esco dall"]
        let origin1: Set<String> = ["da", "dal", "dalla", "dall", "dai", "dalle"]

        if origin3.contains(t3) || origin2.contains(t2) || origin1.contains(t1) {
            return .origin
        }

        let dest3: Set<String> = ["devo tornare a", "devo andare a", "voglio andare a", "devo essere a", "arrivare fino a"]
        let dest2: Set<String> = ["torno a", "tornare a", "rientro a", "vado a", "vado al", "andare a", "andare al", "essere a", "arrivare a", "fino a", "diretto a", "portami a"]
        let dest1: Set<String> = ["a", "ad", "al", "alla", "all", "per", "verso", "in", "direzione"]

        if dest3.contains(t3) || dest2.contains(t2) || dest1.contains(t1) {
            return .destination
        }
        return .neutral
    }

    private static func scanCandidateMentions(
        tokens: [String],
        knownStations: [RFIStation],
        nearbyStation: String?,
        homeStations: [String],
        workStations: [String],
        favoriteStations: [String]
    ) -> [MentionSpan] {
        var spans: [MentionSpan] = []
        var i = 0
        while i < tokens.count {
            let maxLen = min(4, tokens.count - i)
            var matchedSpan: MentionSpan? = nil
            for len in stride(from: maxLen, through: 1, by: -1) {
                let candidatePhrase = tokens[i..<(i + len)].joined(separator: " ")
                let candLow = candidatePhrase.lowercased()
                let role = inferRoleFromContext(tokens: tokens, beforeIndex: i)

                if ["casa", "casa mia"].contains(candLow) {
                    let res = SmartQueryPostProcessor.resolvePersonalPlace(
                        candLow,
                        otherEndpoint: nil,
                        nearbyStation: nearbyStation,
                        homeStations: homeStations,
                        workStations: workStations,
                        favoriteStations: favoriteStations
                    )
                    matchedSpan = MentionSpan(
                        startToken: i,
                        endToken: i + len,
                        resolvedName: res.station,
                        personalKind: "casa",
                        missingPersonal: res.missingPersonalPlace,
                        role: role
                    )
                    break
                }
                if ["lavoro", "ufficio", "ufficio mio"].contains(candLow) {
                    let res = SmartQueryPostProcessor.resolvePersonalPlace(
                        candLow,
                        otherEndpoint: nil,
                        nearbyStation: nearbyStation,
                        homeStations: homeStations,
                        workStations: workStations,
                        favoriteStations: favoriteStations
                    )
                    matchedSpan = MentionSpan(
                        startToken: i,
                        endToken: i + len,
                        resolvedName: res.station,
                        personalKind: "lavoro",
                        missingPersonal: res.missingPersonalPlace,
                        role: role
                    )
                    break
                }
                if candLow == "qui" || candLow == "mia posizione" || candLow == "posizione attuale" {
                    matchedSpan = MentionSpan(
                        startToken: i,
                        endToken: i + len,
                        resolvedName: SmartQueryPostProcessor.cleanOptString(nearbyStation),
                        personalKind: "qui",
                        missingPersonal: SmartQueryPostProcessor.cleanOptString(nearbyStation) == nil ? "gps" : nil,
                        role: role
                    )
                    break
                }

                // Ignora singole parole stop-word / preposizioni
                if len == 1 && (fuzzyStopWords.contains(candLow) || candLow.count < 3) {
                    continue
                }

                let priorityStations = homeStations + workStations + favoriteStations
                if let matched = exactOrClearStationName(
                    candidatePhrase,
                    in: knownStations,
                    exactOnly: false,
                    allowFuzzy: len == 1 && !fuzzyStopWords.contains(candLow),
                    priorityNames: priorityStations
                ) {
                    matchedSpan = MentionSpan(
                        startToken: i,
                        endToken: i + len,
                        resolvedName: matched,
                        personalKind: nil,
                        missingPersonal: nil,
                        role: role
                    )
                    break
                }
            }
            if let hit = matchedSpan {
                spans.append(hit)
                i = hit.endToken
            } else {
                i += 1
            }
        }
        return spans
    }

    private static func parseDisorderedWithSlotGraph(
        cleanedQuery: String,
        rawLower: String,
        targetDate: String?,
        targetTime: String?,
        knownStations: [RFIStation],
        nearbyStation: String?,
        homeStations: [String],
        workStations: [String],
        favoriteStations: [String]
    ) -> SmartTrainQuery? {
        let tokens = tokenizeWithPrepositions(cleanedQuery)
        guard !tokens.isEmpty else { return nil }

        let mentions = scanCandidateMentions(
            tokens: tokens,
            knownStations: knownStations,
            nearbyStation: nearbyStation,
            homeStations: homeStations,
            workStations: workStations,
            favoriteStations: favoriteStations
        )
        guard !mentions.isEmpty else { return nil }

        // Controlla se manca casa/lavoro esplicitamente richiesto
        if let missingSpan = mentions.first(where: { $0.missingPersonal == "casa" || $0.missingPersonal == "lavoro" }) {
            let msg = missingSpan.missingPersonal == "casa"
                ? "Per usare \"casa\" imposta la tua stazione di casa in Routine Pendolare o nella scheda Stazioni."
                : "Per usare \"lavoro\" imposta la tua stazione di lavoro in Routine Pendolare."
            return SmartTrainQuery(kind: .unknown, confidence: 0.4, clarification: msg, engineUsed: "local_exact")
        }

        var originSpan: MentionSpan? = nil
        var destSpan: MentionSpan? = nil

        if mentions.count >= 2 {
            originSpan = mentions.first(where: { $0.role == .origin })
            destSpan = mentions.first(where: { $0.role == .destination })

            if originSpan == nil && destSpan == nil {
                originSpan = mentions[0]
                destSpan = mentions[1]
            } else if originSpan == nil, let d = destSpan {
                originSpan = mentions.first(where: { $0.startToken != d.startToken })
            } else if destSpan == nil, let o = originSpan {
                destSpan = mentions.first(where: { $0.startToken != o.startToken })
            }
        } else if let single = mentions.first {
            if single.role == .origin {
                originSpan = single
                // Inferenza pendolare intelligente: "esco da lavoro" -> verso Casa; "esco da casa" -> verso Lavoro
                if single.personalKind == "lavoro" && !homeStations.isEmpty {
                    let homePick = SmartQueryPostProcessor.resolvePersonalPlace(
                        "casa",
                        otherEndpoint: single.resolvedName,
                        nearbyStation: nearbyStation,
                        homeStations: homeStations,
                        workStations: workStations,
                        favoriteStations: favoriteStations
                    ).station
                    if let homePick {
                        return SmartTrainQuery(
                            kind: .routeSolutions,
                            originStation: single.resolvedName,
                            destinationStation: homePick,
                            targetDate: targetDate,
                            targetTime: targetTime,
                            confidence: 0.90,
                            normalizedSummary: "\(single.resolvedName?.formattedStationName ?? "") → \(homePick.formattedStationName)",
                            engineUsed: "local_exact"
                        )
                    }
                } else if targetTime != nil {
                    if let stName = single.resolvedName {
                        return SmartTrainQuery(
                            kind: .trainAtTimeFromStation,
                            originStation: stName,
                            targetDate: targetDate,
                            targetTime: targetTime,
                            confidence: 0.90,
                            normalizedSummary: "Treno delle \(targetTime!) da \(stName)",
                            engineUsed: "local_exact"
                        )
                    }
                }
            } else {
                destSpan = single
                var inferredOrigin = SmartQueryPostProcessor.cleanOptString(nearbyStation)
                if inferredOrigin == nil {
                    if single.personalKind == "casa" && !workStations.isEmpty {
                        inferredOrigin = SmartQueryPostProcessor.resolvePersonalPlace(
                            "lavoro",
                            otherEndpoint: single.resolvedName,
                            nearbyStation: nearbyStation,
                            homeStations: homeStations,
                            workStations: workStations,
                            favoriteStations: favoriteStations
                        ).station
                    } else if single.personalKind == "lavoro" && !homeStations.isEmpty {
                        inferredOrigin = SmartQueryPostProcessor.resolvePersonalPlace(
                            "casa",
                            otherEndpoint: single.resolvedName,
                            nearbyStation: nearbyStation,
                            homeStations: homeStations,
                            workStations: workStations,
                            favoriteStations: favoriteStations
                        ).station
                    }
                }
                if let destName = single.resolvedName {
                    return SmartTrainQuery(
                        kind: .routeSolutions,
                        originStation: inferredOrigin,
                        destinationStation: destName,
                        targetDate: targetDate,
                        targetTime: targetTime,
                        confidence: inferredOrigin != nil ? 0.91 : 0.86,
                        normalizedSummary: inferredOrigin != nil ? "\(inferredOrigin!.formattedStationName) → \(destName.formattedStationName)" : "Percorso verso \(destName.formattedStationName)",
                        engineUsed: "local_exact"
                    )
                }
            }
        }

        if let oSpan = originSpan, let dSpan = destSpan {
            let resolvedOrig: String?
            let resolvedDest: String?
            if dSpan.personalKind == "casa" {
                resolvedOrig = oSpan.resolvedName
                resolvedDest = SmartQueryPostProcessor.resolvePersonalPlace(
                    "casa",
                    otherEndpoint: resolvedOrig,
                    nearbyStation: nearbyStation,
                    homeStations: homeStations,
                    workStations: workStations,
                    favoriteStations: favoriteStations
                ).station ?? dSpan.resolvedName
            } else if dSpan.personalKind == "lavoro" {
                resolvedOrig = oSpan.resolvedName
                resolvedDest = SmartQueryPostProcessor.resolvePersonalPlace(
                    "lavoro",
                    otherEndpoint: resolvedOrig,
                    nearbyStation: nearbyStation,
                    homeStations: homeStations,
                    workStations: workStations,
                    favoriteStations: favoriteStations
                ).station ?? dSpan.resolvedName
            } else if oSpan.personalKind == "casa" {
                resolvedDest = dSpan.resolvedName
                resolvedOrig = SmartQueryPostProcessor.resolvePersonalPlace(
                    "casa",
                    otherEndpoint: resolvedDest,
                    nearbyStation: nearbyStation,
                    homeStations: homeStations,
                    workStations: workStations,
                    favoriteStations: favoriteStations
                ).station ?? oSpan.resolvedName
            } else if oSpan.personalKind == "lavoro" {
                resolvedDest = dSpan.resolvedName
                resolvedOrig = SmartQueryPostProcessor.resolvePersonalPlace(
                    "lavoro",
                    otherEndpoint: resolvedDest,
                    nearbyStation: nearbyStation,
                    homeStations: homeStations,
                    workStations: workStations,
                    favoriteStations: favoriteStations
                ).station ?? oSpan.resolvedName
            } else {
                resolvedOrig = oSpan.resolvedName
                resolvedDest = dSpan.resolvedName
            }

            if let o = resolvedOrig, let d = resolvedDest, o.lowercased() != d.lowercased() {
                return SmartTrainQuery(
                    kind: .routeSolutions,
                    originStation: o,
                    destinationStation: d,
                    targetDate: targetDate,
                    targetTime: targetTime,
                    confidence: 0.94,
                    normalizedSummary: "\(o.formattedStationName) → \(d.formattedStationName)",
                    engineUsed: "local_exact"
                )
            }
        }

        return nil
    }

    static func preScanHints(
        query: String,
        knownStations: [RFIStation],
        nearbyStation: String?,
        homeStations: [String],
        workStations: [String],
        favoriteStations: [String],
        now: Date
    ) -> String {
        let cleaned = SmartQueryPostProcessor.stripTemporalAndFillerTokens(
            SmartQueryPostProcessor.preprocessMessySpeech(query)
        )
        let tokens = tokenizeWithPrepositions(cleaned)
        let mentions = scanCandidateMentions(
            tokens: tokens,
            knownStations: knownStations,
            nearbyStation: nearbyStation,
            homeStations: homeStations,
            workStations: workStations,
            favoriteStations: favoriteStations
        )
        let names = Array(Set(mentions.compactMap { $0.resolvedName })).prefix(4)
        var parts: [String] = []
        if !names.isEmpty {
            parts.append("stazioni candidate=\(names.joined(separator: ", "))")
        }
        if let dt = SmartQueryPostProcessor.extractTargetDate(from: query, now: now) {
            parts.append("data=\(dt)")
        }
        if let tm = SmartQueryPostProcessor.extractExplicitTime(from: query, now: now) {
            parts.append("ora=\(tm)")
        }
        return parts.joined(separator: "; ")
    }

    static func applyKnownAlias(_ raw: String) -> String {
        let clean = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if let mapped = stationAliasMap[clean.lowercased()] {
            return mapped
        }
        return clean
    }

    private static func normalizeStationMatchKey(_ raw: String) -> String {
        var s = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "'", with: " ")
            .lowercased()
        s = s.replacingOccurrences(of: #"\bs\s+"#, with: "san ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\bp\s*ta\b"#, with: "porta", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var dp = Array(0...b.count)
        for i in 1...a.count {
            var prev = dp[0]
            dp[0] = i
            for j in 1...b.count {
                let temp = dp[j]
                if a[i - 1] == b[j - 1] {
                    dp[j] = prev
                } else {
                    dp[j] = min(prev, dp[j], dp[j - 1]) + 1
                }
                prev = temp
            }
        }
        return dp[b.count]
    }

    static func exactOrClearStationName(
        _ raw: String,
        in stations: [RFIStation],
        exactOnly: Bool = false,
        allowFuzzy: Bool = false,
        priorityNames: [String] = []
    ) -> String? {
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = applyKnownAlias(trimmedRaw)
        let normCandidate = candidate.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard normCandidate.count >= 2 else { return nil }

        let keyCandidate = normalizeStationMatchKey(candidate)

        // Hub generico "Milano" per ricerche tratta
        if normCandidate == "milano" {
            return "Milano"
        }

        if let exact = stations.first(where: { $0.name.lowercased() == normCandidate }) {
            return exact.name
        }
        if let foldedExact = stations.first(where: { normalizeStationMatchKey($0.name) == keyCandidate }) {
            return foldedExact.name
        }

        // Prefisso primario prima del trattino (es. "vittuone" -> "VITTUONE-ARLUNO", "corbetta" -> "CORBETTA-S.STEFANO TICINO")
        let hyphenHeadMatches = stations.filter { st in
            let parts = st.name.split(separator: "-").map { normalizeStationMatchKey(String($0)) }
            return parts.first == keyCandidate && !keyCandidate.isEmpty
        }
        if hyphenHeadMatches.count == 1 {
            return hyphenHeadMatches[0].name
        }

        let wasKnownAlias = stationAliasMap[trimmedRaw.lowercased()] != nil
        if exactOnly {
            if wasKnownAlias {
                return candidate
            }
            return nil
        }

        let prefixMatches = stations.filter {
            let stKey = normalizeStationMatchKey($0.name)
            return stKey.hasPrefix(keyCandidate + " ")
        }
        if prefixMatches.count == 1 {
            return prefixMatches[0].name
        }

        if wasKnownAlias {
            return candidate
        }

        // Fuzzy matching protetto da stopword per refusi vocali (es. "maggenta", "galarate", "domodosola")
        if allowFuzzy && keyCandidate.count >= 5 && !fuzzyStopWords.contains(keyCandidate) {
            let maxDist = keyCandidate.count >= 8 ? 2 : 1
            let priorityLowers = Set(priorityNames.map { normalizeStationMatchKey($0) })
            var bestMatch: (name: String, score: Int)? = nil
            for st in stations {
                let stKey = normalizeStationMatchKey(st.name)
                guard abs(stKey.count - keyCandidate.count) <= maxDist else { continue }
                let dist = levenshteinDistance(keyCandidate, stKey)
                guard dist <= maxDist else { continue }
                let isPriority = priorityLowers.contains(stKey) ? 0 : 1
                let score = dist * 10 + isPriority
                if bestMatch == nil || score < bestMatch!.score {
                    bestMatch = (st.name, score)
                }
            }
            if let bestMatch {
                return bestMatch.name
            }
        }

        return nil
    }
}

// MARK: - Apple Intelligence Query Parser (iOS 26+)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "Parametri strutturati estratti da una richiesta ferroviaria italiana per In Orario")
private nonisolated struct GenerableSmartTrainQuery {
    @Guide(description: "Tipo intento esattamente tra: routeSolutions, trainAtTimeFromStation, stationBoard, trainStatus, unknown")
    var kind: String

    @Guide(description: "Stazione di partenza esatta oppure stringa vuota se non specificata e GPS assente")
    var originStation: String

    @Guide(description: "Stazione di arrivo esatta oppure stringa vuota se assente")
    var destinationStation: String

    @Guide(description: "Data richiesta in formato YYYY-MM-DD oppure stringa vuota")
    var targetDate: String

    @Guide(description: "Orario esatto in formato HH:mm senza mai alterare i numeri detti dall'utente, oppure stringa vuota")
    var targetTime: String

    @Guide(description: "Numero treno solo cifre oppure stringa vuota")
    var trainNumber: String

    @Guide(description: "true solo per arrivi stazione, altrimenti false")
    var isArrivals: Bool

    @Guide(description: "Breve frase riassuntiva in italiano della richiesta")
    var normalizedSummary: String
}
#endif

enum AppleIntelligenceQueryParser {
    static func parse(
        query: String,
        currentDate: String,
        currentWeekday: String,
        currentTime: String,
        nearbyStation: String?,
        homeStations: [String] = [],
        workStations: [String] = [],
        favoriteStations: [String],
        favoriteTrains: [String],
        entityHints: String = ""
    ) async -> SmartTrainQuery? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                return nil
            }
            let tomorrowDate = SmartQueryPostProcessor.relativeDateString(daysOffset: 1)
            let dayAfterDate = SmartQueryPostProcessor.relativeDateString(daysOffset: 2)
            let gpsLine = (nearbyStation?.isEmpty == false)
                ? "Stazione GPS attuale: \(nearbyStation!)"
                : "Posizione GPS attuale: non disponibile (se manca la partenza lascia originStation vuoto)."
            let homeLine = homeStations.isEmpty ? "non configurata" : homeStations.prefix(4).joined(separator: ", ")
            let workLine = workStations.isEmpty ? "non configurato" : workStations.prefix(4).joined(separator: ", ")
            let hintsLine = entityHints.isEmpty ? "" : "\nEntità pre-rilevate dalla frase: \(entityHints)"

            let prompt = """
            Sei un parser rigoroso di richieste ferroviarie italiane per In Orario.
            NON inventare treni o orari. Estrai SOLO i parametri dalla richiesta dell'utente.
            Date di riferimento (Europe/Rome):
            - Oggi: \(currentDate) (\(currentWeekday))
            - Domani: \(tomorrowDate)
            - Dopodomani: \(dayAfterDate)
            Ora attuale di riferimento: \(currentTime) (usala SOLO se l'utente chiede "adesso" o "prossimo treno", NON sovrascrivere MAI un orario esplicito come "11:34", "18:19" o "12:00").
            \(gpsLine)
            Stazioni di CASA utente: \(homeLine) (se l'utente dice "casa", usa una stazione di casa diversa dall'altro capo della tratta).
            Stazioni di LAVORO/UFFICIO utente: \(workLine) (se l'utente dice "lavoro" o "ufficio", usa una stazione di lavoro diversa dall'altro capo della tratta).
            Stazioni preferite: \(favoriteStations.isEmpty ? "non indicate" : favoriteStations.prefix(6).joined(separator: ", ")).
            Treni preferiti: \(favoriteTrains.isEmpty ? "non indicati" : favoriteTrains.prefix(6).joined(separator: ", ")).\(hintsLine)

            Regole sui campi:
            - kind="routeSolutions": spostamenti da A a B in qualsiasi ordine sintattico (anche disordinato o parlato):
              • Autocorrezioni parlate ("a Milano Centrale anzi no Porta Garibaldi"): prendi SOLO la correzione finale.
              • Ordine diretto: "da A a B", "domani mattina alle 8 da Magenta a Milano", "sono a A e devo tornare a B" -> originStation=A, destinationStation=B.
              • Ordine inverso: "Portami a <destinazione> da <partenza>" -> originStation="<partenza>", destinationStation="<destinazione>".
              • Parti del giorno: "mattina presto"->"06:30", "mattina"->"08:00", "dopo pranzo"->"14:00", "pomeriggio"->"14:30", "tardo pomeriggio"->"17:30", "stasera"->"19:30".
            - kind="trainAtTimeFromStation": treno ad un orario preciso in partenza da UNA sola stazione senza arrivo (es. "Treno delle 11:34 da Magenta" -> originStation="Magenta", targetTime="11:34", destinationStation="").
            - kind="stationBoard": tabellone partenze/arrivi di una stazione (es. "Stazione di Magenta", "Partenze Milano Rogoredo").
            - kind="trainStatus": stato di un numero treno (es. "treno 24627").

            Richiesta utente: "\(query)"
            """
            do {
                let parsed: SmartTrainQuery? = try await withThrowingTaskGroup(of: SmartTrainQuery?.self) { group in
                    group.addTask {
                        let session = LanguageModelSession()
                        let response = try await session.respond(to: prompt, generating: GenerableSmartTrainQuery.self)
                        let gen = response.content
                        let kind = SmartTrainQuery.IntentKind(rawValue: gen.kind.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .unknown
                        return SmartTrainQuery(
                            kind: kind,
                            originStation: SmartQueryPostProcessor.cleanOptString(gen.originStation),
                            destinationStation: SmartQueryPostProcessor.cleanOptString(gen.destinationStation),
                            targetDate: SmartQueryPostProcessor.cleanOptString(gen.targetDate),
                            targetTime: SmartQueryPostProcessor.cleanOptString(gen.targetTime),
                            trainNumber: SmartQueryPostProcessor.cleanTrainDigits(gen.trainNumber),
                            isArrivals: gen.isArrivals,
                            confidence: kind == .unknown ? 0.35 : 0.92,
                            normalizedSummary: SmartQueryPostProcessor.cleanOptString(gen.normalizedSummary),
                            clarification: kind == .unknown ? "Non ho capito con certezza la richiesta. Specifica stazione o tratta." : nil,
                            engineUsed: "apple_intelligence"
                        )
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 12_000_000_000)
                        throw CancellationError()
                    }
                    let first = try await group.next() ?? nil
                    group.cancelAll()
                    return first
                }
                return parsed
            } catch {
                AppLogger.error("Errore AppleIntelligenceQueryParser: \(error.localizedDescription)")
                return nil
            }
        }
        #endif
        return nil
    }

    static func decodeJSONResponse(_ rawText: String, engine: String) -> SmartTrainQuery? {
        var cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: #"^```[a-zA-Z]*\n?"#, with: "", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: #"\n?```$"#, with: "", options: .regularExpression)
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}"), start <= end {
            cleaned = String(cleaned[start...end])
        }
        guard let data = cleaned.data(using: .utf8),
              var decoded = try? JSONDecoder().decode(SmartTrainQuery.self, from: data) else {
            return nil
        }
        decoded.engineUsed = engine
        return decoded
    }
}

// MARK: - SmartQueryParser (Orchestratore Ibrido)

@MainActor
final class SmartQueryParser {
    static let shared = SmartQueryParser()

    private struct CloudParseResponse: Decodable {
        let status: String?
        let engine: String?
        let parsed: SmartTrainQuery
    }

    func parse(
        query rawQuery: String,
        hasSupport: Bool,
        aiModeChoice: AIFeatureManager.AIMode? = nil,
        nearbyStation: String?,
        homeStations: [String] = [],
        workStations: [String] = [],
        favoriteStations: [String],
        favoriteTrains: [String],
        knownStations: [RFIStation]
    ) async -> SmartQueryParseOutcome {
        let report = await parseDetailed(
            query: rawQuery,
            hasSupport: hasSupport,
            aiModeChoice: aiModeChoice,
            inputMode: "text",
            nearbyStation: nearbyStation,
            homeStations: homeStations,
            workStations: workStations,
            favoriteStations: favoriteStations,
            favoriteTrains: favoriteTrains,
            knownStations: knownStations
        )
        return report.outcome
    }

    func parseDetailed(
        query rawQuery: String,
        hasSupport: Bool,
        aiModeChoice: AIFeatureManager.AIMode? = nil,
        inputMode: String = "text",
        nearbyStation: String?,
        homeStations: [String] = [],
        workStations: [String] = [],
        favoriteStations: [String],
        favoriteTrains: [String],
        knownStations: [RFIStation]
    ) async -> SmartQueryParseReport {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SmartQueryParseReport(
                outcome: .clarification("Scrivi o pronuncia una richiesta sui treni."),
                parsedSnapshot: nil,
                engineUsed: "none"
            )
        }

        let effectiveChoice = aiModeChoice ?? AIFeatureManager.shared.aiModeChoice
        let engineChoice = SmartQueryEnginePolicy.resolve(
            hasSupport: hasSupport,
            hasAppleIntelligence: AIFeatureManager.shared.isAppleIntelligenceAvailable,
            aiModeChoice: effectiveChoice
        )

        let now = Date()
        let romeTZ = TimeZone(identifier: "Europe/Rome") ?? .current
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.timeZone = romeTZ
        dateFmt.dateFormat = "yyyy-MM-dd"
        let currDate = dateFmt.string(from: now)

        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "en_US_POSIX")
        timeFmt.timeZone = romeTZ
        timeFmt.dateFormat = "HH:mm"
        let currTime = timeFmt.string(from: now)

        let wdFmt = DateFormatter()
        wdFmt.locale = Locale(identifier: "it_IT")
        wdFmt.timeZone = romeTZ
        wdFmt.dateFormat = "EEEE"
        let currWeekday = wdFmt.string(from: now).capitalized

        func tryLocalExact(requireComplete: Bool) -> SmartQueryParseReport? {
            guard let localMatch = LocalExactQueryParser.parse(
                query: trimmed,
                knownStations: knownStations,
                nearbyStation: nearbyStation,
                homeStations: homeStations,
                workStations: workStations,
                favoriteStations: favoriteStations,
                favoriteTrains: favoriteTrains,
                now: now
            ) else {
                return nil
            }
            let refinedLocal = SmartQueryPostProcessor.refine(
                parsed: localMatch,
                rawQuery: trimmed,
                nearbyStation: nearbyStation,
                homeStations: homeStations,
                workStations: workStations,
                favoriteStations: favoriteStations,
                now: now
            )
            let isCompleteLocal: Bool = {
                if refinedLocal.kind == .unknown && refinedLocal.clarification != nil { return true }
                if refinedLocal.confidence < 0.85 { return false }
                switch refinedLocal.kind {
                case .trainStatus: return refinedLocal.trainNumber != nil
                case .stationBoard, .trainAtTimeFromStation: return refinedLocal.originStation != nil
                case .routeSolutions: return refinedLocal.destinationStation != nil && (refinedLocal.originStation != nil || nearbyStation == nil)
                case .unknown: return false
                }
            }()
            if isCompleteLocal || !requireComplete {
                return SmartQueryParseReport(
                    outcome: validateOutcome(refinedLocal),
                    parsedSnapshot: refinedLocal,
                    engineUsed: "local_exact"
                )
            }
            return nil
        }

        let hints = LocalExactQueryParser.preScanHints(
            query: trimmed,
            knownStations: knownStations,
            nearbyStation: nearbyStation,
            homeStations: homeStations,
            workStations: workStations,
            favoriteStations: favoriteStations,
            now: now
        )

        switch engineChoice {
        case .geminiCloud:
            // Utente Cloud (Pro): passa SEMPRE dal motore Cloud prima di qualsiasi fallback locale
            if let cloudResult = await callCloudParser(
                query: trimmed,
                currentDate: currDate,
                currentTime: currTime,
                nearbyStation: nearbyStation,
                homeStations: homeStations,
                workStations: workStations,
                favoriteStations: favoriteStations,
                favoriteTrains: favoriteTrains,
                hasSupport: hasSupport,
                inputMode: inputMode,
                clientLogsResult: true
            ) {
                let refined = SmartQueryPostProcessor.refine(
                    parsed: cloudResult,
                    rawQuery: trimmed,
                    nearbyStation: nearbyStation,
                    homeStations: homeStations,
                    workStations: workStations,
                    favoriteStations: favoriteStations,
                    now: now
                )
                return SmartQueryParseReport(
                    outcome: validateOutcome(refined),
                    parsedSnapshot: refined,
                    engineUsed: refined.engineUsed ?? "gemini_cloud"
                )
            }
            if let aiResult = await AppleIntelligenceQueryParser.parse(
                query: trimmed,
                currentDate: currDate,
                currentWeekday: currWeekday,
                currentTime: currTime,
                nearbyStation: nearbyStation,
                homeStations: homeStations,
                workStations: workStations,
                favoriteStations: favoriteStations,
                favoriteTrains: favoriteTrains,
                entityHints: hints
            ) {
                let refined = SmartQueryPostProcessor.refine(
                    parsed: aiResult,
                    rawQuery: trimmed,
                    nearbyStation: nearbyStation,
                    homeStations: homeStations,
                    workStations: workStations,
                    favoriteStations: favoriteStations,
                    now: now
                )
                return SmartQueryParseReport(
                    outcome: validateOutcome(refined),
                    parsedSnapshot: refined,
                    engineUsed: "apple_intelligence"
                )
            }
            if let localFallback = tryLocalExact(requireComplete: true) {
                return localFallback
            }
            return SmartQueryParseReport(
                outcome: .error("Non sono riuscito a contattare l'assistente Cloud in questo momento. Riprova o usa la ricerca standard."),
                parsedSnapshot: nil,
                engineUsed: "gemini_cloud"
            )

        case .appleIntelligence:
            // Utente base con Apple Intelligence: usa Apple Intelligence prima del fallback locale
            if let aiResult = await AppleIntelligenceQueryParser.parse(
                query: trimmed,
                currentDate: currDate,
                currentWeekday: currWeekday,
                currentTime: currTime,
                nearbyStation: nearbyStation,
                homeStations: homeStations,
                workStations: workStations,
                favoriteStations: favoriteStations,
                favoriteTrains: favoriteTrains,
                entityHints: hints
            ) {
                let refined = SmartQueryPostProcessor.refine(
                    parsed: aiResult,
                    rawQuery: trimmed,
                    nearbyStation: nearbyStation,
                    homeStations: homeStations,
                    workStations: workStations,
                    favoriteStations: favoriteStations,
                    now: now
                )
                if refined.kind != .unknown {
                    return SmartQueryParseReport(
                        outcome: validateOutcome(refined),
                        parsedSnapshot: refined,
                        engineUsed: "apple_intelligence"
                    )
                }
            }
            if let localFallback = tryLocalExact(requireComplete: true) {
                return localFallback
            }
            return SmartQueryParseReport(
                outcome: .clarification("Non ho capito con certezza la richiesta. Prova a indicare chiaramente stazione di partenza, arrivo o orario (es. \"Da Magenta a Milano alle 16\")."),
                parsedSnapshot: nil,
                engineUsed: "apple_intelligence"
            )

        case .localExactOnly:
            if let localReport = tryLocalExact(requireComplete: false) {
                return localReport
            }
            if effectiveChoice == .none && (hasSupport || AIFeatureManager.shared.isAppleIntelligenceAvailable) {
                return SmartQueryParseReport(
                    outcome: .clarification("L'elaborazione IA è disattivata nelle Impostazioni IA. Seleziona Apple Intelligence o Cloud per comprendere richieste in linguaggio naturale."),
                    parsedSnapshot: nil,
                    engineUsed: "none"
                )
            }
            return SmartQueryParseReport(
                outcome: .needsUpgrade("Per comprendere richieste complesse o vocali in linguaggio naturale (come date e orari relativi) serve Apple Intelligence oppure il motore Cloud di In Orario Pro. Per ricerche immediate puoi anche usare i campi manuali."),
                parsedSnapshot: nil,
                engineUsed: "local_exact"
            )
        }
    }

    func logAnonymousQuery(
        rawQuery: String,
        inputMode: String,
        engine: String,
        outcome: String,
        parsed: SmartTrainQuery?,
        resultSummary: String?
    ) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/ai/log-query") else { return }

        var payload: [String: Any] = [
            "query": String(trimmed.prefix(300)),
            "input_mode": inputMode,
            "engine": engine,
            "outcome": outcome,
            "kind": parsed?.kind.rawValue ?? "unknown"
        ]
        if let conf = parsed?.confidence {
            payload["confidence"] = conf
        }
        if let parsed {
            var parsedDict: [String: Any] = [
                "kind": parsed.kind.rawValue,
                "is_arrivals": parsed.isArrivals,
                "confidence": parsed.confidence
            ]
            if let v = parsed.originStation { parsedDict["origin_station"] = v }
            if let v = parsed.destinationStation { parsedDict["destination_station"] = v }
            if let v = parsed.targetDate { parsedDict["target_date"] = v }
            if let v = parsed.targetTime { parsedDict["target_time"] = v }
            if let v = parsed.trainNumber { parsedDict["train_number"] = v }
            if let v = parsed.normalizedSummary { parsedDict["normalized_summary"] = v }
            if let v = parsed.clarification { parsedDict["clarification"] = v }
            payload["parsed"] = parsedDict
        }
        if let resultSummary = resultSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !resultSummary.isEmpty {
            payload["result_summary"] = String(resultSummary.prefix(240))
        }

        Task.detached(priority: .utility) {
            guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 8
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // NESSUN header X-Device-Token o X-Device-ID: query completamente anonima
            req.httpBody = body
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    private func validateOutcome(_ parsed: SmartTrainQuery) -> SmartQueryParseOutcome {
        if parsed.kind == .unknown || parsed.confidence < 0.45 {
            let msg = parsed.clarification ?? "Richiesta non chiara: specifica meglio stazione, orario o numero del treno."
            return .clarification(msg)
        }
        return .parsed(parsed)
    }

    private func callCloudParser(
        query: String,
        currentDate: String,
        currentTime: String,
        nearbyStation: String?,
        homeStations: [String] = [],
        workStations: [String] = [],
        favoriteStations: [String],
        favoriteTrains: [String],
        hasSupport: Bool,
        inputMode: String = "text",
        clientLogsResult: Bool = true
    ) async -> SmartTrainQuery? {
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/ai/parse-query") else {
            return nil
        }
        var payload: [String: Any] = [
            "query": query,
            "current_date": currentDate,
            "current_time": currentTime,
            "home_stations": Array(homeStations.prefix(6)),
            "work_stations": Array(workStations.prefix(6)),
            "favorite_stations": Array(favoriteStations.prefix(8)),
            "favorite_trains": Array(favoriteTrains.prefix(8)),
            "has_support": hasSupport,
            "input_mode": inputMode,
            "client_logs_result": clientLogsResult
        ]
        if let nearby = nearbyStation, !nearby.isEmpty {
            payload["nearby_station"] = nearby
        }
        do {
            let (data, response) = try await NetworkService.shared.post(url: url, payload: payload)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let decoded = try JSONDecoder().decode(CloudParseResponse.self, from: data)
            var res = decoded.parsed
            res.engineUsed = decoded.engine ?? "gemini_cloud"
            return res
        } catch {
            AppLogger.error("Errore chiamata /ai/parse-query: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - SmartQueryExecutor (Esecuzione 100% Reale sui Dati dell'App)

@MainActor
final class SmartQueryExecutor {
    static let shared = SmartQueryExecutor()

    static func bundledRFIStations() -> [RFIStation] {
        RFIStationCatalog.shared.rfiStations
    }

    func execute(
        parsed: SmartTrainQuery,
        manager: TrainManager,
        nearbyStation: Station?
    ) async -> SmartQueryExecutionResult {
        let knownStations = manager.allRFIStations.isEmpty ? Self.bundledRFIStations() : manager.allRFIStations

        switch parsed.kind {
        case .trainStatus:
            guard let num = parsed.trainNumber, !num.isEmpty else {
                return .message("Specifica il numero del treno da cercare.")
            }
            let dummy = manager.createDummyTrain(from: SavedTrain(number: num, description: "Treno \(num)"))
            let stopsRes = await manager.fetchLiveStops(for: num)
            if !stopsRes.stops.isEmpty {
                let first = stopsRes.stops.first
                let last = stopsRes.stops.last
                let delayVal = last?.delay ?? 0
                let delayStr: String
                if stopsRes.status.statusMessage.contains("Soppresso") {
                    delayStr = "Soppresso"
                } else if delayVal > 0 {
                    delayStr = "+\(delayVal)'"
                } else {
                    delayStr = "In orario"
                }
                let liveTrain = Train(
                    category: dummy.category,
                    number: num,
                    destination: last?.stationName ?? dummy.destination,
                    time: first?.time ?? "--:--",
                    delay: delayStr,
                    platform: last?.actualPlatform ?? last?.plannedPlatform ?? "--",
                    origin: first?.stationName
                )
                return .trainStatus(train: liveTrain)
            }
            return .trainStatus(train: dummy)

        case .trainAtTimeFromStation:
            let origName = parsed.originStation ?? nearbyStation?.name
            guard let origName, !origName.isEmpty,
                  let resolvedOrigin = await resolveStation(name: origName, allStations: knownStations, fallbackNearby: nearbyStation) else {
                return .message("Non sono riuscito a trovare la stazione di partenza richiesta.")
            }
            let targetDt = parsed.resolvedDate()
            let (matched, sample) = await fetchTrainAtTime(
                station: resolvedOrigin,
                targetDate: targetDt,
                requestedHHmm: parsed.targetTime,
                destinationHint: parsed.destinationStation,
                manager: manager
            )
            return .trainAtTime(
                train: matched,
                station: resolvedOrigin,
                boardSample: sample,
                requestedTime: parsed.targetTime ?? SharedFormatters.time.string(from: targetDt)
            )

        case .stationBoard:
            let stName = parsed.originStation ?? parsed.destinationStation ?? nearbyStation?.name
            guard let stName, !stName.isEmpty,
                  let resolved = await resolveStation(name: stName, allStations: knownStations, fallbackNearby: nearbyStation) else {
                return .message("Non ho trovato la stazione richiesta nei sistemi ferroviari.")
            }
            return .stationBoard(station: resolved, isArrivals: parsed.isArrivals)

        case .routeSolutions:
            let rawOrig = parsed.originStation ?? nearbyStation?.name
            let rawDest = parsed.destinationStation
            guard let rawDest, !rawDest.isEmpty else {
                return .message("Per cercare soluzioni reali indica la stazione di arrivo.")
            }
            guard let rawOrig, !rawOrig.isEmpty else {
                return .message("Per trovare il percorso verso \(rawDest) attiva la posizione GPS oppure indica la stazione di partenza.")
            }
            let targetDt = parsed.resolvedDate()
            let origResolved = await resolveStation(name: rawOrig, allStations: knownStations, fallbackNearby: nearbyStation, forRouteSearch: true)
            let destResolved = await resolveStation(name: rawDest, allStations: knownStations, fallbackNearby: nil, forRouteSearch: true)

            let finalOrigName = origResolved?.name ?? LocalExactQueryParser.applyKnownAlias(rawOrig)
            let finalDestName = destResolved?.name ?? LocalExactQueryParser.applyKnownAlias(rawDest)
            if finalOrigName.lowercased() == finalDestName.lowercased() {
                return .message("Ti trovi già vicino a \(finalDestName.formattedStationName). Specifica una stazione di partenza diversa.")
            }
            let initialOrigID = origResolved?.rfiID ?? origResolved?.vtID ?? ""
            let initialDestID = destResolved?.rfiID ?? destResolved?.vtID ?? ""
            let hasExplicitTime = SmartQueryPostProcessor.cleanOptString(parsed.targetTime) != nil

            let routeRes = await searchSolutionsWithUrbanBridge(
                manager: manager,
                originName: finalOrigName,
                destName: finalDestName,
                originID: initialOrigID,
                destID: initialDestID,
                date: targetDt,
                hasExplicitTargetTime: hasExplicitTime
            )
            return .solutions(
                solutions: routeRes.solutions,
                origin: finalOrigName,
                destination: finalDestName,
                originID: routeRes.originID,
                destID: routeRes.destID,
                searchDate: targetDt
            )

        case .unknown:
            return .message(parsed.clarification ?? "Non ho capito con certezza la richiesta. Riprova specificando tratte, stazioni o orari.")
        }
    }

    private func stationHubPriorityScore(_ stationName: String) -> Int {
        let up = stationName.uppercased()
        var score = 0
        if up.contains("CENTRALE") { score += 100 }
        if up.contains("PORTA GARIBALDI") && !up.contains("SOTTERRANEA") { score += 90 }
        if up.contains("PORTA NUOVA") { score += 90 }
        if up.contains("TERMINI") { score += 95 }
        if up.contains("SANTA MARIA NOVELLA") { score += 90 }
        if up.contains("SANTA LUCIA") { score += 90 }
        if up.contains("PIAZZA PRINCIPE") { score += 90 }
        if up.contains("S. GIOVANNI") || up.contains("S.GIOVANNI") { score += 85 }
        return score - stationName.count
    }

    func resolveStation(
        name rawName: String,
        allStations: [RFIStation],
        fallbackNearby: Station?,
        forRouteSearch: Bool = false
    ) async -> Station? {
        let rawTrimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawNorm = rawTrimmed.lowercased()
        let aliased = LocalExactQueryParser.applyKnownAlias(rawTrimmed)
        let norm = aliased.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Hub cittadini: nelle tratte (es. "da Magenta a Milano") non risolvere mai a "MILANO AFFORI"
        let cityHubs: [String: (routeName: String, routeRfiID: String?, boardName: String, vtID: String)] = [
            "milano": ("Milano", "830001650", "Milano Centrale", "S01700"),
            "roma": ("Roma", nil, "Roma Termini", "S08409"),
            "torino": ("Torino", nil, "Torino Porta Nuova", "S00219"),
            "venezia": ("Venezia", nil, "Venezia S.Lucia", "S02593"),
            "firenze": ("Firenze", nil, "Firenze Santa Maria Novella", "S06421"),
            "napoli": ("Napoli", nil, "Napoli Centrale", "S09218"),
            "bologna": ("Bologna", nil, "Bologna Centrale", "S05043"),
            "genova": ("Genova", nil, "Genova Piazza Principe", "S04700")
        ]
        if let hub = cityHubs[rawNorm] ?? cityHubs[norm] {
            if forRouteSearch {
                return Station(name: hub.routeName, rfiID: hub.routeRfiID, vtID: hub.vtID)
            } else if let boardExact = allStations.first(where: { $0.name.lowercased() == hub.boardName.lowercased() }) {
                return Station(name: boardExact.name, rfiID: boardExact.rfiID, vtID: boardExact.vtID, lat: boardExact.lat, lon: boardExact.lon)
            } else {
                return Station(name: hub.boardName, rfiID: nil, vtID: hub.vtID)
            }
        }

        if let nearby = fallbackNearby, nearby.name.lowercased() == norm {
            return nearby
        }

        if let exact = allStations.first(where: { $0.name.lowercased() == norm }) {
            return Station(name: exact.name, rfiID: exact.rfiID, vtID: exact.vtID, lat: exact.lat, lon: exact.lon)
        }
        let prefixCandidates = allStations.filter {
            let low = $0.name.lowercased()
            return low.hasPrefix(norm + " ") || low.hasPrefix(norm + "-")
        }
        if let bestPrefix = prefixCandidates.max(by: { stationHubPriorityScore($0.name) < stationHubPriorityScore($1.name) }) {
            return Station(name: bestPrefix.name, rfiID: bestPrefix.rfiID, vtID: bestPrefix.vtID, lat: bestPrefix.lat, lon: bestPrefix.lon)
        }
        if let prefixFallback = allStations.first(where: { $0.name.lowercased().hasPrefix(norm) }) {
            return Station(name: prefixFallback.name, rfiID: prefixFallback.rfiID, vtID: prefixFallback.vtID, lat: prefixFallback.lat, lon: prefixFallback.lon)
        }
        if let contains = allStations.first(where: { $0.name.lowercased().contains(norm) && $0.vtID != nil }) {
            return Station(name: contains.name, rfiID: contains.rfiID, vtID: contains.vtID, lat: contains.lat, lon: contains.lon)
        }

        // Fallback su ViaggiaTreno autocompletaStazione
        let encoded = aliased.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? aliased
        if let url = URL(string: "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/autocompletaStazione/\(encoded)") {
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            if let (data, _) = try? await NetworkService.shared.get(request: req),
               let body = String(data: data, encoding: .utf8) {
                for line in body.components(separatedBy: .newlines) {
                    let parts = line.split(separator: "|", maxSplits: 1)
                    if parts.count == 2 {
                        let stName = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines).capitalized
                        let vtCode = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !vtCode.isEmpty {
                            return Station(name: stName, rfiID: nil, vtID: vtCode)
                        }
                    }
                }
            }
        }
        return nil
    }

    func fetchTrainAtTime(
        station: Station,
        targetDate: Date,
        requestedHHmm: String?,
        destinationHint: String?,
        manager: TrainManager? = nil
    ) async -> (matched: Train?, candidates: [Train]) {
        let isNearNow = abs(targetDate.timeIntervalSinceNow) <= 4500 // entro ±75 min

        // 1. Tentativo live su ViaggiaTreno / RFI solo se l'orario richiesto è vicino a quello attuale
        var liveBoard: [Train] = []
        if isNearNow {
            if let vtID = station.vtID, !vtID.isEmpty {
                let queryDate = targetDate.addingTimeInterval(-15 * 60)
                liveBoard = await StationRepository.shared.fetchVTDepartures(vtID: vtID, at: queryDate)
            }
            if liveBoard.isEmpty {
                let board = await StationRepository.shared.getStationBoard(station: station, isDepartures: true, force: true)
                liveBoard = board.trains
            }
            if let liveMatch = matchTrainInList(liveBoard, requestedHHmm: requestedHHmm, destinationHint: destinationHint) {
                let nearbySample = filterTrainsNearTime(liveBoard, requestedHHmm: requestedHHmm, maxDeltaMinutes: 60)
                return (liveMatch, nearbySample)
            }
        }

        // 2. Se l'orario richiesto è fuori dalla finestra live (es. cerco le 11:34 quando sono le 21:44)
        // interroghiamo il catalogo orari ufficiali Trenitalia verso le direttrici reali della stazione
        if let requestedHHmm, !requestedHHmm.isEmpty, let manager {
            if liveBoard.isEmpty {
                let board = await StationRepository.shared.getStationBoard(station: station, isDepartures: true, force: false)
                liveBoard = board.trains
            }

            var probeDestinations: [String] = []
            var seenProbe = Set<String>()
            func appendProbe(_ raw: String?) {
                guard let clean = SmartQueryPostProcessor.cleanOptString(raw) else { return }
                let low = clean.lowercased()
                if low == station.name.lowercased() { return }
                if seenProbe.insert(low).inserted {
                    probeDestinations.append(clean)
                }
            }

            appendProbe(destinationHint)
            for tr in liveBoard {
                appendProbe(tr.destination)
                if probeDestinations.count >= 4 { break }
            }
            if probeDestinations.count < 3 {
                for st in manager.myStations {
                    appendProbe(st.name)
                    if probeDestinations.count >= 4 { break }
                }
            }
            for fallback in ["Milano Centrale", "Milano Porta Garibaldi", "Novara", "Torino Porta Nuova"] {
                if probeDestinations.count >= 4 { break }
                appendProbe(fallback)
            }

            // Se l'orario richiesto è già passato oggi, spostiamo di +24h per recuperare da LeFrecce l'orario programmato
            var probeDate = targetDate
            if probeDate < Date().addingTimeInterval(-300) {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
                probeDate = cal.date(byAdding: .day, value: 1, to: probeDate) ?? probeDate
            }
            let searchWindowStart = probeDate.addingTimeInterval(-10 * 60)
            let origID = station.rfiID ?? station.vtID ?? ""
            let origCleanPrefix = station.name.lowercased().split(separator: " ").first.map(String.init) ?? station.name.lowercased()

            var scheduledTrains: [Train] = []
            await withTaskGroup(of: [Train].self) { group in
                for destName in probeDestinations.prefix(4) {
                    group.addTask {
                        let res = await manager.queryTravelSolutionsDirect(
                            originID: origID,
                            destID: "",
                            date: searchWindowStart,
                            originName: station.name,
                            destName: destName
                        )
                        return res.solutions.compactMap { sol -> Train? in
                            guard let firstRail = sol.segments.first(where: { !$0.isStationWalk && !$0.trainCategory.lowercased().contains("metro") }) else {
                                return nil
                            }
                            let segOrigLow = firstRail.origin.lowercased()
                            guard segOrigLow.contains(origCleanPrefix) || origCleanPrefix.isEmpty else {
                                return nil
                            }
                            let rawNum = firstRail.trainNumber.filter { $0.isNumber }
                            guard !rawNum.isEmpty else { return nil }
                            let destDisplay = firstRail.destination.isEmpty ? destName : firstRail.destination
                            return Train(
                                category: firstRail.trainCategory,
                                number: rawNum,
                                destination: destDisplay,
                                time: firstRail.departureTime,
                                delay: "Programmato",
                                platform: "--",
                                origin: station.name
                            )
                        }
                    }
                }
                for await batch in group {
                    scheduledTrains.append(contentsOf: batch)
                }
            }

            var deduped: [Train] = []
            var seenKeys = Set<String>()
            for tr in scheduledTrains {
                let key = "\(tr.number)_\(tr.time)"
                if seenKeys.insert(key).inserted {
                    deduped.append(tr)
                }
            }
            deduped.sort { (minutesFromHHMM($0.time) ?? 9999) < (minutesFromHHMM($1.time) ?? 9999) }

            var matched = matchTrainInList(deduped, requestedHHmm: requestedHHmm, destinationHint: destinationHint)
            if let m = matched {
                // Prova ad arricchire con stato/capolinea reale odierno da ViaggiaTreno se compatibile
                let stopsRes = await manager.fetchLiveStops(for: m.number)
                if !stopsRes.stops.isEmpty {
                    let origMatch = stopsRes.stops.first {
                        $0.stationName.lowercased().contains(origCleanPrefix)
                    }
                    let lastStop = stopsRes.stops.last
                    let depTimeAtOrigin = origMatch?.time ?? m.time
                    if let reqM = minutesFromHHMM(requestedHHmm),
                       let depM = minutesFromHHMM(depTimeAtOrigin),
                       circularMinutesDiff(reqM, depM) <= 15 {
                        let delayVal = origMatch?.delay ?? lastStop?.delay ?? 0
                        let liveDelay: String
                        if stopsRes.status.statusMessage.lowercased().contains("soppresso") {
                            liveDelay = "Soppresso"
                        } else if delayVal > 0 {
                            liveDelay = "+\(delayVal)'"
                        } else {
                            liveDelay = "In orario"
                        }
                        matched = Train(
                            category: m.category,
                            number: m.number,
                            destination: lastStop?.stationName.isEmpty == false ? lastStop!.stationName : m.destination,
                            time: depTimeAtOrigin,
                            delay: liveDelay,
                            platform: origMatch?.actualPlatform ?? origMatch?.plannedPlatform ?? m.platform,
                            origin: stopsRes.stops.first?.stationName ?? station.name
                        )
                    }
                }
            }

            let nearbySample = filterTrainsNearTime(deduped, requestedHHmm: requestedHHmm, maxDeltaMinutes: 60)
            return (matched, nearbySample)
        }

        let matched = matchTrainInList(liveBoard, requestedHHmm: requestedHHmm, destinationHint: destinationHint)
        let sample = filterTrainsNearTime(liveBoard, requestedHHmm: requestedHHmm, maxDeltaMinutes: 60)
        return (matched, sample)
    }

    func matchTrainInList(_ trains: [Train], requestedHHmm: String?, destinationHint: String?) -> Train? {
        guard !trains.isEmpty else { return nil }
        let destFilter = destinationHint?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        func matchesDest(_ train: Train) -> Bool {
            guard let destFilter, !destFilter.isEmpty else { return true }
            return train.destination.lowercased().contains(destFilter)
        }

        if let requestedHHmm, !requestedHHmm.isEmpty {
            if let exactWithDest = trains.first(where: { $0.time == requestedHHmm && matchesDest($0) }) {
                return exactWithDest
            }
            if let exactTime = trains.first(where: { $0.time == requestedHHmm }) {
                return exactTime
            }
            if let reqMin = minutesFromHHMM(requestedHHmm) {
                let candidates = trains.compactMap { tr -> (Train, Int)? in
                    guard let m = minutesFromHHMM(tr.time) else { return nil }
                    let diff = circularMinutesDiff(reqMin, m)
                    guard diff <= 15 else { return nil }
                    return (tr, diff)
                }
                if let bestWithDest = candidates.filter({ matchesDest($0.0) }).min(by: { $0.1 < $1.1 })?.0 {
                    return bestWithDest
                }
                if let closest = candidates.min(by: { $0.1 < $1.1 })?.0 {
                    return closest
                }
            }
            // MAI restituire un treno di un altro orario (es. 21:41 quando l'utente cerca 11:34)
            return nil
        }
        return trains.first(where: matchesDest) ?? trains.first
    }

    private func filterTrainsNearTime(_ trains: [Train], requestedHHmm: String?, maxDeltaMinutes: Int) -> [Train] {
        guard let requestedHHmm, !requestedHHmm.isEmpty, let reqMin = minutesFromHHMM(requestedHHmm) else {
            return trains
        }
        return trains.filter { tr in
            guard let m = minutesFromHHMM(tr.time) else { return false }
            return circularMinutesDiff(reqMin, m) <= maxDeltaMinutes
        }
    }

    private func circularMinutesDiff(_ a: Int, _ b: Int) -> Int {
        let diff = abs(a - b)
        return min(diff, 1440 - diff)
    }

    private func filterSolutionsAroundTargetTime(_ solutions: [TravelSolution], targetDate: Date) -> [TravelSolution] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let comps = cal.dateComponents([.hour, .minute], from: targetDate)
        let targetMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let filtered = solutions.filter { sol in
            guard let depMin = minutesFromHHMM(sol.departureTime) else { return false }
            var diff = depMin - targetMin
            if diff < -720 { diff += 1440 }
            if diff > 720 { diff -= 1440 }
            return (-5...180).contains(diff)
        }
        return filtered.isEmpty ? solutions : filtered
    }

    func searchSolutionsWithUrbanBridge(
        manager: TrainManager,
        originName: String,
        destName: String,
        originID: String,
        destID: String,
        date: Date,
        hasExplicitTargetTime: Bool = false
    ) async -> (solutions: [TravelSolution], originID: String, destID: String) {
        let queryDate = hasExplicitTargetTime ? date.addingTimeInterval(-10 * 60) : date
        let direct = await manager.queryTravelSolutionsDirect(
            originID: originID,
            destID: destID,
            date: queryDate,
            originName: originName,
            destName: destName
        )
        if !direct.solutions.isEmpty {
            let finalSolutions = hasExplicitTargetTime
                ? filterSolutionsAroundTargetTime(direct.solutions, targetDate: date)
                : direct.solutions
            return (finalSolutions, direct.resolvedOriginID, direct.resolvedDestID)
        }

        let origLower = originName.lowercased()
        let destLower = destName.lowercased()
        let isOrigCadorna = origLower.contains("cadorna") && !destLower.contains("milano")
        let isDestCadorna = destLower.contains("cadorna") && !origLower.contains("milano")

        // Ponte multimodale reale: se Milano Cadorna (Trenord/FNM) non ha soluzioni dirette verso stazioni RFI,
        // abbina Metro M2 reale (GTFS ATM locale / backend) + vere soluzioni ferroviarie da Milano Porta Garibaldi.
        if isOrigCadorna {
            let depHHmm = SharedFormatters.time.string(from: queryDate)
            let sampleMetro = TrainManager.localResolveUrbanLeg(orig: "Milano Nord Cadorna", dest: "Milano Porta Garibaldi", time: depHHmm)
            let metroMins = sampleMetro?.mins ?? 8
            let transferDate = queryDate.addingTimeInterval(TimeInterval((metroMins + 4) * 60))
            let railRes = await manager.queryTravelSolutionsDirect(
                originID: "830001645",
                destID: destID,
                date: transferDate,
                originName: "Milano Porta Garibaldi",
                destName: destName
            )
            let composed = railRes.solutions.map { sol -> TravelSolution in
                let railMins = minutesFromHHMM(sol.departureTime) ?? 0
                let boardMins = max(0, railMins - metroMins - 4)
                let metroDepStr = String(format: "%02d:%02d", (boardMins / 60) % 24, boardMins % 60)
                let legMetro = TrainManager.localResolveUrbanLeg(orig: "Milano Nord Cadorna", dest: "Milano Porta Garibaldi", time: metroDepStr)
                let mSeg = TravelSegment(
                    origin: "Milano Nord Cadorna",
                    destination: "Milano Porta Garibaldi",
                    departureTime: legMetro?.dep ?? metroDepStr,
                    arrivalTime: legMetro?.arr ?? sol.departureTime,
                    trainNumber: legMetro != nil ? "\(legMetro!.line) (Metro)" : "(Metro / Mezzi)",
                    trainCategory: legMetro != nil ? "Metro \(legMetro!.line)" : "Trasporto Urbano",
                    travelMinutes: legMetro?.mins ?? metroMins,
                    urbanHeadsign: legMetro?.headsign,
                    isStationWalk: false
                )
                let allSegs = [mSeg] + sol.segments
                let totalDur = computeDurationString(startHHmm: mSeg.departureTime, endHHmm: sol.arrivalTime) ?? sol.duration
                return TravelSolution(
                    trainNumber: sol.trainNumber,
                    category: sol.category,
                    departureTime: mSeg.departureTime,
                    arrivalTime: sol.arrivalTime,
                    origin: "Milano Nord Cadorna",
                    destination: sol.destination,
                    duration: totalDur,
                    segments: allSegs
                )
            }
            if !composed.isEmpty {
                let finalComposed = hasExplicitTargetTime
                    ? filterSolutionsAroundTargetTime(composed, targetDate: date)
                    : composed
                return (finalComposed, direct.resolvedOriginID, railRes.resolvedDestID)
            }
        } else if isDestCadorna {
            let railRes = await manager.queryTravelSolutionsDirect(
                originID: originID,
                destID: "830001645",
                date: queryDate,
                originName: originName,
                destName: "Milano Porta Garibaldi"
            )
            let composed = railRes.solutions.map { sol -> TravelSolution in
                let arrMins = minutesFromHHMM(sol.arrivalTime) ?? 0
                let metroDepMins = (arrMins + 3) % 1440
                let metroDepStr = String(format: "%02d:%02d", metroDepMins / 60, metroDepMins % 60)
                let legMetro = TrainManager.localResolveUrbanLeg(orig: "Milano Porta Garibaldi", dest: "Milano Nord Cadorna", time: metroDepStr)
                let mSeg = TravelSegment(
                    origin: "Milano Porta Garibaldi",
                    destination: "Milano Nord Cadorna",
                    departureTime: legMetro?.dep ?? metroDepStr,
                    arrivalTime: legMetro?.arr ?? sol.arrivalTime,
                    trainNumber: legMetro != nil ? "\(legMetro!.line) (Metro)" : "(Metro / Mezzi)",
                    trainCategory: legMetro != nil ? "Metro \(legMetro!.line)" : "Trasporto Urbano",
                    travelMinutes: legMetro?.mins ?? 8,
                    urbanHeadsign: legMetro?.headsign,
                    isStationWalk: false
                )
                let allSegs = sol.segments + [mSeg]
                let finalArr = mSeg.arrivalTime
                let totalDur = computeDurationString(startHHmm: sol.departureTime, endHHmm: finalArr) ?? sol.duration
                return TravelSolution(
                    trainNumber: sol.trainNumber,
                    category: sol.category,
                    departureTime: sol.departureTime,
                    arrivalTime: finalArr,
                    origin: sol.origin,
                    destination: "Milano Nord Cadorna",
                    duration: totalDur,
                    segments: allSegs
                )
            }
            if !composed.isEmpty {
                let finalComposed = hasExplicitTargetTime
                    ? filterSolutionsAroundTargetTime(composed, targetDate: date)
                    : composed
                return (finalComposed, railRes.resolvedOriginID, direct.resolvedDestID)
            }
        }

        return (direct.solutions, direct.resolvedOriginID, direct.resolvedDestID)
    }

    private func minutesFromHHMM(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    private func computeDurationString(startHHmm: String, endHHmm: String) -> String? {
        guard let s = minutesFromHHMM(startHHmm), let e = minutesFromHHMM(endHHmm) else { return nil }
        var diff = e - s
        if diff < 0 { diff += 1440 }
        let h = diff / 60
        let m = diff % 60
        return h > 0 ? String(format: "%dh %02dmin", h, m) : "\(m)min"
    }
}
