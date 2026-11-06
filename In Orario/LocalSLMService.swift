import Foundation

/// Stub di LocalSLMService senza dipendenza da llama.cpp.
/// Il modello locale è stato rimosso: questa implementazione fa fallback
/// diretto ai dati originali, lasciando che AIEngine usi AppleFoundationModelProvider.
class LocalSLMService: SLMProvider {
    static let shared = LocalSLMService()

    var isAvailable: Bool { false }

    private init() {}

    func initializeModel() async -> Bool { false }

    func generateSummary(for text: String) async -> String { text }

    func formatWithLocalModel(rawItems: [NewsItem]) async -> [NewsItem] { rawItems }

    // MARK: - Analisi Ritardi (rule-based, istantanea)

    /// Genera una breve descrizione testuale del ritardo di un treno.
    /// Non richiede il modello AI installato — è rule-based e istantanea.
    static func analyzeDelay(minutes: Int, isCancelled: Bool, trainNumber: String) -> String {
        guard UserDefaults.standard.bool(forKey: "ai_delayPredictionEnabled") else { return "" }

        if isCancelled {
            return "Il treno \(trainNumber) risulta soppresso. Si consiglia di verificare percorsi alternativi o treni successivi sulla stessa tratta."
        }

        switch minutes {
        case 0:
            return ""
        case 1...4:
            return "Ritardo lieve di \(minutes) minuti. Nella norma per le percorrenze regionali."
        case 5...9:
            return "Ritardo di \(minutes) minuti. Potrebbe impattare coincidenze ravvicinate con metro o altri treni."
        case 10...19:
            return "Ritardo di \(minutes) minuti. Verifica le coincidenze previste: potrebbe essere necessario prendere il collegamento successivo."
        case 20...29:
            return "Ritardo significativo: \(minutes) minuti. Probabile impatto su coincidenze. Considera percorsi alternativi se hai urgenza."
        case 30...59:
            return "Ritardo elevato: \(minutes) minuti. Si consiglia di verificare aggiornamenti ufficiali RFI e valutare percorsi alternativi."
        default:
            return "Ritardo critico: oltre \(minutes) minuti. Situazione anomala — verifica comunicazioni ufficiali RFI per aggiornamenti sul servizio."
        }
    }
}
