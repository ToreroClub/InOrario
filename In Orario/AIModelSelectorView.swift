import SwiftUI
import StoreKit
import SafariServices

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
                    badgeText: manager.hasSupport() ? "Attivo" : "Pro"
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
                            Text("IA su server (In Orario Pro)")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                        }
                        
                        Text("L'elaborazione intelligente su server dedicati è inclusa nel piano In Orario Pro.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            showPaywallSheet = true
                        }) {
                            HStack {
                                Text("Passa a In Orario Pro")
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
    private static let privacyPolicyURL = URL(string: "https://inorario.toreroclub.com/#privacy")!
    private static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject var aiManager = AIFeatureManager.shared
    @EnvironmentObject var manager: TrainManager
    @StateObject private var tipManager = TipManager()

    @State private var selectedProductID: String?
    @State private var activeLegalURL: LegalURLItem?
    @State private var showManageSubscriptions = false

    private var selectedProduct: Product? {
        if let id = selectedProductID,
           let match = tipManager.products.first(where: { $0.id == id }) {
            return match
        }
        return tipManager.products.first(where: { $0.id == TipManager.yearlySubscriptionID })
            ?? tipManager.products.first
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
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
                                .frame(width: 76, height: 76)

                            Image(systemName: "sparkles")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .indigo],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .padding(.top, 8)

                        Text("In Orario Pro")
                            .font(.title2.bold())

                        Text("Sblocca tutte le funzionalità avanzate di monitoraggio in tempo reale, notifiche scioperi e intelligenza artificiale su server.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    // Elenco dettagliato dei servizi inclusi nell'abbonamento
                    VStack(alignment: .leading, spacing: 14) {
                        SupportBenefitRow(
                            icon: "brain.head.profile",
                            iconColor: .indigo,
                            title: "IA su server per scioperi e lavori",
                            description: "IA su server per il riepilogo intelligente di scioperi e lavori programmati."
                        )

                        Divider()

                        SupportBenefitRow(
                            icon: "bell.badge.fill",
                            iconColor: .red,
                            title: "Notifiche push per scioperi",
                            description: "Notifiche push dedicate per gli scioperi e le variazioni della circolazione ferroviaria."
                        )

                        Divider()

                        SupportBenefitRow(
                            icon: "tram.fill",
                            iconColor: .blue,
                            title: "Monitoraggio fino a 10 treni",
                            description: "Monitoraggio simultaneo fino a 10 treni con notifiche push e giorni attivi personalizzati."
                        )

                        Divider()

                        SupportBenefitRow(
                            icon: "bolt.fill",
                            iconColor: .orange,
                            title: "Live Activities ad alta frequenza",
                            description: "Live Activities ad alta frequenza con aggiornamenti automatici ogni 30–60 secondi su schermata di blocco e Isola Dinamica."
                        )

                        Divider()

                        SupportBenefitRow(
                            icon: "star.fill",
                            iconColor: .purple,
                            title: "Accesso prioritario alle novità",
                            description: "Accesso prioritario a tutte le nuove funzionalità avanzate introdotte nei prossimi aggiornamenti."
                        )
                    }
                    .padding(18)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 16)

                    // Piani o stato attivo
                    VStack(alignment: .leading, spacing: 12) {
                        if manager.hasSupport() {
                            activeSubscriptionCard
                        } else if tipManager.isLoadingProducts {
                            HStack {
                                Spacer()
                                ProgressView("Caricamento piani...")
                                    .padding(.vertical, 20)
                                Spacer()
                            }
                        } else if tipManager.products.isEmpty {
                            VStack(spacing: 12) {
                                Text("I piani di abbonamento non sono al momento disponibili.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)

                                Button("Riprova") {
                                    Haptics.play(.light)
                                    Task {
                                        await tipManager.fetchProducts()
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.bordered)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else {
                            Text("Scegli il tuo piano")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(tipManager.products, id: \.id) { product in
                                let isSelected = selectedProduct?.id == product.id
                                PlanSelectionCard(
                                    title: product.displayName,
                                    badgeText: planBadgeText(for: product),
                                    badgeColor: product.subscription != nil ? .blue : .orange,
                                    subtitle: planSubtitle(for: product),
                                    priceText: product.displayPrice,
                                    periodText: planPriceUnit(for: product),
                                    isSelected: isSelected
                                ) {
                                    Haptics.play(.light)
                                    selectedProductID = product.id
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .padding(.vertical, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                checkoutFooterBar
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
                if selectedProductID == nil {
                    selectedProductID = tipManager.products.first(where: { $0.id == TipManager.yearlySubscriptionID })?.id
                        ?? tipManager.products.first?.id
                }
            }
            .sheet(item: $activeLegalURL) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
            }
            .manageSubscriptionsSheet(
                isPresented: $showManageSubscriptions,
                subscriptionGroupID: tipManager.activeSubscriptionGroupID
            )
            .alert("Piano Attivato", isPresented: Binding(
                get: { tipManager.purchaseState == .success },
                set: { if !$0 { tipManager.resetState() } }
            )) {
                Button("Inizia", role: .cancel) {
                    if manager.hasSupport() {
                        aiManager.aiModeChoice = .cloud
                        aiManager.preferLocalAI = false
                        dismiss()
                    }
                }
            } message: {
                Text("Il tuo piano In Orario Pro è attivo e tutte le funzionalità avanzate sono ora sbloccate.")
            }
            .alert("Ripristino Acquisti", isPresented: Binding(
                get: { tipManager.restoreOutcome != nil },
                set: { if !$0 { tipManager.restoreOutcome = nil } }
            )) {
                Button("OK", role: .cancel) {
                    if tipManager.restoreOutcome == .restored && manager.hasSupport() {
                        aiManager.aiModeChoice = .cloud
                        aiManager.preferLocalAI = false
                        dismiss()
                    }
                }
            } message: {
                if tipManager.restoreOutcome == .restored {
                    Text("I tuoi acquisti precedenti sono stati ripristinati con successo.")
                } else {
                    Text("Nessun acquisto precedente da ripristinare per questo account Apple.")
                }
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

    // MARK: - Subviews

    private var activeSubscriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.title2)
                    .foregroundColor(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activePlanTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Tutte le funzionalità avanzate sono sbloccate.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if tipManager.activeProductType == .yearly {
                Button {
                    showManageSubscriptions = true
                } label: {
                    HStack {
                        Image(systemName: "gearshape.fill")
                        Text("Gestisci Abbonamento")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var checkoutFooterBar: some View {
        VStack(spacing: 10) {
            if !manager.hasSupport(), let product = selectedProduct {
                Button {
                    Task {
                        await tipManager.purchase(product)
                        if manager.hasSupport() {
                            aiManager.aiModeChoice = .cloud
                            aiManager.preferLocalAI = false
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if tipManager.purchaseState == .purchasing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(purchaseButtonTitle(for: product))
                                .font(.headline.bold())
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(
                        LinearGradient(
                            colors: product.subscription != nil
                                ? [Color.blue, Color.indigo]
                                : [Color.orange, Color(red: 0.92, green: 0.42, blue: 0.08)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: (product.subscription != nil ? Color.blue : Color.orange).opacity(0.25), radius: 8, x: 0, y: 4)
                }
                .disabled(tipManager.purchaseState == .purchasing || tipManager.isRestoringPurchases)

                Text(billingDisclosure(for: product))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 6) {
                if !manager.hasSupport() {
                    Button {
                        Task {
                            await tipManager.restorePurchases()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if tipManager.isRestoringPurchases {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Text("Ripristina Acquisti")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundColor(.blue)
                        .padding(.vertical, 4)
                    }
                    .disabled(tipManager.isRestoringPurchases || tipManager.purchaseState == .purchasing)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        privacyPolicyButton
                        Text("·")
                            .foregroundColor(.secondary)
                        termsOfUseButton
                    }

                    VStack(spacing: 4) {
                        privacyPolicyButton
                        termsOfUseButton
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var privacyPolicyButton: some View {
        Button {
            Haptics.play(.light)
            activeLegalURL = LegalURLItem(url: Self.privacyPolicyURL)
        } label: {
            Text("Informativa sulla Privacy")
                .font(.caption.weight(.medium))
                .underline()
                .foregroundColor(.blue)
                .padding(.vertical, 4)
        }
    }

    private var termsOfUseButton: some View {
        Button {
            Haptics.play(.light)
            activeLegalURL = LegalURLItem(url: Self.termsOfUseURL)
        } label: {
            Text("Termini d'Uso (EULA)")
                .font(.caption.weight(.medium))
                .underline()
                .foregroundColor(.blue)
                .padding(.vertical, 4)
        }
    }

    // MARK: - StoreKit Plan Formatting Helpers

    private var activePlanTitle: LocalizedStringKey {
        switch tipManager.activeProductType {
        case .yearly:
            return "In Orario Pro · Piano Annuale"
        case .lifetime, .legacy, .none:
            return "In Orario Pro · Piano a Vita"
        }
    }

    private func planBadgeText(for product: Product) -> String? {
        if let subscription = product.subscription {
            if let intro = subscription.introductoryOffer,
               tipManager.isEligibleForIntroOffer(product),
               intro.paymentMode == .freeTrial {
                let trial = introOfferDurationText(intro)
                return String(localized: LocalizedStringResource("\(trial) gratis", locale: locale))
            }
            return billingCycleAdjective(subscription.subscriptionPeriod)
        }
        return String(localized: LocalizedStringResource("Una tantum", locale: locale))
    }

    private func planSubtitle(for product: Product) -> String {
        if let subscription = product.subscription {
            let cycle = billingCycleAdjective(subscription.subscriptionPeriod)
            let period = periodDurationText(subscription.subscriptionPeriod)
            let shortUnit = periodShortUnitText(subscription.subscriptionPeriod)

            if let intro = subscription.introductoryOffer,
               tipManager.isEligibleForIntroOffer(product) {
                let trial = introOfferDurationText(intro)
                if intro.paymentMode == .freeTrial {
                    return String(localized: LocalizedStringResource("Abbonamento \(cycle) · \(trial) gratis, poi \(product.displayPrice)/\(shortUnit)", locale: locale))
                } else {
                    return String(localized: LocalizedStringResource("Abbonamento \(cycle) · \(intro.displayPrice) per \(trial), poi \(product.displayPrice)/\(shortUnit)", locale: locale))
                }
            }
            return String(localized: LocalizedStringResource("Abbonamento \(cycle) · Rinnovo automatico ogni \(period)", locale: locale))
        }
        return String(localized: LocalizedStringResource("Acquisto singolo · Accesso permanente, nessun rinnovo", locale: locale))
    }

    private func planPriceUnit(for product: Product) -> String {
        if let subscription = product.subscription {
            let shortUnit = periodShortUnitText(subscription.subscriptionPeriod)
            return String(localized: LocalizedStringResource("/ \(shortUnit)", locale: locale))
        }
        return String(localized: LocalizedStringResource("una tantum", locale: locale))
    }

    private func purchaseButtonTitle(for product: Product) -> String {
        if let subscription = product.subscription {
            let shortUnit = periodShortUnitText(subscription.subscriptionPeriod)
            if let intro = subscription.introductoryOffer,
               tipManager.isEligibleForIntroOffer(product),
               intro.paymentMode == .freeTrial {
                let trial = introOfferDurationText(intro)
                return String(localized: LocalizedStringResource("Prova gratis \(trial) · poi \(product.displayPrice)/\(shortUnit)", locale: locale))
            }
            return String(localized: LocalizedStringResource("Abbonati · \(product.displayPrice)/\(shortUnit)", locale: locale))
        }
        return String(localized: LocalizedStringResource("Acquista a vita · \(product.displayPrice)", locale: locale))
    }

    private func billingDisclosure(for product: Product) -> String {
        if let subscription = product.subscription {
            let period = periodDurationText(subscription.subscriptionPeriod)
            let shortUnit = periodShortUnitText(subscription.subscriptionPeriod)

            if let intro = subscription.introductoryOffer,
               tipManager.isEligibleForIntroOffer(product) {
                let trial = introOfferDurationText(intro)
                if intro.paymentMode == .freeTrial {
                    return String(localized: LocalizedStringResource("Piano: \(product.displayName) · Durata: \(period) · Prezzo: \(product.displayPrice)/\(shortUnit). Dopo \(trial) di prova gratuita, l'abbonamento si rinnova automaticamente salvo annullamento almeno 24 ore prima della scadenza.", locale: locale))
                } else {
                    return String(localized: LocalizedStringResource("Piano: \(product.displayName) · Durata: \(period) · Offerta iniziale \(intro.displayPrice) per \(trial), poi \(product.displayPrice)/\(shortUnit) con rinnovo automatico salvo annullamento almeno 24 ore prima della scadenza.", locale: locale))
                }
            }
            return String(localized: LocalizedStringResource("Piano: \(product.displayName) · Durata: \(period) · Prezzo: \(product.displayPrice)/\(shortUnit). L'abbonamento si rinnova automaticamente salvo annullamento almeno 24 ore prima della scadenza.", locale: locale))
        }
        return String(localized: LocalizedStringResource("Prodotto: \(product.displayName) · Acquisto una tantum · Prezzo: \(product.displayPrice). Pagamento singolo senza rinnovo automatico.", locale: locale))
    }

    private func introOfferDurationText(_ offer: Product.SubscriptionOffer) -> String {
        let totalValue = offer.period.value * max(1, offer.periodCount)
        return durationText(unit: offer.period.unit, value: totalValue)
    }

    private func periodDurationText(_ period: Product.SubscriptionPeriod) -> String {
        durationText(unit: period.unit, value: period.value)
    }

    private func durationText(unit: Product.SubscriptionPeriod.Unit, value: Int) -> String {
        switch (unit, value) {
        case (.day, 1): return String(localized: LocalizedStringResource("1 giorno", locale: locale))
        case (.day, let n): return String(localized: LocalizedStringResource("\(n) giorni", locale: locale))
        case (.week, 1): return String(localized: LocalizedStringResource("1 settimana", locale: locale))
        case (.week, let n): return String(localized: LocalizedStringResource("\(n) settimane", locale: locale))
        case (.month, 1): return String(localized: LocalizedStringResource("1 mese", locale: locale))
        case (.month, let n): return String(localized: LocalizedStringResource("\(n) mesi", locale: locale))
        case (.year, 1): return String(localized: LocalizedStringResource("1 anno", locale: locale))
        case (.year, let n): return String(localized: LocalizedStringResource("\(n) anni", locale: locale))
        @unknown default: return "\(value)"
        }
    }

    private func periodShortUnitText(_ period: Product.SubscriptionPeriod) -> String {
        switch (period.unit, period.value) {
        case (.day, 1): return String(localized: LocalizedStringResource("giorno", locale: locale))
        case (.day, let n): return String(localized: LocalizedStringResource("\(n) giorni", locale: locale))
        case (.week, 1): return String(localized: LocalizedStringResource("settimana", locale: locale))
        case (.week, let n): return String(localized: LocalizedStringResource("\(n) settimane", locale: locale))
        case (.month, 1): return String(localized: LocalizedStringResource("mese", locale: locale))
        case (.month, let n): return String(localized: LocalizedStringResource("\(n) mesi", locale: locale))
        case (.year, 1): return String(localized: LocalizedStringResource("anno", locale: locale))
        case (.year, let n): return String(localized: LocalizedStringResource("\(n) anni", locale: locale))
        @unknown default: return "\(period.value)"
        }
    }

    private func billingCycleAdjective(_ period: Product.SubscriptionPeriod) -> String {
        switch (period.unit, period.value) {
        case (.day, 1): return String(localized: LocalizedStringResource("Giornaliero", locale: locale))
        case (.week, 1): return String(localized: LocalizedStringResource("Settimanale", locale: locale))
        case (.month, 1): return String(localized: LocalizedStringResource("Mensile", locale: locale))
        case (.year, 1): return String(localized: LocalizedStringResource("Annuale", locale: locale))
        default: return periodDurationText(period)
        }
    }
}

// MARK: - PlanSelectionCard

private struct PlanSelectionCard: View {
    let title: String
    let badgeText: String?
    let badgeColor: Color
    let subtitle: String
    let priceText: String
    let periodText: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? badgeColor : .secondary.opacity(0.6))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)

                        if let badgeText {
                            Text(badgeText)
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(badgeColor.opacity(0.14))
                                .foregroundColor(badgeColor)
                                .clipShape(Capsule())
                        }
                    }

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(priceText)
                        .font(.headline.bold())
                        .foregroundColor(.primary)
                    Text(periodText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? badgeColor.opacity(0.06) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? badgeColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SafariView & LegalURLItem

private struct LegalURLItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
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
