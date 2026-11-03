import Foundation

@MainActor
class AIEngine {
    static let shared = AIEngine()
    
    private var provider: SLMProvider?
    
    private init() {
        updateProvider()
    }
    
    private func updateProvider() {
        if AIFeatureManager.shared.isAppleIntelligenceSelected {
            if #available(iOS 26.0, *) {
                self.provider = AppleFoundationModelProvider()
                return
            }
        }
        self.provider = LocalSLMService.shared
    }
    
    func initializeIfNeeded() async -> Bool {
        updateProvider()
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
            if raw.category == "realtime" || raw.category == "lavoro" {
                result.append(raw)
                continue
            }
            let userRegion = UserDefaults.standard.string(forKey: "strikeRegion_v1") ?? "Tutte"
            let contextualContent = "Regione di interesse: \(userRegion). Estrai e riassumi SOLO le informazioni pertinenti a questa regione, ignorando il resto.\n\n\(raw.content)"
            let cleaned = await provider.generateSummary(for: contextualContent)
            let finalContent = (cleaned.isEmpty || cleaned == contextualContent) ? raw.content : cleaned
            result.append(NewsItem(
                title: raw.title,
                content: finalContent,
                isUrgent: raw.isUrgent,
                category: raw.category,
                date: raw.date
            ))
        }
        return result
    }
}
