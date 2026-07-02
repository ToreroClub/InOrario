import SwiftUI

struct AISettingsView: View {
    @ObservedObject private var aiManager = AIFeatureManager.shared
    @EnvironmentObject var manager: TrainManager
    @AppStorage("ai_smartSummaryEnabled") private var smartSummaryEnabled: Bool = true
    @AppStorage("ai_routeSuggestionsEnabled") private var routeSuggestionsEnabled: Bool = false
    @State private var showRemoveConfirm = false

    var body: some View {
        List {

            // MARK: - Stato Motore AI
            Section(header: Text("Motore AI"), footer: Text(engineFooter)) {
                // Cloud (Premium)
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "cloud.fill")
                            .foregroundColor(.blue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cloud In Orario")
                            .font(.headline)
                        Text("Elaborazione istantanea sul server")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !aiManager.preferLocalAI && manager.hasSupport() {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    } else if !manager.hasSupport() {
                        Text("Premium")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange)
                            .cornerRadius(8)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if manager.hasSupport() {
                        Haptics.play(.medium)
                        aiManager.preferLocalAI = false
                    }
                }
                .opacity(manager.hasSupport() ? 1.0 : 0.6)

                // Locale
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.indigo.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "cpu")
                            .foregroundColor(.indigo)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Modello IA Locale (Qwen 0.5B)")
                            .font(.headline)
                        Text(aiManager.isLocalModelInstalled ? "Installato · Gratis per tutti" : "Non installato · Gratis per tutti")
                            .font(.caption)
                            .foregroundColor(aiManager.isLocalModelInstalled ? .green : .secondary)
                    }
                    Spacer()
                    if aiManager.preferLocalAI || !manager.hasSupport() {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.indigo)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptics.play(.medium)
                    aiManager.preferLocalAI = true
                }
            }

            // MARK: - Gestione Modello Locale
            if aiManager.isHardwareCompatible {
                Section(header: Text("Modello Locale"), footer: Text("Il modello Qwen 2.5 0.5B Instruct (Q4_K_M) è ottimizzato per dispositivi Apple Silicon. Occupa circa 320 MB di spazio.")) {

                    if aiManager.isDownloadingModel {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Download in corso...", systemImage: "arrow.down.circle.fill")
                                    .foregroundColor(.indigo)
                                    .font(.subheadline.bold())
                                Spacer()
                                Text("\(Int(aiManager.downloadProgress * 100))%")
                                    .font(.caption.bold())
                                    .foregroundColor(.indigo)
                            }
                            ProgressView(value: aiManager.downloadProgress)
                                .tint(.indigo)
                            Button(action: { aiManager.cancelDownload() }) {
                                Label("Annulla Download", systemImage: "xmark.circle")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    } else if aiManager.isLocalModelInstalled {
                        HStack {
                            Label("Modello installato", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.subheadline.bold())
                            Spacer()
                            Text("~320 MB")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Button(role: .destructive, action: {
                            showRemoveConfirm = true
                        }) {
                            Label("Rimuovi Modello (Libera 320 MB)", systemImage: "trash")
                        }
                        .confirmationDialog("Sei sicuro di voler rimuovere il modello AI locale?", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
                            Button("Rimuovi", role: .destructive) {
                                Haptics.play(.medium)
                                aiManager.removeLocalModel()
                                aiManager.preferLocalAI = false
                            }
                            Button("Annulla", role: .cancel) {}
                        }
                    } else {
                        Button(action: {
                            Haptics.play(.medium)
                            aiManager.downloadLocalModel()
                        }) {
                            Label("Scarica Modello AI Locale (320 MB)", systemImage: "arrow.down.circle.fill")
                                .foregroundColor(.indigo)
                                .font(.subheadline.bold())
                        }
                    }
                }
            } else {
                Section(header: Text("Modello Locale")) {
                    Label("Dispositivo non compatibile (richiesti ≥ 6 GB RAM)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                }
            }

            // MARK: - Funzionalità AI
            Section(header: Text("Funzionalità AI"), footer: Text("Le funzionalità AI usano il motore selezionato (Cloud o Locale) per arricchire la tua esperienza.")) {

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
                            Text("Usa l'AI per sintetizzare e formattare le notizie sugli scioperi nella scheda News")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .tint(.red)

                // Suggerimenti Percorso (prossimamente)
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
                        Text("Suggerirà percorsi alternativi in caso di cancellazioni o ritardi rilevanti")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "lock.fill")
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .opacity(0.5)
            }

            // MARK: - Upgrade (solo per utenti free)
            if !manager.hasSupport() {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "cloud.bolt.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sblocca Cloud In Orario")
                                    .font(.headline)
                                Text("Offri un caffè per spostare tutta l'elaborazione AI sul server: zero batteria, zero attesa.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Intelligenza Artificiale")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if !manager.hasSupport() {
                aiManager.preferLocalAI = true
            }
        }
    }

    private var engineFooter: String {
        if !manager.hasSupport() {
            return "Stai usando il Modello IA Locale gratuito. Offri un caffè nelle Impostazioni per sbloccare il Cloud."
        } else if aiManager.preferLocalAI {
            return "L'elaborazione avviene direttamente sul dispositivo, senza passare per il server."
        } else {
            return "L'elaborazione avviene sul server Cloud In Orario."
        }
    }
}
