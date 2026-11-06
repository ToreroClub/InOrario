import Foundation

/// Motore di scraping e recupero dati identico all'applicazione In Orario.
public actor ClipService {
    public static let shared = ClipService()
    
    private let session: URLSession
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 12.0
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Station Board Fetching (RFI + ViaggiaTreno merge)
    
    public func fetchBoard(for station: Station, isDepartures: Bool) async -> StationBoardResult {
        let rfiID = station.rfiID ?? ""
        let vtID = station.vtID ?? ""
        
        if !rfiID.isEmpty {
            let rfiResult = await performRfiScraping(for: rfiID, isDepartures: isDepartures)
            guard !Task.isCancelled else { return StationBoardResult(trains: []) }
            
            if !rfiResult.trains.isEmpty {
                let hasUpcoming = rfiResult.trains.contains { trainIsWithinNextMinutes($0, minutes: 45) }
                
                if hasUpcoming && !vtID.isEmpty {
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
    
    // MARK: - RFI Scraping
    
    private func performRfiScraping(for rfiID: String, isDepartures: Bool) async -> (trains: [Train], alerts: String?) {
        let arrivalsParam = isDepartures ? "false" : "true"
        let urlString = "https://iechub.rfi.it/ArriviPartenze/ArrivalsDepartures/Monitor?placeId=\(rfiID)&arrivals=\(arrivalsParam)"
        guard let url = URL(string: urlString) else { return ([], nil) }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await session.data(for: request)
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return ([], nil)
            }
            
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
            var trains: [Train] = []
            
            for row in rows.dropFirst() {
                let cols = row.components(separatedBy: "<td")
                if cols.count >= 8 {
                    var rawCat = stripHTML(cols[2])
                        .replacingOccurrences(of: "Categoria", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "Category", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if rawCat.isEmpty {
                        if let altRange = cols[2].range(of: "alt=\"([^\"]+)\"", options: .regularExpression) {
                            let match = String(cols[2][altRange])
                            rawCat = stripHTML(
                                match.replacingOccurrences(of: "alt=\"", with: "")
                                     .replacingOccurrences(of: "\"", with: "")
                                     .replacingOccurrences(of: "Categoria", with: "", options: .caseInsensitive)
                                     .replacingOccurrences(of: "Category", with: "", options: .caseInsensitive)
                            ).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    
                    var cat = cleanTrainCategory(rawCat)
                    
                    let num = stripHTML(cols[3])
                    let dest = stripHTML(cols[4])
                    let time = stripHTML(cols[5])
                    let delayRaw = stripHTML(cols[6])
                    let plat = stripHTML(cols[7])
                    
                    let catUpper = cat.uppercased()
                    let col2Upper = cols[2].uppercased()
                    let isItalo = isItaloTrain(category: cat, number: num) || catUpper.contains("ITALO") || catUpper.contains("NTV") || col2Upper.contains("ITALO") || col2Upper.contains("NTV")
                    
                    if isItalo {
                        cat = "Italo"
                    } else if catUpper.contains("ALTA VELOCIT") {
                        cat = "AV"
                    } else if catUpper.contains("INTERCITY") {
                        cat = "IC"
                    } else if catUpper.contains("EUROCITY") {
                        cat = "EC"
                    } else if catUpper == "REGIONALE VELOCE" {
                        cat = "RV"
                    } else if catUpper == "REGIONALE" {
                        cat = "REG"
                    }
                    
                    if cat.isEmpty {
                        if num.hasPrefix("20") || num.hasPrefix("21") { cat = "RV" }
                        else if num.hasPrefix("24") || num.hasPrefix("10") { cat = "S" }
                        else { cat = "REG" }
                    }
                    
                    let parsedDelay: String
                    let dLower = delayRaw.lowercased()
                    if dLower.contains("cancell") || dLower.contains("soppr") {
                        parsedDelay = "+Cancellato'"
                    } else if dLower.contains("orario") {
                        parsedDelay = "In orario"
                    } else {
                        let digits = delayRaw.filter { "0123456789".contains($0) }
                        parsedDelay = digits.isEmpty ? delayRaw : "+\(digits)'"
                    }
                    
                    if !num.isEmpty && !time.isEmpty {
                        let train = Train(
                            category: cat,
                            number: num,
                            destination: dest,
                            time: time,
                            delay: parsedDelay.isEmpty ? "In orario" : parsedDelay,
                            platform: plat.isEmpty ? "--" : plat
                        )
                        trains.append(train)
                    }
                }
            }
            return (trains, stationAlerts)
        } catch {
            return ([], nil)
        }
    }
    
    // MARK: - ViaggiaTreno Fetching
    
    private func performVTFetch(for vtID: String, isDepartures: Bool, dateStr: String) async -> [Train] {
        let endpoint = isDepartures ? "partenze" : "arrivi"
        let urlString = "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/\(endpoint)/\(vtID)/\(dateStr)"
        guard let url = URL(string: urlString) else { return [] }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, _) = try await session.data(for: request)
            guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }
            
            return jsonArray.compactMap { item in
                let num = String(item["numeroTreno"] as? Int ?? 0)
                guard num != "0" else { return nil }
                
                let rawCatCode = ((item["categoria"] as? String) ?? "").trimmingCharacters(in: .whitespaces).uppercased()
                var cat = (item["categoriaDescrizione"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                let dest = ((isDepartures ? item["destinazione"] : item["origine"]) as? String)?.capitalized ?? ""
                let timeVal = (isDepartures ? item["orarioPartenza"] : item["orarioArrivo"]) as? Int ?? 0
                let ritardo = item["ritardo"] as? Int ?? 0
                
                let binEff = (isDepartures ? item["binarioEffettivoPartenzaDescrizione"] : item["binarioEffettivoArrivoDescrizione"]) as? String
                let binProg = (isDepartures ? item["binarioProgrammatoPartenzaDescrizione"] : item["binarioProgrammatoArrivoDescrizione"]) as? String
                let platform = binEff ?? binProg ?? "--"
                
                let timeStr = formatMillisToTime(timeVal)
                let delayStr = ritardo <= 0 ? "In orario" : "+\(ritardo)'"
                
                let catUpper = cat.uppercased()
                let isItalo = isItaloTrain(category: rawCatCode.isEmpty ? cat : rawCatCode, number: num) || catUpper.contains("ITALO") || catUpper.contains("NTV") || rawCatCode.contains("NTV") || rawCatCode.contains("ITA")
                
                if isItalo {
                    cat = "Italo"
                } else if catUpper.contains("ALTA VELOCIT") {
                    cat = "AV"
                } else if catUpper.contains("INTERCITY") {
                    cat = "IC"
                } else if catUpper.contains("EUROCITY") {
                    cat = "EC"
                } else if catUpper == "REGIONALE VELOCE" {
                    cat = "RV"
                } else if catUpper == "REGIONALE" {
                    cat = "REG"
                } else if catUpper == "SUBURBANO" {
                    cat = "S"
                }
                
                return Train(
                    category: cat.isEmpty ? "REG" : cat,
                    number: num,
                    destination: dest,
                    time: timeStr,
                    delay: delayStr,
                    platform: platform
                )
            }
        } catch {
            return []
        }
    }
    
    // MARK: - Merge Delays Logic (Exact from StationRepository)
    
    private func mergeVTDelays(rfiTrains: [Train], vtTrains: [Train]) -> [Train] {
        var vtDict: [String: Train] = [:]
        for vt in vtTrains {
            vtDict[vt.number] = vt
        }
        
        return rfiTrains.map { rfi in
            guard let vt = vtDict[rfi.number] else { return rfi }
            
            let rfiRitardo = parseDelayInt(rfi.delay)
            let vtRitardo = parseDelayInt(vt.delay)
            
            var delayToUse = rfi.delay
            var isUncertain = false
            
            if abs(rfiRitardo - vtRitardo) > 15 {
                isUncertain = true
                delayToUse = rfi.delay
            } else if vtRitardo > 0 {
                delayToUse = "+\(vtRitardo)'"
            } else if vtRitardo == 0 {
                delayToUse = "In orario"
            }
            
            let resolvedPlat = (rfi.platform != "--" && !rfi.platform.isEmpty) ? rfi.platform : vt.platform
            
            return Train(
                category: rfi.category,
                number: rfi.number,
                destination: rfi.destination,
                time: rfi.time,
                delay: delayToUse,
                platform: resolvedPlat,
                isDelayUncertain: isUncertain,
                origin: rfi.origin
            )
        }
    }
    
    // MARK: - Live Stops & Train Status (Exact from TrainRepository)
    
    public func fetchLiveStops(for train: Train) async -> StopsResult {
        let cleanNumber = train.number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNumber.isEmpty else {
            return StopsResult(stops: [], status: TrainStatus(), errorMessage: "Numero treno non valido.")
        }
        
        // Se il treno è Italo, interroga ESCLUSIVAMENTE il provider Italo
        if isItaloTrain(category: train.category, number: cleanNumber) {
            return await fetchItaloLiveStops(cleanNumber: cleanNumber)
        }
        
        // Tutti gli altri treni seguono ViaggiaTreno senza commistione
        let searchUrl = "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/cercaNumeroTrenoTrenoAutocomplete/\(cleanNumber)"
        guard let sUrl = URL(string: searchUrl) else {
            return StopsResult(stops: [], status: TrainStatus(), errorMessage: "URL non valido.")
        }
        
        do {
            let (sData, _) = try await session.data(from: sUrl)
            let result = String(data: sData, encoding: .utf8) ?? ""
            let lines = result.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard let firstLine = lines.first(where: { $0.contains("|\(cleanNumber)-") }) ?? lines.first else {
                return StopsResult(stops: [], status: TrainStatus(), errorMessage: "Treno non tracciato o non ancora nel sistema.")
            }
            
            let pipes = firstLine.components(separatedBy: "|")
            guard pipes.count >= 2 else {
                return StopsResult(stops: [], status: TrainStatus(), errorMessage: "Dati treno non disponibili.")
            }
            let subParts = pipes[1].components(separatedBy: "-")
            guard subParts.count >= 2 else {
                return StopsResult(stops: [], status: TrainStatus(), errorMessage: "Dati treno non disponibili.")
            }
            
            let originID = subParts[1]
            let timestamp = subParts.count >= 3 ? subParts[2] : ""
            
            var stopsUrl = "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/andamentoTreno/\(originID)/\(cleanNumber)"
            if !timestamp.isEmpty { stopsUrl += "/\(timestamp)" }
            guard let stUrl = URL(string: stopsUrl) else {
                return StopsResult(stops: [], status: TrainStatus(), errorMessage: "URL non valido.")
            }
            
            let (stData, _) = try await session.data(from: stUrl)
            guard let json = try? JSONSerialization.jsonObject(with: stData) as? [String: Any] else {
                return StopsResult(stops: [], status: TrainStatus(), errorMessage: "Dati non disponibili.")
            }
            
            let nonPartito = (json["nonPartito"] as? Bool) ?? false
            let arrivato = (json["arrivato"] as? Bool) ?? false
            let ritardo = (json["ritardo"] as? Int) ?? parseDelayInt(train.delay)
            let ultimoRil = json["stazioneUltimoRilevamento"] as? String ?? ""
            let oraRil = json["oraUltimoRilevamento"] as? Int
            
            let statusMessage: String
            if nonPartito {
                statusMessage = "Non ancora partito"
            } else if arrivato {
                statusMessage = "Arrivato a destinazione"
            } else if ritardo > 0 {
                statusMessage = "ritardo \(ritardo) min."
            } else {
                statusMessage = "in orario"
            }
            
            let status = TrainStatus(
                lastStation: ultimoRil.isEmpty ? "--" : ultimoRil,
                lastTime: oraRil != nil ? formatMillisToTime(oraRil!) : "--",
                statusMessage: statusMessage,
                isDeparted: !nonPartito,
                cancellationNote: nil,
                isArrived: arrivato
            )
            
            let fermateRaw = (json["fermate"] as? [[String: Any]]) ?? []
            var stops: [Stop] = []
            
            for f in fermateRaw {
                let stName = (f["stazione"] as? String) ?? ""
                let prog = f["programmata"] as? Int ?? f["partenzaTeoricaZero"] as? Int ?? 0
                let eff = f["effettiva"] as? Int ?? f["partenzaReale"] as? Int
                let rit = f["ritardoPartenza"] as? Int ?? f["ritardoArrivo"] as? Int ?? 0
                let binProg = (f["binarioProgrammatoPartenzaDescrizione"] ?? f["binarioProgrammatoArrivoDescrizione"]) as? String
                let binEff = (f["binarioEffettivoPartenzaDescrizione"] ?? f["binarioEffettivoArrivoDescrizione"]) as? String
                
                let stop = Stop(
                    stationName: stName,
                    time: formatMillisToTime(prog),
                    actualTime: eff != nil ? formatMillisToTime(eff!) : nil,
                    delay: rit,
                    estimatedTime: nil,
                    plannedPlatform: binProg,
                    actualPlatform: binEff
                )
                stops.append(stop)
            }
            
            return StopsResult(stops: stops, status: status, errorMessage: nil)
        } catch {
            return StopsResult(stops: [], status: TrainStatus(), errorMessage: "Errore di connessione.")
        }
    }
    
    // MARK: - Italo Live Stops Fetching
    
    public func fetchItaloLiveStops(cleanNumber: String) async -> StopsResult {
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
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, !data.isEmpty else {
                    continue
                }
                
                if let parsed = parseItaloPayload(data: data, trainNumber: cleanNumber) {
                    return parsed
                }
            } catch {
                continue
            }
        }
        
        return StopsResult(
            stops: [],
            status: TrainStatus(),
            errorMessage: "Treno Italo \(cleanNumber) non trovato o non ancora nel sistema."
        )
    }
    
    private func parseItaloPayload(data: Data, trainNumber: String) -> StopsResult? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        
        if (jsonObject["IsEmpty"] as? Bool) == true {
            return StopsResult(
                stops: [],
                status: TrainStatus(),
                errorMessage: "Treno Italo \(trainNumber) non in circolazione per la data odierna."
            )
        }
        
        guard let schedule = jsonObject["TrainSchedule"] as? [String: Any] else { return nil }
        
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
            let lastT = (lastF?["ActualDepartureTime"] as? String) ?? (lastF?["ActualArrivalTime"] as? String) ?? (jsonObject["LastUpdate"] as? String) ?? "--:--"
            status.lastStation = SharedFormatters.formatDestination(Train.cleanStationName(lastLoc))
            status.lastTime = cleanTimeString(lastT)
        } else if isDeparted, let part = stazPartenza {
            let partLoc = (part["LocationDescription"] as? String) ?? "--"
            status.lastStation = SharedFormatters.formatDestination(Train.cleanStationName(partLoc))
            status.lastTime = cleanTimeString(actualDeparture)
        } else {
            status.lastStation = "--"
            status.lastTime = "--:--"
        }
        
        var mappedStops: [Stop] = []
        
        // 1. Fermata di partenza
        if let part = stazPartenza {
            let name = SharedFormatters.formatDestination(Train.cleanStationName((part["LocationDescription"] as? String) ?? "Origine"))
            let prog = cleanTimeString((part["EstimatedDepartureTime"] as? String) ?? (part["EstimatedArrivalTime"] as? String))
            let act = cleanTimeString(part["ActualDepartureTime"] as? String)
            let plat = (part["ActualArrivalPlatform"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let depDelay = (act != "--:--" && prog != "--:--") ? calculateDiffMinutes(scheduled: prog, actual: act) : (isDeparted ? globalDelay : 0)
            
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
            let name = SharedFormatters.formatDestination(Train.cleanStationName((s["LocationDescription"] as? String) ?? "Stazione"))
            let prog = cleanTimeString((s["EstimatedArrivalTime"] as? String) ?? (s["EstimatedDepartureTime"] as? String))
            let act = cleanTimeString((s["ActualArrivalTime"] as? String) ?? (s["ActualDepartureTime"] as? String))
            let plat = (s["ActualArrivalPlatform"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let stopDelay = (act != "--:--" && prog != "--:--") ? calculateDiffMinutes(scheduled: prog, actual: act) : globalDelay
            
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
            let name = SharedFormatters.formatDestination(Train.cleanStationName((s["LocationDescription"] as? String) ?? "Stazione"))
            let prog = cleanTimeString((s["EstimatedArrivalTime"] as? String) ?? (s["EstimatedDepartureTime"] as? String))
            let rawEta = cleanTimeString(s["ActualArrivalTime"] as? String)
            let plat = (s["ActualArrivalPlatform"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            var estT: String? = nil
            if rawEta != "--:--" && rawEta != prog && globalDelay > 0 {
                estT = rawEta
            } else if globalDelay >= 3, prog != "--:--" {
                estT = addMinutesToTimeString(timeStr: prog, minutes: globalDelay)
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
    
    private func cleanTimeString(_ val: String?) -> String {
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
    
    private func calculateDiffMinutes(scheduled: String, actual: String) -> Int {
        guard let sDate = SharedFormatters.time.date(from: scheduled),
              let aDate = SharedFormatters.time.date(from: actual) else {
            return 0
        }
        let diff = Int(aDate.timeIntervalSince(sDate) / 60.0)
        return diff
    }
    
    private func addMinutesToTimeString(timeStr: String, minutes: Int) -> String? {
        guard let date = SharedFormatters.time.date(from: timeStr),
              let newDate = Calendar.current.date(byAdding: .minute, value: minutes, to: date) else {
            return nil
        }
        return SharedFormatters.time.string(from: newDate)
    }
    

    
    // MARK: - Helpers
    
    private func trainIsWithinNextMinutes(_ train: Train, minutes: Int) -> Bool {
        let parts = train.time.components(separatedBy: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return false }
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        guard let nowH = now.hour, let nowM = now.minute else { return false }
        
        let trainMins = h * 60 + m
        let nowMins = nowH * 60 + nowM
        let diff = trainMins - nowMins
        return diff >= -10 && diff <= minutes
    }
    
    private func parseDelayInt(_ text: String) -> Int {
        if text.lowercased().contains("orario") { return 0 }
        let digits = text.filter { "0123456789-+".contains($0) }
        return Int(digits) ?? 0
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE%20MMM%20dd%20yyyy%20HH:mm:ss%20'GMT'Z"
        return formatter.string(from: Date())
    }
    
    private func formatMillisToTime(_ millis: Int) -> String {
        guard millis > 0 else { return "--:--" }
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
