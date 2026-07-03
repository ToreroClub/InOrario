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
}

struct WidgetTrainData: Identifiable {
    var id: String { number }
    let number: String
    let description: String
    let delayText: String
    let delayColor: Color
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), trains: [
            WidgetTrainData(number: "2010", description: "Milano Centrale", delayText: "In orario", delayColor: .green),
            WidgetTrainData(number: "24555", description: "Treviglio", delayText: "Ritardo 5 min", delayColor: .red)
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let trains = getFavorites()
        let placeholderData = trains.isEmpty ? placeholder(in: context).trains : trains.map { WidgetTrainData(number: $0.number, description: $0.description, delayText: "--", delayColor: .gray) }
        let entry = SimpleEntry(date: Date(), trains: placeholderData)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        Task {
            let savedTrains = getFavorites()
            var widgetData: [WidgetTrainData] = []
            
            for train in savedTrains {
                let (delay, color) = await fetchTrainStatus(number: train.number)
                widgetData.append(WidgetTrainData(number: train.number, description: train.description, delayText: delay, delayColor: color))
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
    
    private func fetchTrainStatus(number: String) async -> (String, Color) {
        let cleanNumber = number.trimmingCharacters(in: .whitespaces)
        let searchUrl = "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/cercaNumeroTrenoTrenoAutocomplete/\(cleanNumber)"
        
        guard let url = URL(string: searchUrl),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let responseStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !responseStr.isEmpty else {
            return ("Non disp.", .gray)
        }
        
        let lines = responseStr.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var targets = lines.filter { $0.contains("|\(cleanNumber)-") }
        if targets.isEmpty, let firstLine = lines.first { targets = [firstLine] }
        if targets.isEmpty { return ("Non disp.", .gray) }
        
        let results: [(String, [String: Any])] = await withTaskGroup(of: (String, [String: Any])?.self) { group in
            for targetLine in targets {
                group.addTask {
                    let pipes = targetLine.components(separatedBy: "|")
                    let subParts = pipes.count > 1 ? pipes[1].components(separatedBy: "-") : []
                    guard subParts.count >= 2 else { return nil }
                    
                    let originID = subParts[1].trimmingCharacters(in: .whitespaces)
                    let timestamp = subParts.count >= 3 ? subParts[2].trimmingCharacters(in: .whitespaces) : ""
                    let dateStr = String(timestamp.prefix(13))
                    
                    var stopsUrl = "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/andamentoTreno/\(originID)/\(cleanNumber)"
                    if !dateStr.isEmpty { stopsUrl += "/\(dateStr)" }
                    
                    guard let sUrl = URL(string: stopsUrl),
                          let (sData, response) = try? await URLSession.shared.data(from: sUrl),
                          let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                          let json = try? JSONSerialization.jsonObject(with: sData) as? [String: Any] else {
                        return nil
                    }
                    return (targetLine, json)
                }
            }
            var collected = [(String, [String: Any])]()
            for await res in group {
                if let r = res { collected.append(r) }
            }
            return collected
        }
        
        guard !results.isEmpty else { return ("Non disp.", .gray) }
        
        let nowTs = Date().timeIntervalSince1970 * 1000.0
        var bestJson: [String: Any]? = nil
        var bestScore: Double = -1.0
        
        for (targetLine, json) in results {
            let pipes = targetLine.components(separatedBy: "|")
            let subParts = pipes.count > 1 ? pipes[1].components(separatedBy: "-") : []
            let tsStr = subParts.count >= 3 ? subParts[2].trimmingCharacters(in: .whitespaces) : ""
            let trainTs = Double(String(tsStr.prefix(13))) ?? nowTs
            
            let deltaDays = abs(nowTs - trainTs) / (1000.0 * 60 * 60 * 24)
            let isDeparted = !(json["nonPartito"] as? Bool ?? true)
            let isArrived = (json["arrivato"] as? Bool) ?? false
            
            let baseScore = (isDeparted && !isArrived) ? 10000.0 : 1000.0
            let score = baseScore - (deltaDays * 100.0)
            
            if score > bestScore {
                bestScore = score
                bestJson = json
            }
        }
        
        let json = bestJson ?? results[0].1
        
        if let compRitardo = json["compRitardo"] as? [String], !compRitardo.isEmpty {
            let ritardoStr = compRitardo[0]
            if ritardoStr.contains("In orario") {
                return ("In orario", .green)
            } else if ritardoStr.contains("ritardo") {
                if let min = extractMinutes(from: ritardoStr) {
                    return ("Ritardo \(min) min", .red)
                }
                return ("In ritardo", .red)
            } else if ritardoStr.contains("anticipo") {
                if let min = extractMinutes(from: ritardoStr) {
                    return ("Anticipo \(min) min", .green)
                }
                return ("In anticipo", .green)
            }
        }
        
        return ("Non disp.", .gray)
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
        let defaults = UserDefaults(suiteName: "group.carlo.InOrario")
        return (defaults?.bool(forKey: "tip.colazionee") ?? false)
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
                .replacingOccurrences(of: " min", with: "'")
                .replacingOccurrences(of: "In orario", with: "0'")
            
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
            HStack {
                Image(systemName: "train.side.front.car")
                Text("Nessun treno")
            }
        } else {
            let train = entry.trains[0]
            HStack(spacing: 8) {
                Image(systemName: "train.side.front.car")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(train.number) \(train.description)")
                        .font(.headline)
                        .lineLimit(1)
                    Text(train.delayText)
                        .font(.subheadline)
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
                    Text("Sblocca Cappuccino o Colazione Pendolare nelle impostazioni.")
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
