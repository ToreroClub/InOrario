import Foundation

class LocalScrapingService {
    static let shared = LocalScrapingService()
    
    private init() {}
    
    static func loadReferenceStations() -> [Station] {
        guard let url = Bundle.main.url(forResource: "rfi_stations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([RFIStation].self, from: data) else {
            return []
        }
        return decoded.compactMap { rfi in
            guard rfi.lat != nil, rfi.lon != nil else { return nil }
            return Station(
                name: rfi.name,
                rfiID: rfi.rfiID,
                vtID: rfi.vtID,
                lat: rfi.lat,
                lon: rfi.lon
            )
        }
    }
    
    private func matches(in text: String, regex: String) -> [String] {
        guard let regexObj = try? NSRegularExpression(pattern: regex, options: [.dotMatchesLineSeparators]) else { return [] }
        let nsString = text as NSString
        let results = regexObj.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        return results.map { result in
            if result.numberOfRanges > 1 {
                return nsString.substring(with: result.range(at: 1))
            }
            return nsString.substring(with: result.range)
        }
    }

    private func containsWord(_ word: String, in text: String) -> Bool {
        let cleanWord = word.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "'", with: " ")
        let cleanText = text.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "'", with: " ")
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: cleanWord))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(location: 0, length: (cleanText as NSString).length)
        return regex.firstMatch(in: cleanText, options: [], range: range) != nil
    }

    // MARK: - Trenitalia InfoLavori Scraping
    func scrapeTrenitalia(region: String) async -> [NewsItem] {
        let urlStr = "https://www.trenitalia.com/it/informazioni/Infomobilita/notizie-infomobilita.html"
        guard let url = URL(string: urlStr) else { return [] }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let htmlString = String(data: data, encoding: .utf8) else { return [] }
            
            var scrapedItems: [NewsItem] = []
            var items: [String] = []
            var currentSearchRange = htmlString.startIndex..<htmlString.endIndex
            
            while let match = htmlString.range(of: "<div class=\"accordion-item\"", options: [.caseInsensitive], range: currentSearchRange) {
                let end = htmlString.range(of: "<div class=\"accordion-item\"", options: [.caseInsensitive], range: match.upperBound..<htmlString.endIndex)?.lowerBound ?? htmlString.endIndex
                items.append(String(htmlString[match.lowerBound..<end]))
                currentSearchRange = match.upperBound..<htmlString.endIndex
            }
            
            let regionLower = region.lowercased()
            
            for itemHtml in items {
                let titleMatch = matches(in: itemHtml, regex: "<h3\\s+class=\"infomobility-title\"[^>]*>(.*?)</h3>").first ?? ""
                let title = titleMatch.trimmingCharacters(in: .whitespacesAndNewlines)
                if title.isEmpty { continue }
                
                let tagMatches = matches(in: itemHtml, regex: "<div\\s+class=\"tag-category\\b[^>]*>(.*?)</div>")
                let tags = tagMatches.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " ")
                
                var content = ""
                if let bodyRange = itemHtml.range(of: "class=\"accordion-body\"", options: [.caseInsensitive]) {
                    let rawBody = String(itemHtml[bodyRange.upperBound..<itemHtml.endIndex])
                    let fullContent = rawBody
                        .replacingOccurrences(of: "<br\\s*/?>", with: " ", options: .regularExpression)
                        .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                        .replacingOccurrences(of: "&nbsp;", with: " ")
                        .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
                    
                    // Tronca il testo se troppo lungo (spesso contiene tabelle enormi illeggibili)
                    if fullContent.count > 600 {
                        content = String(fullContent.prefix(600)) + "..."
                    } else {
                        content = fullContent
                    }
                }
                
                let dataRegionMatch = matches(in: itemHtml, regex: "data-region=\"([^\"]+)\"").first ?? ""
                
                var isRegional = false
                if regionLower != "tutte" && !regionLower.isEmpty {
                    if dataRegionMatch == "empty" || dataRegionMatch.contains("nazionale") {
                        isRegional = true
                    } else if dataRegionMatch.contains(regionLower) {
                        isRegional = true
                    } else {
                        isRegional = containsWord(regionLower, in: title) || containsWord(regionLower, in: tags)
                    }
                } else {
                    isRegional = true
                }
                
                if isRegional {
                    let isLavoro = title.uppercased().contains("INFOLAVORI")
                    let typeStr = isLavoro ? "InfoLavori Trenitalia" : "Notizia Realtime Trenitalia"
                    
                    let titleUpper = title.uppercased()
                    let isRegolare = titleUpper.contains("REGOLARE") || titleUpper.contains("RIPRESA") || titleUpper.contains("TORNATA REGOLARE")
                    let isUrgentRealtime = !isRegolare
                    let isUrgentItem = isLavoro ? false : isUrgentRealtime
                    
                    // FORMATO DETERMINISTICO
                    let structuredText = "Tipo: \(typeStr) | Titolo: \(title) | Dettagli: \(content)"
                    let item = NewsItem(title: title, content: structuredText, isUrgent: isUrgentItem, category: isLavoro ? "lavoro" : "realtime", date: nil)
                    scrapedItems.append(item)
                }
            }
            return scrapedItems
        } catch {
            print("Errore nello scraping Trenitalia locale: \(error)")
            return []
        }
    }
    
    // MARK: - MIT Scioperi Scraping (via RSS)
    func scrapeMinistero(region: String = "Tutte") async -> [NewsItem] {
        let urlStr = "https://scioperi.mit.gov.it/mit2/public/scioperi/rss"
        guard let url = URL(string: urlStr) else { return [] }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let parser = XMLParser(data: data)
            let delegate = MITRSSParser(region: region)
            parser.delegate = delegate
            parser.parse()
            return delegate.parsedItems
        } catch {
            print("Errore nello scraping Ministero RSS: \(error)")
            return []
        }
    }
}

// MARK: - RSS XML Parser Delegate
class MITRSSParser: NSObject, XMLParserDelegate {
    private let targetRegion: String
    private var currentElement = ""
    private var currentTitle = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var isInsideItem = false
    var parsedItems: [NewsItem] = []
    
    // Parole chiave trasporti
    private let transportKeywords = ["ferroviar", "trasporto", "trenitalia", "rfi", "trenord",
                                     "italo", "autobus", "autoferro", "tram", "metro", "ferr"]
    
    // Formatter date
    private let rssDateFormatter = DateFormatter()
    private let outDateFormatter = DateFormatter()
    
    init(region: String) {
        self.targetRegion = region.lowercased()
        rssDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        rssDateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        outDateFormatter.locale = Locale(identifier: "it_IT")
        outDateFormatter.dateFormat = "dd/MM/yyyy"
        super.init()
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            isInsideItem = true
            currentTitle = ""
            currentDescription = ""
            currentPubDate = ""
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideItem {
            if currentElement == "title" {
                currentTitle += string
            } else if currentElement == "description" {
                currentDescription += string
            } else if currentElement == "pubDate" {
                currentPubDate += string
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if isInsideItem && currentElement == "description" {
            if let str = String(data: CDATABlock, encoding: .utf8) {
                currentDescription += str
            }
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            isInsideItem = false
            
            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let descRaw = currentDescription
                .replacingOccurrences(of: "<br\\s*/?>", with: " | ", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            
            // Filtro Trasporti
            let combined = (title + " " + descRaw).lowercased()
            let isTransport = transportKeywords.contains { combined.contains($0) }
            guard isTransport else { return }
            
            // Filtro Esclusione (es. appalti, ristorazione a bordo, pulizie)
            let excludeKeywords = ["appalti", "ristorazione", "pulizie", "merci", "logistica"]
            let isExcluded = excludeKeywords.contains { combined.contains($0) }
            guard !isExcluded else { return }
            
            // Filtro Regione (cerca "Regione:" nel title o description)
            var isRegional = false
            if targetRegion == "tutte" || combined.contains("nazionale") {
                isRegional = true
            } else if combined.contains(targetRegion) {
                isRegional = true
            }
            guard isRegional else { return }
            
            // Estrai data inizio dal titolo: "Data inizio: 10/07/2026 -"
            var scioperoDateStr = ""
            if let match = title.range(of: "Data inizio: (\\d{2}/\\d{2}/\\d{4})", options: .regularExpression) {
                let s = String(title[match])
                scioperoDateStr = s.replacingOccurrences(of: "Data inizio: ", with: "")
            }
            
            let structuredText = "Tipo: Sciopero | Dettagli: \(title) | Note: \(descRaw)"
            
            var isUrgentStrike = false
            if !scioperoDateStr.isEmpty, let strikeDate = outDateFormatter.date(from: scioperoDateStr) {
                let today = Calendar.current.startOfDay(for: Date())
                let strikeDay = Calendar.current.startOfDay(for: strikeDate)
                if let diff = Calendar.current.dateComponents([.day], from: today, to: strikeDay).day {
                    isUrgentStrike = diff >= 0 && diff <= 10
                }
            }
            
            let item = NewsItem(title: title, content: structuredText, isUrgent: isUrgentStrike, category: "sciopero", date: scioperoDateStr.isEmpty ? nil : scioperoDateStr)
            parsedItems.append(item)
        }
    }

}
