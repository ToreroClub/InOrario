import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - AppIntent per aggiornamento manuale Live Activity (Device-Only, 0 chiamate server)

@available(iOS 17.0, *)
struct RefreshLiveActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Aggiorna Treno"
    static let description = IntentDescription("Aggiorna manualmente lo stato del treno nella Live Activity interrogando Viaggiatreno direttamente dal dispositivo.")
    
    @Parameter(title: "Numero Treno")
    var trainNumber: String

    init() {
        self.trainNumber = ""
    }

    init(trainNumber: String) {
        self.trainNumber = trainNumber
    }

    func perform() async throws -> some IntentResult {
        let clean = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return .result() }

        let matched = Activity<TrainLiveActivityAttributes>.activities.filter {
            $0.attributes.trainNumber == clean
        }
        guard !matched.isEmpty else { return .result() }

        if let newState = await LiveActivityFetcher.fetchState(for: clean) {
            for act in matched {
                await act.update(ActivityContent(state: newState, staleDate: nil))
            }
        }

        return .result()
    }
}

// MARK: - Fetcher locale Viaggiatreno per Live Activity (senza passare dal bridge)

struct LiveActivityFetcher {
    static func fetchState(for trainNumber: String) async -> TrainLiveActivityAttributes.ContentState? {
        let cleanNumber = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNumber.isEmpty else { return nil }

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 8.0
        sessionConfig.timeoutIntervalForResource = 10.0
        let session = URLSession(configuration: sessionConfig)
        let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 InOrario/1.0"

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

        guard let responseStr = responseStr else { return nil }
        let lines = responseStr.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var targets = lines.filter { $0.contains("|\(cleanNumber)-") }
        if targets.isEmpty, let firstLine = lines.first { targets = [firstLine] }
        guard let targetLine = targets.first else { return nil }

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

        var trainJson: [String: Any]? = nil
        for cUrlStr in candidateUrls {
            guard let sUrl = URL(string: cUrlStr) else { continue }
            var req = URLRequest(url: sUrl)
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            if let (sData, resp) = try? await session.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: sData) as? [String: Any] {
                trainJson = json
                break
            }
        }

        guard let json = trainJson else { return nil }

        let isCancelled = (json["provvedimento"] as? Int != 0) || (json["cancellato"] as? Bool ?? false)
        let rawDelay = json["ritardo"] as? Int ?? 0
        let isArrived = (json["arrivato"] as? Bool) ?? false
        let isNonPartito = (json["nonPartito"] as? Bool) ?? false

        let delayStr: String
        if isCancelled {
            delayStr = "Soppresso"
        } else if isArrived {
            delayStr = "Arrivato"
        } else if rawDelay > 0 {
            delayStr = "+\(rawDelay)'"
        } else if rawDelay < 0 {
            delayStr = "\(rawDelay)'"
        } else {
            delayStr = "In orario"
        }

        let lastStation = (json["stazioneUltimoRilevamento"] as? String) ?? ""

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

        var statusMsg = (json["subTitle"] as? String) ?? ""
        if statusMsg.isEmpty {
            if isCancelled {
                statusMsg = "Corsa soppressa"
            } else if isArrived {
                statusMsg = "Treno arrivato"
            } else if isNonPartito {
                statusMsg = "Non ancora partito"
            } else if !lastStation.isEmpty {
                statusMsg = "Rilevato a \(lastStation)"
            } else {
                statusMsg = "In viaggio"
            }
        }

        let progressVal: Double = Self.computeProgress(
            json: json,
            isArrived: isArrived,
            isDeparted: !isNonPartito,
            lastStation: lastStation,
            rawDelay: rawDelay
        )
        let nextStopInfo = Self.computeNextStop(
            json: json,
            isArrived: isArrived,
            isCancelled: isCancelled,
            lastStation: lastStation,
            rawDelay: rawDelay
        )

        return TrainLiveActivityAttributes.ContentState(
            delay: delayStr,
            statusMessage: statusMsg,
            lastStation: lastStation,
            progress: progressVal,
            lastDetectionTime: detectionTime,
            nextStation: nextStopInfo.station,
            nextStationEstimatedTime: nextStopInfo.estimatedTime
        )
    }

    private static func normalizeStationKey(_ name: String) -> String {
        var s = name.folding(options: .diacriticInsensitive, locale: Locale(identifier: "it_IT"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "porta nuova", with: "pn")
            .replacingOccurrences(of: "p.ta nuova", with: "pn")
            .replacingOccurrences(of: "p.nuova", with: "pn")
            .replacingOccurrences(of: "p.n.", with: "pn")
            .replacingOccurrences(of: "porta garibaldi", with: "pg")
            .replacingOccurrences(of: "p.ta garibaldi", with: "pg")
            .replacingOccurrences(of: "p.garibaldi", with: "pg")
            .replacingOccurrences(of: "p.g.", with: "pg")
            .replacingOccurrences(of: "porta susa", with: "ps")
            .replacingOccurrences(of: "p.ta susa", with: "ps")
            .replacingOccurrences(of: "p.susa", with: "ps")
            .replacingOccurrences(of: "p.s.", with: "ps")
            .replacingOccurrences(of: "santa lucia", with: "sl")
            .replacingOccurrences(of: "s. lucia", with: "sl")
            .replacingOccurrences(of: "s.lucia", with: "sl")
            .replacingOccurrences(of: "s.l.", with: "sl")
            .replacingOccurrences(of: "centrale", with: "cle")
            .replacingOccurrences(of: "c.le", with: "cle")
        return s.filter { $0.isLetter || $0.isNumber }
    }

    private static func resolveEffectiveStopIndex(
        fermate: [[String: Any]],
        lastStation: String
    ) -> (effectiveIdx: Int?, matchedIdx: Int?) {
        var lastPassedIdx: Int? = nil
        for (idx, f) in fermate.enumerated() {
            let eff = (f["effettiva"] as? Double) ?? Double(f["effettiva"] as? Int ?? 0)
            let pReale = (f["partenzaReale"] as? Double) ?? Double(f["partenzaReale"] as? Int ?? 0)
            let aReale = (f["arrivoReale"] as? Double) ?? Double(f["arrivoReale"] as? Int ?? 0)
            if eff > 0 || pReale > 0 || aReale > 0 {
                lastPassedIdx = idx
            }
        }

        let lastKey = normalizeStationKey(lastStation)
        var matchedIdx: Int? = nil
        if !lastKey.isEmpty {
            let names = fermate.map { ($0["stazione"] as? String) ?? "" }
            matchedIdx = names.firstIndex(where: { normalizeStationKey($0) == lastKey })
            if matchedIdx == nil && lastKey.count >= 4 {
                matchedIdx = names.firstIndex { name in
                    let sk = normalizeStationKey(name)
                    return sk.count >= 4 && (sk.contains(lastKey) || lastKey.contains(sk))
                }
            }
        }

        let effectiveIdx: Int?
        switch (lastPassedIdx, matchedIdx) {
        case let (.some(a), .some(b)): effectiveIdx = max(a, b)
        case let (.some(a), .none): effectiveIdx = a
        case let (.none, .some(b)): effectiveIdx = b
        case (.none, .none): effectiveIdx = nil
        }
        return (effectiveIdx, matchedIdx)
    }

    private static func computeNextStop(
        json: [String: Any],
        isArrived: Bool,
        isCancelled: Bool,
        lastStation: String,
        rawDelay: Int
    ) -> (station: String?, estimatedTime: String?) {
        if isArrived || isCancelled { return (nil, nil) }
        guard let fermate = json["fermate"] as? [[String: Any]], !fermate.isEmpty else { return (nil, nil) }

        let (effectiveIdx, _) = resolveEffectiveStopIndex(fermate: fermate, lastStation: lastStation)
        let startSearch = (effectiveIdx != nil) ? (effectiveIdx! + 1) : 0
        guard startSearch < fermate.count else { return (nil, nil) }

        var chosenIdx: Int? = nil
        for idx in startSearch..<fermate.count {
            let f = fermate[idx]
            let isSuppressed = (f["actualFermataType"] as? Int) == 3 || ((f["tipoFermata"] as? String)?.uppercased() == "S")
            if !isSuppressed {
                chosenIdx = idx
                break
            }
        }
        guard let nextIdx = chosenIdx else { return (nil, nil) }

        let nextStop = fermate[nextIdx]
        let rawName = ((nextStop["stazione"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty else { return (nil, nil) }

        let tsKeys = nextIdx == 0
            ? ["partenza_teorica", "programmata", "arrivo_teorico"]
            : ["arrivo_teorico", "programmata", "partenza_teorica"]
        var schedMs: Double = 0
        for k in tsKeys {
            if let v = nextStop[k] as? Double, v > 1_000_000_000 {
                schedMs = v
                break
            } else if let vInt = nextStop[k] as? Int, vInt > 1_000_000_000 {
                schedMs = Double(vInt)
                break
            }
        }

        var estimatedTime: String? = nil
        if schedMs > 0 {
            let estSec = (schedMs > 100_000_000_000 ? schedMs / 1000.0 : schedMs) + Double(rawDelay) * 60.0
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Europe/Rome")
            estimatedTime = formatter.string(from: Date(timeIntervalSince1970: estSec))
        }

        return (rawName.capitalized, estimatedTime)
    }

    private static func computeProgress(
        json: [String: Any],
        isArrived: Bool,
        isDeparted: Bool,
        lastStation: String,
        rawDelay: Int
    ) -> Double {
        if isArrived { return 1.0 }
        guard let fermate = json["fermate"] as? [[String: Any]], !fermate.isEmpty else { return 0.0 }
        if fermate.count == 1 { return isDeparted ? 1.0 : 0.0 }

        let (effectiveIdx, matchedIdx) = resolveEffectiveStopIndex(fermate: fermate, lastStation: lastStation)

        let totalSegments = Double(fermate.count - 1)
        if let idx = effectiveIdx {
            var frac = Double(idx) / totalSegments
            if idx < fermate.count - 1 {
                let trimmedLast = lastStation.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedLast.isEmpty && trimmedLast != "--" && matchedIdx == nil {
                    frac += 0.5 / totalSegments
                } else if idx == 0 && isDeparted {
                    frac = max(frac, 0.06)
                }
            }
            return min(1.0, max(0.0, frac))
        }

        if isDeparted,
           let depMs = fermate.first?["programmata"] as? Double, depMs > 0,
           let arrMs = fermate.last?["programmata"] as? Double, arrMs > depMs {
            let nowMs = Date().timeIntervalSince1970 * 1000.0
            let delayMs = Double(max(0, rawDelay)) * 60_000.0
            let elapsed = nowMs - depMs - delayMs
            return min(0.95, max(0.05, elapsed / (arrMs - depMs)))
        }

        return 0.0
    }
}

private extension TrainLiveActivityAttributes.ContentState {
    var isPositiveStatus: Bool {
        let lower = delay.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.contains("in orario") || lower.contains("arrivato") || lower.contains("anticipo") || lower.hasPrefix("-")
    }

    var isCancelledStatus: Bool {
        delay.localizedCaseInsensitiveContains("soppresso")
    }

    var badgeColor: Color {
        isPositiveStatus ? .green : .red
    }

    var trackAccentColor: Color {
        if isPositiveStatus { return .green }
        if isCancelledStatus { return .red }
        return .orange
    }

    var clampedProgress: Double {
        min(1.0, max(0.0, progress))
    }
}

struct TrainWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainLiveActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                // Header: Train number with Category badge and Delay status
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Text(context.attributes.category)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.18))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                        
                        Text(context.attributes.trainNumber)
                            .font(.system(size: 17, weight: .black))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    // Delay Badge
                    Text(context.state.delay)
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(context.state.badgeColor.opacity(0.18))
                        .foregroundColor(context.state.badgeColor)
                        .cornerRadius(8)
                }
                
                // Route Progress Visualizer
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        let width = geo.size.width
                        let progressWidth = width * CGFloat(context.state.clampedProgress)
                        let iconSize: CGFloat = 16
                        
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 4)
                            
                            Capsule()
                                .fill(context.state.trackAccentColor)
                                .frame(width: progressWidth, height: 4)
                            
                            Image(systemName: "tram.fill")
                                .font(.system(size: 10))
                                .foregroundColor(context.state.trackAccentColor)
                                .frame(width: iconSize, height: iconSize)
                                .background(Color.black)
                                .clipShape(Circle())
                                .shadow(radius: 2)
                                .offset(x: max(0, min(width - iconSize, progressWidth - iconSize / 2)))
                        }
                        .frame(height: iconSize)
                    }
                    .frame(height: 16)
                    
                    HStack {
                        Text(context.attributes.origin.abbreviatedStationName())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(context.attributes.destination.abbreviatedStationName())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Footer Status Message, Last Detection and Next Stop Info
                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: "location.fill")
                                .foregroundColor(context.state.trackAccentColor)
                                .font(.system(size: 11))
                            
                            Text(context.state.lastStation.isEmpty ? "--" : context.state.lastStation.abbreviatedStationName())
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(context.state.trackAccentColor)
                            
                            if let time = context.state.lastDetectionTime, !time.isEmpty, time != "--:--" {
                                Text(time)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.65))
                            }
                        }
                        .lineLimit(1)

                        if let nextStation = context.state.nextStation, !nextStation.isEmpty {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.forward.circle.fill")
                                    .foregroundColor(.cyan)
                                    .font(.system(size: 10))
                                
                                Text("Prossima: \(nextStation.abbreviatedStationName())")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.88))
                                
                                if let est = context.state.nextStationEstimatedTime, !est.isEmpty, est != "--:--" {
                                    Text(est)
                                        .font(.system(size: 11, weight: .bold))
                                        .monospacedDigit()
                                        .foregroundColor(.cyan)
                                }
                            }
                            .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    Button(intent: RefreshLiveActivityIntent(trainNumber: context.attributes.trainNumber)) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                            Text("Aggiorna")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color.black.opacity(0.8))
            .widgetURL(URL(string: "inorario://train/\(context.attributes.trainNumber)"))
            
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Text(context.attributes.category)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.18))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                        
                        Text(context.attributes.trainNumber)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 6)
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.delay)
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(context.state.badgeColor.opacity(0.18))
                        .foregroundColor(context.state.badgeColor)
                        .cornerRadius(6)
                        .padding(.top, 6)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Small route visualizer for Dynamic Island Bottom
                        VStack(spacing: 4) {
                            GeometryReader { geo in
                                let width = geo.size.width
                                let progressWidth = width * CGFloat(context.state.clampedProgress)
                                let iconSize: CGFloat = 12
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.15))
                                        .frame(height: 3)
                                    
                                    Capsule()
                                        .fill(context.state.trackAccentColor)
                                        .frame(width: progressWidth, height: 3)
                                    
                                    Image(systemName: "tram.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(context.state.trackAccentColor)
                                        .frame(width: iconSize, height: iconSize)
                                        .background(Color.black)
                                        .clipShape(Circle())
                                        .offset(x: max(0, min(width - iconSize, progressWidth - iconSize / 2)))
                                }
                                .frame(height: iconSize)
                            }
                            .frame(height: 12)
                            
                            HStack {
                                Text(context.attributes.origin.abbreviatedStationName())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                                Spacer()
                                Text(context.attributes.destination.abbreviatedStationName())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                        
                        HStack(alignment: .center, spacing: 5) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: "location.fill")
                                        .foregroundColor(context.state.trackAccentColor)
                                        .font(.system(size: 9))
                                    
                                    Text(context.state.lastStation.isEmpty ? "--" : context.state.lastStation.abbreviatedStationName())
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(context.state.trackAccentColor)
                                    
                                    if let time = context.state.lastDetectionTime, !time.isEmpty, time != "--:--" {
                                        Text(time)
                                            .font(.system(size: 8, weight: .medium))
                                            .foregroundColor(.white.opacity(0.65))
                                    }
                                }
                                .lineLimit(1)

                                if let nextStation = context.state.nextStation, !nextStation.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.forward.circle.fill")
                                            .foregroundColor(.cyan)
                                            .font(.system(size: 8))
                                        
                                        Text(nextStation.abbreviatedStationName())
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.88))
                                        
                                        if let est = context.state.nextStationEstimatedTime, !est.isEmpty, est != "--:--" {
                                            Text(est)
                                                .font(.system(size: 9, weight: .bold))
                                                .monospacedDigit()
                                                .foregroundColor(.cyan)
                                        }
                                    }
                                    .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                                
                            Button(intent: RefreshLiveActivityIntent(trainNumber: context.attributes.trainNumber)) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("Aggiorna")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.18))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                Image(systemName: "tram.fill")
                    .foregroundColor(context.state.badgeColor)
            } compactTrailing: {
                Text(context.state.delay)
                    .foregroundColor(context.state.badgeColor)
                    .font(.system(size: 12, weight: .bold))
            } minimal: {
                Image(systemName: "tram.fill")
                    .foregroundColor(context.state.badgeColor)
            }
            .widgetURL(URL(string: "inorario://train/\(context.attributes.trainNumber)"))
        }
    }
}
