import Foundation
import SwiftUI
import AppIntents

// MARK: - Helper Execution Bridge (MainActor)

private struct SmartIntentSummaryPayload: Sendable {
    let title: String
    let subtitle: String
    let primaryLine: String
    let secondaryLine: String?
    let badgeText: String?
    let badgeIsAlert: Bool
    let speechText: String
}

private enum SmartIntentRunner {
    @MainActor
    static func executeTrainAtTime(stationName: String, timeInput: String) async -> SmartIntentSummaryPayload {
        let manager = TrainManager()
        let normalizedTime = normalizeTimeInput(timeInput)
        let query = SmartTrainQuery(
            kind: .trainAtTimeFromStation,
            originStation: stationName,
            targetTime: normalizedTime,
            confidence: 1.0,
            normalizedSummary: "Treno delle \(normalizedTime ?? timeInput) da \(stationName)",
            engineUsed: "app_intent"
        )
        let result = await SmartQueryExecutor.shared.execute(parsed: query, manager: manager, nearbyStation: nil)
        return buildPayload(from: result, parsed: query)
    }

    @MainActor
    static func executeRoute(originStation: String, destinationStation: String) async -> SmartIntentSummaryPayload {
        let manager = TrainManager()
        let query = SmartTrainQuery(
            kind: .routeSolutions,
            originStation: originStation,
            destinationStation: destinationStation,
            confidence: 1.0,
            normalizedSummary: "Primo treno \(originStation) → \(destinationStation)",
            engineUsed: "app_intent"
        )
        let result = await SmartQueryExecutor.shared.execute(parsed: query, manager: manager, nearbyStation: nil)
        return buildPayload(from: result, parsed: query)
    }

    @MainActor
    static func executeNaturalLanguage(requestText: String) async -> SmartIntentSummaryPayload {
        let manager = TrainManager()
        let hasSup = manager.hasSupport() || SupporterCommuteManager.shared.hasSupport()
        let knownStations = manager.allRFIStations.isEmpty ? SmartQueryExecutor.bundledRFIStations() : manager.allRFIStations
        let homeStList = SupporterCommuteManager.shared.origins
        let workStList = SupporterCommuteManager.shared.destinations
        let report = await SmartQueryParser.shared.parseDetailed(
            query: requestText,
            hasSupport: hasSup,
            inputMode: "siri",
            nearbyStation: nil,
            homeStations: homeStList,
            workStations: workStList,
            favoriteStations: manager.myStations.map { $0.name },
            favoriteTrains: manager.favoriteTrains.map { $0.number },
            knownStations: knownStations
        )

        switch report.outcome {
        case .parsed(let parsed):
            let execResult = await SmartQueryExecutor.shared.execute(parsed: parsed, manager: manager, nearbyStation: nil)
            SmartQueryParser.shared.logAnonymousQuery(
                rawQuery: requestText,
                inputMode: "siri",
                engine: report.engineUsed,
                outcome: execResult.isSuccessfulForHistory ? "ok" : "empty_result",
                parsed: parsed,
                resultSummary: execResult.telemetrySummary
            )
            return buildPayload(from: execResult, parsed: parsed)
        case .needsUpgrade(let msg):
            SmartQueryParser.shared.logAnonymousQuery(
                rawQuery: requestText,
                inputMode: "siri",
                engine: report.engineUsed,
                outcome: "needs_upgrade",
                parsed: report.parsedSnapshot,
                resultSummary: msg
            )
            return SmartIntentSummaryPayload(
                title: "In Orario",
                subtitle: requestText,
                primaryLine: msg,
                secondaryLine: nil,
                badgeText: "Assistente",
                badgeIsAlert: false,
                speechText: msg
            )
        case .clarification(let msg):
            SmartQueryParser.shared.logAnonymousQuery(
                rawQuery: requestText,
                inputMode: "siri",
                engine: report.engineUsed,
                outcome: "clarification",
                parsed: report.parsedSnapshot,
                resultSummary: msg
            )
            return SmartIntentSummaryPayload(
                title: "In Orario",
                subtitle: requestText,
                primaryLine: msg,
                secondaryLine: nil,
                badgeText: "Assistente",
                badgeIsAlert: false,
                speechText: msg
            )
        case .error(let msg):
            SmartQueryParser.shared.logAnonymousQuery(
                rawQuery: requestText,
                inputMode: "siri",
                engine: report.engineUsed,
                outcome: "error",
                parsed: report.parsedSnapshot,
                resultSummary: msg
            )
            return SmartIntentSummaryPayload(
                title: "In Orario",
                subtitle: requestText,
                primaryLine: msg,
                secondaryLine: nil,
                badgeText: "Assistente",
                badgeIsAlert: false,
                speechText: msg
            )
        }
    }

    private static func normalizeTimeInput(_ raw: String) -> String? {
        let digitsAndColon = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: ":")
        let pattern = #"(\d{1,2})(?::(\d{2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: digitsAndColon, range: NSRange(digitsAndColon.startIndex..<digitsAndColon.endIndex, in: digitsAndColon)),
              let rH = Range(match.range(at: 1), in: digitsAndColon),
              let h = Int(digitsAndColon[rH]), (0...23).contains(h) else {
            return nil
        }
        var m = 0
        if match.range(at: 2).location != NSNotFound,
           let rM = Range(match.range(at: 2), in: digitsAndColon),
           let parsedM = Int(digitsAndColon[rM]), (0...59).contains(parsedM) {
            m = parsedM
        }
        return String(format: "%02d:%02d", h, m)
    }

    private static func buildPayload(from result: SmartQueryExecutionResult, parsed: SmartTrainQuery) -> SmartIntentSummaryPayload {
        switch result {
        case .trainAtTime(let train, let station, let sample, let requestedTime):
            let stName = station.name.formattedStationName
            if let t = train {
                let cat = t.category.isEmpty ? "Treno" : t.category
                let status = t.delay.isEmpty ? "In orario" : t.delay
                let bin = (!t.platform.isEmpty && t.platform != "--") ? "Binario \(t.platform)" : nil
                let isAlert = status.contains("+") || status.contains("Soppresso")
                let speech = "\(cat) \(t.number) per \(t.destination.formattedStationName) delle \(t.time) da \(stName): \(status)\(bin != nil ? ", \(bin!)" : "")."
                return SmartIntentSummaryPayload(
                    title: "\(cat) \(t.number)",
                    subtitle: "\(stName) → \(t.destination.formattedStationName)",
                    primaryLine: "Partenza \(t.time)",
                    secondaryLine: bin,
                    badgeText: status,
                    badgeIsAlert: isAlert,
                    speechText: speech
                )
            } else if let next = sample.first {
                let speech = "Nessun treno esattamente alle \(requestedTime) da \(stName). Il prossimo è \(next.category) \(next.number) alle \(next.time) per \(next.destination.formattedStationName)."
                return SmartIntentSummaryPayload(
                    title: "Da \(stName)",
                    subtitle: "Nessuno alle \(requestedTime)",
                    primaryLine: "Prossimo: \(next.category) \(next.number) alle \(next.time)",
                    secondaryLine: "Direzione \(next.destination.formattedStationName)",
                    badgeText: next.delay.isEmpty ? "In orario" : next.delay,
                    badgeIsAlert: next.delay.contains("+") || next.delay.contains("Soppresso"),
                    speechText: speech
                )
            } else {
                let speech = "Nessuna partenza trovata alle \(requestedTime) da \(stName)."
                return SmartIntentSummaryPayload(
                    title: stName,
                    subtitle: "Orario \(requestedTime)",
                    primaryLine: "Nessun treno trovato",
                    secondaryLine: nil,
                    badgeText: nil,
                    badgeIsAlert: false,
                    speechText: speech
                )
            }

        case .trainStatus(let train):
            let cat = train.category.isEmpty ? "Treno" : train.category
            let status = train.delay.isEmpty ? "In orario" : train.delay
            let isAlert = status.contains("+") || status.contains("Soppresso")
            let speech = "\(cat) \(train.number) per \(train.destination.formattedStationName): \(status), partenza \(train.time)."
            return SmartIntentSummaryPayload(
                title: "\(cat) \(train.number)",
                subtitle: "Dir. \(train.destination.formattedStationName)",
                primaryLine: "Orario: \(train.time)",
                secondaryLine: train.platform != "--" ? "Binario \(train.platform)" : nil,
                badgeText: status,
                badgeIsAlert: isAlert,
                speechText: speech
            )

        case .solutions(let solutions, let origin, let destination, _, _, _):
            let o = origin.formattedStationName
            let d = destination.formattedStationName
            if let first = solutions.first {
                let isUrbanBridge = first.segments.contains { $0.trainCategory.localizedCaseInsensitiveContains("Metro") }
                let detail = isUrbanBridge
                    ? first.segments.map { "\($0.trainNumber) (\($0.departureTime))" }.joined(separator: " → ")
                    : "Durata \(first.duration) • \(first.segments.count == 1 ? "Diretto" : "\(first.segments.count) tratte")"
                let speech = "Primo treno reale da \(o) a \(d): parte alle \(first.departureTime) e arriva alle \(first.arrivalTime), durata \(first.duration)."
                return SmartIntentSummaryPayload(
                    title: "\(o) → \(d)",
                    subtitle: "\(first.category) \(first.trainNumber)",
                    primaryLine: "\(first.departureTime) → \(first.arrivalTime)",
                    secondaryLine: detail,
                    badgeText: first.duration,
                    badgeIsAlert: false,
                    speechText: speech
                )
            } else {
                let speech = "Nessuna soluzione di viaggio trovata da \(o) a \(d)."
                return SmartIntentSummaryPayload(
                    title: "\(o) → \(d)",
                    subtitle: parsed.targetTime != nil ? "Dalle \(parsed.targetTime!)" : "Oggi",
                    primaryLine: "Nessuna soluzione trovata",
                    secondaryLine: "Verifica stazioni o orario in app.",
                    badgeText: nil,
                    badgeIsAlert: false,
                    speechText: speech
                )
            }

        case .stationBoard(let station, let isArrivals):
            let stName = station.name.formattedStationName
            let kind = isArrivals ? "Arrivi" : "Partenze"
            let speech = "Apri In Orario per vedere il tabellone \(kind.lowercased()) di \(stName)."
            return SmartIntentSummaryPayload(
                title: stName,
                subtitle: "Tabellone \(kind)",
                primaryLine: "Stazione trovata nei sistemi ferroviari",
                secondaryLine: "Tocca per aprire il tabellone live",
                badgeText: kind,
                badgeIsAlert: false,
                speechText: speech
            )

        case .message(let text):
            return SmartIntentSummaryPayload(
                title: "In Orario",
                subtitle: parsed.normalizedSummary ?? "Assistente",
                primaryLine: text,
                secondaryLine: nil,
                badgeText: nil,
                badgeIsAlert: false,
                speechText: text
            )
        }
    }
}

// MARK: - Snippet View

private struct SmartIntentSnippetView: View {
    let payload: SmartIntentSummaryPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(payload.title)
                        .font(.headline)
                    Text(payload.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let badge = payload.badgeText, !badge.isEmpty {
                    Text(badge)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((payload.badgeIsAlert ? Color.red : Color.green).opacity(0.15))
                        .foregroundColor(payload.badgeIsAlert ? .red : .green)
                        .clipShape(Capsule())
                }
            }

            Text(payload.primaryLine)
                .font(.title3.bold())

            if let secondary = payload.secondaryLine, !secondary.isEmpty {
                Text(secondary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - AppIntents

struct FindTrainAtTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Treno a un orario"
    static let description = IntentDescription("Trova il treno reale in partenza da una stazione a un determinato orario.")

    @Parameter(title: "Stazione di partenza")
    var stationName: String

    @Parameter(title: "Orario (es. 11:34)")
    var timeString: String

    static var parameterSummary: some ParameterSummary {
        Summary("Treno delle \(\.$timeString) da \(\.$stationName)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let payload = await SmartIntentRunner.executeTrainAtTime(stationName: stationName, timeInput: timeString)
        return .result(
            dialog: IntentDialog(stringLiteral: payload.speechText),
            view: SmartIntentSnippetView(payload: payload)
        )
    }
}

struct FindNextTrainBetweenStationsIntent: AppIntent {
    static let title: LocalizedStringResource = "Primo treno tra due stazioni"
    static let description = IntentDescription("Trova il prossimo treno o percorso reale tra partenza e arrivo.")

    @Parameter(title: "Stazione di partenza")
    var originStation: String

    @Parameter(title: "Stazione di arrivo")
    var destinationStation: String

    static var parameterSummary: some ParameterSummary {
        Summary("Primo treno da \(\.$originStation) a \(\.$destinationStation)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let payload = await SmartIntentRunner.executeRoute(originStation: originStation, destinationStation: destinationStation)
        return .result(
            dialog: IntentDialog(stringLiteral: payload.speechText),
            view: SmartIntentSnippetView(payload: payload)
        )
    }
}

struct AskInOrarioIntent: AppIntent {
    static let title: LocalizedStringResource = "Chiedi a In Orario"
    static let description = IntentDescription("Fai una domanda sui treni e ottieni dati reali da ViaggiaTreno e Trenitalia.")

    @Parameter(title: "Richiesta")
    var requestText: String

    static var parameterSummary: some ParameterSummary {
        Summary("Chiedi \(\.$requestText)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let payload = await SmartIntentRunner.executeNaturalLanguage(requestText: requestText)
        return .result(
            dialog: IntentDialog(stringLiteral: payload.speechText),
            view: SmartIntentSnippetView(payload: payload)
        )
    }
}

// MARK: - AppShortcutsProvider

struct InOrarioShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .purple

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskInOrarioIntent(),
            phrases: [
                "Chiedi a \(.applicationName)",
                "Cerca un treno con \(.applicationName)"
            ],
            shortTitle: "Chiedi a In Orario",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: FindNextTrainBetweenStationsIntent(),
            phrases: [
                "Prossimo treno con \(.applicationName)",
                "Primo treno su \(.applicationName)"
            ],
            shortTitle: "Prossimo treno",
            systemImageName: "tram.fill"
        )
        AppShortcut(
            intent: FindTrainAtTimeIntent(),
            phrases: [
                "Treno ad un orario su \(.applicationName)",
                "Controlla orario treno su \(.applicationName)"
            ],
            shortTitle: "Treno ad un orario",
            systemImageName: "clock.fill"
        )
    }
}
