import Foundation

@MainActor
class AIEngine {
    static let shared = AIEngine()
    
    private var provider: SLMProvider?
    
    private init() {
        if #available(iOS 26.0, *) {
            let appleProvider = AppleFoundationModelProvider()
            // Se Apple Intelligence è disponibile, usa quello, altrimenti fallback su Llama
            if appleProvider.isAvailable {
                self.provider = appleProvider
            } else {
                self.provider = LocalSLMService.shared
            }
        } else {
            self.provider = LocalSLMService.shared
        }
    }
    
    func initializeIfNeeded() async -> Bool {
        guard let provider = provider else { return false }
        if !provider.isAvailable {
            return await provider.initializeModel()
        }
        return true
    }
    
    func formatWithLocalModel(rawItems: [NewsItem]) async -> [NewsItem] {
        _ = await initializeIfNeeded()
        
        guard let provider = provider, provider.isAvailable else {
            print("[-] AIEngine: Nessun provider pronto, fallback dati grezzi.")
            return rawItems
        }
        
        var result: [NewsItem] = []
        for raw in rawItems {
            if raw.category == "realtime" {
                result.append(raw)
                continue
            }
            let userRegion = UserDefaults.standard.string(forKey: "strikeRegion_v1") ?? "Tutte"
            let contextualContent = "Regione di interesse: \(userRegion). Estrai e riassumi SOLO le informazioni pertinenti a questa regione, ignorando il resto.\n\n\(raw.content)"
            let cleaned = await provider.generateSummary(for: contextualContent)
            result.append(NewsItem(
                title: raw.title,
                content: cleaned,
                isUrgent: raw.isUrgent,
                category: raw.category,
                date: raw.date
            ))
        }
        return result
    }
}
