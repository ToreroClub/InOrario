import Foundation
import os

/// Logger centralizzato, sicuro ed essenziale.
/// Può essere attivato o disattivato a runtime tramite `AppLogger.setEnabled(Bool)` o `AppLogger.isEnabled`.
/// Conforme alle linee guida di privacy: NON logga token APNs, header di autenticazione o dati personali dell'utente.
public struct AppLogger {
    /// Flag di attivazione globale. Abilitato di default in DEBUG, oppure impostabile tramite UserDefaults.
    public static var isEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "debug_logging_enabled")
        #endif
    }()
    
    private static let subsystem = Bundle.main.bundleIdentifier ?? "carlo.InOrario"
    private static let netLogger = Logger(subsystem: subsystem, category: "Network")
    private static let cacheLogger = Logger(subsystem: subsystem, category: "Cache")
    private static let appLogger = Logger(subsystem: subsystem, category: "App")
    
    public nonisolated static func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "debug_logging_enabled")
    }
    
    // MARK: - 1. Durata delle chiamate
    
    public nonisolated static func duration(method: String = "GET", endpoint: String, statusCode: Int, durationMs: Int) {
        guard isEnabled else { return }
        netLogger.debug("⏱️ [\(statusCode)] \(method) \(endpoint) in \(durationMs)ms")
    }
    
    // MARK: - 2. Richieste duplicate evitate (deduplicazione)
    
    public nonisolated static func duplicateAvoided(key: String) {
        guard isEnabled else { return }
        cacheLogger.debug("🔁 Richiesta duplicata evitata (deduplicata in-flight): \(key)")
    }
    
    // MARK: - 3. Errori di decoding
    
    public nonisolated static func decodingError(context: String, error: Error) {
        guard isEnabled else { return }
        appLogger.error("⚠️ Errore di decodifica [\(context)]: \(error.localizedDescription)")
    }
    
    // MARK: - 4. Fallimenti di refresh
    
    public nonisolated static func refreshFailed(target: String, error: Error? = nil) {
        guard isEnabled else { return }
        if let err = error {
            appLogger.error("❌ Fallimento refresh [\(target)]: \(err.localizedDescription)")
        } else {
            appLogger.error("❌ Fallimento refresh [\(target)]: risposta vuota o non valida")
        }
    }
    
    // MARK: - Generic Logging
    
    public nonisolated static func network(_ message: String) {
        guard isEnabled else { return }
        netLogger.debug("🌐 \(message)")
    }
    
    public nonisolated static func cache(_ message: String) {
        guard isEnabled else { return }
        cacheLogger.debug("📦 \(message)")
    }
    
    public nonisolated static func info(_ message: String) {
        guard isEnabled else { return }
        appLogger.info("ℹ️ \(message)")
    }
    
    public nonisolated static func error(_ message: String) {
        guard isEnabled else { return }
        appLogger.error("❌ \(message)")
    }
}
