import Foundation
import os

/// Logger centralizzato, sicuro ed essenziale con ring buffer in memoria per diagnostica e feedback.
/// Può essere attivato o disattivato a runtime tramite `AppLogger.setEnabled(Bool)` o `AppLogger.isEnabled`.
/// Conforme alle linee guida di privacy: NON logga token APNs, header di autenticazione o dati personali dell'utente.
public struct AppLogger {
    /// Flag di attivazione globale per i log estesi di debug.
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
    
    // Buffer circolare thread-safe in memoria degli ultimi eventi/errori per diagnostica e bug report
    private final class RingLogBuffer: @unchecked Sendable {
        static let shared = RingLogBuffer()
        private let lock = NSLock()
        private var buffer: [String] = []
        private let maxEntries = 80
        private let dateFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "HH:mm:ss"
            df.locale = Locale(identifier: "it_IT")
            return df
        }()
        
        func append(category: String, level: String, message: String) {
            let timestamp = dateFormatter.string(from: Date())
            let line = "[\(timestamp)] [\(category)] [\(level)] \(message)"
            lock.lock()
            defer { lock.unlock() }
            buffer.append(line)
            if buffer.count > maxEntries {
                buffer.removeFirst(buffer.count - maxEntries)
            }
        }
        
        func getLogs(limit: Int = 50) -> String {
            lock.lock()
            defer { lock.unlock() }
            if buffer.isEmpty {
                return "Nessun errore o log anomalo riscontrato di recente."
            }
            let slice = buffer.suffix(limit)
            return slice.joined(separator: "\n")
        }
        
        func clear() {
            lock.lock()
            defer { lock.unlock() }
            buffer.removeAll()
        }
    }
    
    public nonisolated static func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "debug_logging_enabled")
    }
    
    /// Restituisce la cronologia formattata degli ultimi log ed errori registrati dall'app per allegarli alle segnalazioni.
    public nonisolated static func getRecentLogs(limit: Int = 50) -> String {
        return RingLogBuffer.shared.getLogs(limit: limit)
    }
    
    public nonisolated static func clearLogs() {
        RingLogBuffer.shared.clear()
    }
    
    // MARK: - 1. Durata delle chiamate
    
    public nonisolated static func duration(method: String = "GET", endpoint: String, statusCode: Int, durationMs: Int) {
        if statusCode >= 400 {
            RingLogBuffer.shared.append(category: "Network", level: "HTTP \(statusCode)", message: "\(method) \(endpoint) in \(durationMs)ms")
        }
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
        RingLogBuffer.shared.append(category: "Decoding", level: "ERROR", message: "[\(context)]: \(error.localizedDescription)")
        guard isEnabled else { return }
        appLogger.error("⚠️ Errore di decodifica [\(context)]: \(error.localizedDescription)")
    }
    
    // MARK: - 4. Fallimenti di refresh
    
    public nonisolated static func refreshFailed(target: String, error: Error? = nil) {
        let msg = error != nil ? "[\(target)]: \(error!.localizedDescription)" : "[\(target)]: risposta vuota o non valida"
        RingLogBuffer.shared.append(category: "Refresh", level: "ERROR", message: msg)
        guard isEnabled else { return }
        if let err = error {
            appLogger.error("❌ Fallimento refresh [\(target)]: \(err.localizedDescription)")
        } else {
            appLogger.error("❌ Fallimento refresh [\(target)]: risposta vuota o non valida")
        }
    }
    
    // MARK: - Generic Logging
    
    public nonisolated static func network(_ message: String) {
        if message.lowercased().contains("error") || message.lowercased().contains("timeout") || message.lowercased().contains("fail") {
            RingLogBuffer.shared.append(category: "Network", level: "WARN", message: message)
        }
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
        RingLogBuffer.shared.append(category: "App", level: "ERROR", message: message)
        guard isEnabled else { return }
        appLogger.error("❌ \(message)")
    }
}
