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
    var progress: Double = 0.0
    
    var shortCategoryText: String {
        guard let cat = category?.trimmingCharacters(in: .whitespacesAndNewlines), !cat.isEmpty else {
            return "Treno"
        }
        let upper = cat.uppercased()
        switch upper {
        case "REG": return "Reg"
        case "RV": return "Reg. Veloce"
        case "FR": return "FrRossa"
        case "FA": return "FrArgento"
        case "FB": return "FrBianca"
        case "IC": return "Intercity"
        case "ICN": return "IC Notte"
        case "EC": return "Eurocity"
        case "EN": return "Euronight"
        case "XP", "MXP": return "Malpensa Exp"
        default: return cat
        }
    }
    
    var categoryThemeColor: Color {
        guard let cat = category?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) else {
            return Color(red: 0.95, green: 0.45, blue: 0.10)
        }
        if cat.contains("FR") || cat.contains("FRECCIAROSSA") {
            return Color(red: 0.77, green: 0.08, blue: 0.11)
        } else if cat.contains("FA") || cat.contains("FRECCIARGENTO") {
            return Color(white: 0.35)
        } else if cat.contains("FB") || cat.contains("FRECCIABIANCA") {
            return Color(red: 0.15, green: 0.45, blue: 0.75)
        } else if cat.contains("ITALO") {
            return Color(red: 0.65, green: 0.05, blue: 0.15)
        } else if cat.contains("IC") || cat.contains("INTERCITY") {
            return Color(red: 0.0, green: 0.48, blue: 0.55)
        } else if cat.contains("REG") || cat.contains("RV") {
            return Color(red: 0.95, green: 0.45, blue: 0.10)
        } else if cat.contains("XP") || cat.contains("MXP") {
            return Color(red: 0.75, green: 0.10, blue: 0.25)
        } else if cat.hasPrefix("S") {
            return Color(red: 0.15, green: 0.65, blue: 0.35)
        }
        return Color(red: 0.95, green: 0.45, blue: 0.10)
    }
    
    var displayTitle: String {
        let num = number.trimmingCharacters(in: .whitespacesAndNewlines)
        let cat = shortCategoryText
        if num.uppercased().hasPrefix(cat.uppercased()) {
            return num
        }
        return "\(cat) \(num)"
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
        delayText.localizedCaseInsensitiveContains("ritardo") || isCancelled
    }
    
    var middleStationToDisplay: String? {
        guard isDeparted && !isArrived,
              let last = lastStation?.trimmingCharacters(in: .whitespacesAndNewlines),
              !last.isEmpty, last != "--" else {
            return nil
        }
        let lastLower = last.lowercased()
        if let orig = originStation?.lowercased(), lastLower == orig || lastLower.contains(orig) || orig.contains(lastLower) {
            return nil
        }
        if let dest = destinationStation?.lowercased(), lastLower == dest || lastLower.contains(dest) || dest.contains(lastLower) {
            return nil
        }
        return last
    }
}

// MARK: - Progress Bar Component

struct TrainProgressBar: View {
    let progress: Double
    let isDeparted: Bool
    let isArrived: Bool
    let accentColor: Color
    var barHeight: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let dotRadius: CGFloat = 3.5
            let haloRadius: CGFloat = 6.5
            let clampedProgress = min(max(CGFloat(progress), 0.0), 1.0)
            let currentX: CGFloat = isArrived ? (w - dotRadius) : (!isDeparted ? dotRadius : min(max(w * clampedProgress, dotRadius + 3), w - dotRadius - 3))

            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 3)

                // Completed progress track
                if isDeparted {
                    Capsule()
                        .fill(accentColor)
                        .frame(width: isArrived ? w : currentX, height: 3)
                }

                // Origin dot
                Circle()
                    .fill(isDeparted ? accentColor : Color.secondary.opacity(0.6))
                    .frame(width: dotRadius * 2, height: dotRadius * 2)
                    .position(x: dotRadius, y: geo.size.height / 2)

                // Current position dot with glowing halo
                if isDeparted && !isArrived {
                    Circle()
                        .fill(accentColor.opacity(0.3))
                        .frame(width: haloRadius * 2, height: haloRadius * 2)
                        .position(x: currentX, y: geo.size.height / 2)

                    Circle()
                        .fill(accentColor)
                        .frame(width: dotRadius * 2, height: dotRadius * 2)
                        .position(x: currentX, y: geo.size.height / 2)
                }

                // Destination terminal dot
                Circle()
                    .strokeBorder(isArrived ? accentColor : Color.secondary.opacity(0.4), lineWidth: 2)
                    .background(Circle().fill(isArrived ? accentColor : Color(.systemBackground)))
                    .frame(width: dotRadius * 2, height: dotRadius * 2)
                    .position(x: w - dotRadius, y: geo.size.height / 2)
            }
        }
        .frame(height: barHeight)
    }
}

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), trains: [
            WidgetTrainData(
                number: "2017",
                description: "Torino P.N. - Milano C.le",
                delayText: "Ritardo 4 min",
                delayColor: .red,
                category: "Regionale",
                departureTime: "12:28",
                arrivalTime: "13:12",
                originStation: "Torino P.N.",
                destinationStation: "Milano C.le",
                lastStation: "Novara",
                detectionTime: "12:55",
                isDeparted: true,
                isArrived: false,
                isCancelled: false,
                progress: 0.65
            ),
            WidgetTrainData(
                number: "9616",
                description: "Napoli C.le - Firenze S.M.N.",
                delayText: "Ritardo 12 min",
                delayColor: .red,
                category: "FR",
                departureTime: "14:08",
                arrivalTime: "17:00",
                originStation: "Napoli C.le",
                destinationStation: "Firenze S.M.N.",
                lastStation: "Roma Termini",
                detectionTime: "15:17",
                isDeparted: true,
                isArrived: false,
                isCancelled: false,
                progress: 0.42
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
            progress: 0.0
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
        
        // Calcolo progresso percorso
        var progress: Double = 0.0
        if isArrived {
            progress = 1.0
        } else if isDeparted {
            if let fermate = json["fermate"] as? [[String: Any]], fermate.count > 1 {
                let passedCount = fermate.filter { ($0["effettiva"] as? Int ?? 0) > 0 }.count
                if passedCount > 0 {
                    progress = Double(passedCount) / Double(fermate.count - 1)
                } else if let last = lastStation?.lowercased() {
                    if let idx = fermate.firstIndex(where: { (($0["stazione"] as? String) ?? "").lowercased().contains(last) || last.contains((($0["stazione"] as? String) ?? "").lowercased()) }) {
                        progress = Double(idx) / Double(fermate.count - 1)
                    } else {
                        progress = 0.4
                    }
                } else {
                    progress = 0.35
                }
            } else {
                progress = 0.4
            }
            progress = min(0.92, max(0.08, progress))
        }
        
        // Parsing dello stato e ritardo
        var delayText = fallback.0
        var delayColor = fallback.1
        
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
                    if let min = extractMinutes(from: ritardoText) {
                        delayText = "Ritardo \(min) min"
                    } else {
                        delayText = "In ritardo"
                    }
                    delayColor = .red
                } else if ritardoText.localizedCaseInsensitiveContains("anticipo") {
                    if let min = extractMinutes(from: ritardoText) {
                        delayText = "Anticipo \(min) min"
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
            progress: progress
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
                    Text(train.displayTitle)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    
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
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 5) {
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
                switch family {
                case .systemSmall:
                    smallContent
                case .systemMedium:
                    mediumContent
                default:
                    largeContent
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, family == .systemSmall ? 2 : 4)
    }

    @ViewBuilder
    private var mediumContent: some View {
        let count = entry.trains.count
        if count == 1 {
            Link(destination: URL(string: "inorario://\(entry.trains[0].number)")!) {
                richTrainCard(train: entry.trains[0], isCompact: false)
            }
        } else if count == 2 {
            VStack(spacing: 6) {
                Link(destination: URL(string: "inorario://\(entry.trains[0].number)")!) {
                    richTrainCard(train: entry.trains[0], isCompact: false)
                }
                Divider().opacity(0.35)
                Link(destination: URL(string: "inorario://\(entry.trains[1].number)")!) {
                    richTrainCard(train: entry.trains[1], isCompact: false)
                }
            }
        } else {
            // 3 treni o più: Primi 2 con timeline, terzo normale
            VStack(spacing: 4) {
                Link(destination: URL(string: "inorario://\(entry.trains[0].number)")!) {
                    richTrainCard(train: entry.trains[0], isCompact: true)
                }
                Divider().opacity(0.3)
                Link(destination: URL(string: "inorario://\(entry.trains[1].number)")!) {
                    richTrainCard(train: entry.trains[1], isCompact: true)
                }
                Divider().opacity(0.3)
                Link(destination: URL(string: "inorario://\(entry.trains[2].number)")!) {
                    normalTrainRow(train: entry.trains[2])
                }
            }
        }
    }

    @ViewBuilder
    private var smallContent: some View {
        let count = entry.trains.count
        if count == 1 {
            Link(destination: URL(string: "inorario://\(entry.trains[0].number)")!) {
                richTrainCard(train: entry.trains[0], isCompact: true)
            }
        } else {
            VStack(spacing: 4) {
                Link(destination: URL(string: "inorario://\(entry.trains[0].number)")!) {
                    richTrainCard(train: entry.trains[0], isCompact: true)
                }
                Divider().opacity(0.3)
                Link(destination: URL(string: "inorario://\(entry.trains[1].number)")!) {
                    normalTrainRow(train: entry.trains[1])
                }
            }
        }
    }

    @ViewBuilder
    private var largeContent: some View {
        let trains = Array(entry.trains.prefix(4))
        VStack(spacing: 6) {
            ForEach(Array(trains.enumerated()), id: \.element.id) { index, train in
                if index > 0 {
                    Divider().opacity(0.35)
                }
                Link(destination: URL(string: "inorario://\(train.number)")!) {
                    if trains.count >= 4 && index == 3 {
                        normalTrainRow(train: train)
                    } else {
                        richTrainCard(train: train, isCompact: false)
                    }
                }
            }
        }
    }

    private func normalTrainRow(train: WidgetTrainData) -> some View {
        HStack(alignment: .center, spacing: 6) {
            HStack(spacing: 3) {
                Text(train.shortCategoryText)
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(train.categoryThemeColor)
                Text(train.number)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)
            }

            Text("•")
                .font(.system(size: 9))
                .foregroundColor(.secondary)

            Text(train.destinationStation ?? train.description)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let time = train.departureTime, !time.isEmpty, time != "--:--" {
                Text(time)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            Text(train.shortDelayBadge)
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(train.delayColor)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
    }

    private func richTrainCard(train: WidgetTrainData, isCompact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 1 : 2) {
            // Line 1: Header (Category + Number ... Delay badge)
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 4) {
                    Text(train.shortCategoryText)
                        .font(.system(size: isCompact ? 11 : 13, weight: .black))
                        .foregroundColor(train.categoryThemeColor)

                    Text(train.number)
                        .font(.system(size: isCompact ? 11 : 13, weight: .bold))
                        .foregroundColor(.primary)
                }

                Spacer(minLength: 4)

                Text(train.shortDelayBadge)
                    .font(.system(size: isCompact ? 10 : 12, weight: .heavy))
                    .foregroundColor(train.delayColor)
            }

            // Line 2: Station Names
            HStack(alignment: .center) {
                Text(train.originStation ?? "Partenza")
                    .font(.system(size: isCompact ? 9 : 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 4)

                if let mid = train.middleStationToDisplay {
                    Text(mid)
                        .font(.system(size: isCompact ? 9 : 10, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 4)
                }

                Text(train.destinationStation ?? train.description)
                    .font(.system(size: isCompact ? 9 : 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            // Line 3: Progress track
            TrainProgressBar(
                progress: train.progress,
                isDeparted: train.isDeparted,
                isArrived: train.isArrived,
                accentColor: train.categoryThemeColor,
                barHeight: isCompact ? 10 : 12
            )

            // Line 4: Times
            HStack(alignment: .center) {
                Text(train.departureTime ?? "--:--")
                    .font(.system(size: isCompact ? 9 : 10, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                if train.middleStationToDisplay != nil, let det = train.detectionTime {
                    Text(det)
                        .font(.system(size: isCompact ? 9 : 10, weight: .heavy))
                        .foregroundColor(train.categoryThemeColor)

                    Spacer()
                }

                Text(train.arrivalTime ?? "--:--")
                    .font(.system(size: isCompact ? 9 : 10, weight: .semibold))
                    .foregroundColor(train.isDelayed ? .red : .secondary)
            }
        }
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
