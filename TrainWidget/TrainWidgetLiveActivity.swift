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
            delayStr = "Ritardo \(rawDelay) min"
        } else if rawDelay < 0 {
            delayStr = "Anticipo \(abs(rawDelay)) min"
        } else {
            delayStr = "In orario"
        }

        let lastStation = (json["stazioneUltimoRilevamento"] as? String) ?? ""

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

        var progressVal: Double = 0.0
        if isArrived {
            progressVal = 1.0
        } else if let fermate = json["fermate"] as? [[String: Any]], fermate.count > 1 {
            var passedCount = 0
            for f in fermate {
                if let pReale = f["partenzaReale"] as? Int, pReale > 0 {
                    passedCount += 1
                } else if let aReale = f["arrivoReale"] as? Int, aReale > 0 {
                    passedCount += 1
                } else if let staz = f["stazione"] as? String, !lastStation.isEmpty, staz.localizedCaseInsensitiveContains(lastStation) {
                    passedCount += 1
                    break
                }
            }
            progressVal = min(1.0, max(0.0, Double(passedCount) / Double(fermate.count - 1)))
        }

        return TrainLiveActivityAttributes.ContentState(
            delay: delayStr,
            statusMessage: statusMsg,
            lastStation: lastStation,
            progress: progressVal
        )
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
                        .background(
                            context.state.delay.contains("In orario") ? Color.green.opacity(0.18) :
                            context.state.delay.contains("anticipo") ? Color.green.opacity(0.18) : Color.red.opacity(0.18)
                        )
                        .foregroundColor(
                            context.state.delay.contains("In orario") ? .green :
                            context.state.delay.contains("anticipo") ? .green : .red
                        )
                        .cornerRadius(8)
                }
                
                // Route Progress Visualizer
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        let width = geo.size.width
                        let progressWidth = width * CGFloat(context.state.progress)
                        
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 4)
                            
                            Capsule()
                                .fill(
                                    context.state.delay.contains("In orario") ? Color.green :
                                    context.state.delay.contains("anticipo") ? Color.green : Color.orange
                                )
                                .frame(width: progressWidth, height: 4)
                            
                            Image(systemName: "tram.fill")
                                .font(.system(size: 10))
                                .foregroundColor(
                                    context.state.delay.contains("In orario") ? .green :
                                    context.state.delay.contains("anticipo") ? .green : .orange
                                )
                                .padding(3)
                                .background(Color.black)
                                .clipShape(Circle())
                                .shadow(radius: 2)
                                .offset(x: max(0, progressWidth - 8), y: -3.5)
                        }
                    }
                    .frame(height: 12)
                    
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
                
                // Footer Status Message and Last Detection Info
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .foregroundColor(
                            context.state.delay.contains("In orario") ? .green :
                            context.state.delay.contains("anticipo") ? .green : .orange
                        )
                        .font(.system(size: 11))
                    Text(context.state.lastStation.isEmpty ? "--" : context.state.lastStation.abbreviatedStationName())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(
                            context.state.delay.contains("In orario") ? .green :
                            context.state.delay.contains("anticipo") ? .green : .orange
                        )
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(context.state.statusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                    
                    Button(intent: RefreshLiveActivityIntent(trainNumber: context.attributes.trainNumber)) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(5)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
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
                        .background(
                            context.state.delay.contains("In orario") ? Color.green.opacity(0.18) :
                            context.state.delay.contains("anticipo") ? Color.green.opacity(0.18) : Color.red.opacity(0.18)
                        )
                        .foregroundColor(
                            context.state.delay.contains("In orario") ? .green :
                            context.state.delay.contains("anticipo") ? .green : .red
                        )
                        .cornerRadius(6)
                        .padding(.top, 6)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Small route visualizer for Dynamic Island Bottom
                        VStack(spacing: 4) {
                            GeometryReader { geo in
                                let progressWidth = geo.size.width * CGFloat(context.state.progress)
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.15))
                                        .frame(height: 3)
                                    
                                    Capsule()
                                        .fill(
                                            context.state.delay.contains("In orario") ? Color.green :
                                            context.state.delay.contains("anticipo") ? Color.green : Color.orange
                                        )
                                        .frame(width: progressWidth, height: 3)
                                    
                                    Image(systemName: "tram.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(
                                            context.state.delay.contains("In orario") ? .green :
                                            context.state.delay.contains("anticipo") ? .green : .orange
                                        )
                                        .padding(2)
                                        .background(Color.black)
                                        .clipShape(Circle())
                                        .offset(x: max(0, progressWidth - 6), y: -3)
                                }
                            }
                            .frame(height: 10)
                            
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
                        
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .foregroundColor(
                                    context.state.delay.contains("In orario") ? .green :
                                    context.state.delay.contains("anticipo") ? .green : .orange
                                )
                                .font(.system(size: 9))
                            Text(context.state.lastStation.isEmpty ? "--" : context.state.lastStation.abbreviatedStationName())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(
                                    context.state.delay.contains("In orario") ? .green :
                                    context.state.delay.contains("anticipo") ? .green : .orange
                                )
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(context.state.statusMessage)
                                .font(.system(size: 9))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                                
                            Button(intent: RefreshLiveActivityIntent(trainNumber: context.attributes.trainNumber)) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.85))
                                    .padding(4)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                Image(systemName: "tram.fill")
                    .foregroundColor(
                        context.state.delay.contains("In orario") ? .green :
                        context.state.delay.contains("anticipo") ? .green : .red
                    )
            } compactTrailing: {
                Text(context.state.delay)
                    .foregroundColor(
                        context.state.delay.contains("In orario") ? .green :
                        context.state.delay.contains("anticipo") ? .green : .red
                    )
                    .font(.system(size: 12, weight: .bold))
            } minimal: {
                Image(systemName: "tram.fill")
                    .foregroundColor(
                        context.state.delay.contains("In orario") ? .green :
                        context.state.delay.contains("anticipo") ? .green : .red
                    )
            }
            .widgetURL(URL(string: "inorario://train/\(context.attributes.trainNumber)"))
        }
    }
}
