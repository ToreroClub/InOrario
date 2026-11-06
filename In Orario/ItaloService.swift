import Foundation

/// Provider dedicato e autonomo per il recupero in tempo reale delle fermate, degli orari e dei ritardi dei treni Italo (NTV).
/// Completamente indipendente e disaccoppiato da ViaggiaTreno e Trenitalia.
actor ItaloTrackingProvider {
    static let shared = ItaloTrackingProvider()
    
    private struct CacheEntry {
        let result: StopsResult
        let timestamp: Date
    }
    
    private var cache: [String: CacheEntry] = [:]
    private var inFlightTasks: [String: Task<StopsResult, Never>] = [:]
    private let cacheTTL: TimeInterval = 45.0
    
    private init() {}
    
    func clearCache() {
        cache.removeAll()
    }
    
    /// Recupera lo stato e l'elenco delle fermate di un treno Italo tramite il suo numero commerciale.
    func getLiveStops(for trainNumber: String, force: Bool = false) async -> StopsResult {
        let cleanNumber = trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNumber.isEmpty else {
            return StopsResult(stops: [], status: TrainStatus(), errorMessage: "Numero treno non valido.")
        }
        
        let key = cleanNumber
        
        if !force {
            if let entry = cache[key], Date().timeIntervalSince(entry.timestamp) < cacheTTL {
                AppLogger.cache("ItaloTrackingProvider: Cache hit per treno Italo \(cleanNumber)")
                return entry.result
            }
            if let inFlight = inFlightTasks[key] {
                AppLogger.duplicateAvoided(key: "ItaloTrackingProvider:\(cleanNumber)")
                return await inFlight.value
            }
        }
        
        let task = Task<StopsResult, Never> {
            await self.fetchLiveStopsUncached(cleanNumber: cleanNumber)
        }
        
        inFlightTasks[key] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: key)
        
        if result.errorMessage == nil && !result.stops.isEmpty {
            cache[key] = CacheEntry(result: result, timestamp: Date())
        }
        
        return result
    }
    
    private func fetchLiveStopsUncached(cleanNumber: String) async -> StopsResult {
        // Canale Primario: API ufficiale Italo in Viaggio (italotreno.com)
        if let primaryResult = await fetchFromItaloOfficialAPI(cleanNumber: cleanNumber) {
            return primaryResult
        }
        
        // Canale Secondario: Feed GTFS-RT TripUpdates
        if let fallbackResult = await fetchFromGTFSRT(cleanNumber: cleanNumber) {
            return fallbackResult
        }
        
        return StopsResult(
            stops: [],
            status: TrainStatus(),
            errorMessage: "Treno Italo \(cleanNumber) non trovato o non ancora nel sistema."
        )
    }
    
    // MARK: - 1. API Ufficiale Italo in Viaggio
    
    private func fetchFromItaloOfficialAPI(cleanNumber: String) async -> StopsResult? {
        let endpoints = [
            "https://italoinviaggio.italotreno.com/api/RicercaTrenoService?TrainNumber=\(cleanNumber)",
            "https://italoinviaggio.italotreno.it/api/RicercaTrenoService?TrainNumber=\(cleanNumber)"
        ]
        
        for urlString in endpoints {
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10.0
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
            request.setValue("it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
            request.setValue("https://italoinviaggio.italotreno.com/", forHTTPHeaderField: "Referer")
            
            do {
                let (data, response) = try await NetworkService.shared.get(request: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, !data.isEmpty else {
                    continue
                }
                
                if let parsed = parseItaloSchedulePayload(data: data, trainNumber: cleanNumber) {
                    return parsed
                }
            } catch {
                AppLogger.decodingError(context: "ItaloOfficialAPI:\(cleanNumber)", error: error)
                continue
            }
        }
        return nil
    }
    
    private func parseItaloSchedulePayload(data: Data, trainNumber: String) -> StopsResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        if (json["IsEmpty"] as? Bool) == true {
            return StopsResult(
                stops: [],
                status: TrainStatus(),
                errorMessage: "Treno Italo \(trainNumber) non in circolazione per la data odierna."
            )
        }
        
        guard let schedule = json["TrainSchedule"] as? [String: Any] else {
            return nil
        }
        
        let stazPartenza = schedule["StazionePartenza"] as? [String: Any]
        let stazioniFerme = (schedule["StazioniFerme"] as? [[String: Any]]) ?? []
        let stazioniNonFerme = (schedule["StazioniNonFerme"] as? [[String: Any]]) ?? []
        
        guard stazPartenza != nil || !stazioniFerme.isEmpty || !stazioniNonFerme.isEmpty else {
            return nil
        }
        
        let disruption = schedule["Distruption"] as? [String: Any]
        let globalDelay = (disruption?["DelayAmount"] as? Int) ?? 0
        let runningState = (disruption?["RunningState"] as? Int) ?? 0
        
        let actualDeparture = (stazPartenza?["ActualDepartureTime"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isDeparted = !stazioniFerme.isEmpty || (!actualDeparture.isEmpty && actualDeparture != "01:00")
        let isArrived = stazioniNonFerme.isEmpty && !stazioniFerme.isEmpty
        
        var status = TrainStatus()
        status.isDeparted = isDeparted
        status.isArrived = isArrived
        
        if runningState == 3 {
            status.cancellationNote = "TRENO ITALO SOPPRESSO"
            status.statusMessage = "Soppresso"
        } else if globalDelay > 0 {
            status.statusMessage = "ritardo \(globalDelay) min."
        } else if isArrived {
            status.statusMessage = "Arrivato a destinazione"
        } else if isDeparted {
            status.statusMessage = "in orario"
        } else {
            status.statusMessage = "Non ancora partito"
        }
        
        if !stazioniFerme.isEmpty {
            let lastF = stazioniFerme.last
            let lastLoc = (lastF?["LocationDescription"] as? String) ?? "--"
            let lastT = (lastF?["ActualDepartureTime"] as? String) ?? (lastF?["ActualArrivalTime"] as? String) ?? (json["LastUpdate"] as? String) ?? "--:--"
            status.lastStation = Train.cleanStationName(lastLoc).formattedStationName
            status.lastTime = Self.cleanTime(lastT)
        } else if isDeparted, let part = stazPartenza {
            let partLoc = (part["LocationDescription"] as? String) ?? "--"
            status.lastStation = Train.cleanStationName(partLoc).formattedStationName
            status.lastTime = Self.cleanTime(actualDeparture)
        } else {
            status.lastStation = "--"
            status.lastTime = "--:--"
        }
        
        var mappedStops: [Stop] = []
        
        // 1. Fermata di partenza
        if let part = stazPartenza {
            let name = Train.cleanStationName((part["LocationDescription"] as? String) ?? "Origine").formattedStationName
            let prog = Self.cleanTime((part["EstimatedDepartureTime"] as? String) ?? (part["EstimatedArrivalTime"] as? String))
            let act = Self.cleanTime(part["ActualDepartureTime"] as? String)
            let plat = Self.cleanPlatform(part["ActualArrivalPlatform"] as? String)
            
            let depDelay = (act != "--:--" && prog != "--:--") ? Self.calculateDiffMinutes(scheduled: prog, actual: act) : (isDeparted ? globalDelay : 0)
            
            mappedStops.append(Stop(
                stationName: name,
                time: prog,
                actualTime: isDeparted ? act : nil,
                delay: max(0, depDelay),
                estimatedTime: nil,
                plannedPlatform: plat,
                actualPlatform: plat
            ))
        }
        
        // 2. Fermate già effettuate
        for s in stazioniFerme {
            let name = Train.cleanStationName((s["LocationDescription"] as? String) ?? "Stazione").formattedStationName
            let prog = Self.cleanTime((s["EstimatedArrivalTime"] as? String) ?? (s["EstimatedDepartureTime"] as? String))
            let act = Self.cleanTime((s["ActualArrivalTime"] as? String) ?? (s["ActualDepartureTime"] as? String))
            let plat = Self.cleanPlatform(s["ActualArrivalPlatform"] as? String)
            
            let stopDelay = (act != "--:--" && prog != "--:--") ? Self.calculateDiffMinutes(scheduled: prog, actual: act) : globalDelay
            
            mappedStops.append(Stop(
                stationName: name,
                time: prog,
                actualTime: act,
                delay: max(0, stopDelay),
                estimatedTime: nil,
                plannedPlatform: plat,
                actualPlatform: plat
            ))
        }
        
        // 3. Fermate non ancora effettuate
        for s in stazioniNonFerme {
            let name = Train.cleanStationName((s["LocationDescription"] as? String) ?? "Stazione").formattedStationName
            let prog = Self.cleanTime((s["EstimatedArrivalTime"] as? String) ?? (s["EstimatedDepartureTime"] as? String))
            let rawEta = Self.cleanTime(s["ActualArrivalTime"] as? String)
            let plat = Self.cleanPlatform(s["ActualArrivalPlatform"] as? String)
            
            var estT: String? = nil
            if rawEta != "--:--" && rawEta != prog && globalDelay > 0 {
                estT = rawEta
            } else if globalDelay >= 3, prog != "--:--" {
                estT = Self.addMinutes(to: prog, minutes: globalDelay)
            }
            
            mappedStops.append(Stop(
                stationName: name,
                time: prog,
                actualTime: nil,
                delay: globalDelay,
                estimatedTime: estT,
                plannedPlatform: plat,
                actualPlatform: plat
            ))
        }
        
        guard !mappedStops.isEmpty else { return nil }
        return StopsResult(stops: mappedStops, status: status, errorMessage: nil)
    }
    
    // MARK: - 2. Feed GTFS-RT TripUpdates (Fallback)
    
    private func fetchFromGTFSRT(cleanNumber: String) async -> StopsResult? {
        guard let url = URL(string: "https://proxy.busone.app/italo/gtfs-rt/trip-updates.json") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0
        request.setValue("InOrario-iOS", forHTTPHeaderField: "X-BusOne-Client")
        request.setValue("transit-info", forHTTPHeaderField: "X-BusOne-Use")
        request.setValue("InOrario/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await NetworkService.shared.get(request: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, !data.isEmpty else {
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entities = json["entity"] as? [[String: Any]] else {
                return nil
            }
            
            let targetEntity = entities.first { entity in
                let tu = entity["trip_update"] as? [String: Any]
                let v = tu?["vehicle"] as? [String: Any]
                let vid = (v?["id"] as? String) ?? ""
                let vlabel = (v?["label"] as? String) ?? ""
                let trip = tu?["trip"] as? [String: Any]
                let tid = (trip?["trip_id"] as? String) ?? ""
                
                return vid == "italo-\(cleanNumber)" ||
                       vlabel.contains(cleanNumber) ||
                       tid.contains("-\(cleanNumber)-") ||
                       tid.hasSuffix("-\(cleanNumber)")
            }
            
            guard let matched = targetEntity,
                  let tripUpdate = matched["trip_update"] as? [String: Any],
                  let stopUpdates = tripUpdate["stop_time_update"] as? [[String: Any]],
                  !stopUpdates.isEmpty else {
                return nil
            }
            
            var mappedStops: [Stop] = []
            let nowEpoch = Date().timeIntervalSince1970
            var maxDelaySec = 0
            var lastPassedStopName = "--"
            var lastPassedTime = "--:--"
            var hasDeparted = false
            
            for su in stopUpdates {
                let stopId = (su["stop_id"] as? String) ?? ""
                let cleanStopId = stopId.components(separatedBy: ":").first ?? stopId
                let stationName = Self.italoStationNames[cleanStopId] ?? cleanStopId
                
                let arr = su["arrival"] as? [String: Any]
                let dep = su["departure"] as? [String: Any]
                
                let delaySec = (dep?["delay"] as? Int) ?? (arr?["delay"] as? Int) ?? 0
                if delaySec > maxDelaySec { maxDelaySec = delaySec }
                
                let schedEpoch = (dep?["time"] as? Double) ?? (arr?["time"] as? Double) ?? 0.0
                guard schedEpoch > 0 else { continue }
                
                let schedDate = Date(timeIntervalSince1970: schedEpoch - Double(delaySec))
                let actDate = Date(timeIntervalSince1970: schedEpoch)
                
                let schedStr = SharedFormatters.time.string(from: schedDate)
                let actStr = SharedFormatters.time.string(from: actDate)
                let isPast = schedEpoch <= nowEpoch
                
                if isPast {
                    hasDeparted = true
                    lastPassedStopName = stationName
                    lastPassedTime = actStr
                }
                
                let stopDelayMin = max(0, delaySec / 60)
                let estStr = (!isPast && stopDelayMin >= 3) ? actStr : nil
                
                mappedStops.append(Stop(
                    stationName: stationName.formattedStationName,
                    time: schedStr,
                    actualTime: isPast ? actStr : nil,
                    delay: stopDelayMin,
                    estimatedTime: estStr,
                    plannedPlatform: nil,
                    actualPlatform: nil
                ))
            }
            
            guard !mappedStops.isEmpty else { return nil }
            
            var status = TrainStatus()
            let globalDelayMin = maxDelaySec / 60
            status.isDeparted = hasDeparted
            status.isArrived = hasDeparted && (stopUpdates.last?["departure"] as? [String: Any])?["time"] as? Double ?? 0 <= nowEpoch
            status.statusMessage = globalDelayMin > 0 ? "ritardo \(globalDelayMin) min." : (hasDeparted ? "in orario" : "Non ancora partito")
            status.lastStation = lastPassedStopName
            status.lastTime = lastPassedTime
            
            return StopsResult(stops: mappedStops, status: status, errorMessage: nil)
        } catch {
            AppLogger.decodingError(context: "ItaloGTFS:\(cleanNumber)", error: error)
            return nil
        }
    }
    
    // MARK: - Helper di formattazione e calcolo
    
    private static func cleanTime(_ val: String?) -> String {
        guard let s = val?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, s != "01:00", s != "00:00:00" else {
            return "--:--"
        }
        if s.count == 5 && s.contains(":") {
            return s
        }
        if s.contains("T") {
            let parts = s.components(separatedBy: "T")
            if parts.count > 1 {
                let timePart = String(parts[1].prefix(5))
                if timePart.contains(":") { return timePart }
            }
        }
        if s.count >= 5 {
            return String(s.prefix(5))
        }
        return s
    }
    
    private static func cleanPlatform(_ val: String?) -> String? {
        guard let p = val?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty, p.lowercased() != "null" else {
            return nil
        }
        return p
    }
    
    private static func calculateDiffMinutes(scheduled: String, actual: String) -> Int {
        guard let sDate = SharedFormatters.time.date(from: scheduled),
              let aDate = SharedFormatters.time.date(from: actual) else {
            return 0
        }
        let diff = Int(aDate.timeIntervalSince(sDate) / 60.0)
        return diff
    }
    
    private static func addMinutes(to timeStr: String, minutes: Int) -> String? {
        guard let date = SharedFormatters.time.date(from: timeStr),
              let newDate = Calendar.current.date(byAdding: .minute, value: minutes, to: date) else {
            return nil
        }
        return SharedFormatters.time.string(from: newDate)
    }
    
    private static let italoStationNames: [String: String] = [
        "MC_": "Milano Centrale",
        "MPG": "Milano Porta Garibaldi",
        "MRO": "Milano Rogoredo",
        "TO_": "Torino Porta Nuova",
        "TPS": "Torino Porta Susa",
        "AAV": "Reggio Emilia AV Mediopadana",
        "BO2": "Bologna Centrale",
        "BC_": "Bologna Centrale",
        "SMN": "Firenze Santa Maria Novella",
        "RMT": "Roma Termini",
        "RTI": "Roma Tiburtina",
        "NAC": "Napoli Centrale",
        "NAF": "Napoli Afragola",
        "SAL": "Salerno",
        "VE_": "Venezia Mestre",
        "VSL": "Venezia Santa Lucia",
        "PD_": "Padova",
        "VR_": "Verona Porta Nuova",
        "VIC": "Vicenza",
        "BS_": "Brescia",
        "FE_": "Ferrara",
        "F__": "Ferrara",
        "RN_": "Rimini",
        "PS_": "Pesaro",
        "AN_": "Ancona",
        "PE_": "Pescara",
        "FG_": "Foggia",
        "BAR": "Bari Centrale",
        "CAS": "Caserta",
        "BEN": "Benevento",
        "AGR": "Agropoli Castellabate",
        "VLH": "Vallo della Lucania",
        "SRI": "Sapri",
        "MRT": "Maratea",
        "PAR": "Paola",
        "LON": "Lamezia Terme Centrale",
        "VIP": "Vibo Valentia-Pizzo",
        "RUT": "Rosarno",
        "VSG": "Villa San Giovanni",
        "RCE": "Reggio Calabria Centrale",
        "TSC": "Trieste Centrale",
        "TSA": "Trieste Airport",
        "MNF": "Monfalcone",
        "LAT": "Latisana-Lignano",
        "PTG": "Portogruaro",
        "CDN": "Conegliano",
        "PN_": "Pordenone",
        "UD_": "Udine",
        "RO_": "Rovigo",
        "BZ_": "Bolzano",
        "TN_": "Trento",
        "ROV": "Rovereto"
    ]
}

/// Alias per garantire la compatibilità del codice esistente
typealias ItaloService = ItaloTrackingProvider
