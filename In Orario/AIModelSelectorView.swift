import SwiftUI
import StoreKit

// MARK: - AIModelSelectorView
// Usata sia in onboarding che in impostazioni

struct AIModelSelectorView: View {
    @ObservedObject var aiManager = AIFeatureManager.shared
    @EnvironmentObject var manager: TrainManager
    
    var isOnboarding: Bool = false
    var onFinish: (() -> Void)? = nil
    
    @State private var showPaywallSheet = false
    
    var body: some View {
        VStack(spacing: 16) {
            
            // Opzione 1: Nessuna IA
            AIOptionCard(
                icon: "xmark.circle",
                iconColor: .gray,
                title: "Senza IA",
                description: "Nessuna elaborazione automatica degli scioperi.",
                isSelected: aiManager.aiModeChoice == .none,
                isDisabled: false,
                badgeText: nil
            ) {
                Haptics.play(.light)
                aiManager.aiModeChoice = .none
                aiManager.preferLocalAI = false
            }
            
            // Opzione 2: Apple Intelligence (Locale)
            VStack(alignment: .leading, spacing: 6) {
                AIOptionCard(
                    icon: "applelogo",
                    iconColor: .primary,
                    title: "Apple Intelligence",
                    description: "Sfrutta l'IA integrata nel tuo dispositivo senza inviare dati all'esterno.",
                    isSelected: aiManager.aiModeChoice == .local,
                    isDisabled: !aiManager.isAppleIntelligenceAvailable,
                    badgeText: aiManager.isAppleIntelligenceAvailable ? "Incluso in iOS" : "Non supportato"
                ) {
                    if aiManager.isAppleIntelligenceAvailable {
                        Haptics.play(.medium)
                        aiManager.aiModeChoice = .local
                        aiManager.selectedModelID = "apple_intelligence"
                        aiManager.preferLocalAI = true
                    }
                }
                
                if !aiManager.isAppleIntelligenceAvailable {
                    Text("Apple Intelligence richiede un dispositivo Apple compatibile ed una versione di iOS supportata.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                }
            }
            
            // Opzione 3: Cloud InOrario
            AIOptionCard(
                icon: "cloud.fill",
                iconColor: .blue,
                title: "Cloud In Orario",
                description: "Elaborazione istantanea ed avanzata sui server dedicati di In Orario.",
                isSelected: aiManager.aiModeChoice == .cloud,
                isDisabled: false,
                badgeText: manager.hasSupport() ? "Attivo" : "Sostenitori"
            ) {
                if manager.hasSupport() {
                    Haptics.play(.medium)
                    aiManager.aiModeChoice = .cloud
                    aiManager.preferLocalAI = false
                } else {
                    Haptics.play(.light)
                    showPaywallSheet = true
                }
            }
            
            // Pulsante continua (solo in onboarding se gestito esternamente)
            if isOnboarding, let onFinish = onFinish {
                Button(action: {
                    onFinish()
                }) {
                    Text("Continua")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.indigo)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .padding(.top, 8)
            }
            
        }
        .padding(.horizontal, 20)
        .onAppear {
            setupDefaultSelection()
        }
        .sheet(isPresented: $showPaywallSheet) {
            SupportPaywallSheet()
                .environmentObject(manager)
        }
        .navigationTitle(isOnboarding ? "" : "Modello AI")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func setupDefaultSelection() {
        // Se l'utente non ha il supporto ed era impostato su Cloud, reimpostiamo il default
        if aiManager.aiModeChoice == .cloud && !manager.hasSupport() {
            if aiManager.isAppleIntelligenceAvailable {
                aiManager.aiModeChoice = .local
                aiManager.selectedModelID = "apple_intelligence"
                aiManager.preferLocalAI = true
            } else {
                aiManager.aiModeChoice = .none
                aiManager.preferLocalAI = false
            }
            return
        }
        
        // Se l'hardware supporta Apple Intelligence e non è stato ancora configurato Cloud, auto-selezioniamo Apple Intelligence
        if aiManager.isAppleIntelligenceAvailable {
            if aiManager.aiModeChoice == .local || aiManager.selectedModelID.starts(with: "qwen") {
                aiManager.aiModeChoice = .local
                aiManager.selectedModelID = "apple_intelligence"
                aiManager.preferLocalAI = true
            }
        } else {
            // Se Apple Intelligence non è disponibile, reset a Nessuna IA
            if aiManager.aiModeChoice == .local {
                aiManager.aiModeChoice = .none
                aiManager.preferLocalAI = false
            }
        }
    }
}

// MARK: - AIOptionCard

private struct AIOptionCard: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let isSelected: Bool
    let isDisabled: Bool
    let badgeText: LocalizedStringKey?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Cerchio radio a sinistra
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? iconColor : .secondary)
                    .padding(.top, 2)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title).font(.headline)
                            .foregroundColor(isDisabled ? .secondary : .primary)
                        if let badge = badgeText {
                            Text(badge)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isDisabled ? Color.gray.opacity(0.12) : Color.blue.opacity(0.12))
                                .foregroundColor(isDisabled ? .secondary : .blue)
                                .cornerRadius(6)
                        }
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? iconColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
    }
}

// MARK: - SupportPaywallSheet

struct SupportPaywallSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var aiManager = AIFeatureManager.shared
    @EnvironmentObject var manager: TrainManager
    @StateObject private var tipManager = TipManager()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 76, height: 76)
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 38))
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 16)
                    
                    Text("Cloud InOrario")
                        .font(.title2.bold())
                    
                    Text("L'elaborazione Cloud è riservata a chi sostiene il progetto In Orario per coprire i costi dei server di calcolo.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                
                // Vantaggi
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.yellow)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Risposte Istantanee & Chiare")
                                .font(.subheadline.bold())
                            Text("Sintesi automatica degli scioperi elaborata in tempo reale.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sostieni il Progetto")
                                .font(.subheadline.bold())
                            Text("Aiuta un singolo sviluppatore a mantenere l'app sempre attiva.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Image(systemName: "nosign")
                            .foregroundColor(.green)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Senza Pubblicità")
                                .font(.subheadline.bold())
                            Text("L'app è e rimarrà sempre senza alcun banner o tracciamento.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Opzioni di acquisto
                if tipManager.isLoadingProducts {
                    ProgressView("Caricamento offerte...")
                        .padding()
                } else if tipManager.products.isEmpty {
                    Text("Le offerte donazione non sono al momento disponibili.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(tipManager.products, id: \.id) { product in
                        Button(action: {
                            Task {
                                await tipManager.purchase(product)
                                if manager.hasSupport() {
                                    aiManager.aiModeChoice = .cloud
                                    aiManager.preferLocalAI = false
                                    dismiss()
                                }
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Sostieni & Attiva Cloud")
                                        .font(.headline)
                                    Text("Offri una Colazione Pendolare 🥐")
                                        .font(.caption)
                                        .opacity(0.9)
                                }
                                Spacer()
                                if tipManager.purchaseState == .purchasing {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(product.displayPrice)
                                        .font(.title3.bold())
                                }
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                        }
                        .disabled(tipManager.purchaseState == .purchasing)
                        .padding(.horizontal, 20)
                    }
                }
                
                Button("Ripristina Acquisti") {
                    Haptics.play(.medium)
                    Task {
                        do {
                            try await AppStore.sync()
                            await tipManager.updatePurchases()
                            if manager.hasSupport() {
                                aiManager.aiModeChoice = .cloud
                                aiManager.preferLocalAI = false
                                dismiss()
                            }
                        } catch {
                            print("Errore ripristino acquisti: \(error)")
                        }
                    }
                }
                .font(.subheadline)
                .foregroundColor(.blue)
                .padding(.bottom, 16)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") {
                        dismiss()
                    }
                    .font(.body.bold())
                }
            }
            .task {
                await tipManager.fetchProducts()
            }
            .alert("Grazie di cuore! ❤️", isPresented: Binding(
                get: { tipManager.purchaseState == .success },
                set: { if !$0 { tipManager.resetState() } }
            )) {
                Button("Prego!", role: .cancel) {
                    if manager.hasSupport() {
                        aiManager.aiModeChoice = .cloud
                        aiManager.preferLocalAI = false
                        dismiss()
                    }
                }
            } message: {
                Text("La modalità Cloud InOrario è stata attivata con successo.")
            }
            .alert("Errore Acquisto", isPresented: Binding(
                get: {
                    if case .error = tipManager.purchaseState { return true }
                    return false
                },
                set: { if !$0 { tipManager.resetState() } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                if case .error(let msg) = tipManager.purchaseState {
                    Text(msg)
                }
            }
        }
    }
}

// MARK: - SpaceAlertBannerView (Compatibilità)

struct SpaceAlertBannerView: View {
    var body: some View {
        EmptyView()
    }
}
