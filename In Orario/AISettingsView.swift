import SwiftUI

struct AISettingsView: View {
    @ObservedObject private var aiManager = AIFeatureManager.shared
    @EnvironmentObject var manager: TrainManager
    @AppStorage("ai_smartSummaryEnabled") private var smartSummaryEnabled: Bool = true
    @AppStorage("ai_routeSuggestionsEnabled") private var routeSuggestionsEnabled: Bool = false
    @State private var showRemoveConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                
                AIModelSelectorView(isOnboarding: false)
                    .environmentObject(manager)

                // MARK: - Funzionalità AI
                VStack(spacing: 16) {
                    Text("Funzionalità AI")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("Le funzionalità AI usano il motore selezionato (Cloud o Locale) per arricchire la tua esperienza.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Riepilogo Scioperi
                    Toggle(isOn: $smartSummaryEnabled) {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.red.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "megaphone.fill")
                                    .foregroundColor(.red)
                                    .font(.subheadline)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Riepilogo Scioperi")
                                    .font(.subheadline.bold())
                                Text("Usa l'AI per sintetizzare e formattare le notizie sugli scioperi")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .tint(.red)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)

                    // Suggerimenti Percorso
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.green.opacity(0.08))
                                .frame(width: 36, height: 36)
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundColor(.green.opacity(0.5))
                                .font(.subheadline)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Suggerimenti Percorso")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.secondary)
                                Text("Prossimamente")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.gray)
                                    .cornerRadius(6)
                            }
                            Text("Suggerirà percorsi alternativi in caso di cancellazioni o ritardi")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "lock.fill")
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)
                    .opacity(0.5)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationTitle("Assistente IA")
        .navigationBarTitleDisplayMode(.large)
    }
}
