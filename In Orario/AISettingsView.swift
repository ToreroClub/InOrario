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
                                 : "Richiede un dispositivo Apple compatibile con Apple Intelligence.")
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
                    } else {
                        Haptics.play(.light)
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
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Cloud In Orario")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                
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
                        }
                        
                        Spacer()
                        
                        if aiManager.aiModeChoice == .cloud {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                                .font(.subheadline.bold())
                        } else if !manager.hasSupport() {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.secondary.opacity(0.5))
                                .font(.caption)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            // MARK: Sezione 2: Funzionalità IA
            Section(
                header: Text("Funzionalità IA"),
                footer: Text("Le funzionalità avanzate contrassegnate con Pro sono incluse nel piano In Orario Pro.")
            ) {
                // 1. Notizie e Scioperi
                AIFeatureRow(
                    icon: "megaphone.fill",
                    iconColor: .red,
                    iconBg: Color.red.opacity(0.12),
                    title: "Sintesi Notizie e Scioperi",
                    description: "Riassunti chiari e formattati delle agitazioni sindacali e degli avvisi Trenitalia/Trenord.",
                    status: (manager.strikeRegion == "Lombardia" || manager.hasSupport()) ? .active : .disabled
                )
                
                // 2. Info Lavori
                AIFeatureRow(
                    icon: "wrench.and.screwdriver.fill",
                    iconColor: .orange,
                    iconBg: Color.orange.opacity(0.12),
                    title: "Riepilogo Info Lavori",
                    description: "Estrazione automatica dei cantieri, delle date e delle linee ferroviarie interessate.",
                    status: (manager.strikeRegion == "Lombardia" || manager.hasSupport()) ? .active : .disabled
                )
                
                // 3. Suggerimenti Intelligenti
                Button {
                    if !manager.hasSupport() {
                        showPaywallSheet = true
                    }
                } label: {
                    AIFeatureRow(
                        icon: "sparkles",
                        iconColor: .indigo,
                        iconBg: Color.indigo.opacity(0.12),
                        title: "Suggerimenti Intelligenti",
                        description: "Anticipa stazioni, treni e tratte frequenti mostrandoli nella schermata Home al momento opportuno.",
                        status: manager.hasSupport() ? .active : .supporter
                    )
                }
                .buttonStyle(.plain)
                
                // 4. Suggerimenti Percorso
                Button {
                    if !manager.hasSupport() {
                        showPaywallSheet = true
                    }
                } label: {
                    AIFeatureRow(
                        icon: "arrow.triangle.branch",
                        iconColor: .purple,
                        iconBg: Color.purple.opacity(0.12),
                        title: "Suggerimenti Percorso",
                        description: "Consigli intelligenti di itinerari alternativi in caso di ritardi significativi o cancellazioni.",
                        status: manager.hasSupport() ? .active : .supporter
                    )
                }
                .buttonStyle(.plain)
                
                // 5. Previsione Ritardi
                AIFeatureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: .blue,
                    iconBg: Color.blue.opacity(0.12),
                    title: "Previsione Ritardi",
                    description: "Stima preventiva della puntualità e delle tendenze basata sullo storico delle corse.",
                    status: .upcoming
                )
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
        
        if aiManager.isAppleIntelligenceAvailable {
            if aiManager.aiModeChoice != .cloud && aiManager.aiModeChoice != .none {
                aiManager.aiModeChoice = .local
                aiManager.selectedModelID = "apple_intelligence"
                aiManager.preferLocalAI = true
            }
        } else {
            if aiManager.aiModeChoice == .local {
                aiManager.aiModeChoice = .none
                aiManager.preferLocalAI = false
            }
        }
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
