import Foundation

struct ResolvedTrainOriginEntry: Codable, Sendable, Equatable {
    let originID: String
    let timestamp: String
    let dayKey: String
}

/// Repository dedicato al recupero, parsing, calcolo punteggi e caching dei dettagli treno e fermate (ViaggiaTreno).
/// Tutte le operazioni di scraping, deserializzazione JSON e comparazione corse avvengono fuori dal MainActor.
actor TrainRepository {
    static let shared = TrainRepository()
    
    private struct CacheEntry {
        let result: StopsResult
        let timestamp: Date
    }
    
    private var cache: [String: CacheEntry] = [:]
    private var inFlightTasks: [String: Task<StopsResult, Never>] = [:]
    private let cacheTTL: TimeInterval = 45.0
    private var resolvedOrigins: [String: ResolvedTrainOriginEntry] = [:]
    private var hasLoadedResolvedOrigins = false
    private let resolvedOriginsStorageKey = "vtResolvedTrainOrigins_v1"

    nonisolated private static let romeCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        return cal
    }()

    nonisolated static func currentRomeDayKey(for date: Date = Date()) -> String {
        let comps = romeCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    nonisolated static func originResolutionKeys(
        dayKey: String,
        cleanNumber: String,
        destination: String?,
        origin: String?
    ) -> (specific: String, generic: String) {
        let normOrig = (origin ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normDest = (destination ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return (
            specific: "\(dayKey)|\(cleanNumber)|\(normOrig)|\(normDest)",
            generic: "\(dayKey)|\(cleanNumber)"
        )
    }
    
    private init() {}
    
    func clearCache() {
        cache.removeAll()
    }
    
    func cacheCount() -> Int {
        return cache.count
    }

    private func loadResolvedOriginsIfNeeded(todayKey: String) {
        guard !hasLoadedResolvedOrigins else { return }
        hasLoadedResolvedOrigins = true
        guard let data = UserDefaults.standard.data(forKey: resolvedOriginsStorageKey),
              let decoded = try? JSONDecoder().decode([String: ResolvedTrainOriginEntry].self, from: data) else {
            return
        }
        resolvedOrigins = decoded.filter { $0.value.dayKey == todayKey }
    }

    private func lookupResolvedOrigin(
        cleanNumber: String,
        destination: String?,
        origin: String?,
        todayKey: String
    ) -> ResolvedTrainOriginEntry? {
        loadResolvedOriginsIfNeeded(todayKey: todayKey)
        let keys = Self.originResolutionKeys(
            dayKey: todayKey,
            cleanNumber: cleanNumber,
            destination: destination,
            origin: origin
        )
        if let exact = resolvedOrigins[keys.specific], exact.dayKey == todayKey {
            return exact
        }
        if let generic = resolvedOrigins[keys.generic], generic.dayKey == todayKey {
            return generic
        }
        return nil
    }

    private func saveResolvedOrigin(
        originID: String,
        timestamp: String,
        dayKey: String,
        cleanNumber: String,
        destination: String?,
        origin: String?,
        isUnambiguousSingleTarget: Bool
    ) {
        guard !originID.isEmpty else { return }
        loadResolvedOriginsIfNeeded(todayKey: dayKey)
        let entry = ResolvedTrainOriginEntry(originID: originID, timestamp: timestamp, dayKey: dayKey)
        let keys = Self.originResolutionKeys(
            dayKey: dayKey,
            cleanNumber: cleanNumber,
            destination: destination,
            origin: origin
        )
        resolvedOrigins = resolvedOrigins.filter { $0.value.dayKey == dayKey }
        resolvedOrigins[keys.specific] = entry
        if isUnambiguousSingleTarget {
            resolvedOrigins[keys.generic] = entry
        }
        if let encoded = try? JSONEncoder().encode(resolvedOrigins) {
            UserDefaults.standard.set(encoded, forKey: resolvedOriginsStorageKey)
        }
    }

    private func freshCachedResultByTrainNumber(
        cleanNumber: String,
        destination: String?,
        origin: String?
    ) -> StopsResult? {
        let prefix = "\(cleanNumber)|"
        let now = Date()
        let normOrig = (origin ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normDest = (destination ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        for (cachedKey, entry) in cache where cachedKey.hasPrefix(prefix) {
            guard now.timeIntervalSince(entry.timestamp) < cacheTTL else { continue }
            guard entry.result.errorMessage == nil, !entry.result.stops.isEmpty else { continue }
            if normOrig.isEmpty && normDest.isEmpty {
                return entry.result
            }
            let firstStop = entry.result.stops.first?.stationName.lowercased() ?? ""
            let lastStop = entry.result.stops.last?.stationName.lowercased() ?? ""
            let destMatches = normDest.isEmpty || normDest.contains(lastStop) || lastStop.contains(normDest)
                || entry.result.stops.contains { $0.stationName.lowercased().contains(normDest) || normDest.contains($0.stationName.lowercased()) }
            let origMatches = normOrig.isEmpty || normOrig.contains(firstStop) || firstStop.contains(normOrig)
                || entry.result.stops.contains { $0.stationName.lowercased().contains(normOrig) || normOrig.contains($0.stationName.lowercased()) }
            if destMatches && origMatches {
                return entry.result
            }
        }
        return nil
    }
    
    func cacheKey(trainNumber: String, destination: String?, origin: String?, scheduledTime: String?) -> String {
        let num = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let dest = destination?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let orig = origin?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let sched = scheduledTime?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(num)|\(dest)|\(orig)|\(sched)"
    }
    
    func getLiveStops(
        for trainNumber: String,
        category: String? = nil,
        destination: String? = nil,
        origin: String? = nil,
        scheduledTime: String? = nil,
        force: Bool = false
    ) async -> StopsResult {
        let cleanNumber = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNumber.isEmpty else {
            return StopsResult(stops: [], status: TrainStatus(), errorMessage: "Numero treno non valido.")
        }
        
        // Se il treno è identificato come Italo, interroga ESCLUSIVAMENTE ItaloTrackingProvider
        if isItaloTrain(category: category, number: cleanNumber) {
            return await ItaloTrackingProvider.shared.getLiveStops(for: cleanNumber, force: force)
        }
        
        let key = cacheKey(trainNumber: cleanNumber, destination: destination, origin: origin, scheduledTime: scheduledTime)
        
        if !force {
            if let entry = cache[key], Date().timeIntervalSince(entry.timestamp) < cacheTTL {
                AppLogger.cache("TrainRepository: Cache hit per treno \(cleanNumber) (key: \(key))")
                return entry.result
            }
            if let matchingEntry = freshCachedResultByTrainNumber(cleanNumber: cleanNumber, destination: destination, origin: origin) {
                AppLogger.cache("TrainRepository: Cross-key cache hit per treno \(cleanNumber)")
                return matchingEntry
            }
            if let inFlight = inFlightTasks[key] {
                AppLogger.duplicateAvoided(key: "TrainRepository:\(cleanNumber)")
                return await inFlight.value
            }
        }
        
        let task = Task<StopsResult, Never> {
            await self.fetchLiveStopsUncached(
                cleanNumber: cleanNumber,
                destination: destination,
                origin: origin,
                scheduledTime: scheduledTime
            )
        }
        
        inFlightTasks[key] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: key)
        
        // Salva in cache solo risposte valide senza errore
        if result.errorMessage == nil && !result.stops.isEmpty {
            cache[key] = CacheEntry(result: result, timestamp: Date())
        } else if result.errorMessage != nil {
            AppLogger.refreshFailed(target: "Train:\(cleanNumber)")
        }
        
        return result
    }
    
    private func fetchLiveStopsUncached(
        cleanNumber: String,
        destination: String?,
        origin: String?,
        scheduledTime: String?
    ) async -> StopsResult {
        let todayKey = Self.currentRomeDayKey()
        if let cachedOrigin = lookupResolvedOrigin(
            cleanNumber: cleanNumber,
            destination: destination,
            origin: origin,
            todayKey: todayKey
        ) {
            var directUrl = "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/andamentoTreno/\(cachedOrigin.originID)/\(cleanNumber)"
            if !cachedOrigin.timestamp.isEmpty { directUrl += "/\(cachedOrigin.timestamp)" }
            if let dUrl = URL(string: directUrl) {
                var request = URLRequest(url: dUrl)
                request.timeoutInterval = 10.0
                if let (stData, response) = try? await NetworkService.shared.get(request: request),
                   let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200,
                   !stData.isEmpty,
                   let json = try? JSONSerialization.jsonObject(with: stData) as? [String: Any] {
                    let directParsed = parseStopsResult(from: json, cleanNumber: cleanNumber)
                    if directParsed.errorMessage == nil && !directParsed.stops.isEmpty {
                        AppLogger.cache("TrainRepository: Direct origin cache hit per treno \(cleanNumber)")
                        return directParsed
                    }
                }
            }
        }

        let searchUrl = "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/cercaNumeroTrenoTrenoAutocomplete/\(cleanNumber)"
        
        guard let sUrl = URL(string: searchUrl) else {
            return StopsResult(stops: [], status: TrainStatus(), errorMessage: "URL non valido.")
        }
        
        do {
            let (sData, _) = try await NetworkService.shared.get(url: sUrl)
            let result = String(data: sData, encoding: .utf8) ?? ""
            
            if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return StopsResult(stops: [], status: TrainStatus(), errorMessage: "Treno non tracciato o non ancora nel sistema.")
            }
            
            let lines = result.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            var targets = lines.filter { $0.contains("|\(cleanNumber)-") }
            if targets.isEmpty, let firstLine = lines.first {
                targets = [firstLine]
            }
            if targets.isEmpty {
                return StopsResult(stops: [], status: TrainStatus(), errorMessage: "Dettagli del treno non trovati.")
            }
            
            let results: [(String, [String: Any])] = await withTaskGroup(of: (String, [String: Any])?.self) { group in
                for targetLine in targets {
                    group.addTask {
                        let pipes = targetLine.components(separatedBy: "|")
                        guard pipes.count >= 2 else { return nil }
                        let subParts = pipes[1].components(separatedBy: "-")
                        guard subParts.count >= 2 else { return nil }
                        
                        let originID = subParts[1]
                        let timestamp = subParts.count >= 3 ? subParts[2] : ""
                        
                        var stopsUrl = "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/andamentoTreno/\(originID)/\(cleanNumber)"
                        if !timestamp.isEmpty { stopsUrl += "/\(timestamp)" }
                        
                        guard let stUrl = URL(string: stopsUrl) else { return nil }
                        var request = URLRequest(url: stUrl)
                        request.timeoutInterval = 10.0
                        
                        do {
                            let (stData, response) = try await NetworkService.shared.get(request: request)
                            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, !stData.isEmpty else { return nil }
                            guard let json = try JSONSerialization.jsonObject(with: stData) as? [String: Any] else {
                                AppLogger.decodingError(context: "andamentoTreno:\(cleanNumber)", error: AppNetworkError.invalidResponse)
                                return nil
                            }
                            return (targetLine, json)
                        } catch {
                            AppLogger.decodingError(context: "andamentoTreno:\(cleanNumber)", error: error)
                            return nil
                        }
                    }
                }
                
                var collected = [(String, [String: Any])]()
                for await res in group {
                    if let r = res {
                        collected.append(r)
                    }
                }
                return collected
            }
            
            guard !results.isEmpty else {
                return StopsResult(stops: [], status: TrainStatus(), errorMessage: "Dati in aggiornamento o temporaneamente non disponibili.")
            }
            
            let nowTs = Date().timeIntervalSince1970 * 1000.0
            var bestTargetLine: String? = nil
            var bestJson: [String: Any]? = nil
            var bestScore: Double = -999999.0
            
            for (targetLine, json) in results {
                let pipes = targetLine.components(separatedBy: "|")
                let subParts = pipes.count >= 2 ? pipes[1].components(separatedBy: "-") : []
                let tsStr = subParts.count >= 3 ? subParts[2] : ""
                let trainTs = Double(tsStr) ?? nowTs
                
                let deltaDays = abs(nowTs - trainTs) / (1000.0 * 60 * 60 * 24)
                let isDeparted = !(json["nonPartito"] as? Bool ?? true)
                let isArrived = (json["arrivato"] as? Bool) ?? false
                
                let baseScore = (isDeparted && !isArrived) ? 5000.0 : 1000.0
                var score = baseScore - (deltaDays * 500.0)
                
                let destJson = ((json["destinazione"] as? String) ?? "").uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let origJson = ((json["origine"] as? String) ?? "").uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let fermate = (json["fermate"] as? [[String: Any]]) ?? []
                let firstStopUpper = ((fermate.first?["stazione"] as? String) ?? origJson).uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let lastStopUpper = ((fermate.last?["stazione"] as? String) ?? destJson).uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                let targetOrigUpper: String = {
                    guard let firstP = pipes.first else { return "" }
                    let splitDash = firstP.components(separatedBy: " - ")
                    return (splitDash.count > 1 ? splitDash.dropFirst().joined(separator: " - ") : firstP).uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                }()
                
                // 1. Corrispondenza Destinazione
                if let dest = destination, !dest.isEmpty {
                    let destUpper = dest.uppercased()
                        .replacingOccurrences(of: "MILANO P. ", with: "MILANO ")
                        .replacingOccurrences(of: "MILANO ", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanDestJson = destJson.replacingOccurrences(of: "MILANO P. ", with: "MILANO ")
                                                .replacingOccurrences(of: "MILANO ", with: "")
                    let cleanLastStop = lastStopUpper.replacingOccurrences(of: "MILANO P. ", with: "MILANO ")
                                                     .replacingOccurrences(of: "MILANO ", with: "")
                    
                    let isDirectMatch = cleanDestJson.contains(destUpper) || destUpper.contains(cleanDestJson) ||
                                        cleanLastStop.contains(destUpper) || destUpper.contains(cleanLastStop)
                    
                    if isDirectMatch {
                        score += 200_000.0
                    } else {
                        let matchesAnyStop = fermate.contains { f in
                            let st = ((f["stazione"] as? String) ?? "").uppercased()
                                .replacingOccurrences(of: "MILANO P. ", with: "MILANO ")
                                .replacingOccurrences(of: "MILANO ", with: "")
                            return st.contains(destUpper) || destUpper.contains(st)
                        }
                        if matchesAnyStop {
                            score += 50_000.0
                        } else {
                            score -= 200_000.0
                        }
                    }
                }
                
                // 2. Corrispondenza Origine / Stazione di partenza
                if let orig = origin, !orig.isEmpty {
                    let origUpper = orig.uppercased()
                        .replacingOccurrences(of: "MILANO P. ", with: "MILANO ")
                        .replacingOccurrences(of: "MILANO ", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanOrigJson = origJson.replacingOccurrences(of: "MILANO P. ", with: "MILANO ")
                                                .replacingOccurrences(of: "MILANO ", with: "")
                    let cleanFirstStop = firstStopUpper.replacingOccurrences(of: "MILANO P. ", with: "MILANO ")
                                                       .replacingOccurrences(of: "MILANO ", with: "")
                    let cleanTargetOrig = targetOrigUpper.replacingOccurrences(of: "MILANO P. ", with: "MILANO ")
                                                         .replacingOccurrences(of: "MILANO ", with: "")
                    
                    let isOriginDirect = cleanOrigJson.contains(origUpper) || origUpper.contains(cleanOrigJson) ||
                                         cleanFirstStop.contains(origUpper) || origUpper.contains(cleanFirstStop) ||
                                         cleanTargetOrig.contains(origUpper) || origUpper.contains(cleanTargetOrig)
                    if isOriginDirect {
                        score += 100_000.0
                    } else {
                        let matchesAnyStop = fermate.contains { f in
                            let st = ((f["stazione"] as? String) ?? "").uppercased()
                                .replacingOccurrences(of: "MILANO P. ", with: "MILANO ")
                                .replacingOccurrences(of: "MILANO ", with: "")
                            return st.contains(origUpper) || origUpper.contains(st)
                        }
                        if matchesAnyStop {
                            score += 30_000.0
                        }
                    }
                }
                
                // 3. Corrispondenza Orario programmato
                if let sched = scheduledTime, !sched.isEmpty, sched.contains(":") {
                    let jsonTimeStr = ((json["compOrarioPartenza"] as? String) ?? (json["orarioPartenza"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let partsTarget = sched.split(separator: ":")
                    let partsJson = (jsonTimeStr.components(separatedBy: " ").last ?? "").split(separator: ":")
                    if partsTarget.count == 2, partsJson.count >= 2,
                       let th = Int(partsTarget[0]), let tm = Int(partsTarget[1]),
                       let jh = Int(partsJson[0]), let jm = Int(partsJson[1]) {
                        let targetMin = th * 60 + tm
                        let jsonMin = jh * 60 + jm
                        let diff = abs(targetMin - jsonMin)
                        if diff <= 30 {
                            score += 40_000.0 - (Double(diff) * 500.0)
                        } else if diff > 90 {
                            score -= 50_000.0
                        }
                    }
                }
                
                if score > bestScore {
                    bestScore = score
                    bestJson = json
                    bestTargetLine = targetLine
                }
            }
            
            let winningLine = bestTargetLine ?? results[0].0
            let json = bestJson ?? results[0].1
            let parsed = parseStopsResult(from: json, cleanNumber: cleanNumber)
            if parsed.errorMessage == nil && !parsed.stops.isEmpty {
                let pipes = winningLine.components(separatedBy: "|")
                if pipes.count >= 2 {
                    let subParts = pipes[1].components(separatedBy: "-")
                    if subParts.count >= 2 {
                        let resolvedOrigID = subParts[1]
                        let resolvedTs = subParts.count >= 3 ? subParts[2] : ""
                        saveResolvedOrigin(
                            originID: resolvedOrigID,
                            timestamp: resolvedTs,
                            dayKey: todayKey,
                            cleanNumber: cleanNumber,
                            destination: destination,
                            origin: origin,
                            isUnambiguousSingleTarget: targets.count == 1
                        )
                    }
                }
            }
            return parsed
        } catch is CancellationError {
            return StopsResult(stops: [], status: TrainStatus(), errorMessage: nil)
        } catch {
            AppLogger.refreshFailed(target: "TrainLiveStops:\(cleanNumber)", error: error)
            return StopsResult(stops: [], status: TrainStatus(), errorMessage: "Errore di rete o blocco di sicurezza (controlla i permessi ATS nel file Info.plist).")
        }
    }

    private func parseStopsResult(from json: [String: Any], cleanNumber: String) -> StopsResult {
        var status = TrainStatus()
        status.isDeparted = !(json["nonPartito"] as? Bool ?? true)
        status.isArrived = (json["arrivato"] as? Bool) ?? false
        status.lastStation = (json["stazioneUltimoRilevamento"] as? String) ?? "--"
        status.lastTime = (json["compOraUltimoRilevamento"] as? String) ?? (json["oraUltimoRilevamento"] as? String) ?? "--:--"
        let rawCatJson = ((json["compNumeroTreno"] as? String) ?? (json["categoria"] as? String) ?? (json["subTitle"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let origNameJson = (json["origine"] as? String) ?? ((json["fermate"] as? [[String: Any]])?.first?["stazione"] as? String) ?? ""
        let destNameJson = (json["destinazione"] as? String) ?? ((json["fermate"] as? [[String: Any]])?.last?["stazione"] as? String) ?? ""
        status.detectedCategory = resolveTrainCategory(
            number: cleanNumber,
            rawCategory: rawCatJson.replacingOccurrences(of: cleanNumber, with: "").trimmingCharacters(in: .whitespacesAndNewlines),
            description: "\(origNameJson) - \(destNameJson)"
        )

        if let ritardi = json["compRitardo"] as? [String], !ritardi.isEmpty { status.statusMessage = ritardi[0] }
        else { status.statusMessage = status.isDeparted ? "In viaggio" : "In attesa di partenza" }
        if let provv = json["provvedimento"] as? Int, provv != 0 { status.cancellationNote = "TRENO CANCELLATO O DEVIATO"; status.statusMessage = "Soppresso" }

        let globalDelay = (json["ritardo"] as? Int) ?? 0

        if let fermate = json["fermate"] as? [[String: Any]] {
            let mappedStops = fermate.map { f -> Stop in
                let name = (f["stazione"] as? String) ?? "Sconosciuta"
                let tProg = (f["programmata"] as? Int) ?? 0
                let tEff = (f["effettiva"] as? Int) ?? 0

                let stopSpecificDelay = (f["ritardo"] as? Int) ?? 0
                let effectiveDelay = stopSpecificDelay > 0 ? stopSpecificDelay : globalDelay

                let d = Date(timeIntervalSince1970: TimeInterval(tProg/1000))
                let actT = tEff > 0 ? SharedFormatters.time.string(from: Date(timeIntervalSince1970: TimeInterval(tEff/1000))) : nil

                var estT: String? = nil
                if actT == nil && effectiveDelay >= 3 {
                    if let futureDate = Calendar.current.date(byAdding: .minute, value: effectiveDelay, to: d) {
                        estT = SharedFormatters.time.string(from: futureDate)
                    }
                }

                let progArr = f["binarioProgrammatoArrivoDescrizione"] as? String
                let progPart = f["binarioProgrammatoPartenzaDescrizione"] as? String
                let effArr = f["binarioEffettivoArrivoDescrizione"] as? String
                let effPart = f["binarioEffettivoPartenzaDescrizione"] as? String

                let plannedPlatform = (progPart ?? progArr)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let actualPlatform = (effPart ?? effArr)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let isSuppressed = (f["actualFermataType"] as? Int) == 3 || ((f["tipoFermata"] as? String)?.uppercased() == "S")

                return Stop(
                    stationName: name.capitalized,
                    time: SharedFormatters.time.string(from: d),
                    actualTime: actT,
                    delay: effectiveDelay,
                    estimatedTime: estT,
                    plannedPlatform: plannedPlatform,
                    actualPlatform: actualPlatform,
                    isSuppressed: isSuppressed
                )
            }
            return StopsResult(stops: mappedStops, status: status, errorMessage: nil)
        }
        return StopsResult(stops: [], status: status, errorMessage: "Nessuna fermata trovata.")
    }
}
