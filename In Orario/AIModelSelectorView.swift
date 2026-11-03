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
    @State private var showCloudPaidBanner = false
    
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
                showCloudPaidBanner = false
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
                        showCloudPaidBanner = false
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
            VStack(alignment: .leading, spacing: 8) {
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
                        showCloudPaidBanner = false
                    } else {
                        Haptics.play(.light)
                        withAnimation {
                            showCloudPaidBanner = true
                        }
                        showPaywallSheet = true
                    }
                }
                
                if showCloudPaidBanner && !manager.hasSupport() {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text("IA Cloud a pagamento")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                        }
                        
                        Text("L'elaborazione tramite server Cloud è riservata a chi sostiene il progetto In Orario per coprire i costi di calcolo.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            showPaywallSheet = true
                        }) {
                            HStack {
                                Text("Sostieni il progetto per sbloccare")
                                    .font(.caption.bold())
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
        .padding(.horizontal, isOnboarding ? 20 : 0)
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
        if isOnboarding {
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
            if aiManager.aiModeChoice != .cloud {
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
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? iconColor : Color.gray.opacity(0.15), lineWidth: isSelected ? 2 : 1)
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
            ScrollView {
                VStack(spacing: 22) {
                    // Header Hero
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.18), Color.indigo.opacity(0.12)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "heart.fill")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .indigo],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .padding(.top, 12)
                        
                        Text("Sostieni InOrario")
                            .font(.title2.bold())
                        
                        Text("Sblocca tutte le funzionalità avanzate e aiuta a coprire i costi dei server di calcolo per mantenere l'app attiva ed indipendente.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    
                    // Vantaggi
                    VStack(alignment: .leading, spacing: 16) {
                        SupportBenefitRow(
                            icon: "bell.badge.fill",
                            iconColor: .blue,
                            title: "Live Activity & Notifiche insieme",
                            description: "Monitora fino a 10 treni contemporaneamente e attiva Notifiche Push e Live Activity senza limitazioni."
                        )
                        
                        Divider()
                        
                        SupportBenefitRow(
                            icon: "sparkles",
                            iconColor: .indigo,
                            title: "Sintesi Scioperi con IA",
                            description: "Capisci al volo cosa succede durante un'agitazione con riassunti automatici, chiari e semplici."
                        )
                        
                        Divider()
                        
                        SupportBenefitRow(
                            icon: "arrow.triangle.branch",
                            iconColor: .purple,
                            title: "Soluzioni alternative per ritardi e cancellazioni",
                            description: "Ricevi itinerari e soluzioni di viaggio alternative su misura se il tuo treno subisce forti ritardi o cancellazioni."
                        )
                        
                        Divider()
                        
                        SupportBenefitRow(
                            icon: "square.dashed.inset.filled",
                            iconColor: .orange,
                            title: "Widget su Schermata Home e di Blocco",
                            description: "Visualizza partenze, binari e ritardi in tempo reale con i widget dedicati direttamente sulla schermata di blocco o Home."
                        )
                        
                        Divider()
                        
                        SupportBenefitRow(
                            icon: "heart.fill",
                            iconColor: .red,
                            title: "Supporto allo Sviluppatore",
                            description: "Aiuta un singolo sviluppatore a sostenere i costi continuativi dell'app, mantenendola gratuita per tutti e senza alcuna pubblicità."
                        )
                    }
                    .padding(18)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(20)
                    .padding(.horizontal, 16)
                    
                    // Opzioni di acquisto
                    VStack(spacing: 12) {
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
                                    HStack(spacing: 14) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Sostieni il Progetto")
                                                .font(.headline.bold())
                                            Text("Acquisto una tantum")
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
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 16)
                                    .background(
                                        LinearGradient(
                                            colors: [.blue, .indigo],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(16)
                                    .shadow(color: Color.blue.opacity(0.25), radius: 8, x: 0, y: 4)
                                }
                                .disabled(tipManager.purchaseState == .purchasing)
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
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.blue)
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 12)
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
                Text("Il tuo supporto è stato registrato ed hai sbloccato tutte le funzioni per sostenitori.")
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

// MARK: - SupportBenefitRow

private struct SupportBenefitRow: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.subheadline.bold())
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            
            Spacer(minLength: 0)
        }
    }
}

// MARK: - SpaceAlertBannerView (Compatibilità)

struct SpaceAlertBannerView: View {
    var body: some View {
        EmptyView()
    }
}
