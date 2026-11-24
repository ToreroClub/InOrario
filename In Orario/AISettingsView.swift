import SwiftUI

// MARK: - AISettingsView

struct AISettingsView: View {
    @ObservedObject private var aiManager = AIFeatureManager.shared
    @EnvironmentObject var manager: TrainManager
    @State private var showPaywallSheet = false

    var body: some View {
        List {
            // MARK: Sezione 1: Selezione Motore IA
            Section(
                header: Text("Seleziona Motore IA"),
                footer: Text("Apple Intelligence elabora le informazioni direttamente sul tuo dispositivo. Cloud In Orario sfrutta server dedicati ad alte prestazioni.")
            ) {
                // Opzione 1: Senza IA
                Button {
                    Haptics.play(.light)
                    aiManager.aiModeChoice = .none
                    aiManager.preferLocalAI = false
                    aiManager.hasUserChosenAIMode = true
                    manager.syncRemoteNotifications()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.gray.opacity(0.12))
                                .frame(width: 32, height: 32)
                            Image(systemName: "slash.circle")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Senza IA")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Text("Nessuna elaborazione automatica o riassunti intelligenti.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if aiManager.aiModeChoice == .none {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                                .font(.subheadline.bold())
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Opzione 2: Apple Intelligence
                Button {
                    guard aiManager.isAppleIntelligenceAvailable else { return }
                    Haptics.play(.medium)
                    aiManager.aiModeChoice = .local
                    aiManager.selectedModelID = "apple_intelligence"
                    aiManager.preferLocalAI = true
                    aiManager.hasUserChosenAIMode = true
                    manager.syncRemoteNotifications()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                                .frame(width: 32, height: 32)
                            Image(systemName: "applelogo")
                                .foregroundColor(aiManager.isAppleIntelligenceAvailable ? .primary : .secondary)
                                .font(.subheadline)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Apple Intelligence")
                                    .font(.subheadline.bold())
                                    .foregroundColor(aiManager.isAppleIntelligenceAvailable ? .primary : .secondary)
                                
                                Text(aiManager.isAppleIntelligenceAvailable ? "Incluso in iOS" : "Non supportato")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(aiManager.isAppleIntelligenceAvailable ? .blue : .secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(aiManager.isAppleIntelligenceAvailable ? Color.blue.opacity(0.1) : Color.gray.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            
                            Text(aiManager.isAppleIntelligenceAvailable
                                 ? "Elaborazione privata e integrata direttamente sul tuo iPhone."
                                 : "Richiede un dispositivo Apple compatibile con Apple Intelligence e iOS 26 o successivo.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if aiManager.aiModeChoice == .local {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                                .font(.subheadline.bold())
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!aiManager.isAppleIntelligenceAvailable)
                
                // Opzione 3: Cloud In Orario
                Button {
                    if manager.hasSupport() {
                        Haptics.play(.medium)
                        aiManager.aiModeChoice = .cloud
                        aiManager.preferLocalAI = false
                        aiManager.hasUserChosenAIMode = true
                        manager.syncRemoteNotifications()
                    } else {
                        Haptics.notify(.warning)
                        showPaywallSheet = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.blue.opacity(0.12))
                                .frame(width: 32, height: 32)
                            Image(systemName: "cloud.fill")
                                .foregroundColor(.blue)
                                .font(.subheadline)
                        }
                        .saturation(manager.hasSupport() ? 1.0 : 0.0)
                        .opacity(manager.hasSupport() ? 1.0 : 0.55)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Cloud In Orario")
                                    .font(.subheadline.bold())
                                    .foregroundColor(manager.hasSupport() ? .primary : .secondary)
                                
                                Text(cloudBadgeText)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(cloudBadgeColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(cloudBadgeColor.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            
                            Text("Elaborazione rapida ed avanzata con modelli IA dedicati ad alta precisione.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .opacity(manager.hasSupport() ? 1.0 : 0.75)
                        }
                        
                        Spacer()
                        
                        if aiManager.aiModeChoice == .cloud {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                                .font(.subheadline.bold())
                        } else if !manager.hasSupport() {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.secondary.opacity(0.7))
                                .font(.caption)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            // MARK: Sezione 2: Funzionalità IA
            Section(header: Text("Funzionalità IA")) {
                // 1. Notizie e Scioperi
                AIFeatureRow(
                    icon: "megaphone.fill",
                    iconColor: .red,
                    iconBg: Color.red.opacity(0.12),
                    title: "Sintesi Notizie e Scioperi",
                    description: "Riassunti chiari e formattati delle agitazioni sindacali e degli avvisi Trenitalia/Trenord.",
                    status: .active
                )
                
                // 2. Info Lavori
                AIFeatureRow(
                    icon: "wrench.and.screwdriver.fill",
                    iconColor: .orange,
                    iconBg: Color.orange.opacity(0.12),
                    title: "Riepilogo Info Lavori",
                    description: "Estrazione automatica dei cantieri, delle date e delle linee ferroviarie interessate.",
                    status: .active
                )
                
                // 3. Suggerimenti Intelligenti
                AIFeatureRow(
                    icon: "sparkles",
                    iconColor: .indigo,
                    iconBg: Color.indigo.opacity(0.12),
                    title: "Suggerimenti Intelligenti",
                    description: "Anticipa stazioni, treni e tratte frequenti mostrandoli nella schermata Home al momento opportuno.",
                    status: .active
                )
                
                // 4. Alternative smart
                Button {
                    if !manager.hasSupport() && !hasCloudOrAppleAI {
                        showPaywallSheet = true
                    }
                } label: {
                    AIFeatureRow(
                        icon: "arrow.triangle.branch",
                        iconColor: .purple,
                        iconBg: Color.purple.opacity(0.12),
                        title: "Alternative smart",
                        description: "Consigli intelligenti di itinerari alternativi in caso di ritardi significativi o cancellazioni.",
                        status: hasCloudOrAppleAI ? .active : .disabled
                    )
                }
                .buttonStyle(.plain)
            }

            // MARK: Sezione 3: Assistente di ricerca
            Section(header: Text("Assistente di ricerca")) {
                Button {
                    if !manager.hasSupport() {
                        Haptics.notify(.warning)
                        showPaywallSheet = true
                    }
                } label: {
                    AIFeatureRow(
                        icon: "waveform.and.magnifyingglass",
                        iconColor: .purple,
                        iconBg: Color.purple.opacity(0.12),
                        title: "Assistente di ricerca",
                        description: "Cerca treni, tratte, orari e tabelloni scrivendo o parlando in linguaggio naturale con dati ferroviari reali. Per gli utenti Free usa l'elaborazione locale sul dispositivo, mentre per gli utenti Pro usa l'elaborazione Cloud tramite motore Google AI.",
                        status: assistantSearchStatus,
                        showBetaBadge: true
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Privacy e conservazione query")
                            .font(.caption.bold())
                            .foregroundColor(.primary)
                        Text("Le registrazioni vocali non vengono conservate: la voce viene convertita in testo sul momento. Le query testuali possono essere salvate in forma completamente anonima (scollegate da te e dal tuo dispositivo) per un periodo massimo di 30 giorni per migliorare il servizio.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Assistente IA")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywallSheet) {
            SupportPaywallSheet()
                .environmentObject(manager)
        }
        .onAppear {
            setupDefaultSelection()
        }
    }
    
    private var hasCloudOrAppleAI: Bool {
        (aiManager.aiModeChoice == .cloud && manager.hasSupport()) ||
        (aiManager.aiModeChoice == .local && aiManager.isAppleIntelligenceAvailable)
    }

    private var assistantSearchStatus: AIFeatureStatus {
        if hasCloudOrAppleAI {
            return .active
        }
        return .disabled
    }

    private var cloudBadgeText: String {
        if manager.hasSupport() {
            return "Attivo"
        } else {
            return "Pro"
        }
    }
    
    private var cloudBadgeColor: Color {
        if manager.hasSupport() {
            return .green
        } else {
            return .indigo
        }
    }
    
    private func setupDefaultSelection() {
        aiManager.reconcileDefaultAIMode(hasSupport: manager.hasSupport())
    }
}

// MARK: - AIFeatureRow

private enum AIFeatureStatus {
    case active
    case disabled
    case supporter
    case upcoming
}

private struct AIFeatureRow: View {
    let icon: String
    let iconColor: Color
    let iconBg: Color
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let status: AIFeatureStatus
    var showBetaBadge: Bool = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(status == .disabled ? Color.gray.opacity(0.08) : iconBg)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .foregroundColor(status == .disabled ? .secondary.opacity(0.5) : iconColor)
                    .font(.subheadline)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundColor(status == .disabled ? .secondary : .primary)

                    if showBetaBadge {
                        BetaBadgeView()
                    }
                    
                    Spacer()
                    
                    switch status {
                    case .active:
                        Text("Attivo")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    case .disabled:
                        Text("Disattivo")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.12))
                            .clipShape(Capsule())
                    case .supporter:
                        HStack(spacing: 3) {
                            Text("Pro")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.red)
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                    case .upcoming:
                        HStack(spacing: 3) {
                            Text("Prossimamente")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .opacity(status == .upcoming ? 0.75 : 1.0)
    }
}
