import Foundation

/// Protocollo per nascondere i dettagli di implementazione del modello linguistico.
protocol SLMProvider {
    /// Indica se il provider è attualmente disponibile ed inizializzato.
    var isAvailable: Bool { get }
    
    /// Inizializza il modello (es. carica in RAM, prepara il contesto).
    func initializeModel() async -> Bool
    
    /// Genera un testo elaborato a partire da un prompt.
    func generateSummary(for text: String) async -> String
}
