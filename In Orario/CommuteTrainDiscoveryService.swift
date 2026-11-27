import Foundation
import CoreLocation

private struct DiscoveryRFIStation: Decodable, Sendable {
    let name: String
    let vtID: String?
}

/// Servizio on-device (iPhone) per scoprire i treni reali nelle fasce orarie configurate
/// tramite API Trenitalia (LeFrecce) con fallback diretto su ViaggiaTreno e Italo.
actor CommuteTrainDiscoveryService {
    static let shared = CommuteTrainDiscoveryService()

    private struct DiscoveryCacheEntry {
        let timestamp: Date
        let trains: [CommuteHabitTrain]
    }

    private struct LocalPlanCacheEntry {
        let fetchedAt: Date
        let requestedDate: Date
        let report: PlanBReportDTO
    }

    private var locationIDCache: [String: [Int]] = [:]
    private var vtIDCache: [String: [String]] = [:]
    private var discoveryCache: [String: DiscoveryCacheEntry] = [:]
    private var localPlanCache: [String: LocalPlanCacheEntry] = [:]
    private var rfiStationsCache: [DiscoveryRFIStation]? = nil
    private let cacheTTL: TimeInterval = 600.0
    private let localPlanCacheTTL: TimeInterval = 1200.0

    private init() {}

    func clearCache() {
        discoveryCache.removeAll()
        localPlanCache.removeAll()
    }

    // MARK: - Pure Helpers (nonisolated for unit tests & background parsing)

    nonisolated static func nextDate(
        forISOWeekday weekday: Int,
        hour: Int,
        minute: Int,
        referenceDate: Date = Date()
    ) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current

        let clampedWeekday = (1...7).contains(weekday) ? weekday : 1
        let refComp = cal.component(.weekday, from: referenceDate)
        let refISO = ((refComp + 5) % 7) + 1
        var deltaDays = (clampedWeekday - refISO + 7) % 7
        if deltaDays == 0 {
            deltaDays = 7
        }

        let startOfRef = cal.startOfDay(for: referenceDate)
        let targetDay = cal.date(byAdding: .day, value: deltaDays, to: startOfRef) ?? referenceDate
        var comps = cal.dateComponents([.year, .month, .day], from: targetDay)
        comps.hour = ((hour % 24) + 24) % 24
        comps.minute = ((minute % 60) + 60) % 60
        comps.second = 0
        return cal.date(from: comps) ?? targetDay
    }

    nonisolated static func weekdayBucket(for weekday: Int) -> String {
        switch weekday {
        case 1: return "mon"
        case 2, 3, 4: return "midweek"
        case 5: return "fri"
        case 6: return "sat"
        case 7: return "sun"
        default: return "d\(weekday)"
        }
    }

    nonisolated static func normalizeTrainCategory(
        acronym: String,
        category: String,
        denomination: String,
        trainNumber: String,
        destination: String
    ) -> String {
        let acrU = acronym.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let catU = category.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let denU = denomination.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let combined = "\(acrU) \(catU) \(denU)"

        if isItaloTrain(category: combined, number: trainNumber) || combined.contains("ITALO") || combined.contains("NTV") {
            return "Italo"
        }
        if combined.contains("FRECCIAROSSA") || acrU == "FR" {
            return "FR"
        }
        if combined.contains("FRECCIARGENTO") || acrU == "FA" {
            return "FA"
        }
        if combined.contains("FRECCIABIANCA") || acrU == "FB" {
            return "FB"
        }
        if combined.contains("INTERCITY NOTTE") || acrU == "ICN" {
            return "ICN"
        }
        if combined.contains("INTERCITY") || acrU == "IC" {
            return "IC"
        }
        if combined.contains("EUROCITY") || acrU == "EC" {
            return "EC"
        }
        if combined.contains("MALPENSA") || acrU == "MXP" {
            return "MXP"
        }
        if let match = combined.range(of: #"\bS\d{1,2}\b"#, options: .regularExpression) {
            return String(combined[match])
        }
        if combined.contains("FAST REGIONAL") || combined.contains("REGIONALE VELOCE") || acrU == "RV" || catU == "RV" {
            return "RV"
        }

        var result: String
        if combined.contains("SUBURBAN") || acrU == "S" || catU == "S" {
            result = "S"
        } else if combined.contains("REGIONALE") || acrU == "REG" || catU == "REG" || acrU == "R" || catU == "R" {
            result = "REG"
        } else if !acrU.isEmpty {
            result = acrU
        } else {
            let cleaned = cleanTrainCategory(denomination.isEmpty ? category : denomination)
            result = cleaned.isEmpty ? "Treno" : cleaned
        }

        // Riconoscimento linee S lombarde quando Trenitalia/ViaggiaTreno espone solo S o REG
        if result == "S" || result == "REG" {
            let num = StationNameMatcher.cleanTrainDigits(trainNumber)
            if num.hasPrefix("240") || num.hasPrefix("230") || num.hasPrefix("241") || num.hasPrefix("231") {
                return "S1"
            } else if num.hasPrefix("242") || num.hasPrefix("232") {
                let d = destination.lowercased()
                return (d.contains("melegnano") || d.contains("cormano")) ? "S12" : "S2"
            } else if num.hasPrefix("243") || num.hasPrefix("233") || num.hasPrefix("328") || num.hasPrefix("329") {
                return "S13"
            } else if num.hasPrefix("245") || num.hasPrefix("235") {
                return "S5"
            } else if num.hasPrefix("246") || num.hasPrefix("236") {
                return "S6"
            } else if num.hasPrefix("256") || num.hasPrefix("257") || num.hasPrefix("247") || num.hasPrefix("237") {
                return "S12"
            } else if num.hasPrefix("248") || num.hasPrefix("238") {
                return "S8"
            } else if num.hasPrefix("249") || num.hasPrefix("239") {
                return "S9"
            } else if num.hasPrefix("250") || num.hasPrefix("251") || num.hasPrefix("252") {
                return "S11"
            }
        }

        return result
    }

    nonisolated static func extractCleanTrainNumber(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let lastToken = trimmed.split(whereSeparator: { $0.isWhitespace }).last,
           lastToken.allSatisfy({ $0.isNumber }) {
            return String(lastToken)
        }
        return StationNameMatcher.cleanTrainDigits(trimmed)
    }

    nonisolated private static func extractHHmm(from isoString: String?) -> String? {
        guard let raw = isoString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let fmt1 = DateFormatter()
        fmt1.locale = Locale(identifier: "en_US_POSIX")
        fmt1.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        fmt1.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        if let d = fmt1.date(from: raw) {
            return SharedFormatters.time.string(from: d)
        }
        let fmt2 = DateFormatter()
        fmt2.locale = Locale(identifier: "en_US_POSIX")
        fmt2.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        fmt2.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        if let d = fmt2.date(from: raw) {
            return SharedFormatters.time.string(from: d)
        }
        if let tIdx = raw.firstIndex(of: "T") {
            let afterT = raw[raw.index(after: tIdx)...]
            if afterT.count >= 5 {
                let candidate = String(afterT.prefix(5))
                if CommuteTimeBand.parseHHmm(candidate) != nil {
                    return candidate
                }
            }
        }
        return nil
    }

    nonisolated static func parseLefrecceBandTrains(
        from data: Data,
        originStation: String,
        destinationStation: String,
        band: CommuteTimeBand,
        marginBefore: Int = 0,
        marginAfter: Int = 0
    ) -> (trains: [CommuteHabitTrain], lastDepartureMinutes: Int?, totalSolutions: Int) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let solutions = json["solutions"] as? [[String: Any]] else {
            return ([], nil, 0)
        }

        var trains: [CommuteHabitTrain] = []
        var lastDepMin: Int? = nil

        for item in solutions {
            guard let sol = item["solution"] as? [String: Any] else { continue }

            let solDepHHmm = extractHHmm(from: sol["departureTime"] as? String)
            let solArrHHmm = extractHHmm(from: sol["arrivalTime"] as? String)
            if let solDepHHmm, let m = CommuteTimeBand.parseHHmm(solDepHHmm) {
                lastDepMin = m
            }

            if let nodes = sol["nodes"] as? [[String: Any]] {
                // Accetta solo corse ferroviarie dirette (nessun cambio, nessun segmento urbano o pedonale)
                guard nodes.count == 1, let railNode = nodes.first,
                      let tr = railNode["train"] as? [String: Any] else {
                    continue
                }
                let acronym = (tr["acronym"] as? String)?.uppercased() ?? ""
                let cat = (tr["trainCategory"] as? String) ?? ""
                let denom = (tr["denomination"] as? String) ?? ""
                let catLow = cat.lowercased()
                let denomLow = denom.lowercased()
                let isUrb = (tr["urban"] as? Bool) ?? false
                if isUrb || acronym == "UB" || acronym == "WK" ||
                   ((catLow.contains("urban") || denomLow.contains("urban") || catLow.contains("metro") || catLow.contains("walk")) && !catLow.contains("suburbano")) {
                    continue
                }

                let nodeOrigin = (railNode["origin"] as? String) ?? (sol["origin"] as? String) ?? ""
                let nodeDest = (railNode["destination"] as? String) ?? (sol["destination"] as? String) ?? ""
                guard StationNameMatcher.isSameStation(nodeOrigin, originStation),
                      StationNameMatcher.isSameStation(nodeDest, destinationStation) else {
                    continue
                }

                guard let depHHmm = extractHHmm(from: railNode["departureTime"] as? String) ?? solDepHHmm else {
                    continue
                }
                if let m = CommuteTimeBand.parseHHmm(depHHmm) {
                    lastDepMin = m
                }
                guard band.contains(timeString: depHHmm, marginBefore: marginBefore, marginAfter: marginAfter) else {
                    continue
                }

                let arrHHmm = extractHHmm(from: railNode["arrivalTime"] as? String) ?? solArrHHmm
                let rawName = (tr["name"] as? String) ?? (tr["description"] as? String) ?? ""
                let cleanNum = extractCleanTrainNumber(from: rawName)
                guard !cleanNum.isEmpty else { continue }

                let normCat = normalizeTrainCategory(
                    acronym: acronym,
                    category: cat,
                    denomination: denom,
                    trainNumber: cleanNum,
                    destination: destinationStation
                )

                trains.append(CommuteHabitTrain(
                    trainNumber: cleanNum,
                    category: normCat,
                    originStation: originStation,
                    destinationStation: destinationStation,
                    departureTime: depHHmm,
                    arrivalTime: arrHHmm,
                    isManuallyAdded: false
                ))
            } else if let solTrains = sol["trains"] as? [[String: Any]], solTrains.count == 1, let firstTrain = solTrains.first {
                let solOrigin = (sol["origin"] as? String) ?? ""
                let solDest = (sol["destination"] as? String) ?? ""
                guard StationNameMatcher.isSameStation(solOrigin, originStation),
                      StationNameMatcher.isSameStation(solDest, destinationStation),
                      let depHHmm = solDepHHmm,
                      band.contains(timeString: depHHmm, marginBefore: marginBefore, marginAfter: marginAfter) else {
                    continue
                }

                let rawName = (firstTrain["name"] as? String) ?? (firstTrain["description"] as? String) ?? ""
                let cleanNum = extractCleanTrainNumber(from: rawName)
                guard !cleanNum.isEmpty else { continue }

                let acronym = (firstTrain["acronym"] as? String) ?? ""
                let cat = (firstTrain["trainCategory"] as? String) ?? ""
                let denom = (firstTrain["denomination"] as? String) ?? ""
                let normCat = normalizeTrainCategory(
                    acronym: acronym,
                    category: cat,
                    denomination: denom,
                    trainNumber: cleanNum,
                    destination: destinationStation
                )

                trains.append(CommuteHabitTrain(
                    trainNumber: cleanNum,
                    category: normCat,
                    originStation: originStation,
                    destinationStation: destinationStation,
                    departureTime: depHHmm,
                    arrivalTime: solArrHHmm,
                    isManuallyAdded: false
                ))
            }
        }

        return (trains, lastDepMin, solutions.count)
    }

    nonisolated static func sortKeyMinutes(for timeString: String, anchorMinutes: Int) -> Int {
        guard let m = CommuteTimeBand.parseHHmm(timeString) else { return Int.max }
        var diff = m - anchorMinutes
        if diff < -720 { diff += 1440 }
        else if diff > 720 { diff -= 1440 }
        return diff
    }

    nonisolated static func deduplicateAndSort(
        _ trains: [CommuteHabitTrain],
        origins: [String],
        band: CommuteTimeBand
    ) -> [CommuteHabitTrain] {
        var bestByNum: [String: CommuteHabitTrain] = [:]

        func originRank(_ station: String) -> Int {
            if let idx = origins.firstIndex(where: { StationNameMatcher.isSameStation($0, station) }) {
                return idx
            }
            return Int.max
        }

        for candidate in trains {
            let key = StationNameMatcher.cleanTrainDigits(candidate.trainNumber)
            guard !key.isEmpty else { continue }

            guard let existing = bestByNum[key] else {
                bestByNum[key] = candidate
                continue
            }

            let candOrigRank = originRank(candidate.originStation)
            let exOrigRank = originRank(existing.originStation)
            if candOrigRank < exOrigRank {
                bestByNum[key] = candidate
                continue
            }
            if candOrigRank == exOrigRank {
                let candArr = candidate.arrivalTime.flatMap { CommuteTimeBand.parseHHmm($0) } ?? Int.max
                let exArr = existing.arrivalTime.flatMap { CommuteTimeBand.parseHHmm($0) } ?? Int.max
                if candArr < exArr {
                    bestByNum[key] = candidate
                }
            }
        }

        let anchor = ((band.startMinutes - 120) % 1440 + 1440) % 1440
        return bestByNum.values.sorted { a, b in
            let ka = sortKeyMinutes(for: a.departureTime, anchorMinutes: anchor)
            let kb = sortKeyMinutes(for: b.departureTime, anchorMinutes: anchor)
            if ka != kb { return ka < kb }
            return a.trainNumber < b.trainNumber
        }
    }

    nonisolated static func mergeDiscoveredWithExisting(
        discovered: [CommuteHabitTrain],
        existing: [CommuteHabitTrain],
        band: CommuteTimeBand,
        origins: [String] = []
    ) -> [CommuteHabitTrain] {
        var merged = discovered
        let discoveredNums = Set(discovered.map { StationNameMatcher.cleanTrainDigits($0.trainNumber) })
        for tr in existing where tr.isManuallyAdded {
            let clean = StationNameMatcher.cleanTrainDigits(tr.trainNumber)
            if !clean.isEmpty && !discoveredNums.contains(clean) {
                merged.append(tr)
            }
        }
        return deduplicateAndSort(merged, origins: origins, band: band)
    }

    // MARK: - On-Device Discovery API

    func discoverTrains(
        weekday: Int,
        bandString: String,
        origins: [String],
        destinations: [String],
        extraMarginBefore: Int = 0,
        extraMarginAfter: Int = 0,
        forceRefresh: Bool = false
    ) async -> [CommuteHabitTrain] {
        let cleanOrigins = origins.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let cleanDests = destinations.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleanOrigins.isEmpty, !cleanDests.isEmpty else { return [] }

        let band = CommuteTimeBand.parse(bandString)
        let cacheKey = "\(Self.weekdayBucket(for: weekday))|\(band.formatted)|\(extraMarginBefore):\(extraMarginAfter)|\(cleanOrigins.joined(separator: ","))->\(cleanDests.joined(separator: ","))"

        if !forceRefresh,
           let cached = discoveryCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.trains
        }

        // 1. Risolvi i location ID Trenitalia di tutte le stazioni in parallelo
        let uniqueStations = Array(Set(cleanOrigins + cleanDests))
        var locMap: [String: [Int]] = [:]
        await withTaskGroup(of: (String, [Int]).self) { group in
            for st in uniqueStations {
                group.addTask {
                    let ids = await self.resolveLefrecceLocationIDs(for: st)
                    return (st, ids)
                }
            }
            for await (st, ids) in group {
                locMap[st] = ids
            }
        }

        guard !Task.isCancelled else { return [] }

        let targetBaseDate = Self.nextDate(forISOWeekday: weekday, hour: band.startHour, minute: band.startMinute)
        let searchStartDate = targetBaseDate.addingTimeInterval(TimeInterval(-extraMarginBefore * 60))

        let isoFmt = DateFormatter()
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        isoFmt.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        isoFmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.000ZZZZZ"
        let depTimeISO = isoFmt.string(from: searchStartDate)

        struct PairQuery: Sendable {
            let origin: String
            let destination: String
            let depID: Int
            let arrID: Int
        }

        var pairQueries: [PairQuery] = []
        var fallbackPairs: [(origin: String, destination: String)] = []
        var seenIDPairs: Set<String> = []

        for orig in cleanOrigins {
            let depIDs = locMap[orig] ?? []
            for dest in cleanDests {
                let arrIDs = locMap[dest] ?? []
                if depIDs.isEmpty || arrIDs.isEmpty {
                    fallbackPairs.append((orig, dest))
                    continue
                }
                var addedForPair = false
                for dID in depIDs {
                    for aID in arrIDs where dID != aID {
                        let pk = "\(dID)->\(aID)"
                        if seenIDPairs.insert(pk).inserted {
                            pairQueries.append(PairQuery(origin: orig, destination: dest, depID: dID, arrID: aID))
                            addedForPair = true
                        }
                    }
                }
                if !addedForPair {
                    fallbackPairs.append((orig, dest))
                }
            }
        }

        // 2. Interroga LeFrecce Solutions (concorrenza limitata a 4)
        var discoveredTrains: [CommuteHabitTrain] = []
        var coveredStationPairs: Set<String> = []
        let maxWindowRelEnd = band.durationMinutes + extraMarginAfter

        var pairIterator = pairQueries.makeIterator()
        await withTaskGroup(of: (PairQuery, [CommuteHabitTrain], Bool).self) { group in
            func enqueueNext() {
                guard let pq = pairIterator.next() else { return }
                group.addTask {
                    let (trains, ok) = await self.fetchLefreccePairTrains(
                        origin: pq.origin,
                        destination: pq.destination,
                        depID: pq.depID,
                        arrID: pq.arrID,
                        depTimeISO: depTimeISO,
                        band: band,
                        marginBefore: extraMarginBefore,
                        marginAfter: extraMarginAfter,
                        maxWindowRelEnd: maxWindowRelEnd
                    )
                    return (pq, trains, ok)
                }
            }

            for _ in 0..<4 {
                enqueueNext()
            }
            for await (pq, trains, ok) in group {
                if ok {
                    coveredStationPairs.insert("\(pq.origin)->\(pq.destination)")
                }
                discoveredTrains.append(contentsOf: trains)
                enqueueNext()
            }
        }

        guard !Task.isCancelled else { return [] }

        // Aggiungi eventuali coppie con ID presente ma nessuna risposta valida / copertura LeFrecce
        for pq in pairQueries {
            let key = "\(pq.origin)->\(pq.destination)"
            if !coveredStationPairs.contains(key) && !fallbackPairs.contains(where: { $0.origin == pq.origin && $0.destination == pq.destination }) {
                fallbackPairs.append((pq.origin, pq.destination))
            }
        }

        // 3. Fallback ViaggiaTreno on-device per stazioni non coperte da LeFrecce (es. FerrovieNord / stazioni locali)
        if !fallbackPairs.isEmpty {
            let vtTrains = await discoverViaViaggiaTrenoFallback(
                pairs: fallbackPairs,
                allDestinations: cleanDests,
                band: band,
                marginBefore: extraMarginBefore,
                marginAfter: extraMarginAfter
            )
            discoveredTrains.append(contentsOf: vtTrains)
        }

        let finalTrains = Self.deduplicateAndSort(discoveredTrains, origins: cleanOrigins, band: band)
        if !Task.isCancelled {
            discoveryCache[cacheKey] = DiscoveryCacheEntry(timestamp: Date(), trains: finalTrains)
        }
        return finalTrains
    }

    func lookupTrainByNumber(
        _ query: String,
        preferredOrigins: [String],
        preferredDestinations: [String]
    ) async -> [CommuteHabitTrain] {
        let cleanNum = Self.extractCleanTrainNumber(from: query)
        let searchToken = cleanNum.isEmpty ? query.trimmingCharacters(in: .whitespacesAndNewlines) : cleanNum
        guard !searchToken.isEmpty else { return [] }

        var found: [CommuteHabitTrain] = []
        let encoded = searchToken.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? searchToken
        if let url = URL(string: "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/cercaNumeroTrenoTrenoAutocomplete/\(encoded)") {
            var req = URLRequest(url: url)
            req.timeoutInterval = 8.0
            if let (data, _) = try? await NetworkService.shared.get(request: req),
               let raw = String(data: data, encoding: .utf8) {
                let lines = raw.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                for line in lines.prefix(4) {
                    let parts = line.components(separatedBy: "|")
                    let headerPart = parts.first?.components(separatedBy: " - ") ?? []
                    let candidateNum = Self.extractCleanTrainNumber(from: headerPart.first ?? searchToken)
                    let numToUse = candidateNum.isEmpty ? searchToken : candidateNum
                    let rawOriginHint = headerPart.count > 1 ? headerPart.dropFirst().joined(separator: " - ") : ""

                    let stopsRes = await TrainRepository.shared.getLiveStops(
                        for: numToUse,
                        origin: rawOriginHint.isEmpty ? nil : rawOriginHint
                    )
                    if let built = buildHabitTrainFromStops(
                        trainNumber: numToUse,
                        categoryHint: headerPart.first ?? "",
                        stops: stopsRes.stops,
                        preferredOrigins: preferredOrigins,
                        preferredDestinations: preferredDestinations
                    ) {
                        if !found.contains(where: { $0.trainNumber == built.trainNumber && $0.departureTime == built.departureTime }) {
                            found.append(built)
                        }
                    }
                }
            }
        }

        if found.isEmpty && searchToken.count == 4 && searchToken.allSatisfy({ $0.isNumber }) {
            let italoRes = await ItaloTrackingProvider.shared.getLiveStops(for: searchToken)
            if italoRes.errorMessage == nil,
               let built = buildHabitTrainFromStops(
                    trainNumber: searchToken,
                    categoryHint: "Italo",
                    stops: italoRes.stops,
                    preferredOrigins: preferredOrigins,
                    preferredDestinations: preferredDestinations
               ) {
                found.append(built)
            }
        }

        return found
    }

    // MARK: - Private LeFrecce Helpers

    private func resolveLefrecceLocationIDs(for stationName: String) async -> [Int] {
        let key = StationNameMatcher.canonicalKey(stationName)
        if let cached = locationIDCache[key], !cached.isEmpty {
            return cached
        }
        if StationNameMatcher.isMilanoGaribaldi(stationName) {
            let ids = [830001645, 830001662]
            locationIDCache[key] = ids
            return ids
        }

        var queries = [stationName.trimmingCharacters(in: .whitespacesAndNewlines)]
        if !key.isEmpty && key.lowercased() != queries[0].lowercased() {
            queries.append(key.capitalized)
        }
        if stationName.contains("-") || stationName.contains("/") {
            let spaced = stationName
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "/", with: " ")
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            if !spaced.isEmpty && !queries.contains(spaced) {
                queries.append(spaced)
            }
        }
        if stationName.uppercased().contains("CADORNA") && !stationName.uppercased().contains("NORD") {
            queries.insert("Milano Nord Cadorna", at: 0)
        }

        for q in queries where !q.isEmpty {
            guard let safeQuery = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://www.lefrecce.it/Channels.Website.BFF.WEB/website/locations/search?name=\(safeQuery)") else {
                continue
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 7.0
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")

            if let (data, _) = try? await NetworkService.shared.get(request: request),
               let decoded = try? JSONDecoder().decode([TrenitaliaLocation].self, from: data),
               let matchedLoc = decoded.first(where: { StationNameMatcher.matchesLefrecceLocation($0, targetStationName: stationName) }) {
                let ids = [matchedLoc.id]
                locationIDCache[key] = ids
                return ids
            }
        }
        return []
    }

    private func fetchLefreccePairTrains(
        origin: String,
        destination: String,
        depID: Int,
        arrID: Int,
        depTimeISO: String,
        band: CommuteTimeBand,
        marginBefore: Int,
        marginAfter: Int,
        maxWindowRelEnd: Int
    ) async -> ([CommuteHabitTrain], Bool) {
        var collected: [CommuteHabitTrain] = []
        var hadValidResponse = false

        for offset in [0, 30] {
            guard !Task.isCancelled else { break }
            guard let url = URL(string: "https://www.lefrecce.it/Channels.Website.BFF.WEB/website/ticket/solutions") else {
                break
            }
            let payload: [String: Any] = [
                "departureLocationId": depID,
                "arrivalLocationId": arrID,
                "departureTime": depTimeISO,
                "adults": 1,
                "children": 0,
                "criteria": [
                    "frecceOnly": false,
                    "regionalOnly": false,
                    "noChanges": true,
                    "order": "DEPARTURE_DATE",
                    "offset": offset,
                    "limit": 30
                ],
                "advancedSearchRequest": [
                    "bestFare": false
                ]
            ]

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 9.0
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                let (data, response) = try await NetworkService.shared.post(request: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard statusCode == 200 else { break }

                let page = Self.parseLefrecceBandTrains(
                    from: data,
                    originStation: origin,
                    destinationStation: destination,
                    band: band,
                    marginBefore: marginBefore,
                    marginAfter: marginAfter
                )
                collected.append(contentsOf: page.trains)
                if page.totalSolutions > 0 {
                    hadValidResponse = true
                }

                // Se l'ultima partenza della pagina è ancora prima della fine della fascia e la pagina è corposa, carica la pagina successiva
                guard offset == 0,
                      page.totalSolutions >= 15,
                      let lastMin = page.lastDepartureMinutes else {
                    break
                }
                var relEnd = lastMin - band.startMinutes
                if relEnd < -720 { relEnd += 1440 }
                else if relEnd > 720 { relEnd -= 1440 }
                if relEnd >= maxWindowRelEnd {
                    break
                }
            } catch {
                break
            }
        }

        return (collected, hadValidResponse)
    }

    // MARK: - Private ViaggiaTreno Fallback Helpers

    private func loadBundledRFIStations() -> [DiscoveryRFIStation] {
        if let cached = rfiStationsCache {
            return cached
        }
        guard let url = Bundle.main.url(forResource: "rfi_stations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([DiscoveryRFIStation].self, from: data) else {
            return []
        }
        rfiStationsCache = decoded
        return decoded
    }

    private func resolveVTStationIDs(for stationName: String) async -> [String] {
        let key = StationNameMatcher.canonicalKey(stationName)
        if let cached = vtIDCache[key], !cached.isEmpty {
            return cached
        }
        if StationNameMatcher.isMilanoGaribaldi(stationName) {
            let ids = ["S01645", "S01647"]
            vtIDCache[key] = ids
            return ids
        }

        let stations = loadBundledRFIStations()
        if let exact = stations.first(where: {
            $0.name.localizedCaseInsensitiveCompare(stationName) == .orderedSame && !($0.vtID ?? "").isEmpty
        }), let vt = exact.vtID {
            vtIDCache[key] = [vt]
            return [vt]
        }
        if let matched = stations.first(where: {
            StationNameMatcher.isSameStation($0.name, stationName) && !($0.vtID ?? "").isEmpty
        }), let vt = matched.vtID {
            vtIDCache[key] = [vt]
            return [vt]
        }

        if let encoded = stationName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/autocompletaStazione/\(encoded)") {
            var req = URLRequest(url: url)
            req.timeoutInterval = 7.0
            if let (data, _) = try? await NetworkService.shared.get(request: req),
               let raw = String(data: data, encoding: .utf8) {
                let lines = raw.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                for line in lines {
                    let parts = line.components(separatedBy: "|")
                    if parts.count == 2 {
                        let stName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                        let code = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                        if !code.isEmpty && StationNameMatcher.isSameStation(stName, stationName) {
                            vtIDCache[key] = [code]
                            return [code]
                        }
                    }
                }
            }
        }

        return []
    }

    private func discoverViaViaggiaTrenoFallback(
        pairs: [(origin: String, destination: String)],
        allDestinations: [String],
        band: CommuteTimeBand,
        marginBefore: Int,
        marginAfter: Int
    ) async -> [CommuteHabitTrain] {
        let uniqueOrigins = Array(Set(pairs.map(\.origin)))
        let totalMinutes = band.durationMinutes + marginBefore + marginAfter
        let chunkOffsets: [Int] = {
            if totalMinutes <= 60 { return [0] }
            if totalMinutes <= 120 { return [0, 60] }
            return [0, 60, 120]
        }()

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        var baseComps = cal.dateComponents([.year, .month, .day], from: Date())
        baseComps.hour = band.startHour
        baseComps.minute = band.startMinute
        baseComps.second = 0
        let todayBandStart = cal.date(from: baseComps) ?? Date()
        let windowStartDate = todayBandStart.addingTimeInterval(TimeInterval(-marginBefore * 60))

        var discovered: [CommuteHabitTrain] = []

        for origin in uniqueOrigins {
            guard !Task.isCancelled else { break }
            let targetDestsForOrigin = pairs.filter { $0.origin == origin }.map(\.destination)
            let destsToCheck = targetDestsForOrigin.isEmpty ? allDestinations : targetDestsForOrigin
            let vtIDs = await resolveVTStationIDs(for: origin)
            guard !vtIDs.isEmpty else { continue }

            var boardTrains: [Train] = []
            var seenKeys: Set<String> = []
            for vtID in vtIDs {
                for offsetMin in chunkOffsets {
                    let queryDate = windowStartDate.addingTimeInterval(TimeInterval(offsetMin * 60))
                    let fetched = await StationRepository.shared.fetchVTDepartures(vtID: vtID, at: queryDate)
                    for tr in fetched {
                        guard band.contains(timeString: tr.time, marginBefore: marginBefore, marginAfter: marginAfter) else {
                            continue
                        }
                        let cleanNum = StationNameMatcher.cleanTrainDigits(tr.number)
                        let dedupeKey = "\(cleanNum)_\(tr.time)"
                        if seenKeys.insert(dedupeKey).inserted {
                            boardTrains.append(tr)
                        }
                    }
                }
            }

            var unmatched: [Train] = []
            for tr in boardTrains {
                let cleanNum = StationNameMatcher.cleanTrainDigits(tr.number)
                guard !cleanNum.isEmpty else { continue }
                if let directDest = destsToCheck.first(where: { StationNameMatcher.isSameStation(tr.destination, $0) }) {
                    let normCat = Self.normalizeTrainCategory(
                        acronym: tr.category,
                        category: tr.category,
                        denomination: "",
                        trainNumber: cleanNum,
                        destination: directDest
                    )
                    discovered.append(CommuteHabitTrain(
                        trainNumber: cleanNum,
                        category: normCat,
                        originStation: origin,
                        destinationStation: directDest,
                        departureTime: tr.time,
                        arrivalTime: nil,
                        isManuallyAdded: false
                    ))
                } else {
                    unmatched.append(tr)
                }
            }

            // Verifica fermate per i treni che proseguono oltre la destinazione (concorrenza limitata a 4, max 15 treni)
            let toVerify = Array(unmatched.prefix(15))
            var iterator = toVerify.makeIterator()
            await withTaskGroup(of: CommuteHabitTrain?.self) { group in
                func enqueue() {
                    guard let tr = iterator.next() else { return }
                    group.addTask {
                        let cleanNum = StationNameMatcher.cleanTrainDigits(tr.number)
                        let stopsRes = await TrainRepository.shared.getLiveStops(
                            for: cleanNum,
                            category: tr.category,
                            destination: tr.destination,
                            origin: origin,
                            scheduledTime: tr.time
                        )
                        guard let hit = StationNameMatcher.stopsContainOrderedRoute(
                            stops: stopsRes.stops,
                            originStationName: origin,
                            targetStations: destsToCheck
                        ) else {
                            return nil
                        }
                        let normCat = Self.normalizeTrainCategory(
                            acronym: tr.category,
                            category: tr.category,
                            denomination: "",
                            trainNumber: cleanNum,
                            destination: hit.targetStation
                        )
                        return CommuteHabitTrain(
                            trainNumber: cleanNum,
                            category: normCat,
                            originStation: origin,
                            destinationStation: hit.targetStation,
                            departureTime: tr.time,
                            arrivalTime: hit.arrivalTime,
                            isManuallyAdded: false
                        )
                    }
                }
                for _ in 0..<4 { enqueue() }
                for await item in group {
                    if let item { discovered.append(item) }
                    enqueue()
                }
            }
        }

        return discovered
    }

    private func buildHabitTrainFromStops(
        trainNumber: String,
        categoryHint: String,
        stops: [Stop],
        preferredOrigins: [String],
        preferredDestinations: [String]
    ) -> CommuteHabitTrain? {
        guard !stops.isEmpty else { return nil }

        let origStop = stops.first(where: { s in
            !s.isSuppressed && preferredOrigins.contains(where: { StationNameMatcher.isSameStation(s.stationName, $0) })
        }) ?? stops.first(where: { !$0.isSuppressed }) ?? stops.first!

        let origIdx = stops.firstIndex(where: { $0.id == origStop.id }) ?? 0
        let afterOrig = stops.dropFirst(origIdx + 1)

        let destStop = afterOrig.first(where: { s in
            !s.isSuppressed && preferredDestinations.contains(where: { StationNameMatcher.isSameStation(s.stationName, $0) })
        }) ?? afterOrig.last(where: { !$0.isSuppressed }) ?? stops.last ?? origStop

        let matchedOriginName = preferredOrigins.first(where: { StationNameMatcher.isSameStation(origStop.stationName, $0) })
            ?? origStop.stationName
        let matchedDestName = preferredDestinations.first(where: { StationNameMatcher.isSameStation(destStop.stationName, $0) })
            ?? destStop.stationName

        let depTime = origStop.time.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawArr = destStop.time.trimmingCharacters(in: .whitespacesAndNewlines)
        let arrTime = (rawArr.isEmpty || rawArr == "--:--" || destStop.id == origStop.id) ? nil : rawArr

        let normCat = Self.normalizeTrainCategory(
            acronym: categoryHint,
            category: categoryHint,
            denomination: "",
            trainNumber: trainNumber,
            destination: matchedDestName
        )

        return CommuteHabitTrain(
            trainNumber: trainNumber,
            category: normCat,
            originStation: matchedOriginName,
            destinationStation: matchedDestName,
            departureTime: depTime.isEmpty ? "--:--" : depTime,
            arrivalTime: arrTime,
            isManuallyAdded: true
        )
    }

    // MARK: - On-Device Multi-Station Commute Aggregator (Free & Offline Fallback)

    nonisolated static func extractAVCity(_ stationName: String) -> String? {
        let u = stationName.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let avCities = [
            "TORINO", "MILANO", "REGGIO EMILIA", "MEDIOPADANA", "BOLOGNA",
            "FIRENZE", "ROMA", "NAPOLI", "SALERNO", "VENEZIA",
            "PADOVA", "VERONA", "BRESCIA", "BARI"
        ]
        for city in avCities {
            if u == city || u.hasPrefix(city + " ") || u.contains(" " + city) {
                return city == "MEDIOPADANA" ? "REGGIO EMILIA" : city
            }
        }
        return nil
    }

    nonisolated static func isAVCommuteCorridor(origins: [String], destinations: [String]) -> Bool {
        let origCities = Set(origins.compactMap { extractAVCity($0) })
        let destCities = Set(destinations.compactMap { extractAVCity($0) })
        guard !origCities.isEmpty, !destCities.isEmpty else { return false }
        for oc in origCities {
            for dc in destCities where oc != dc {
                return true
            }
        }
        return false
    }

    nonisolated static func isAVOrLongDistanceTrain(category: String, trainNumber: String = "") -> Bool {
        let catU = category.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let hints = ["FRECCIA", "ITALO", "NTV", "EUROCITY", "EURONIGHT", "INTERCITY", "ALTA VELOCIT"]
        if hints.contains(where: { catU.contains($0) }) { return true }
        if ["FR", "FA", "FB", "AV", "IC", "ICN", "EC", "EN", "ITA"].contains(catU) { return true }
        let cleanN = extractCleanTrainNumber(from: trainNumber)
        if cleanN.count == 4 && cleanN.allSatisfy(\.isNumber) {
            let prefix = String(cleanN.prefix(2))
            if ["88", "89", "93", "94", "95", "96", "97", "98", "99"].contains(prefix) {
                return true
            }
        }
        return false
    }

    nonisolated static func canCatchTransfer(
        prevArrivalHHmm: String,
        nextDepartureHHmm: String,
        stationName: String
    ) -> Bool {
        guard let arrMin = CommuteTimeBand.parseHHmm(prevArrivalHHmm),
              let depMin = CommuteTimeBand.parseHHmm(nextDepartureHHmm) else {
            return true
        }
        var adjustedDep = depMin
        if adjustedDep < arrMin - 720 {
            adjustedDep += 1440
        }
        let u = stationName.uppercased()
        let buffer: Int
        if u.contains("CENTRALE") {
            buffer = 5
        } else if u.contains("GARIBALDI") {
            buffer = 4
        } else {
            buffer = 3
        }
        return (adjustedDep - (arrMin + buffer)) >= 0
    }

    nonisolated static func parseLefrecceMultiStationSolutions(
        from data: Data,
        fallbackOrigin: String,
        fallbackDest: String,
        allowAV: Bool
    ) -> [PlanBAlternativeItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let solutions = json["solutions"] as? [[String: Any]] else {
            return []
        }

        var items: [PlanBAlternativeItem] = []

        for entry in solutions {
            guard let sol = entry["solution"] as? [String: Any],
                  let nodes = sol["nodes"] as? [[String: Any]],
                  !nodes.isEmpty,
                  nodes.count <= 2 else {
                continue
            }

            var builtLegs: [PlanBLegItem] = []
            var rejectSolution = false

            for node in nodes {
                let tr = (node["train"] as? [String: Any]) ?? [:]
                let acronym = (tr["acronym"] as? String) ?? ""
                let rawCat = (tr["trainCategory"] as? String) ?? ""
                let denom = (tr["denomination"] as? String) ?? ""
                let catLow = rawCat.lowercased()
                let denomLow = denom.lowercased()
                let isUrbanFlag = (tr["urban"] as? Bool) ?? false

                let isUrban = isUrbanFlag || acronym.uppercased() == "UB" ||
                    ((catLow.contains("urban") || denomLow.contains("urban") || catLow.contains("metro")) && !catLow.contains("suburbano"))
                let isWalk = acronym.uppercased() == "WK" || catLow.contains("walk") || denomLow.contains("piedi")

                let orig = ((node["origin"] as? String) ?? fallbackOrigin).trimmingCharacters(in: .whitespacesAndNewlines)
                let dest = ((node["destination"] as? String) ?? fallbackDest).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !orig.isEmpty, !dest.isEmpty else {
                    rejectSolution = true
                    break
                }

                // Escludi falsi cambi nello stesso complesso di stazione (es. Garibaldi Superficie <-> Passante)
                if planBStationMatch(orig, dest) {
                    continue
                }

                let depHHmm = extractHHmm(from: node["departureTime"] as? String) ?? "--:--"
                let arrHHmm = extractHHmm(from: node["arrivalTime"] as? String) ?? "--:--"

                if !builtLegs.isEmpty {
                    let prevLeg = builtLegs[builtLegs.count - 1]
                    if !canCatchTransfer(prevArrivalHHmm: prevLeg.arrival_time, nextDepartureHHmm: depHHmm, stationName: orig) {
                        rejectSolution = true
                        break
                    }
                }

                if isWalk {
                    builtLegs.append(PlanBLegItem(
                        train_number: "A piedi",
                        category: "Interscambio a piedi",
                        origin: orig,
                        destination: dest,
                        departure_time: depHHmm,
                        arrival_time: arrHHmm,
                        delay: 0,
                        platform: "--",
                        is_urban: false,
                        is_station_walk: true,
                        travel_minutes: 3,
                        urban_headsign: nil
                    ))
                } else if isUrban {
                    builtLegs.append(PlanBLegItem(
                        train_number: "(Metro / Mezzi)",
                        category: "Trasporto Urbano",
                        origin: orig,
                        destination: dest,
                        departure_time: depHHmm,
                        arrival_time: arrHHmm,
                        delay: 0,
                        platform: "--",
                        is_urban: true,
                        is_station_walk: false,
                        travel_minutes: 15,
                        urban_headsign: nil
                    ))
                } else {
                    let rawName = (tr["name"] as? String) ?? (tr["description"] as? String) ?? ""
                    let cleanNum = extractCleanTrainNumber(from: rawName)
                    guard !cleanNum.isEmpty else {
                        rejectSolution = true
                        break
                    }
                    let normCat = normalizeTrainCategory(
                        acronym: acronym,
                        category: rawCat,
                        denomination: denom,
                        trainNumber: cleanNum,
                        destination: dest
                    )
                    if !allowAV && isAVOrLongDistanceTrain(category: normCat, trainNumber: cleanNum) {
                        rejectSolution = true
                        break
                    }
                    builtLegs.append(PlanBLegItem(
                        train_number: cleanNum,
                        category: normCat,
                        origin: orig,
                        destination: dest,
                        departure_time: depHHmm,
                        arrival_time: arrHHmm,
                        delay: 0,
                        platform: "--",
                        is_urban: false,
                        is_station_walk: false,
                        travel_minutes: nil,
                        urban_headsign: nil
                    ))
                }
            }

            guard !rejectSolution, !builtLegs.isEmpty else { continue }
            guard let firstRail = builtLegs.first(where: { $0.isRailTrain }) else { continue }

            let firstLeg = builtLegs[0]
            let lastLeg = builtLegs[builtLegs.count - 1]
            let dur = TrainManager.calculateDurationBetween(dep: firstLeg.departure_time, arr: lastLeg.arrival_time) ?? ""
            let transferInfo: String = {
                if builtLegs.count == 1 {
                    return dur.isEmpty ? "Treno diretto" : "Treno diretto (\(dur))"
                }
                let cambioStations = builtLegs.dropFirst().map { $0.origin.compactStationName }.joined(separator: ", ")
                let count = builtLegs.count - 1
                let label = "\(count) camb\(count == 1 ? "io" : "i") (\(cambioStations))"
                return dur.isEmpty ? label : "\(label) • \(dur)"
            }()

            items.append(PlanBAlternativeItem(
                train_number: firstRail.train_number,
                category: firstRail.category,
                destination: lastLeg.destination,
                station: firstLeg.origin,
                departure_time: firstLeg.departure_time,
                arrival_time: lastLeg.arrival_time,
                duration: dur,
                delay: 0,
                platform: "--",
                transfer_info: transferInfo,
                legs: builtLegs
            ))
        }

        return items
    }

    nonisolated static func deduplicateAndRankAlternatives(
        _ rawCandidates: [PlanBAlternativeItem],
        configuredOrigins: [String],
        configuredDestinations: [String],
        maxResults: Int = 10
    ) -> [PlanBAlternativeItem] {
        struct RankedEntry {
            var item: PlanBAlternativeItem
            var reachedDestinations: [String]
        }

        var map: [String: RankedEntry] = [:]

        func canonicalOrigin(for rawStation: String) -> String {
            configuredOrigins.first(where: { planBStationMatch($0, rawStation) }) ?? rawStation
        }

        func minValue(_ hhmm: String?) -> Int {
            guard let hhmm, let m = CommuteTimeBand.parseHHmm(hhmm) else { return Int.max }
            return m
        }

        for candidate in rawCandidates {
            var c = candidate
            let canonOrigin = canonicalOrigin(for: c.station)
            let isDirect = c.resolvedLegs.count <= 1
            let key = "\(c.train_number)_\(c.departure_time)_\(canonOrigin.lowercased())"

            if var updatedLegs = c.legs, !updatedLegs.isEmpty {
                updatedLegs[0] = PlanBLegItem(
                    train_number: updatedLegs[0].train_number,
                    category: updatedLegs[0].category,
                    origin: canonOrigin,
                    destination: updatedLegs[0].destination,
                    departure_time: updatedLegs[0].departure_time,
                    arrival_time: updatedLegs[0].arrival_time,
                    delay: updatedLegs[0].delay,
                    platform: updatedLegs[0].platform,
                    is_urban: updatedLegs[0].is_urban,
                    is_station_walk: updatedLegs[0].is_station_walk,
                    travel_minutes: updatedLegs[0].travel_minutes,
                    urban_headsign: updatedLegs[0].urban_headsign
                )
                c.legs = updatedLegs
            }
            let normalizedCand = PlanBAlternativeItem(
                train_number: c.train_number,
                category: c.category,
                destination: c.destination,
                station: canonOrigin,
                departure_time: c.departure_time,
                arrival_time: c.arrival_time,
                duration: c.duration,
                delay: c.delay,
                platform: c.platform,
                transfer_info: c.transfer_info,
                legs: c.legs
            )

            guard var existing = map[key] else {
                map[key] = RankedEntry(
                    item: normalizedCand,
                    reachedDestinations: [normalizedCand.destination.compactStationName]
                )
                continue
            }

            let existingIsDirect = existing.item.resolvedLegs.count <= 1
            if isDirect && !existingIsDirect {
                existing.item = normalizedCand
                existing.reachedDestinations = [normalizedCand.destination.compactStationName]
                map[key] = existing
                continue
            }
            if !isDirect && existingIsDirect {
                continue
            }

            // Entrambe dirette (o pari numero cambi) sullo stesso treno: unisci le destinazioni raggiunte
            if isDirect && existingIsDirect {
                let destName = normalizedCand.destination.compactStationName
                if !existing.reachedDestinations.contains(where: { planBStationMatch($0, destName) }) {
                    existing.reachedDestinations.append(destName)
                }
                if minValue(normalizedCand.arrival_time) < minValue(existing.item.arrival_time) {
                    existing.item = normalizedCand
                }
                map[key] = existing
            } else if c.resolvedLegs.count < existing.item.resolvedLegs.count {
                existing.item = normalizedCand
                existing.reachedDestinations = [normalizedCand.destination.compactStationName]
                map[key] = existing
            }
        }

        // Arricchisci transfer_info quando lo stesso treno diretto ferma in più stazioni di arrivo configurate
        let mergedList: [PlanBAlternativeItem] = map.values.map { entry in
            var item = entry.item
            if item.resolvedLegs.count <= 1 && entry.reachedDestinations.count > 1 {
                let primaryName = item.destination.compactStationName
                let extraStops = entry.reachedDestinations.filter { !planBStationMatch($0, primaryName) }
                if !extraStops.isEmpty {
                    let durSuffix = (item.duration ?? "").isEmpty ? "" : " (\(item.duration ?? ""))"
                    item = PlanBAlternativeItem(
                        train_number: item.train_number,
                        category: item.category,
                        destination: item.destination,
                        station: item.station,
                        departure_time: item.departure_time,
                        arrival_time: item.arrival_time,
                        duration: item.duration,
                        delay: item.delay,
                        platform: item.platform,
                        transfer_info: "Treno diretto\(durSuffix) · ferma anche a \(extraStops.joined(separator: ", "))",
                        legs: item.legs
                    )
                }
            }
            return item
        }

        let sortedAll = mergedList.sorted { a, b in
            let depA = (CommuteTimeBand.parseHHmm(a.departure_time) ?? 0) + max(0, a.delay)
            let depB = (CommuteTimeBand.parseHHmm(b.departure_time) ?? 0) + max(0, b.delay)
            if depA != depB { return depA < depB }
            return minValue(a.arrival_time) < minValue(b.arrival_time)
        }

        // Garantisci almeno 1 migliore opzione per ciascuna stazione di partenza, poi riempi cronologicamente
        var selected: [PlanBAlternativeItem] = []
        for orig in configuredOrigins {
            if selected.count >= maxResults { break }
            let group = sortedAll.filter { planBStationMatch($0.station, orig) }
            if let best = group.first(where: { $0.resolvedLegs.count <= 1 }) ?? group.first {
                if !selected.contains(where: { $0.id == best.id }) {
                    selected.append(best)
                }
            }
        }
        for item in sortedAll {
            if selected.count >= maxResults { break }
            if !selected.contains(where: { $0.id == item.id }) {
                selected.append(item)
            }
        }

        return selected.sorted { a, b in
            let depA = (CommuteTimeBand.parseHHmm(a.departure_time) ?? 0) + max(0, a.delay)
            let depB = (CommuteTimeBand.parseHHmm(b.departure_time) ?? 0) + max(0, b.delay)
            if depA != depB { return depA < depB }
            return minValue(a.arrival_time) < minValue(b.arrival_time)
        }
    }

    func calculateLocalCommutePlan(
        origins startStations: [String],
        destinations endStations: [String],
        departureDate: Date = Date(),
        isReturn: Bool,
        userLat: Double? = nil,
        userLon: Double? = nil,
        forceRefresh: Bool = false
    ) async -> PlanBReportDTO {
        var cleanOrigins = startStations.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let cleanDests = endStations.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let targetTimeStr = SharedFormatters.time.string(from: departureDate)
        let titleStr = isReturn ? "Lavoro → Casa" : "Casa → Lavoro"

        guard !cleanOrigins.isEmpty, !cleanDests.isEmpty else {
            return PlanBReportDTO(
                title: titleStr,
                body: "Configura almeno una stazione di Casa e una di Lavoro.",
                incident_type: "simulation",
                incident_detail: nil,
                cancelled_train: nil,
                target_time: targetTimeStr,
                origins: cleanOrigins,
                destinations: cleanDests,
                alternatives: [],
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        }

        // Ordina le stazioni di partenza per distanza GPS se disponibile
        if let lat = userLat, let lon = userLon, cleanOrigins.count > 1 {
            let userLoc = CLLocation(latitude: lat, longitude: lon)
            let geoStations = await MainActor.run { RFIStationCatalog.shared.geoStations }
            func dist(for name: String) -> Double {
                if let match = geoStations.first(where: { planBStationMatch($0.name, name) }),
                   let sLat = match.lat,
                   let sLon = match.lon {
                    return userLoc.distance(from: CLLocation(latitude: sLat, longitude: sLon))
                }
                return Double.greatestFiniteMagnitude
            }
            cleanOrigins.sort { dist(for: $0) < dist(for: $1) }
        }

        let dayKey = SupporterCommuteManager.romeDayKey(for: departureDate)
        let cacheKey = "\(dayKey)|\(cleanOrigins.sorted().joined(separator: ","))->\(cleanDests.sorted().joined(separator: ","))"
        let isNearNow = abs(departureDate.timeIntervalSinceNow) < 15 * 60

        if !forceRefresh,
           let cached = localPlanCache[cacheKey],
           Date().timeIntervalSince(cached.fetchedAt) < localPlanCacheTTL,
           abs(cached.requestedDate.timeIntervalSince(departureDate)) <= 20 * 60 {
            if isNearNow {
                let upcoming = SupporterCommuteManager.upcomingAlternatives(in: cached.report, at: Date())
                if upcoming.count >= 2 {
                    return PlanBReportDTO(
                        title: cached.report.title,
                        body: cached.report.body,
                        incident_type: cached.report.incident_type,
                        incident_detail: cached.report.incident_detail,
                        cancelled_train: cached.report.cancelled_train,
                        target_time: targetTimeStr,
                        origins: cleanOrigins,
                        destinations: cleanDests,
                        alternatives: upcoming,
                        timestamp: cached.report.timestamp
                    )
                }
            } else {
                return cached.report
            }
        }

        let uniqueStations = Array(Set(cleanOrigins + cleanDests))
        var locMap: [String: [Int]] = [:]
        await withTaskGroup(of: (String, [Int]).self) { group in
            for st in uniqueStations {
                group.addTask {
                    let ids = await self.resolveLefrecceLocationIDs(for: st)
                    return (st, ids)
                }
            }
            for await (st, ids) in group {
                locMap[st] = ids
            }
        }

        let searchAnchorDate = isNearNow ? Date().addingTimeInterval(-5 * 60) : departureDate
        let isoFmt = DateFormatter()
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        isoFmt.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        isoFmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.000ZZZZZ"
        let depTimeISO = isoFmt.string(from: searchAnchorDate)
        let allowAV = Self.isAVCommuteCorridor(origins: cleanOrigins, destinations: cleanDests)

        struct PairSpec: Sendable {
            let orig: String
            let dest: String
            let depID: Int
            let arrID: Int
        }

        var pairs: [PairSpec] = []
        var seenPairs: Set<String> = []
        for orig in cleanOrigins {
            let depIDs = locMap[orig] ?? []
            for dest in cleanDests {
                guard !planBStationMatch(orig, dest) else { continue }
                let arrIDs = locMap[dest] ?? []
                for dID in depIDs {
                    for aID in arrIDs where dID != aID {
                        let pk = "\(dID)->\(aID)"
                        if seenPairs.insert(pk).inserted {
                            pairs.append(PairSpec(orig: orig, dest: dest, depID: dID, arrID: aID))
                        }
                    }
                }
            }
        }

        var rawCandidates: [PlanBAlternativeItem] = []
        var pairIter = pairs.makeIterator()
        await withTaskGroup(of: [PlanBAlternativeItem].self) { group in
            func enqueue() {
                guard let pair = pairIter.next() else { return }
                group.addTask {
                    await self.fetchLefrecceMultiStationPair(
                        orig: pair.orig,
                        dest: pair.dest,
                        depID: pair.depID,
                        arrID: pair.arrID,
                        depTimeISO: depTimeISO,
                        allowAV: allowAV
                    )
                }
            }
            for _ in 0..<4 { enqueue() }
            for await found in group {
                rawCandidates.append(contentsOf: found)
                enqueue()
            }
        }

        var ranked = Self.deduplicateAndRankAlternatives(
            rawCandidates,
            configuredOrigins: cleanOrigins,
            configuredDestinations: cleanDests,
            maxResults: 12
        )

        // Arricchimento live (ritardi, binari, soppressioni) solo per partenze odierne vicine all'orario corrente
        let timeDeltaFromNow = departureDate.timeIntervalSinceNow
        if timeDeltaFromNow >= -1800 && timeDeltaFromNow <= 10800 && !ranked.isEmpty {
            let uniqueNums = Array(Set(ranked.prefix(10).map(\.train_number))).filter { $0.allSatisfy(\.isNumber) }
            var stopsMap: [String: StopsResult] = [:]
            var numIter = uniqueNums.makeIterator()
            await withTaskGroup(of: (String, StopsResult).self) { group in
                func enqueue() {
                    guard let num = numIter.next() else { return }
                    group.addTask {
                        let res = await TrainRepository.shared.getLiveStops(for: num)
                        return (num, res)
                    }
                }
                for _ in 0..<4 { enqueue() }
                for await (num, res) in group {
                    stopsMap[num] = res
                    enqueue()
                }
            }

            ranked = ranked.compactMap { alt -> PlanBAlternativeItem? in
                guard let stopsRes = stopsMap[alt.train_number], stopsRes.errorMessage == nil else {
                    return alt
                }
                if stopsRes.status.isArrived && isNearNow {
                    return nil
                }
                let matchedOriginStop = stopsRes.stops.first(where: { planBStationMatch($0.stationName, alt.station) })
                if let origStop = matchedOriginStop {
                    if origStop.isSuppressed { return nil }
                    if isNearNow && (origStop.actualTime != nil && !(origStop.actualTime ?? "").isEmpty) && (origStop.actualTime ?? "") != "--" {
                        return nil
                    }
                }
                let liveDelay = matchedOriginStop?.delay ?? stopsRes.stops.compactMap(\.delay).last ?? alt.delay
                let livePlatform: String = {
                    let act = matchedOriginStop?.actualPlatform?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !act.isEmpty && act != "--" { return act }
                    let plan = matchedOriginStop?.plannedPlatform?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return (!plan.isEmpty && plan != "--") ? plan : alt.platform
                }()

                let updatedLegs = alt.resolvedLegs.enumerated().map { idx, leg -> PlanBLegItem in
                    guard idx == 0 && leg.isRailTrain else { return leg }
                    return PlanBLegItem(
                        train_number: leg.train_number,
                        category: leg.category,
                        origin: leg.origin,
                        destination: leg.destination,
                        departure_time: leg.departure_time,
                        arrival_time: leg.arrival_time,
                        delay: liveDelay,
                        platform: livePlatform,
                        is_urban: leg.is_urban,
                        is_station_walk: leg.is_station_walk,
                        travel_minutes: leg.travel_minutes,
                        urban_headsign: leg.urban_headsign
                    )
                }

                if updatedLegs.count >= 2 && liveDelay > 0 {
                    if let arrMin = CommuteTimeBand.parseHHmm(updatedLegs[0].arrival_time) {
                        let delayedArrMin = (arrMin + liveDelay) % 1440
                        let delayedArrStr = String(format: "%02d:%02d", delayedArrMin / 60, delayedArrMin % 60)
                        if !Self.canCatchTransfer(prevArrivalHHmm: delayedArrStr, nextDepartureHHmm: updatedLegs[1].departure_time, stationName: updatedLegs[1].origin) {
                            return nil
                        }
                    }
                }

                return PlanBAlternativeItem(
                    train_number: alt.train_number,
                    category: alt.category,
                    destination: alt.destination,
                    station: alt.station,
                    departure_time: alt.departure_time,
                    arrival_time: alt.arrival_time,
                    duration: alt.duration,
                    delay: liveDelay,
                    platform: livePlatform,
                    transfer_info: alt.transfer_info,
                    legs: updatedLegs
                )
            }
        }

        // Fallback ViaggiaTreno se LeFrecce non ha restituito soluzioni
        if ranked.isEmpty {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
            let startMins = CommuteTimeBand.minutes(from: searchAnchorDate, calendar: cal)
            let band = CommuteTimeBand(startMinutes: startMins, endMinutes: (startMins + 90) % 1440)
            let fallbackPairs = cleanOrigins.flatMap { orig in
                cleanDests.filter { !planBStationMatch(orig, $0) }.map { (origin: orig, destination: $0) }
            }
            let vtTrains = await discoverViaViaggiaTrenoFallback(
                pairs: fallbackPairs,
                allDestinations: cleanDests,
                band: band,
                marginBefore: 5,
                marginAfter: 15
            )
            let vtCandidates = vtTrains.map { tr -> PlanBAlternativeItem in
                let arrStr = tr.arrivalTime ?? "--:--"
                let dur = TrainManager.calculateDurationBetween(dep: tr.departureTime, arr: arrStr) ?? ""
                let leg = PlanBLegItem(
                    train_number: tr.trainNumber,
                    category: tr.category,
                    origin: tr.originStation,
                    destination: tr.destinationStation,
                    departure_time: tr.departureTime,
                    arrival_time: arrStr,
                    delay: 0,
                    platform: "--",
                    is_urban: false,
                    is_station_walk: false,
                    travel_minutes: nil,
                    urban_headsign: nil
                )
                return PlanBAlternativeItem(
                    train_number: tr.trainNumber,
                    category: tr.category,
                    destination: tr.destinationStation,
                    station: tr.originStation,
                    departure_time: tr.departureTime,
                    arrival_time: arrStr,
                    duration: dur,
                    delay: 0,
                    platform: "--",
                    transfer_info: dur.isEmpty ? "Treno diretto" : "Treno diretto (\(dur))",
                    legs: [leg]
                )
            }
            ranked = Self.deduplicateAndRankAlternatives(
                vtCandidates,
                configuredOrigins: cleanOrigins,
                configuredDestinations: cleanDests,
                maxResults: 10
            )
        }

        let finalAlts = Array(ranked.prefix(10))
        let report = PlanBReportDTO(
            title: titleStr,
            body: "\(formatCityOrStationSummary(cleanOrigins)) → \(formatCityOrStationSummary(cleanDests))",
            incident_type: "simulation",
            incident_detail: nil,
            cancelled_train: nil,
            target_time: targetTimeStr,
            origins: cleanOrigins,
            destinations: cleanDests,
            alternatives: finalAlts,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        if !finalAlts.isEmpty {
            localPlanCache[cacheKey] = LocalPlanCacheEntry(
                fetchedAt: Date(),
                requestedDate: departureDate,
                report: report
            )
        }
        return report
    }

    private func fetchLefrecceMultiStationPair(
        orig: String,
        dest: String,
        depID: Int,
        arrID: Int,
        depTimeISO: String,
        allowAV: Bool
    ) async -> [PlanBAlternativeItem] {
        guard let url = URL(string: "https://www.lefrecce.it/Channels.Website.BFF.WEB/website/ticket/solutions") else {
            return []
        }
        let payload: [String: Any] = [
            "departureLocationId": depID,
            "arrivalLocationId": arrID,
            "departureTime": depTimeISO,
            "adults": 1,
            "children": 0,
            "criteria": [
                "frecceOnly": false,
                "regionalOnly": false,
                "noChanges": false,
                "order": "DEPARTURE_DATE",
                "offset": 0,
                "limit": 25
            ],
            "advancedSearchRequest": [
                "bestFare": false
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 9.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await NetworkService.shared.post(request: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            return Self.parseLefrecceMultiStationSolutions(
                from: data,
                fallbackOrigin: orig,
                fallbackDest: dest,
                allowAV: allowAV
            )
        } catch {
            return []
        }
    }
}
