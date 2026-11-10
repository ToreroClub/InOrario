import SwiftUI
import Combine

// MARK: - Modello Risposta Sviluppatore

public struct DeveloperReply: Codable, Identifiable, Equatable {
    public var id: String { feedback_id.isEmpty ? UUID().uuidString : feedback_id }
    public let feedback_id: String
    public let title: String
    public let message: String
    public let timestamp: String
    
    public init(feedback_id: String, title: String, message: String, timestamp: String) {
        self.feedback_id = feedback_id
        self.title = title
        self.message = message
        self.timestamp = timestamp
    }
}

// MARK: - Manager Centralizzato

@MainActor
public class DeveloperReplyManager: ObservableObject {
    public static let shared = DeveloperReplyManager()
    
    @Published public var activeReply: DeveloperReply? = nil
    @Published public var showReplyModal: Bool = false
    
    private let lastReplyKey = "last_developer_reply_v1"
    
    private init() {
        // Carica eventuale messaggio non letto salvato
        if let data = UserDefaults.standard.data(forKey: lastReplyKey),
           let saved = try? JSONDecoder().decode(DeveloperReply.self, from: data) {
            // Se c'è un messaggio pendente non mostrato, può essere recuperato se desiderato
            _ = saved
        }
    }
    
    /// Chiamato quando arriva una notifica push remota con category o type developer_reply
    public func handleIncomingReply(userInfo: [AnyHashable: Any], title: String, body: String) {
        let fbId = (userInfo["feedback_id"] as? String) ?? ""
        let finalTitle = (userInfo["title"] as? String) ?? (title.isEmpty ? "Risposta dallo sviluppatore 💬" : title)
        let finalMessage = (userInfo["message"] as? String) ?? (body.isEmpty ? "Abbiamo ricevuto il tuo feedback. Grazie per la collaborazione!" : body)
        let ts = (userInfo["timestamp"] as? String) ?? ISO8601DateFormatter().string(from: Date())
        
        let reply = DeveloperReply(
            feedback_id: fbId,
            title: finalTitle,
            message: finalMessage,
            timestamp: ts
        )
        
        self.activeReply = reply
        self.showReplyModal = true
        
        // Salvataggio persistente in UserDefaults
        if let data = try? JSONEncoder().encode(reply) {
            UserDefaults.standard.set(data, forKey: lastReplyKey)
        }
        
        Haptics.notify(.success)
    }
    
    public func dismiss() {
        self.showReplyModal = false
    }
}

// MARK: - Scheda Modale In-App Risposta Sviluppatore

struct DeveloperReplySheet: View {
    @Environment(\.dismiss) var dismiss
    let reply: DeveloperReply
    
    private var formattedDate: String {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: reply.timestamp) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            df.locale = Locale(identifier: "it_IT")
            return df.string(from: date)
        }
        return ""
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    // Header Icon
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 80, height: 80)
                            .shadow(color: Color.blue.opacity(0.35), radius: 12, x: 0, y: 6)
                        
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 16)
                    
                    // Titolo e sottotitolo
                    VStack(spacing: 6) {
                        Text(reply.title)
                            .font(.title2)
                            .bold()
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text("Team di Sviluppo In Orario")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if !formattedDate.isEmpty {
                                Text("• \(formattedDate)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Box messaggio dello sviluppatore
                    VStack(alignment: .leading, spacing: 12) {
                        Text(reply.message)
                            .font(.body)
                            .lineSpacing(4)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
                    
                    // Info assistenza
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Questa risposta è stata inviata direttamente al tuo dispositivo in riferimento al tuo feedback.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                    
                    Spacer(minLength: 16)
                    
                    // Pulsanti azione
                    VStack(spacing: 10) {
                        Button(action: {
                            Haptics.play(.medium)
                            dismiss()
                        }) {
                            Text("Ho capito, grazie! ❤️")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.blue)
                                .cornerRadius(14)
                        }
                        
                        if let mailURL = URL(string: "mailto:info@toreroclub.com?subject=Re:%20Risposta%20Feedback%20In%20Orario") {
                            Link(destination: mailURL) {
                                HStack {
                                    Image(systemName: "envelope.fill")
                                    Text("Rispondi via email")
                                }
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 6)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
