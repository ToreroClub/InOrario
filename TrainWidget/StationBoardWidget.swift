import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Models

struct WidgetStation: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    let name: String
    let rfiID: String?
    let vtID: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, rfiID, vtID
    }
    
    init(id: UUID = UUID(), name: String, rfiID: String?, vtID: String?) {
        self.id = id
        self.name = name
        self.rfiID = rfiID
        self.vtID = vtID
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        
        // rfiID può essere salvato come String o Int
        if let rfiStr = try? container.decodeIfPresent(String.self, forKey: .rfiID) {
            self.rfiID = rfiStr
        } else if let rfiInt = try? container.decodeIfPresent(Int.self, forKey: .rfiID) {
            self.rfiID = String(rfiInt)
        } else {
            self.rfiID = nil
        }
        
        // vtID può essere salvato come String o Int
        if let vtStr = try? container.decodeIfPresent(String.self, forKey: .vtID) {
            self.vtID = vtStr
        } else if let vtInt = try? container.decodeIfPresent(Int.self, forKey: .vtID) {
            self.vtID = String(vtInt)
        } else {
            self.vtID = nil
        }
    }
}

struct WidgetStationTrain: Identifiable, Codable {
    var id: String { "\(category)_\(number)_\(time)_\(destination)" }
    let category: String
    let number: String
    let destination: String
    let time: String
    let delay: String
    let platform: String
}

struct StationBoardEntry: TimelineEntry, Codable {
    let date: Date
    let stationName: String
    let source: String
    let alert: String?
    let trains: [WidgetStationTrain]
    let isSupporterUnlocked: Bool
    var stationIndex: Int = 0
    var totalStations: Int = 1
    
    enum CodingKeys: String, CodingKey {
        case date, stationName, source, alert, trains, isSupporterUnlocked, stationIndex, totalStations
    }
    
    init(date: Date, stationName: String, source: String, alert: String?, trains: [WidgetStationTrain], isSupporterUnlocked: Bool, stationIndex: Int = 0, totalStations: Int = 1) {
        self.date = date
        self.stationName = stationName
        self.source = source
        self.alert = alert
        self.trains = trains
        self.isSupporterUnlocked = isSupporterUnlocked
        self.stationIndex = stationIndex
        self.totalStations = totalStations
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.date = try c.decode(Date.self, forKey: .date)
        self.stationName = try c.decode(String.self, forKey: .stationName)
        self.source = try c.decode(String.self, forKey: .source)
        self.alert = try c.decodeIfPresent(String.self, forKey: .alert)
        self.trains = try c.decode([WidgetStationTrain].self, forKey: .trains)
        self.isSupporterUnlocked = try c.decode(Bool.self, forKey: .isSupporterUnlocked)
        self.stationIndex = try c.decodeIfPresent(Int.self, forKey: .stationIndex) ?? 0
        self.totalStations = try c.decodeIfPresent(Int.self, forKey: .totalStations) ?? 1
    }
}

// MARK: - FerrovieNord Catalog

private let ferrovieNordStations: Set<String> = [
    // Rete Milano - Dorsale Milano - Saronno & Passante Ovest
    "milano cadorna", "milano domodossola", "milano bovisa politecnico", "milano bovisa", "milano quarto oggiaro",
    "cormano-cusano milanino", "paderno dugnano", "palazzolo milanese", "varedo", "bovisio masciago-mombello",
    "cesano maderno", "seveso", "camnago-lentate", "novate milanese", "bollate centro", "bollate nord",
    "garbagnate milanese", "garbagnate parco delle groane", "cesate", "caronno pertusella", "saronno sud", "saronno",
    // Linea Seveso - Asso
    "meda", "cabiate", "mariano comense", "carugo-giussano", "arosio", "inverigo", "lambrugo-lurago",
    "merone", "erba", "ponte lambro-castelmarte", "caslino d'erba", "canzo", "canzo-asso",
    // Linea Saronno - Como Lago
    "rovello porro", "rovellasca-manera", "lomazzo", "caslino al piano", "cadorago", "fino mornasco",
    "portichetto-luisago", "grandate-breccia", "como camerlata", "como borghi", "como lago",
    // Linea Saronno - Varese Nord - Laveno Mombello Lago
    "gerenzano-turate", "cislago", "mozzate", "locate varesino-carbonate", "tradate", "tradate-abbiate guazzone",
    "venegono inferiore", "venegono superiore-castiglione olona", "vedano olona", "malnate", "varese nord",
    "varese casbeno", "morosolo-casciago", "barasso-comerio", "gavirate", "gavirate verbano", "cocquio-trevisago",
    "gemonio", "cittiglio", "laveno mombello lago",
    // Linea Saronno - Novara Nord
    "rescaldina", "castellanza", "busto arsizio fn", "vanzaghello-magnago", "castano primo", "turbigo",
    "galliate", "novara nord",
    // Ramo Malpensa
    "ferno-lonate pozzolo", "malpensa aeroporto terminal 1", "malpensa aeroporto terminal 2", "malpensa t1", "malpensa t2",
    // Linea Saronno - Seregno
    "ceriano laghetto-solaro", "ceriano laghetto groane", "cesano maderno groane", "seveso-baruccana", "seregno",
    // Rete Iseo (Brescia - Iseo - Edolo e Ramo Rovato)
    "brescia", "brescia borgo san giovanni", "castegnato", "passirano", "bornato-calino", "borgonato-adro",
    "provaglio-timoline", "iseo", "pilzone", "sulzano", "sale marasino", "marone-zone", "vello", "toline",
    "pisogne", "piancamuno-gratacasolo", "darfo-corna", "boario terme", "cogno-esine", "piancogno",
    "cividate-malegno", "breno", "ceto-cerveno", "capo di ponte", "sellero", "cedegolo", "malonno",
    "sonico", "edolo", "rovato centro", "rovato fn"
]

private func isFerrovieNordStation(name: String, rfiID: String?) -> Bool {
    if rfiID == nil || rfiID?.trimmingCharacters(in: .whitespaces).isEmpty == true {
        return true
    }
    let clean = name.lowercased()
        .replacingOccurrences(of: "stazione di ", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if ferrovieNordStations.contains(clean) {
        return true
    }
    return ferrovieNordStations.contains { clean.contains($0) || $0.contains(clean) }
}

// MARK: - Data Provider

class StationBoardDataProvider {
    static let shared = StationBoardDataProvider()
    private let suiteName = "group.carlo.InOrario"
    private let myStationsKey = "savedMyStations_v3"
    private let supporterKey = "tip.colazionee"
    private let selectedIndexKey = "widgetStationBoardSelectedIndex"
    
    func checkSupporterUnlocked() -> Bool {
        let defaults = UserDefaults(suiteName: suiteName)
        return defaults?.bool(forKey: supporterKey) ?? false
    }
    
    func getSavedStations() -> [WidgetStation] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: myStationsKey),
              let decoded = try? JSONDecoder().decode([WidgetStation].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func resolveStation() -> (station: WidgetStation?, index: Int, total: Int) {
        let stations = getSavedStations()
        guard !stations.isEmpty else {
            return (nil, 0, 0)
        }
        
        let defaults = UserDefaults(suiteName: suiteName)
        var currentIndex = defaults?.integer(forKey: selectedIndexKey) ?? 0
        if currentIndex >= stations.count || currentIndex < 0 {
            currentIndex = 0
            defaults?.set(0, forKey: selectedIndexKey)
        }
        return (stations[currentIndex], currentIndex, stations.count)
    }
    
    func saveToCache(stationName: String, entry: StationBoardEntry) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(entry) else { return }
        defaults.set(data, forKey: "boardCache_\(stationName)")
    }
    
    func loadFromCache(stationName: String) -> StationBoardEntry? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: "boardCache_\(stationName)"),
              let cached = try? JSONDecoder().decode(StationBoardEntry.self, from: data) else {
            return nil
        }
        return cached
    }
    
    func fetchBoard(for station: WidgetStation, index: Int = 0, total: Int = 1) async -> StationBoardEntry {
        let isFNM = isFerrovieNordStation(name: station.name, rfiID: station.rfiID)
        
        if !isFNM, let rfiID = station.rfiID, !rfiID.isEmpty {
            // 1. Stazione RFI: usa SOLO lo scraping del tabellone RFI
            let (rfiTrains, alerts) = await performRfiScraping(for: rfiID)
            if !rfiTrains.isEmpty {
                let entry = StationBoardEntry(
                    date: Date(),
                    stationName: station.name,
                    source: "RFI",
                    alert: alerts,
                    trains: rfiTrains,
                    isSupporterUnlocked: true,
                    stationIndex: index,
                    totalStations: total
                )
                saveToCache(stationName: station.name, entry: entry)
                return entry
            }
            
            // Safety fallback se RFI ha un blocco temporaneo e c'è vtID
            if let vtID = station.vtID, !vtID.isEmpty {
                let vtTrains = await performVTFetch(for: vtID)
                if !vtTrains.isEmpty {
                    let entry = StationBoardEntry(
                        date: Date(),
                        stationName: station.name,
                        source: "RFI",
                        alert: alerts,
                        trains: vtTrains,
                        isSupporterUnlocked: true,
                        stationIndex: index,
                        totalStations: total
                    )
                    saveToCache(stationName: station.name, entry: entry)
                    return entry
                }
            }
        } else if let vtID = station.vtID, !vtID.isEmpty {
            // 2. Stazione FerrovieNord (o senza rfiID): usa ViaggiaTreno
            let vtTrains = await performVTFetch(for: vtID)
            if !vtTrains.isEmpty {
                let entry = StationBoardEntry(
                    date: Date(),
                    stationName: station.name,
                    source: "FerrovieNord",
                    alert: nil,
                    trains: vtTrains,
                    isSupporterUnlocked: true,
                    stationIndex: index,
                    totalStations: total
                )
                saveToCache(stationName: station.name, entry: entry)
                return entry
            }
        }
        
        // Se la rete fallisce, prova a restituire la cache precedente aggiornando gli indici
        if var cached = loadFromCache(stationName: station.name) {
            cached.stationIndex = index
            cached.totalStations = total
            return cached
        }
        
        return StationBoardEntry(
            date: Date(),
            stationName: station.name,
            source: isFNM ? "FerrovieNord" : "RFI",
            alert: nil,
            trains: [],
            isSupporterUnlocked: true,
            stationIndex: index,
            totalStations: total
        )
    }
    
    // MARK: - RFI Scraping
    
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
    
    private func performRfiScraping(for rfiID: String) async -> (trains: [WidgetStationTrain], alerts: String?) {
        let urlString = "https://iechub.rfi.it/ArriviPartenze/ArrivalsDepartures/Monitor?placeId=\(rfiID)&arrivals=false"
        guard let url = URL(string: urlString) else { return ([], nil) }
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 8.0
        sessionConfig.timeoutIntervalForResource = 10.0
        let session = URLSession(configuration: sessionConfig)
        
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
            var scrapedTrains: [WidgetStationTrain] = []
            
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
                    if catUpper.contains("ALTA VELOCIT") || catUpper.contains("FRECCIA") { cat = "AV" }
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
                    }
                    
                    if !num.isEmpty && time.contains(":") {
                        let delayFormatted: String
                        if delayRaw.isEmpty || delayRaw == "0" {
                            delayFormatted = "In orario"
                        } else if delayRaw.lowercased().contains("soppr") || delayRaw.lowercased().contains("cancell") {
                            delayFormatted = "Cancellato"
                        } else {
                            delayFormatted = "+\(delayRaw)'"
                        }
                        scrapedTrains.append(WidgetStationTrain(
                            category: cat,
                            number: num,
                            destination: dest.capitalized,
                            time: time,
                            delay: delayFormatted,
                            platform: plat.isEmpty ? "--" : plat
                        ))
                    }
                }
            }
            return (scrapedTrains, stationAlerts)
        } catch {
            return ([], nil)
        }
    }
    
    // MARK: - ViaggiaTreno Fetching
    
    private func performVTFetch(for vtID: String) async -> [WidgetStationTrain] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        f.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT'ZZZ"
        let str = f.string(from: Date()).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let dateStr = str.replacingOccurrences(of: "+", with: "%2B")
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 8.0
        sessionConfig.timeoutIntervalForResource = 10.0
        let session = URLSession(configuration: sessionConfig)
        
        let urlStrings = [
            "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/partenze/\(vtID)/\(dateStr)",
            "http://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/partenze/\(vtID)/\(dateStr)"
        ]
        
        for urlString in urlStrings {
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("https://www.viaggiatreno.it/", forHTTPHeaderField: "Referer")
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
            
            if let (data, resp) = try? await session.data(for: request),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let jsonArray = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "HH:mm"
                
                return jsonArray.compactMap { item in
                    let num = String(item["numeroTreno"] as? Int ?? 0)
                    var cat = (item["categoriaDescrizione"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                    let dest = ((item["destinazione"]) as? String)?.capitalized ?? ""
                    let timeVal = (item["orarioPartenza"]) as? Int ?? 0
                    let ritardo = item["ritardo"] as? Int ?? 0
                    
                    let binEff = item["binarioEffettivoPartenzaDescrizione"] as? String
                    let binProg = item["binarioProgrammatoPartenzaDescrizione"] as? String
                    let platform = binEff ?? binProg ?? "--"
                    
                    let catUpper = cat.uppercased()
                    if catUpper.contains("ALTA VELOCIT") || catUpper.contains("FRECCIA") { cat = "AV" }
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
                    }
                    
                    let isCancelled = (item["cancellato"] as? Bool ?? false) || (item["provvedimento"] as? Int ?? 0) == 1
                    let delayStr = isCancelled ? "Cancellato" : (ritardo > 0 ? "+\(ritardo)'" : "In orario")
                    
                    if timeVal > 0 {
                        let date = Date(timeIntervalSince1970: TimeInterval(timeVal / 1000))
                        return WidgetStationTrain(
                            category: cat.isEmpty ? "REG" : cat,
                            number: num,
                            destination: dest,
                            time: timeFormatter.string(from: date),
                            delay: delayStr,
                            platform: platform
                        )
                    }
                    return nil
                }
            }
        }
        return []
    }
}

// MARK: - AppIntents (iOS 17+)

@available(iOS 17.0, *)
struct NextStationIntent: AppIntent {
    static var title: LocalizedStringResource = "Scambia Stazione"
    static var description = IntentDescription("Passa alla stazione preferita successiva nel tabellone.")

    func perform() async throws -> some IntentResult {
        let suiteName = "group.carlo.InOrario"
        let selectedIndexKey = "widgetStationBoardSelectedIndex"
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: "savedMyStations_v3"),
              let stations = try? JSONDecoder().decode([WidgetStation].self, from: data),
              !stations.isEmpty else {
            return .result()
        }
        
        let currentIndex = defaults.integer(forKey: selectedIndexKey)
        let nextIndex = (currentIndex + 1) % stations.count
        defaults.set(nextIndex, forKey: selectedIndexKey)
        
        WidgetCenter.shared.reloadTimelines(ofKind: "StationBoardWidget")
        return .result()
    }
}

// MARK: - Timeline Provider (StaticConfiguration)

struct StationBoardTimelineProvider: TimelineProvider {
    typealias Entry = StationBoardEntry
    
    func placeholder(in context: Context) -> StationBoardEntry {
        StationBoardEntry(
            date: Date(),
            stationName: "Milano Centrale",
            source: "RFI",
            alert: nil,
            trains: [
                WidgetStationTrain(category: "FR", number: "9515", destination: "Roma Termini", time: "12:10", delay: "In orario", platform: "8"),
                WidgetStationTrain(category: "RV", number: "2165", destination: "Bologna C.le", time: "12:20", delay: "+5'", platform: "11"),
                WidgetStationTrain(category: "REG", number: "10214", destination: "Treviglio", time: "12:25", delay: "In orario", platform: "5")
            ],
            isSupporterUnlocked: true,
            stationIndex: 0,
            totalStations: 3
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (StationBoardEntry) -> ()) {
        let isUnlocked = StationBoardDataProvider.shared.checkSupporterUnlocked()
        guard isUnlocked else {
            let entry = StationBoardEntry(date: Date(), stationName: "Tabellone", source: "", alert: nil, trains: [], isSupporterUnlocked: false, stationIndex: 0, totalStations: 0)
            completion(entry)
            return
        }
        
        let resolved = StationBoardDataProvider.shared.resolveStation()
        guard let station = resolved.station else {
            let entry = StationBoardEntry(date: Date(), stationName: "Nessuna stazione", source: "", alert: nil, trains: [], isSupporterUnlocked: true, stationIndex: 0, totalStations: 0)
            completion(entry)
            return
        }
        
        if let cached = StationBoardDataProvider.shared.loadFromCache(stationName: station.name) {
            var updatedCached = cached
            updatedCached.stationIndex = resolved.index
            updatedCached.totalStations = resolved.total
            completion(updatedCached)
            return
        }
        completion(placeholder(in: context))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<StationBoardEntry>) -> ()) {
        Task {
            let isUnlocked = StationBoardDataProvider.shared.checkSupporterUnlocked()
            guard isUnlocked else {
                let entry = StationBoardEntry(date: Date(), stationName: "Tabellone", source: "", alert: nil, trains: [], isSupporterUnlocked: false, stationIndex: 0, totalStations: 0)
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
                completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
                return
            }
            
            let resolved = StationBoardDataProvider.shared.resolveStation()
            guard let station = resolved.station else {
                let entry = StationBoardEntry(date: Date(), stationName: "Nessuna stazione", source: "", alert: nil, trains: [], isSupporterUnlocked: true, stationIndex: 0, totalStations: 0)
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
                completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
                return
            }
            
            let entry = await StationBoardDataProvider.shared.fetchBoard(for: station, index: resolved.index, total: resolved.total)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }
}

// MARK: - Widget Views

struct StationBoardWidgetEntryView: View {
    var entry: StationBoardEntry
    @Environment(\.widgetFamily) var family
    
    private func categoryColor(_ cat: String) -> Color {
        let c = cat.uppercased()
        if c.contains("FR") || c.contains("ITA") || c == "AV" { return .red }
        if c == "IC" || c == "EC" { return .gray }
        if c.contains("S") { return Color(red: 0.0, green: 0.6, blue: 0.2) }
        if c.contains("RV") || c.contains("RE") { return .blue }
        return Color(red: 0.2, green: 0.45, blue: 0.85)
    }
    
    private func delayColor(_ delay: String) -> Color {
        let d = delay.lowercased()
        if d.contains("orario") || d.contains("0'") {
            return .green
        } else if d.contains("cancell") || d.contains("soppr") || d.contains("+") || d.contains("ritardo") {
            return .red
        } else if d.contains("anticipo") || d.contains("-") {
            return .green
        }
        return .secondary
    }
    
    private func formatDestination(_ name: String) -> String {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("centrale") { return "Milano Centrale" }
        if lower.contains("garibaldi") { return "Milano P. Garibaldi" }
        if lower.contains("venezia") { return "Milano P. Venezia" }
        if lower.contains("vittoria") { return "Milano P. Vittoria" }
        if lower.contains("malpensa") {
            if lower.contains("2") { return "Malpensa T2" }
            return "Malpensa T1"
        }
        return name
    }
    
    var body: some View {
        if !entry.isSupporterUnlocked {
            lockedSupporterView
        } else if entry.stationName == "Nessuna stazione" {
            noStationConfiguredView
        } else {
            boardContentView
        }
    }
    
    // MARK: - Locked State
    
    private var lockedSupporterView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "lock.fill")
                .foregroundColor(.orange)
                .font(.title2)
            Text("Widget Bloccato")
                .font(.headline)
            Text("Diventa Sostenitore nelle impostazioni dell'app per sbloccare il tabellone partenze.")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - No Station State
    
    private var noStationConfiguredView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "building.2.crop.circle")
                .foregroundColor(.blue)
                .font(.title2)
            Text("Nessuna Stazione")
                .font(.headline)
            Text("Salva una stazione tra i preferiti nell'app per visualizzare qui le sue partenze.")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Board Content
    
    private var boardContentView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "train.side.front.car")
                    .foregroundColor(.blue)
                    .font(.subheadline)
                
                Text(entry.stationName)
                    .font(.headline)
                    .bold()
                    .lineLimit(1)
                
                if !entry.source.isEmpty {
                    Text(entry.source)
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundColor(.secondary)
                        .cornerRadius(3)
                }
                
                Spacer()
                
                // Pulsante 1: Scambio / Giro Stazione (sempre presente e visibile se iOS 17+)
                if #available(iOS 17.0, *) {
                    Button(intent: NextStationIntent()) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 10, weight: .bold))
                            if entry.totalStations > 1 {
                                Text("\(entry.stationIndex + 1)/\(entry.totalStations)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.18))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                
                // Pulsante 2: Ricarica partenze in tempo reale
                if #available(iOS 17.0, *) {
                    Button(intent: RefreshWidgetIntent()) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundColor(.gray.opacity(0.65))
                            .font(.system(size: 17))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Alert Banner (se presente da RFI)
            if let alert = entry.alert, !alert.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 8))
                    Text(alert)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(4)
            }
            
            Divider()
                .padding(.vertical, 1)
            
            // Trains List
            if entry.trains.isEmpty {
                VStack {
                    Spacer()
                    Text("Nessuna partenza in programma al momento.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                }
            } else {
                let maxTrains = family == .systemLarge ? 7 : 3
                VStack(spacing: 5) {
                    ForEach(entry.trains.prefix(maxTrains)) { train in
                        Link(destination: URL(string: "inorario://\(train.number)")!) {
                            HStack(alignment: .center, spacing: 6) {
                                // Category Badge
                                Text(train.category)
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(categoryColor(train.category))
                                    .cornerRadius(4)
                                
                                // Destination and Train Number
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(formatDestination(train.destination))
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text(train.number)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                // Time & Delay
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(train.time)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.primary)
                                    
                                    Text(train.delay)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(delayColor(train.delay))
                                }
                                
                                // Platform Badge
                                Text(train.platform == "--" ? "Bin. -" : "Bin. \(train.platform)")
                                    .font(.system(size: 10, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.85))
                                    .foregroundColor(.yellow)
                                    .cornerRadius(4)
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 4)
                            .background(Color(.secondarySystemBackground).opacity(0.6))
                            .cornerRadius(6)
                        }
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Widget Configuration

struct StationBoardWidget: Widget {
    let kind: String = "StationBoardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StationBoardTimelineProvider()) { entry in
            if #available(iOS 17.0, *) {
                StationBoardWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                StationBoardWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Tabellone Stazione")
        .description("Visualizza le partenze e i binari in tempo reale delle tue stazioni preferite.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
