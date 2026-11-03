import Foundation

struct StationBoardResult: Sendable {
    let trains: [Train]
    let alerts: String?
    
    nonisolated init(trains: [Train], alerts: String? = nil) {
        self.trains = trains
        self.alerts = alerts
    }
}

actor StationRepository {
    static let shared = StationRepository()
    
    private struct CacheEntry: Sendable {
        let timestamp: Date
        let result: StationBoardResult
    }
    
    private var cache: [String: CacheEntry] = [:]
    private var inFlightTasks: [String: Task<StationBoardResult, Never>] = [:]
    private let ttl: TimeInterval = 45.0 // 45 seconds TTL
    
    init() {}
    
    func getStationBoard(station: Station, isDepartures: Bool, force: Bool = false) async -> StationBoardResult {
        let key = cacheKey(for: station, isDepartures: isDepartures)
        
        // 1. Check in-memory cache if not forced
        if !force, let cached = cache[key], Date().timeIntervalSince(cached.timestamp) < ttl {
            AppLogger.cache("StationRepository: cache hit for \(key)")
            return cached.result
        }
        
        // 2. Reuse in-flight task if currently loading
        if let ongoing = inFlightTasks[key] {
            AppLogger.duplicateAvoided(key: "StationRepository:\(key)")
            return await ongoing.value
        }
        
        // 3. Launch fetch task
        let task = Task<StationBoardResult, Never> { [weak self] in
            guard let self = self else { return StationBoardResult(trains: []) }
            return await self.fetchStationData(station: station, isDepartures: isDepartures)
        }
        
        inFlightTasks[key] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: key)
        
        // Cache successful results
        if !result.trains.isEmpty {
            cache[key] = CacheEntry(timestamp: Date(), result: result)
        } else {
            AppLogger.refreshFailed(target: "Station:\(station.name)")
        }
        
        return result
    }
    
    func getTrainsForStation(station: Station) async -> [Train] {
        let result = await getStationBoard(station: station, isDepartures: true, force: false)
        return result.trains
    }
    
    func clearCache() {
        cache.removeAll()
    }
    
    func cacheCount() -> Int {
        return cache.count
    }
    
    // MARK: - Cache Key
    
    func cacheKey(for station: Station, isDepartures: Bool) -> String {
        return "\(station.vtID ?? station.rfiID ?? station.name)_\(isDepartures)"
    }
    
    // MARK: - Core Fetching Logic (Runs in Background)
    
    private func fetchStationData(station: Station, isDepartures: Bool) async -> StationBoardResult {
        let rfiID = station.rfiID ?? ""
        let vtID = station.vtID ?? ""
        
        if !rfiID.isEmpty {
            let rfiResult = await performRfiScraping(for: rfiID, isDepartures: isDepartures)
            guard !Task.isCancelled else { return StationBoardResult(trains: []) }
            
            if !rfiResult.trains.isEmpty {
                let hasUpcomingTrains = rfiResult.trains.contains { trainIsWithinNextMinutes($0, minutes: 45) }
                
                if hasUpcomingTrains && !vtID.isEmpty {
                    let vtDateStr = makeVTDateString()
                    let vtTrains = await performVTFetch(for: vtID, isDepartures: isDepartures, dateStr: vtDateStr)
                    guard !Task.isCancelled else { return StationBoardResult(trains: []) }
                    let finalTrains = vtTrains.isEmpty
                        ? rfiResult.trains
                        : mergeVTDelays(rfiTrains: rfiResult.trains, vtTrains: vtTrains)
                    return StationBoardResult(trains: finalTrains, alerts: rfiResult.alerts)
                } else {
                    return StationBoardResult(trains: rfiResult.trains, alerts: rfiResult.alerts)
                }
            } else if !vtID.isEmpty {
                let vtTrains = await performVTFetch(for: vtID, isDepartures: isDepartures, dateStr: makeVTDateString())
                return StationBoardResult(trains: vtTrains, alerts: nil)
            } else {
                return StationBoardResult(trains: [], alerts: nil)
            }
        } else if !vtID.isEmpty {
            let vtTrains = await performVTFetch(for: vtID, isDepartures: isDepartures, dateStr: makeVTDateString())
            return StationBoardResult(trains: vtTrains, alerts: nil)
        } else {
            return StationBoardResult(trains: [], alerts: nil)
        }
    }
    
    // MARK: - ViaggiaTreno Fetching & Parsing
    
    private func performVTFetch(for vtID: String, isDepartures: Bool, dateStr: String) async -> [Train] {
        let endpoint = isDepartures ? "partenze" : "arrivi"
        let urlString = "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/\(endpoint)/\(vtID)/\(dateStr)"
        guard let url = URL(string: urlString) else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, _) = try await NetworkService.shared.get(request: request)
            guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                AppLogger.decodingError(context: "ViaggiaTreno:\(vtID)", error: AppNetworkError.invalidResponse)
                return []
            }
            
            return jsonArray.compactMap { item in
                let num = String(item["numeroTreno"] as? Int ?? 0)
                var cat = (item["categoriaDescrizione"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                let dest = ((isDepartures ? item["destinazione"] : item["origine"]) as? String)?.capitalized ?? ""
                let timeVal = (isDepartures ? item["orarioPartenza"] : item["orarioArrivo"]) as? Int ?? 0
                let ritardo = item["ritardo"] as? Int ?? 0
                
                let binEff = (isDepartures ? item["binarioEffettivoPartenzaDescrizione"] : item["binarioEffettivoArrivoDescrizione"]) as? String
                let binProg = (isDepartures ? item["binarioProgrammatoPartenzaDescrizione"] : item["binarioProgrammatoArrivoDescrizione"]) as? String
                let platform = binEff ?? binProg ?? "--"
                
                let catUpper = cat.uppercased()
                if catUpper.contains("ALTA VELOCIT") { cat = "AV" }
                else if catUpper.contains("INTERCITY") { cat = "IC" }
                else if catUpper.contains("EUROCITY") { cat = "EC" }
                else if catUpper == "REGIONALE VELOCE" { cat = "RV" }
                else if catUpper == "REGIONALE" { cat = "REG" }
                else if catUpper == "SUBURBANO" { cat = "S" }
                
                if cat.uppercased() == "S" || cat.uppercased() == "REG" {
                    if num.hasPrefix("240") || num.hasPrefix("230") || num.hasPrefix("241") || num.hasPrefix("231") { cat = "S1" }
                    else if num.hasPrefix("242") || num.hasPrefix("232") {
                        let d = dest.lowercased()
                        if d.contains("melegnano") || d.contains("cormano") { cat = "S12" }
                        else { cat = "S2" }
                    }
                    else if num.hasPrefix("243") || num.hasPrefix("233") || num.hasPrefix("328") || num.hasPrefix("329") { cat = "S13" }
                    else if num.hasPrefix("245") || num.hasPrefix("235") { cat = "S5" }
                    else if num.hasPrefix("246") || num.hasPrefix("236") { cat = "S6" }
                    else if num.hasPrefix("256") || num.hasPrefix("257") || num.hasPrefix("247") || num.hasPrefix("237") { cat = "S12" }
                    else if num.hasPrefix("248") || num.hasPrefix("238") { cat = "S8" }
                    else if num.hasPrefix("249") || num.hasPrefix("239") { cat = "S9" }
                    else if num.hasPrefix("250") || num.hasPrefix("251") || num.hasPrefix("252") { cat = "S11" }
                    else {
                        let d = dest.lowercased()
                        if d.contains("saronno") || d.contains("lodi") { cat = "S1" }
                        else if d.contains("mariano") || d.contains("seveso") || d.contains("camnago") { cat = "S2" }
                        else if d.contains("varese") || d.contains("treviglio") || d.contains("gallarate") { cat = "S5" }
                        else if d.contains("novara") || d.contains("nov ") || d.contains("pioltello") || d.contains("piolt") || d.contains("magenta") { cat = "S6" }
                        else if d.contains("melegnano") || d.contains("cormano") { cat = "S12" }
                        else if d.contains("pavia") || d.contains("garbagnate") { cat = "S13" }
                    }
                }
                
                let isCancelled = (item["cancellato"] as? Bool ?? false) || (item["provvedimento"] as? Int ?? 0) == 1
                let delayStr = isCancelled ? "Cancellato" : (ritardo > 0 ? "+\(ritardo)'" : "In orario")
                
                if timeVal > 0 {
                    let date = Date(timeIntervalSince1970: TimeInterval(timeVal/1000))
                    return Train(category: cat, number: num, destination: dest, time: SharedFormatters.time.string(from: date), delay: delayStr, platform: platform)
                }
                return nil
            }
        } catch {
            AppLogger.refreshFailed(target: "ViaggiaTreno:\(vtID)", error: error)
            return []
        }
    }
    
    // MARK: - RFI Scraping & Parsing
    
    private func performRfiScraping(for rfiID: String, isDepartures: Bool) async -> (trains: [Train], alerts: String?) {
        let urlString = "https://iechub.rfi.it/ArriviPartenze/ArrivalsDepartures/Monitor?placeId=\(rfiID)&arrivals=\(!(isDepartures))"
        guard let url = URL(string: urlString) else { return ([], nil) }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await NetworkService.shared.get(request: request)
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return ([], nil) }
            
            var stationAlerts: String? = nil
            if let range = html.range(of: "Avvisi") {
                let subHtml = String(html[range.lowerBound...])
                if let endRange = subHtml.range(of: "</div>") {
                    let alertRaw = String(subHtml[..<endRange.lowerBound])
                    var cleanAlert = stripHTML(alertRaw)
                        .replacingOccurrences(of: "Avvisi", with: "")
                        .replacingOccurrences(of: "<", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if cleanAlert.uppercased().contains("VIETATO APRIRE LE PORTE") {
                        cleanAlert = ""
                    }
                    
                    if !cleanAlert.isEmpty {
                        stationAlerts = cleanAlert
                    }
                }
            }
            
            var cleanHtml = html.replacingOccurrences(of: "<TR", with: "<tr", options: .caseInsensitive)
            cleanHtml = cleanHtml.replacingOccurrences(of: "<TD", with: "<td", options: .caseInsensitive)
            let rows = cleanHtml.components(separatedBy: "<tr")
            var scrapedTrains: [Train] = []
            for row in rows.dropFirst() {
                let cols = row.components(separatedBy: "<td")
                if cols.count >= 8 {
                    var cat = stripHTML(cols[2]).replacingOccurrences(of: "Categoria", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
                    if cat.isEmpty {
                        if let altRange = cols[2].range(of: "alt=\"([^\"]+)\"", options: .regularExpression) {
                            let match = String(cols[2][altRange])
                            let rawAlt = match.replacingOccurrences(of: "alt=\"", with: "")
                                              .replacingOccurrences(of: "\"", with: "")
                                              .replacingOccurrences(of: "Categoria", with: "", options: .caseInsensitive)
                            cat = stripHTML(rawAlt)
                        }
                    }
                    let num = stripHTML(cols[3])
                    let dest = stripHTML(cols[4])
                    let time = stripHTML(cols[5])
                    let delayRaw = stripHTML(cols[6])
                    let plat = stripHTML(cols[7])
                    
                    let catUpper = cat.uppercased()
                    if catUpper.contains("ALTA VELOCIT") { cat = "AV" }
                    else if catUpper.contains("INTERCITY") { cat = "IC" }
                    else if catUpper.contains("EUROCITY") { cat = "EC" }
                    else if catUpper == "REGIONALE VELOCE" { cat = "RV" }
                    else if catUpper == "REGIONALE" { cat = "REG" }
                    
                    if cat.isEmpty {
                        if num.hasPrefix("20") || num.hasPrefix("21") { cat = "RV" }
                        else if num.hasPrefix("24") || num.hasPrefix("10") { cat = "S" }
                        else { cat = "REG" }
                    }
                    
                    if cat.uppercased() == "S" || cat.uppercased() == "REG" {
                        if num.hasPrefix("240") || num.hasPrefix("230") || num.hasPrefix("241") || num.hasPrefix("231") { cat = "S1" }
                        else if num.hasPrefix("242") || num.hasPrefix("232") {
                            let d = dest.lowercased()
                            if d.contains("melegnano") || d.contains("cormano") { cat = "S12" }
                            else { cat = "S2" }
                        }
                        else if num.hasPrefix("243") || num.hasPrefix("233") || num.hasPrefix("328") || num.hasPrefix("329") { cat = "S13" }
                        else if num.hasPrefix("245") || num.hasPrefix("235") { cat = "S5" }
                        else if num.hasPrefix("246") || num.hasPrefix("236") { cat = "S6" }
                        else if num.hasPrefix("256") || num.hasPrefix("257") || num.hasPrefix("247") || num.hasPrefix("237") { cat = "S12" }
                        else if num.hasPrefix("248") || num.hasPrefix("238") { cat = "S8" }
                        else if num.hasPrefix("249") || num.hasPrefix("239") { cat = "S9" }
                        else if num.hasPrefix("250") || num.hasPrefix("251") || num.hasPrefix("252") { cat = "S11" }
                        else {
                            let d = dest.lowercased()
                            if d.contains("saronno") || d.contains("lodi") { cat = "S1" }
                            else if d.contains("mariano") || d.contains("seveso") || d.contains("camnago") { cat = "S2" }
                            else if d.contains("varese") || d.contains("treviglio") || d.contains("gallarate") { cat = "S5" }
                            else if d.contains("novara") || d.contains("nov ") || d.contains("pioltello") || d.contains("piolt") || d.contains("magenta") { cat = "S6" }
                            else if d.contains("melegnano") || d.contains("cormano") { cat = "S12" }
                            else if d.contains("pavia") || d.contains("garbagnate") { cat = "S13" }
                        }
                    }
                    if !num.isEmpty && time.contains(":") {
                        scrapedTrains.append(Train(category: cat, number: num, destination: dest.capitalized, time: time, delay: delayRaw.isEmpty ? "In orario" : "+\(delayRaw)'", platform: plat.isEmpty ? "--" : plat))
                    }
                }
            }
            return (scrapedTrains, stationAlerts)
        } catch {
            return ([], nil)
        }
    }
    
    // MARK: - Delay Merging & Helpers
    
    private func mergeVTDelays(rfiTrains: [Train], vtTrains: [Train]) -> [Train] {
        let vtByNumber: [String: Train] = Dictionary(
            vtTrains.map { ($0.number, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        
        let discrepancyThreshold = 15
        
        return rfiTrains.map { rfi in
            guard trainIsWithinNextMinutes(rfi, minutes: 45) else { return rfi }
            
            let rfiDelayLower = rfi.delay.lowercased()
            if rfiDelayLower.contains("cancellat") || rfiDelayLower.contains("soppress") {
                return rfi
            }
            
            guard let vt = vtByNumber[rfi.number] else { return rfi }
            let vtDelayLower = vt.delay.lowercased()
            if vtDelayLower.contains("cancellat") || vtDelayLower.contains("soppress") {
                return rfi
            }
            
            let rfiMin = parseDelayMinutes(rfi.delay)
            let vtMin  = parseDelayMinutes(vt.delay)
            let diff   = abs(vtMin - rfiMin)
            
            if diff > discrepancyThreshold {
                return Train(
                    category: rfi.category, number: rfi.number,
                    destination: rfi.destination, time: rfi.time,
                    delay: rfi.delay, platform: rfi.platform,
                    isDelayUncertain: true
                )
            }
            
            return Train(
                category: rfi.category, number: rfi.number,
                destination: rfi.destination, time: rfi.time,
                delay: vt.delay, platform: rfi.platform,
                isDelayUncertain: false
            )
        }
    }
    
    private func trainIsWithinNextMinutes(_ train: Train, minutes: Int) -> Bool {
        let parts = train.time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return false }
        
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        
        guard var trainDate = calendar.date(from: components) else { return false }
        
        let diff = trainDate.timeIntervalSince(now)
        if diff < -43200 { trainDate = calendar.date(byAdding: .day, value: 1, to: trainDate) ?? trainDate }
        else if diff > 43200 { trainDate = calendar.date(byAdding: .day, value: -1, to: trainDate) ?? trainDate }
        
        let windowStart = calendar.date(byAdding: .minute, value: -5, to: now)!
        let windowEnd   = calendar.date(byAdding: .minute, value: minutes, to: now)!
        return trainDate >= windowStart && trainDate <= windowEnd
    }
    
    private func parseDelayMinutes(_ delayString: String) -> Int {
        let clean = delayString
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "R: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if clean.contains("orario") { return 0 }
        return Int(clean) ?? 0
    }
    
    private func stripHTML(_ str: String) -> String {
        var text = "<td" + str
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression, range: nil)
        text = text.replacingOccurrences(of: "<td", with: " ", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&#39", with: "'")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func makeVTDateString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        f.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT'ZZZ"
        let str = f.string(from: Date()).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return str.replacingOccurrences(of: "+", with: "%2B")
    }
}
