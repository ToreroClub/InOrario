import WidgetKit
import SwiftUI
import AppIntents

// MARK: - App Intent for Refresh

@available(iOS 17.0, *)
struct RefreshWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Aggiorna Widget"
    static let description = IntentDescription("Ricarica i ritardi e le posizioni dei treni nel widget.")

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Station Name Helper

func compactStationName(_ raw: String) -> String {
    var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return "" }
    
    name = name.capitalized
    
    let replacements: [(String, String)] = [
        ("Porta Nuova", "P.N."),
        ("P. Nuova", "P.N."),
        ("Centrale", "C.le"),
        ("Porta Garibaldi", "P.Gar."),
        ("P. Garibaldi", "P.Gar."),
        ("Santa Maria Novella", "S.M.N."),
        ("S. Maria Novella", "S.M.N."),
        ("S.m. Novella", "S.M.N."),
        ("Santa Lucia", "S.L."),
        ("S. Lucia", "S.L."),
        ("Aeroporto", "Aerop."),
        ("San Cristoforo", "S. Cristoforo"),
        ("San Donato", "S. Donato"),
        ("Pioltello Limito", "Pioltello L.")
    ]
    for (target, rep) in replacements {
        name = name.replacingOccurrences(of: target, with: rep, options: .caseInsensitive)
    }
    return name
}

// MARK: - Category & Time Helpers

func resolveCategory(number: String, categoryDesc: String?, destination: String?) -> String {
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
    
    // Linee suburbane lombarde basate sulla numerazione treno (S1..S13)
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

func categoryColor(for cat: String) -> Color {
    let c = cat.uppercased()
    if c.contains("FR") || c.contains("ITA") || c == "AV" { return .red }
    if c == "IC" || c == "EC" || c == "ICN" || c == "EN" { return Color(white: 0.4) }
    if c.contains("S") { return Color(red: 0.0, green: 0.6, blue: 0.2) } // Verde linee suburbane
    if c.contains("RV") || c.contains("RE") { return .blue }
    if c.contains("XP") || c.contains("MXP") { return Color(red: 0.75, green: 0.10, blue: 0.25) }
    return Color(red: 0.2, green: 0.45, blue: 0.85) // Blu regionale
}

func calculateUpdatedArrivalTime(scheduled: String?, delay: Int) -> String? {
    guard let sched = scheduled?.trimmingCharacters(in: .whitespacesAndNewlines),
          sched.contains(":") else {
        return scheduled
    }
    let parts = sched.components(separatedBy: ":")
    guard parts.count >= 2,
          let h = Int(parts[0].trimmingCharacters(in: .whitespaces)),
          let m = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
        return scheduled
    }
    
    if delay == 0 {
        return sched
    }
    
    var totalMin = h * 60 + m + delay
    if totalMin < 0 { totalMin += 1440 }
    totalMin = totalMin % 1440
    let newH = totalMin / 60
    let newM = totalMin % 60
    return String(format: "%02d:%02d", newH, newM)
}

// MARK: - Models

struct WidgetSavedTrain: Codable, Identifiable {
    var id: String { number }
    let number: String
    let description: String
    var lastDelayText: String?
    var lastDelayColorName: String?
    var category: String?
    var departureTime: String?
    var arrivalTime: String?
    var showInWidget: Bool?
}

struct WidgetTrainData: Identifiable {
    var id: String { number }
    let number: String
    let description: String
    let delayText: String
    let delayColor: Color
    var category: String? = nil
    var departureTime: String? = nil
    var arrivalTime: String? = nil
    var originStation: String? = nil
    var destinationStation: String? = nil
    var lastStation: String? = nil
    var detectionTime: String? = nil
    var isDeparted: Bool = false
    var isArrived: Bool = false
    var isCancelled: Bool = false
    var delayMinutes: Int = 0
    
    var categoryBadge: String {
        resolveCategory(number: number, categoryDesc: category, destination: destinationStation ?? description)
    }
    
    var displayTitle: String {
        let num = number.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(categoryBadge) \(num)"
    }
    
    var effectiveArrivalTime: String? {
        calculateUpdatedArrivalTime(scheduled: arrivalTime, delay: delayMinutes)
    }
    
    var shortDelayBadge: String {
        if isCancelled || delayText.localizedCaseInsensitiveContains("soppresso") {
            return "Soppresso"
        }
        if isArrived || delayText.localizedCaseInsensitiveContains("arrivato") {
            return "Arrivato"
        }
        if !isDeparted {
            return "In attesa"
        }
        let t = delayText
        if t.localizedCaseInsensitiveContains("ritardo") {
            let digits = t.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            return !digits.isEmpty ? "+\(digits)'" : "In ritardo"
        } else if t.localizedCaseInsensitiveContains("anticipo") {
            let digits = t.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            return !digits.isEmpty ? "-\(digits)'" : "In anticipo"
        } else if t.localizedCaseInsensitiveContains("orario") {
            return "In orario"
        }
        return t
    }
    
    var isDelayed: Bool {
        delayMinutes > 0 || delayText.localizedCaseInsensitiveContains("ritardo") || isCancelled
    }
}

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), trains: [
            WidgetTrainData(
                number: "24653",
                description: "Novara - Pioltello Limito",
                delayText: "Ritardo 1 min",
                delayColor: .red,
                category: "S6",
                departureTime: "15:18",
                arrivalTime: "16:37",
                originStation: "Novara",
                destinationStation: "Pioltello L.",
                lastStation: "Rho Fiera",
                detectionTime: "15:56",
                isDeparted: true,
                isArrived: false,
                isCancelled: false,
                delayMinutes: 1
            ),
            WidgetTrainData(
                number: "2029",
                description: "Torino P.N. - Milano C.le",
                delayText: "In orario",
                delayColor: .green,
                category: "RV",
                departureTime: "13:54",
                arrivalTime: "15:49",
                originStation: "Torino P.N.",
                destinationStation: "Milano C.le",
                lastStation: nil,
                detectionTime: nil,
                isDeparted: true,
                isArrived: true,
                isCancelled: false,
                delayMinutes: 0
            ),
            WidgetTrainData(
                number: "24655",
                description: "Novara - Pioltello Limito",
                delayText: "Ritardo 2 min",
                delayColor: .red,
                category: "S6",
                departureTime: "15:48",
                arrivalTime: "17:04",
                originStation: "Novara",
                destinationStation: "Pioltello L.",
                lastStation: "Magenta",
                detectionTime: "16:04",
                isDeparted: true,
                isArrived: false,
                isCancelled: false,
                delayMinutes: 2
            )
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let trains = getFavorites()
        let placeholderData = trains.isEmpty ? placeholder(in: context).trains : trains.map {
            fallbackTrain(for: $0)
        }
        let entry = SimpleEntry(date: Date(), trains: placeholderData)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        Task {
            let savedTrains = getFavorites()
            var widgetData: [WidgetTrainData] = []
            
            for train in savedTrains {
                let fb = fallbackStatus(for: train)
                let item = await fetchTrainStatusWithDetails(train: train, fallback: fb)
                widgetData.append(item)
            }
            
            let entry = SimpleEntry(date: Date(), trains: widgetData)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
    
    private func fallbackTrain(for train: WidgetSavedTrain) -> WidgetTrainData {
        let (fbDelay, fbColor) = fallbackStatus(for: train)
        let orig = originFromDesc(train.description)
        let dest = destFromDesc(train.description)
        return WidgetTrainData(
            number: train.number,
            description: train.description,
            delayText: fbDelay,
            delayColor: fbColor,
            category: train.category,
            departureTime: train.departureTime,
            arrivalTime: train.arrivalTime,
            originStation: orig,
            destinationStation: dest,
            lastStation: nil,
            detectionTime: nil,
            isDeparted: false,
            isArrived: false,
            isCancelled: false,
            delayMinutes: 0
        )
    }

    private func originFromDesc(_ desc: String) -> String? {
        let parts = desc.components(separatedBy: " - ")
        if parts.count >= 2 {
            return compactStationName(parts[0])
        }
        return nil
    }

    private func destFromDesc(_ desc: String) -> String {
        let parts = desc.components(separatedBy: " - ")
        if parts.count >= 2 {
            return compactStationName(parts[1])
        }
        return compactStationName(desc)
    }
    
    private func getFavorites() -> [WidgetSavedTrain] {
        guard let defaults = UserDefaults(suiteName: "group.carlo.InOrario"),
              let data = defaults.data(forKey: "savedFavoriteTrains_v3"),
              let decoded = try? JSONDecoder().decode([WidgetSavedTrain].self, from: data) else {
            return []
        }
        
        var excludedSet = Set<String>()
        if let rawExcludedData = defaults.data(forKey: "excludedWidgetTrainNumbers_v1"),
           let set = try? JSONDecoder().decode(Set<String>.self, from: rawExcludedData) {
            excludedSet = set
        } else if let arr = defaults.stringArray(forKey: "excludedWidgetTrainNumbers_v1") {
            excludedSet = Set(arr)
        }
        
        let filtered = decoded.filter { train in
            if excludedSet.contains(train.number) { return false }
            if train.showInWidget == false { return false }
            return true
        }
        
        let rotationEnabled = defaults.object(forKey: "widgetTimeRotationEnabled_v1") == nil ? true : defaults.bool(forKey: "widgetTimeRotationEnabled_v1")
        if rotationEnabled {
            return sortTrainsByProximity(trains: filtered)
        } else {
            return filtered
        }
    }
    
    private func sortTrainsByProximity(trains: [WidgetSavedTrain]) -> [WidgetSavedTrain] {
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let nowMinuteOfDay = currentHour * 60 + currentMinute
        
        return trains.sorted { t1, t2 in
            let score1 = proximityScore(timeStr: t1.departureTime, nowMinute: nowMinuteOfDay)
            let score2 = proximityScore(timeStr: t2.departureTime, nowMinute: nowMinuteOfDay)
            return score1 < score2
        }
    }
    
    private func proximityScore(timeStr: String?, nowMinute: Int) -> Int {
        guard let timeStr = timeStr?.trimmingCharacters(in: .whitespacesAndNewlines),
              !timeStr.isEmpty,
              timeStr != "--:--" else {
            return 9999
        }
        
        let parts = timeStr.components(separatedBy: ":")
        guard parts.count >= 2,
              let h = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let m = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return 9999
        }
        
        let trainMin = h * 60 + m
        let diff = trainMin - nowMinute
        
        // Se è partito da meno di 90 minuti (è in viaggio in questo momento!) ha priorità assoluta
        if diff >= -90 && diff < 0 {
            return abs(diff) // 0..90
        } else if diff >= 0 {
            // In partenza oggi (tra poco o più tardi)
            return 91 + diff
        } else {
            // Partito molte ore fa oggi -> il prossimo è domani (+ 1440 minuti)
            return 91 + diff + 1440
        }
    }
    
    private func fallbackStatus(for train: WidgetSavedTrain) -> (String, Color) {
        if let lastDelay = train.lastDelayText, !lastDelay.trimmingCharacters(in: .whitespaces).isEmpty {
            let color: Color
            switch train.lastDelayColorName?.lowercased() {
            case "red": color = .red
            case "green": color = .green
            case "blue": color = .blue
            case "orange": color = .orange
            default:
                if lastDelay.localizedCaseInsensitiveContains("ritardo") || lastDelay.localizedCaseInsensitiveContains("soppresso") {
                    color = .red
                } else if lastDelay.localizedCaseInsensitiveContains("orario") || lastDelay.localizedCaseInsensitiveContains("anticipo") {
                    color = .green
                } else {
                    color = .secondary
                }
            }
            return (lastDelay, color)
        }
        return ("In orario", .green)
    }
    
    private func fetchTrainStatusWithDetails(train: WidgetSavedTrain, fallback: (String, Color)) async -> WidgetTrainData {
        let cleanNumber = train.number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNumber.isEmpty else { return fallbackTrain(for: train) }
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 8.0
        sessionConfig.timeoutIntervalForResource = 12.0
        let session = URLSession(configuration: sessionConfig)
        
        let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 InOrario/1.0"
        
        // 1. Cerca autocomplete Viaggiatreno
        let urlStrings = [
            "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/cercaNumeroTrenoTrenoAutocomplete/\(cleanNumber)",
            "http://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/cercaNumeroTrenoTrenoAutocomplete/\(cleanNumber)"
        ]
        
        var responseStr: String? = nil
        for urlStr in urlStrings {
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url)
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("*/*", forHTTPHeaderField: "Accept")
            if let (data, resp) = try? await session.data(for: req),
               let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !s.isEmpty {
                responseStr = s
                break
            }
        }
        
        guard let responseStr = responseStr else {
            return fallbackTrain(for: train)
        }
        
        let lines = responseStr.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var targets = lines.filter { $0.contains("|\(cleanNumber)-") }
        if targets.isEmpty, let firstLine = lines.first { targets = [firstLine] }
        if targets.isEmpty { return fallbackTrain(for: train) }
        
        // 2. Scarica andamento treno per i target
        let results: [(String, [String: Any])] = await withTaskGroup(of: (String, [String: Any])?.self) { group in
            for targetLine in targets {
                group.addTask {
                    let pipes = targetLine.components(separatedBy: "|")
                    let subParts = pipes.count > 1 ? pipes[1].components(separatedBy: "-") : []
                    guard subParts.count >= 2 else { return nil }
                    
                    let originID = subParts[1].trimmingCharacters(in: .whitespaces)
                    let timestamp = subParts.count >= 3 ? subParts[2].trimmingCharacters(in: .whitespaces) : ""
                    let dateStr = String(timestamp.prefix(13))
                    
                    var candidateUrls: [String] = []
                    if !dateStr.isEmpty {
                        candidateUrls.append("https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/andamentoTreno/\(originID)/\(cleanNumber)/\(dateStr)")
                        candidateUrls.append("http://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/andamentoTreno/\(originID)/\(cleanNumber)/\(dateStr)")
                    }
                    candidateUrls.append("https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/andamentoTreno/\(originID)/\(cleanNumber)")
                    candidateUrls.append("http://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/andamentoTreno/\(originID)/\(cleanNumber)")
                    
                    for cUrlStr in candidateUrls {
                        guard let sUrl = URL(string: cUrlStr) else { continue }
                        var req = URLRequest(url: sUrl)
                        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                        req.setValue("application/json", forHTTPHeaderField: "Accept")
                        if let (sData, resp) = try? await session.data(for: req),
                           let http = resp as? HTTPURLResponse, http.statusCode == 200,
                           let json = try? JSONSerialization.jsonObject(with: sData) as? [String: Any] {
                            return (targetLine, json)
                        }
                    }
                    return nil
                }
            }
            var collected = [(String, [String: Any])]()
            for await res in group {
                if let r = res { collected.append(r) }
            }
            return collected
        }
        
        guard !results.isEmpty else { return fallbackTrain(for: train) }
        
        // 3. Seleziona la corsa migliore
        let nowTs = Date().timeIntervalSince1970 * 1000.0
        var bestJson: [String: Any]? = nil
        var bestScore: Double = -999999.0
        let cleanDest = train.description.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        for (targetLine, json) in results {
            let pipes = targetLine.components(separatedBy: "|")
            let subParts = pipes.count > 1 ? pipes[1].components(separatedBy: "-") : []
            let tsStr = subParts.count >= 3 ? subParts[2].trimmingCharacters(in: .whitespaces) : ""
            let trainTs = Double(String(tsStr.prefix(13))) ?? nowTs
            
            let deltaDays = abs(nowTs - trainTs) / (1000.0 * 60 * 60 * 24)
            let isDeparted = !(json["nonPartito"] as? Bool ?? true)
            let isArrived = (json["arrivato"] as? Bool) ?? false
            
            let baseScore = (isDeparted && !isArrived) ? 10000.0 : 1000.0
            var score = baseScore - (deltaDays * 500.0)
            
            if !cleanDest.isEmpty {
                let destUpper = cleanDest.uppercased()
                let destJson = ((json["destinazione"] as? String) ?? "").uppercased()
                let fermate = (json["fermate"] as? [[String: Any]]) ?? []
                let lastStopUpper = ((fermate.last?["stazione"] as? String) ?? "").uppercased()
                
                let isDirectMatch = destJson.contains(destUpper) || destUpper.contains(destJson) ||
                                    lastStopUpper.contains(destUpper) || destUpper.contains(lastStopUpper)
                if isDirectMatch {
                    score += 200_000.0
                } else if fermate.contains(where: { ((($0["stazione"] as? String) ?? "").uppercased()).contains(destUpper) }) {
                    score += 50_000.0
                } else {
                    let targetLower = targetLine.lowercased()
                    let words = cleanDest.components(separatedBy: " ").filter { $0.count > 3 }
                    var hasWord = false
                    for w in words {
                        if targetLower.contains(w) {
                            score += 5000.0
                            hasWord = true
                        }
                    }
                    if !hasWord {
                        score -= 200_000.0
                    }
                }
            }
            
            if score > bestScore {
                bestScore = score
                bestJson = json
            }
        }
        
        guard let json = bestJson ?? results.first?.1 else { return fallbackTrain(for: train) }
        
        // Estrazione dettagli aggiuntivi
        let rawCategory = (json["categoria"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCategory = (rawCategory?.isEmpty == false ? rawCategory : train.category)
        
        var rawStation = (json["stazioneUltimoRilevamento"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawStation == "--" || rawStation?.isEmpty == true {
            rawStation = nil
        }
        let lastStation = rawStation.flatMap { compactStationName($0) }
        
        var detectionTime: String? = nil
        if let compOra = json["compOraUltimoRilevamento"] as? String, !compOra.isEmpty {
            detectionTime = String(compOra.prefix(5))
        } else if let ms = json["oraUltimoRilevamento"] as? Int, ms > 0 {
            let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            formatter.timeZone = TimeZone(identifier: "Europe/Rome")
            detectionTime = formatter.string(from: date)
        } else if let oraStr = json["oraUltimoRilevamento"] as? String, !oraStr.isEmpty {
            detectionTime = String(oraStr.prefix(5))
        }
        
        // Stazioni origine e destinazione
        let rawOrigin = (json["origine"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawDest = (json["destinazione"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let originStation = (rawOrigin?.isEmpty == false ? compactStationName(rawOrigin!) : originFromDesc(train.description)) ?? "Partenza"
        let destStation = (rawDest?.isEmpty == false ? compactStationName(rawDest!) : destFromDesc(train.description))
        
        // Orari partenza e arrivo
        var depTime: String? = nil
        if let origTimeStr = (json["compOrarioPartenza"] as? String) ?? (json["orarioPartenza"] as? String), !origTimeStr.isEmpty {
            depTime = String(origTimeStr.suffix(5))
        } else {
            depTime = train.departureTime
        }
        
        var arrTime: String? = nil
        if let destTimeStr = (json["compOrarioArrivo"] as? String) ?? (json["orarioArrivo"] as? String), !destTimeStr.isEmpty {
            arrTime = String(destTimeStr.suffix(5))
        } else {
            arrTime = train.arrivalTime
        }
        
        let isNonPartito = (json["nonPartito"] as? Bool) ?? false
        let isDeparted = !isNonPartito
        let isArrived = (json["arrivato"] as? Bool) ?? false
        let isCancelled = (json["provvedimento"] as? Int ?? 0) != 0
        
        // Parsing dello stato e ritardo
        var delayText = fallback.0
        var delayColor = fallback.1
        var delayMinutes = 0
        
        if isCancelled {
            delayText = "Soppresso"
            delayColor = .red
        } else {
            let ritardoMin = json["ritardo"] as? Int
            var compRitardoStr: String? = nil
            if let compRitardi = json["compRitardo"] as? [String], let first = compRitardi.first, !first.trimmingCharacters(in: .whitespaces).isEmpty {
                compRitardoStr = first
            }
            
            if let r = ritardoMin {
                delayMinutes = r
                if r > 0 {
                    delayText = "Ritardo \(r) min"
                    delayColor = .red
                } else if r < 0 {
                    delayText = "Anticipo \(abs(r)) min"
                    delayColor = .green
                } else {
                    if isArrived {
                        delayText = "Arrivato"
                        delayColor = .secondary
                    } else {
                        delayText = "In orario"
                        delayColor = .green
                    }
                }
            } else if let ritardoText = compRitardoStr {
                if ritardoText.localizedCaseInsensitiveContains("soppresso") {
                    delayText = "Soppresso"
                    delayColor = .red
                } else if ritardoText.localizedCaseInsensitiveContains("ritardo") {
                    if let minStr = extractMinutes(from: ritardoText), let m = Int(minStr) {
                        delayMinutes = m
                        delayText = "Ritardo \(m) min"
                    } else {
                        delayText = "In ritardo"
                    }
                    delayColor = .red
                } else if ritardoText.localizedCaseInsensitiveContains("anticipo") {
                    if let minStr = extractMinutes(from: ritardoText), let m = Int(minStr) {
                        delayMinutes = -m
                        delayText = "Anticipo \(m) min"
                    } else {
                        delayText = "In anticipo"
                    }
                    delayColor = .green
                } else if ritardoText.localizedCaseInsensitiveContains("in orario") {
                    delayText = "In orario"
                    delayColor = .green
                }
            } else if isArrived {
                delayText = "Arrivato"
                delayColor = .secondary
            } else if isNonPartito {
                delayText = "In orario"
                delayColor = .green
            }
        }
        
        return WidgetTrainData(
            number: cleanNumber,
            description: train.description,
            delayText: delayText,
            delayColor: delayColor,
            category: resolvedCategory,
            departureTime: depTime,
            arrivalTime: arrTime,
            originStation: originStation,
            destinationStation: destStation,
            lastStation: lastStation,
            detectionTime: detectionTime,
            isDeparted: isDeparted,
            isArrived: isArrived,
            isCancelled: isCancelled,
            delayMinutes: delayMinutes
        )
    }
    
    private func extractMinutes(from str: String) -> String? {
        let components = str.components(separatedBy: .whitespaces)
        for comp in components {
            if Int(comp) != nil {
                return comp
            }
        }
        return nil
    }
}

// MARK: - Timeline Entry

struct SimpleEntry: TimelineEntry {
    let date: Date
    let trains: [WidgetTrainData]
}

// MARK: - Widget Entry View

struct TrainWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    private var isUnlocked: Bool {
        return true
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularWidgetBody
        case .accessoryRectangular:
            rectangularWidgetBody
        default:
            systemWidgetBody
        }
    }
    
    @ViewBuilder
    private var circularWidgetBody: some View {
        if !isUnlocked || entry.trains.isEmpty {
            Image(systemName: "tram.fill")
        } else {
            let train = entry.trains[0]
            let shortDelay = train.shortDelayBadge
                .replacingOccurrences(of: "In orario", with: "0'")
                .replacingOccurrences(of: "In attesa", with: "--")
            
            VStack(spacing: 2) {
                Image(systemName: "tram.fill")
                    .font(.system(size: 12))
                Text(shortDelay)
                    .font(.system(size: 15, weight: .bold))
            }
        }
    }
    
    @ViewBuilder
    private var rectangularWidgetBody: some View {
        if !isUnlocked || entry.trains.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("In Orario")
                    .font(.headline)
                Text("Nessun treno")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            let train = entry.trains[0]
            let shortDelay = train.shortDelayBadge
            
            let subtitleText: String = {
                if let st = train.lastStation, !st.isEmpty, st != "--" {
                    return st
                } else if let dest = train.destinationStation, !dest.isEmpty {
                    return "Per \(dest)"
                } else if !train.description.isEmpty {
                    return "Per \(train.description)"
                } else {
                    return "In attesa"
                }
            }()
            
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(train.categoryBadge)
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(categoryColor(for: train.categoryBadge))
                            .cornerRadius(3)
                        
                        Text(train.number)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                    }
                    
                    Text(subtitleText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 4)
                
                VStack(alignment: .trailing, spacing: 1) {
                    if let time = train.detectionTime, !time.isEmpty {
                        Text(time)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    Text(shortDelay)
                        .font(.system(size: 18, weight: .heavy))
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
            }
        }
    }

    private var systemWidgetBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Widget Header
            HStack(spacing: 6) {
                Image(systemName: "tram.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                Text(family == .systemSmall ? "Preferiti" : "Treni Preferiti")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                if #available(iOS 17.0, *) {
                    Button(intent: RefreshWidgetIntent()) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 1)

            if entry.trains.isEmpty {
                VStack {
                    Spacer()
                    Text("Nessun treno salvato")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                }
            } else {
                let maxTrains = family == .systemSmall ? 2 : (family == .systemLarge ? 6 : 3)
                let trainsToShow = Array(entry.trains.prefix(maxTrains))

                VStack(spacing: 4) {
                    ForEach(Array(trainsToShow.enumerated()), id: \.element.id) { index, train in
                        if index > 0 {
                            Divider().opacity(0.3)
                        }
                        Link(destination: URL(string: "inorario://\(train.number)")!) {
                            trainRowView(train: train)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, family == .systemSmall ? 2 : 4)
    }

    private func trainRowView(train: WidgetTrainData) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Riga 1: Badge Categoria + Numero treno ... Ritardo/Stato
            HStack(alignment: .center, spacing: 6) {
                // Badge Categoria (S6, RV, REG, FR, ecc.)
                Text(train.categoryBadge)
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(categoryColor(for: train.categoryBadge))
                    .cornerRadius(4)
                
                // Numero treno
                Text(train.number)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Stato / Ritardo
                HStack(spacing: 4) {
                    if train.isCancelled {
                        Text("Soppresso")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.red)
                    } else if train.isArrived {
                        Text("Arrivato")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                    } else if !train.isDeparted {
                        Text("In attesa")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    } else {
                        Circle()
                            .fill(train.delayColor)
                            .frame(width: 5, height: 5)
                        
                        Text(train.shortDelayBadge)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(train.delayColor)
                    }
                }
            }
            
            // Riga 2: Partenza con ora ➔ Ultimo ril. con ora ➔ Arrivo con ora (aggiornata in base al ritardo)
            HStack(alignment: .center, spacing: 4) {
                // 1. Partenza con ora
                HStack(spacing: 2) {
                    Text(train.originStation ?? "Partenza")
                        .foregroundColor(.secondary)
                    if let dep = train.departureTime, !dep.isEmpty, dep != "--:--" {
                        Text(dep)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                }
                .font(.system(size: 10))
                .lineLimit(1)
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.5))
                
                // 2. Ultimo rilevamento con ora (se in viaggio)
                if let lastSt = train.lastStation, !lastSt.isEmpty, lastSt != "--",
                   let det = train.detectionTime, !det.isEmpty,
                   train.isDeparted && !train.isArrived {
                    HStack(spacing: 2) {
                        Text(lastSt)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text(det)
                            .fontWeight(.heavy)
                            .foregroundColor(train.delayColor)
                    }
                    .font(.system(size: 10))
                    .lineLimit(1)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                
                // 3. Arrivo con ora (aggiornata in base al ritardo)
                HStack(spacing: 2) {
                    Text(train.destinationStation ?? train.description)
                        .foregroundColor(.secondary)
                    if let arr = train.effectiveArrivalTime, !arr.isEmpty, arr != "--:--" {
                        Text(arr)
                            .fontWeight(.semibold)
                            .foregroundColor(train.isDelayed ? .red : .primary)
                    }
                }
                .font(.system(size: 10))
                .lineLimit(1)
                
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Widget Definition

struct TrainWidget: Widget {
    let kind: String = "TrainWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                TrainWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                TrainWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Treni Preferiti")
        .description("Visualizza lo stato in tempo reale e il percorso dei tuoi treni preferiti.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}
