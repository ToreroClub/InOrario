import SwiftUI

// MARK: - AIModelSelectorView
// Usata sia in onboarding che in impostazioni

struct AIModelSelectorView: View {
    @ObservedObject var aiManager = AIFeatureManager.shared
    @EnvironmentObject var manager: TrainManager
    
    var isOnboarding: Bool = false
    var onFinish: (() -> Void)? = nil
    
    var body: some View {

            VStack(spacing: 16) {
                
                // Header spazio libero
                HStack {
                    Image(systemName: "internaldrive")
                        .foregroundColor(.secondary)
                    Text("Spazio libero: \(String(format: "%.1f", aiManager.freeDiskSpaceGB)) GB")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        aiManager.refreshFreeSpace()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, isOnboarding ? 0 : 8)
                
                // Opzione: Nessuna IA
                AIOptionCard(
                    icon: "xmark.circle",
                    iconColor: .gray,
                    title: "Senza IA",
                    description: "Nessuna elaborazione automatica degli scioperi. Puoi attivarla in seguito.",
                    isSelected: aiManager.aiModeChoice == .none,
                    isDisabled: false,
                    badgeText: nil
                ) {
                    Haptics.play(.light)
                    aiManager.aiModeChoice = .none
                }
                
                // Opzione: Locale / Apple Intelligence
                VStack(alignment: .leading, spacing: 8) {
                    if aiManager.isAppleIntelligenceAvailable {
                        AIOptionCard(
                            icon: "applelogo",
                            iconColor: .primary,
                            title: "Apple Intelligence",
                            description: "Sfrutta l'IA integrata nel tuo dispositivo senza consumare spazio aggiuntivo.",
                            isSelected: aiManager.aiModeChoice == .local,
                            isDisabled: false,
                            badgeText: "Incluso in iOS"
                        ) {
                            Haptics.play(.medium)
                            aiManager.aiModeChoice = .local
                            aiManager.selectedModelID = "apple_intelligence"
                        }
                    } else {
                        AIOptionCard(
                            icon: "cpu",
                            iconColor: .indigo,
                            title: "IA Locale (Offline - Beta)",
                            description: "Scarica un modello compatto per riassunti offline sul tuo dispositivo.",
                            isSelected: aiManager.aiModeChoice == .local,
                            isDisabled: !aiManager.isHardwareCompatible,
                            badgeText: aiManager.isHardwareCompatible ? "Beta" : "Non supportato"
                        ) {
                            Haptics.play(.medium)
                            aiManager.aiModeChoice = .local
                        }
                        
                        if !aiManager.isHardwareCompatible {
                            Text("Il tuo dispositivo non supporta l'IA locale (richiesti ≥ 3 GB RAM, iPhone 11 / SE 2 o successivi).")
                                .font(.caption.bold())
                                .foregroundColor(.red)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.08))
                                .cornerRadius(12)
                        } else if aiManager.aiModeChoice == .local {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("ATTENZIONE: Qwen è un modello sperimentale eseguito in-app. Potrebbe causare crash per esaurimento memoria (RAM) o consumi elevati su alcuni dispositivi.")
                                    .font(.caption.bold())
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 4)
                                    .padding(.bottom, 4)
                                
                                ForEach(AIFeatureManager.catalog) { model in
                                    let isSelected = aiManager.selectedModelID == model.id
                                    let isInstalled = aiManager.isLocalModelInstalled && aiManager.selectedModelID == model.id
                                    let isRecommended = aiManager.recommendedModel.id == model.id
                                    let isDownloading = aiManager.isDownloadingModel && aiManager.pendingModelID == model.id
                                    
                                    LocalModelCard(
                                        model: model,
                                        isSelected: isSelected,
                                        isInstalled: isInstalled,
                                        isRecommended: isRecommended,
                                        isDownloading: isDownloading,
                                        downloadProgress: aiManager.downloadProgress,
                                        freeDiskSpaceGB: aiManager.freeDiskSpaceGB,
                                        isAnyDownloading: aiManager.isDownloadingModel,
                                        onSelect: {
                                            Haptics.play(.medium)
                                            aiManager.selectedModelID = model.id
                                        },
                                        onDownload: {
                                            Haptics.play(.medium)
                                            aiManager.switchTo(model)
                                        },
                                        onCancel: {
                                            Haptics.play(.light)
                                            aiManager.cancelDownload()
                                        },
                                        onRemove: {
                                            Haptics.play(.light)
                                            aiManager.removeCurrentModel()
                                        }
                                    )
                                }
                            }
                            .padding(.leading, 24)
                        }
                    }
                }
                
                // Opzione: Cloud
                AIOptionCard(
                    icon: "cloud.fill",
                    iconColor: .blue,
                    title: "Cloud In Orario",
                    description: "Elaborazione istantanea sui server di In Orario.",
                    isSelected: aiManager.aiModeChoice == .cloud,
                    isDisabled: !manager.hasSupport(),
                    badgeText: manager.hasSupport() ? nil : "Sostenitori"
                ) {
                    Haptics.play(.medium)
                    aiManager.aiModeChoice = .cloud
                    aiManager.preferLocalAI = false
                }
                
                if !manager.hasSupport() {
                    Text("L'elaborazione Cloud è riservata a chi sostiene il progetto per coprire i costi dei server.")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(12)
                }
                
                // Pulsante continua (solo in onboarding)
                if isOnboarding {
                    Button(action: {
                        onFinish?()
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
            aiManager.refreshFreeSpace()
            // Se l'utente non supporta il progetto ed era impostato su Cloud, facciamo il reset
            if aiManager.aiModeChoice == .cloud && !manager.hasSupport() {
                aiManager.aiModeChoice = .none
            }
            // Se è il primo avvio ed è compatibile, preselezioniamo il consigliato o Apple Intelligence
            if aiManager.aiModeChoice == .none && !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                if aiManager.isAppleIntelligenceAvailable {
                    aiManager.aiModeChoice = .local
                    aiManager.selectedModelID = "apple_intelligence"
                } else if aiManager.isHardwareCompatible {
                    aiManager.aiModeChoice = .local
                    aiManager.selectedModelID = aiManager.recommendedModel.id
                }
            }
        }
        .navigationTitle(isOnboarding ? "" : "Modello AI")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Subviews

private struct AIOptionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isSelected: Bool
    let isDisabled: Bool
    let badgeText: String?
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
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue)
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

private struct LocalModelCard: View {
    let model: AIModelOption
    let isSelected: Bool
    let isInstalled: Bool
    let isRecommended: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let freeDiskSpaceGB: Double
    let isAnyDownloading: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void
    
    var canInstall: Bool {
        freeDiskSpaceGB >= model.minFreeSpaceGB
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    // Cerchio radio a sinistra
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.title3)
                        .foregroundColor(isSelected ? .indigo : .secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(model.displayName)
                                .font(.headline)
                                .foregroundColor(canInstall ? .primary : .secondary)
                            
                            if isRecommended {
                                Text("Consigliato")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.12))
                                    .foregroundColor(.green)
                                    .cornerRadius(6)
                            }
                            
                            if isInstalled {
                                Text("Installato")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.indigo.opacity(0.12))
                                    .foregroundColor(.indigo)
                                    .cornerRadius(6)
                            }
                        }
                        
                        Text(model.tagline)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Spazio richiesto: \(model.formattedSize)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Stelle a destra
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= model.qualityStars ? "star.fill" : "star")
                                .font(.system(size: 8))
                                .foregroundColor(star <= model.qualityStars ? .yellow : .gray.opacity(0.3))
                        }
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canInstall)
            
            if !canInstall {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Spazio insufficiente (richiesti \(String(format: "%.1f", model.minFreeSpaceGB)) GB liberi)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 30)
            }
            
            if isSelected && !isInstalled && canInstall {
                VStack(spacing: 8) {
                    if isDownloading {
                        VStack(spacing: 6) {
                            ProgressView(value: downloadProgress)
                                .tint(.indigo)
                            HStack {
                                Text("Download in corso... \(Int(downloadProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Annulla") {
                                    onCancel()
                                }
                                .font(.caption.bold())
                                .foregroundColor(.red)
                            }
                        }
                    } else {
                        Button(action: onDownload) {
                            HStack {
                                Spacer()
                                if isAnyDownloading {
                                    Text("Download in corso per un altro modello...")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.secondary)
                                } else {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Scarica ed Attiva (\(model.formattedSize))")
                                        .font(.subheadline.bold())
                                }
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .background(isAnyDownloading ? Color.gray.opacity(0.12) : Color.indigo)
                            .foregroundColor(isAnyDownloading ? .secondary : .white)
                            .cornerRadius(10)
                        }
                        .disabled(isAnyDownloading)
                    }
                }
                .padding(.leading, 30)
                .padding(.top, 4)
            }
            
            if isInstalled {
                Button(action: onRemove) {
                    HStack {
                        Spacer()
                        Image(systemName: "trash.fill")
                        Text("Elimina Modello")
                            .font(.subheadline.bold())
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.12))
                    .foregroundColor(.red)
                    .cornerRadius(10)
                }
                .padding(.leading, 30)
                .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color.indigo : Color.clear, lineWidth: 2)
                )
        )
        .opacity(canInstall ? 1.0 : 0.6)
    }
}

// MARK: - Space Alert Banner

struct SpaceAlertBannerView: View {
    @ObservedObject var aiManager = AIFeatureManager.shared
    @EnvironmentObject var manager: TrainManager
    @State private var showModelSelector = false
    
    var body: some View {
        switch aiManager.spaceAlertLevel {
        case .none:
            EmptyView()
            
        case .warning(let message, let actionLabel):
            alertBanner(
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                message: message,
                actionLabel: actionLabel
            ) {
                showModelSelector = true
            }
            .sheet(isPresented: $showModelSelector) {
                NavigationStack {
                    AIModelSelectorView()
                        .environmentObject(manager)
                }
            }
            
        case .critical(let message, _):
            alertBanner(
                icon: "externaldrive.badge.exclamationmark",
                color: .red,
                message: message,
                actionLabel: "Rimuovi ora"
            ) {
                aiManager.removeCurrentModel()
            }
            
        case .upgradeAvailable(let toModel):
            alertBanner(
                icon: "arrow.up.circle.fill",
                color: .blue,
                message: "Hai abbastanza spazio per il modello \(toModel.displayName).",
                actionLabel: "Aggiorna"
            ) {
                showModelSelector = true
            }
            .sheet(isPresented: $showModelSelector) {
                NavigationStack {
                    AIModelSelectorView()
                        .environmentObject(manager)
                }
            }
        }
    }
    
    @ViewBuilder
    private func alertBanner(icon: String, color: Color, message: String, actionLabel: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            Button(actionLabel) {
                Haptics.play(.medium)
                action()
            }
            .font(.caption.bold())
            .foregroundColor(color)
            .buttonStyle(BorderlessButtonStyle())
            
            Button {
                aiManager.dismissSpaceAlert()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(12)
        .background(color.opacity(0.08))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
