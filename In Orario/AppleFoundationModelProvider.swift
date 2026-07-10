import Foundation
// Framework introdotto a partire da iOS 26 per accedere ad Apple Intelligence
#if canImport(FoundationModels)
import FoundationModels
#endif

@available(iOS 26.0, *)
class AppleFoundationModelProvider: SLMProvider {
    
    // Su iOS 26, si usa il framework FoundationModels per verificare la disponibilità.
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
        #else
        return false
        #endif
    }
    
    func initializeModel() async -> Bool {
        // Il modello di Apple non richiede allocazione manuale di RAM o GGUF,
        // è sempre gestito dal sistema operativo (daemons in background).
        print("[+] AppleFoundationModelProvider inizializzato.")
        return true
    }
    
    func generateSummary(for text: String) async -> String {
        #if canImport(FoundationModels)
        // Esempio di implementazione con l'API FoundationModels di Apple (iOS 26+).
        // Il framework gestisce l'inferenza nativamente sul Neural Engine senza scaricare modelli.
        
        let prompt = """
        Sei un assistente che riassume notizie ferroviarie italiane in 1-2 frasi chiare e dirette. Rispondi solo con il riassunto, senza prefissi o spiegazioni.
        Notizia: \(text)
        Riassunto:
        """
        
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            print("[+] Inferenza tramite Apple Foundation Model completata.")
            return response.content
        } catch {
            print("Errore inferenza Apple Foundation Model: \(error)")
            return text
        }
        #else
        return text
        #endif
    }
}
