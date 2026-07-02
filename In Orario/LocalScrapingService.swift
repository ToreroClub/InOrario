import Foundation

class LocalScrapingService {
    static let shared = LocalScrapingService()
    
    private init() {}
    
    // MARK: - Trenitalia InfoLavori Scraping
    func scrapeTrenitalia(region: String) async -> [NewsItem] {
        let urlStr = "https://www.trenitalia.com/it/informazioni/Infomobilita/notizie-infomobilita.html"
        guard let url = URL(string: urlStr) else { return [] }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let htmlString = String(data: data, encoding: .utf8) else { return [] }
            
            var scrapedItems: [NewsItem] = []
            
            // Dividiamo l'html in sezioni
            let items = htmlString.components(separatedBy: "<div class=\"accordion-item\">")
            let regionLower = region.lowercased()
            
            for itemHtml in items.dropFirst() {
                var title = ""
                var content = ""
                var tags = ""
                
                // Extract title
                if let titleStartRange = itemHtml.range(of: "<h3 class=\"infomobility-title\">"),
                   let titleEndRange = itemHtml.range(of: "</h3>", range: titleStartRange.upperBound..<itemHtml.endIndex) {
                    title = String(itemHtml[titleStartRange.upperBound..<titleEndRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                if title.isEmpty { continue }
                
                // Extract tags
                if let tagStartRange = itemHtml.range(of: "<div class=\"tag\">"),
                   let tagEndRange = itemHtml.range(of: "</div>", range: tagStartRange.upperBound..<itemHtml.endIndex) {
                    tags = String(itemHtml[tagStartRange.upperBound..<tagEndRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // Extract content
                let descriptionStart = itemHtml.range(of: "<div class=\"description\">")
                let accordionStart = itemHtml.range(of: "<div class=\"accordion-body\">")
                
                if let startRange = descriptionStart ?? accordionStart,
                   let endRange = itemHtml.range(of: "</div>", range: startRange.upperBound..<itemHtml.endIndex) {
                    content = String(itemHtml[startRange.upperBound..<endRange.lowerBound])
                        .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression, range: nil)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                var isRegional = false
                if regionLower != "tutte" {
                    if title.lowercased().contains(regionLower) || tags.lowercased().contains(regionLower) {
                        isRegional = true
                    } else if title.lowercased().contains(regionLower.replacingOccurrences(of: "-", with: " ")) || tags.lowercased().contains(regionLower.replacingOccurrences(of: "-", with: " ")) {
                        isRegional = true
                    }
                } else {
                    isRegional = true
                }
                
                if isRegional {
                    let isLavoro = title.uppercased().contains("INFOLAVORI")
                    if isLavoro {
                        let item = NewsItem(title: title, content: content, isUrgent: false, category: "lavoro", date: nil)
                        scrapedItems.append(item)
                    } else {
                        let item = NewsItem(title: title, content: content, isUrgent: true, category: "realtime", date: nil)
                        scrapedItems.append(item)
                    }
                }
            }
            return scrapedItems
            
        } catch {
            print("Errore nello scraping Trenitalia locale: \(error)")
            return []
        }
    }
    
    // MARK: - MIT Scioperi Scraping
    func scrapeMinistero(region: String = "Tutte") async -> [NewsItem] {
        let urlStr = "https://scioperi.mit.gov.it/mit2/public/scioperi"
        guard let url = URL(string: urlStr) else { return [] }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        
        // Parole chiave per filtrare solo trasporti pertinenti
        let transportKeywords = ["ferroviar", "trasporto", "trenitalia", "rfi", "trenord",
                                 "italo", "autobus", "autoferro", "tram", "metro", "ferr"]
        
        // Formatter per confrontare le date
        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(identifier: "it_IT")
        inputFormatter.dateFormat = "dd/MM/yyyy"
        let today = Calendar.current.startOfDay(for: Date())
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let htmlString = String(data: data, encoding: .utf8) else { return [] }
            
            // Struttura per raggruppare per data: [dateStr: (aziende, sindacati, area)]
            struct StrikeGroup {
                var aziende: [String]
                var sindacati: [String]
                var area: String
                var date: Date?
                var dateStr: String
            }
            var groups: [String: StrikeGroup] = [:]
            var dateOrder: [String] = [] // mantiene l'ordine delle date
            
            guard let tbodyStart = htmlString.range(of: "<tbody>"),
                  let tbodyEnd = htmlString.range(of: "</tbody>", range: tbodyStart.upperBound..<htmlString.endIndex) else {
                return []
            }
            
            let tbodyHtml = String(htmlString[tbodyStart.upperBound..<tbodyEnd.lowerBound])
            let rows = tbodyHtml.components(separatedBy: "<tr>")
            
            for rowHtml in rows.dropFirst() {
                let cols = rowHtml.components(separatedBy: "<td")
                var tds: [String] = []
                for colHtml in cols.dropFirst() {
                    if let cs = colHtml.range(of: ">"),
                       let ce = colHtml.range(of: "</td>", range: cs.upperBound..<colHtml.endIndex) {
                        let text = String(colHtml[cs.upperBound..<ce.lowerBound])
                            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                            .components(separatedBy: .whitespacesAndNewlines)
                            .filter { !$0.isEmpty }
                            .joined(separator: " ")
                        tds.append(text)
                    }
                }
                
                guard tds.count >= 4 else { continue }
                
                let dateStr  = tds[0]
                let sindacato = tds[1]
                let azienda  = tds[2]
                let area     = tds[3]
                
                // Filtra per regione: Nazionale vale sempre, regionale solo se matcha
                let areaLower = area.lowercased()
                let regionLower = region.lowercased()
                let isNazionale = areaLower.contains("nazional") || areaLower.isEmpty
                let matchesRegion = region == "Tutte" || isNazionale || areaLower.contains(regionLower)
                guard matchesRegion else { continue }
                let combined = "\(azienda) \(area) \(sindacato)".lowercased()
                let isTransport = transportKeywords.contains { combined.contains($0) }
                guard isTransport else { continue }
                
                // Filtra: solo scioperi da oggi in poi
                if let date = inputFormatter.date(from: dateStr) {
                    let strikeDay = Calendar.current.startOfDay(for: date)
                    guard strikeDay >= today else { continue }
                    
                    // Raggruppa per data
                    if groups[dateStr] == nil {
                        groups[dateStr] = StrikeGroup(aziende: [], sindacati: [], area: area, date: date, dateStr: dateStr)
                        dateOrder.append(dateStr)
                    }
                    if !azienda.isEmpty && !groups[dateStr]!.aziende.contains(azienda) {
                        groups[dateStr]!.aziende.append(azienda)
                    }
                    if !sindacato.isEmpty && !groups[dateStr]!.sindacati.contains(sindacato) {
                        groups[dateStr]!.sindacati.append(sindacato)
                    }
                }
            }
            
            // Costruisci NewsItem raggruppati, ordinati per data
            let sortedDates = dateOrder.sorted {
                let d1 = inputFormatter.date(from: $0) ?? Date.distantFuture
                let d2 = inputFormatter.date(from: $1) ?? Date.distantFuture
                return d1 < d2
            }
            
            var result: [NewsItem] = []
            for dateStr in sortedDates {
                guard let group = groups[dateStr] else { continue }
                
                let aziendaLabel = group.aziende.isEmpty ? "Trasporti" : group.aziende.prefix(2).joined(separator: ", ")
                let title = "Sciopero \(aziendaLabel) — \(dateStr)"
                
                var parts: [String] = []
                if !group.area.isEmpty { parts.append("Settore: \(group.area)") }
                if !group.aziende.isEmpty { parts.append("Operatori: \(group.aziende.joined(separator: ", "))") }
                if !group.sindacati.isEmpty { parts.append("Sindacati: \(group.sindacati.prefix(3).joined(separator: ", "))") }
                let content = parts.joined(separator: "\n")
                
                result.append(NewsItem(title: title, content: content, isUrgent: true, category: "sciopero", date: dateStr))
            }
            
            return result
            
        } catch {
            print("Errore nello scraping Ministero locale: \(error)")
            return []
        }
    }
}

