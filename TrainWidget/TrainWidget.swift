import WidgetKit
import SwiftUI
import AppIntents

@available(iOS 17.0, *)
struct RefreshWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Aggiorna Widget"
    static let description = IntentDescription("Ricarica i ritardi dei treni nel widget.")

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct WidgetSavedTrain: Codable, Identifiable {
    var id: String { number }
    let number: String
    let description: String
    var lastDelayText: String?
    var lastDelayColorName: String?
    var category: String?
    var departureTime: String?
}

struct WidgetTrainData: Identifiable {
    var id: String { number }
    let number: String
    let description: String
    let delayText: String
    let delayColor: Color
    var category: String? = nil
    var departureTime: String? = nil
    var lastStation: String? = nil
    var detectionTime: String? = nil
    
    var formattedCategory: String {
        guard let cat = category?.trimmingCharacters(in: .whitespacesAndNewlines), !cat.isEmpty else {
            return ""
        }
        let upper = cat.uppercased()
        switch upper {
        case "REG": return "Regionale"
        case "RV": return "Reg. Veloce"
        case "FR": return "Frecciarossa"
        case "FA": return "Frecciargento"
        case "FB": return "Frecciabianca"
        case "IC": return "Intercity"
        case "ICN": return "Intercity Notte"
        case "EC": return "Eurocity"
        case "EN": return "Euronight"
        case "XP", "MXP": return "Malpensa Express"
        case "AV": return "Alta Velocità"
        default:
            return cat
        }
    }
    
    var displayTitle: String {
        let num = number.trimmingCharacters(in: .whitespacesAndNewlines)
        let cat = formattedCategory
        if cat.isEmpty {
            return num.lowercased().hasPrefix("treno") ? num : "Treno \(num)"
        }
        if num.uppercased().hasPrefix(cat.uppercased()) || (category != nil && num.uppercased().hasPrefix(category!.uppercased())) {
            return num
        }
        return "\(cat) \(num)"
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), trains: [
            WidgetTrainData(number: "2010", description: "Milano Centrale", delayText: "In orario", delayColor: .green, category: "Regionale", lastStation: "Magenta", detectionTime: "12:15"),
            WidgetTrainData(number: "24555", description: "Treviglio", delayText: "Ritardo 5 min", delayColor: .red, category: "S5", lastStation: "Rho Fiera", detectionTime: "12:20")
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let trains = getFavorites()
        let placeholderData = trains.isEmpty ? placeholder(in: context).trains : trains.map {
            let (fbDelay, fbColor) = fallbackStatus(for: $0)
            return WidgetTrainData(
                number: $0.number,
                description: $0.description,
                delayText: fbDelay,
                delayColor: fbColor,
                category: $0.category,
                departureTime: $0.departureTime,
                lastStation: nil,
                detectionTime: nil
            )
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
                let (delay, color, lastStation, cat, detTime) = await fetchTrainStatusWithDetails(number: train.number, description: train.description, fallback: fb)
                widgetData.append(WidgetTrainData(
                    number: train.number,
                    description: train.description,
                    delayText: delay,
                    delayColor: color,
                    category: cat ?? train.category,
                    departureTime: train.departureTime,
                    lastStation: lastStation,
                    detectionTime: detTime
                ))
            }
            
            let entry = SimpleEntry(date: Date(), trains: widgetData)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
    
    private func getFavorites() -> [WidgetSavedTrain] {
        guard let defaults = UserDefaults(suiteName: "group.carlo.InOrario"),
              let data = defaults.data(forKey: "savedFavoriteTrains_v3"),
              let decoded = try? JSONDecoder().decode([WidgetSavedTrain].self, from: data) else {
            return []
        }
        return decoded
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
    
    private func fetchTrainStatusWithDetails(number: String, description: String, fallback: (String, Color)) async -> (String, Color, String?, String?, String?) {
        let cleanNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNumber.isEmpty else { return (fallback.0, fallback.1, nil, nil, nil) }
        
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
            return (fallback.0, fallback.1, nil, nil, nil)
        }
        
        let lines = responseStr.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var targets = lines.filter { $0.contains("|\(cleanNumber)-") }
        if targets.isEmpty, let firstLine = lines.first { targets = [firstLine] }
        if targets.isEmpty { return (fallback.0, fallback.1, nil, nil, nil) }
        
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
        
        guard !results.isEmpty else { return (fallback.0, fallback.1, nil, nil, nil) }
        
        // 3. Seleziona la corsa migliore
        let nowTs = Date().timeIntervalSince1970 * 1000.0
        var bestJson: [String: Any]? = nil
        var bestScore: Double = -999999.0
        let cleanDest = description.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
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
        
        guard let json = bestJson ?? results.first?.1 else { return (fallback.0, fallback.1, nil, nil, nil) }
        
        // Estrazione dettagli aggiuntivi
        let rawCategory = (json["categoria"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var rawStation = (json["stazioneUltimoRilevamento"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawStation == "--" || rawStation?.isEmpty == true {
            rawStation = nil
        }
        let lastStation = rawStation?.capitalized
        
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
        
        // 4. Parsing affidabile dello stato
        // 4a. Treno soppresso
        if let provv = json["provvedimento"] as? Int, provv != 0 {
            return ("Soppresso", .red, lastStation, rawCategory, detectionTime)
        }
        
        let isNonPartito = (json["nonPartito"] as? Bool) ?? false
        let isArrived = (json["arrivato"] as? Bool) ?? false
        let ritardoMin = json["ritardo"] as? Int
        
        var compRitardoStr: String? = nil
        if let compRitardi = json["compRitardo"] as? [String], let first = compRitardi.first, !first.trimmingCharacters(in: .whitespaces).isEmpty {
            compRitardoStr = first
        }
        
        if let r = ritardoMin {
            if r > 0 {
                return ("Ritardo \(r) min", .red, lastStation, rawCategory, detectionTime)
            } else if r < 0 {
                return ("Anticipo \(abs(r)) min", .green, lastStation, rawCategory, detectionTime)
            } else {
                if isArrived {
                    return ("Arrivato", .secondary, lastStation, rawCategory, detectionTime)
                }
                return ("In orario", .green, lastStation, rawCategory, detectionTime)
            }
        }
        
        if let ritardoText = compRitardoStr {
            if ritardoText.localizedCaseInsensitiveContains("soppresso") {
                return ("Soppresso", .red, lastStation, rawCategory, detectionTime)
            } else if ritardoText.localizedCaseInsensitiveContains("ritardo") {
                if let min = extractMinutes(from: ritardoText) {
                    return ("Ritardo \(min) min", .red, lastStation, rawCategory, detectionTime)
                }
                return ("In ritardo", .red, lastStation, rawCategory, detectionTime)
            } else if ritardoText.localizedCaseInsensitiveContains("anticipo") {
                if let min = extractMinutes(from: ritardoText) {
                    return ("Anticipo \(min) min", .green, lastStation, rawCategory, detectionTime)
                }
                return ("In anticipo", .green, lastStation, rawCategory, detectionTime)
            } else if ritardoText.localizedCaseInsensitiveContains("in orario") {
                return ("In orario", .green, lastStation, rawCategory, detectionTime)
            }
        }
        
        if isArrived {
            return ("Arrivato", .secondary, lastStation, rawCategory, detectionTime)
        }
        if isNonPartito {
            return ("In orario", .green, lastStation, rawCategory, detectionTime)
        }
        
        return (fallback.0, fallback.1, lastStation, rawCategory, detectionTime)
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

struct SimpleEntry: TimelineEntry {
    let date: Date
    let trains: [WidgetTrainData]
}

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
            Image(systemName: "train.side.front.car")
        } else {
            let train = entry.trains[0]
            let shortDelay = train.delayText
                .replacingOccurrences(of: "Ritardo ", with: "+")
                .replacingOccurrences(of: "Anticipo ", with: "-")
                .replacingOccurrences(of: " min", with: "'")
                .replacingOccurrences(of: "In orario", with: "0'")
                .replacingOccurrences(of: "In attesa", with: "--")
            
            VStack(spacing: 2) {
                Image(systemName: "train.side.front.car")
                    .font(.system(size: 12))
                Text(shortDelay)
                    .font(.system(size: 16, weight: .bold))
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
            let shortDelay: String = {
                if train.delayText.localizedCaseInsensitiveContains("soppresso") {
                    return "Soppr."
                }
                return train.delayText
                    .replacingOccurrences(of: "Ritardo ", with: "+")
                    .replacingOccurrences(of: "Anticipo ", with: "-")
                    .replacingOccurrences(of: " min", with: "'")
                    .replacingOccurrences(of: "In orario", with: "0'")
                    .replacingOccurrences(of: "In attesa", with: "--")
            }()
            
            let subtitleText: String = {
                if let st = train.lastStation, !st.isEmpty, st != "--" {
                    return "Visto a \(st)"
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
                        .font(.system(size: 19, weight: .heavy))
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
            }
        }
    }

    private var systemWidgetBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isUnlocked {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "lock.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                    Text("Widget Bloccato")
                        .font(.headline)
                    Text("Diventa Sostenitore nelle impostazioni per sbloccare il widget.")
                        .font(.system(size: 10))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("Treni Preferiti")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    if #available(iOS 17.0, *) {
                        Button(intent: RefreshWidgetIntent()) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundColor(.gray.opacity(0.5))
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)

                if entry.trains.isEmpty {
                    Text("Nessun treno preferito.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    let displayCount = family == .systemSmall ? 2 : 4
                    ForEach(entry.trains.prefix(displayCount)) { train in
                        Link(destination: URL(string: "inorario://\(train.number)")!) {
                            HStack {
                                Image(systemName: "train.side.front.car")
                                    .foregroundColor(.blue)
                                    .font(.subheadline)
                                VStack(alignment: .leading) {
                                    Text("Treno \(train.number)")
                                        .font(.subheadline)
                                        .bold()
                                        .foregroundColor(.primary)
                                    Text(train.description)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                
                                VStack(alignment: .trailing) {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(train.delayColor)
                                            .frame(width: 8, height: 8)
                                        Text(train.delayText)
                                            .font(.caption)
                                            .bold()
                                            .foregroundColor(train.delayColor)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                    }
                }
                Spacer()
            }
        }
    }
}

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
        .description("Accedi rapidamente ai tuoi treni preferiti.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}
