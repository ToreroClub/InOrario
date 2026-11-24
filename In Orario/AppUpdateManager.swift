import SwiftUI
import Combine
import UserNotifications

// MARK: - Remote In-App Alert Model

struct RemoteAlertInfo: Codable, Equatable {
    let id: String
    let enabled: Bool?
    let title: String
    let message: String
    let target: String? // "all", "supporters", "free"
    let primary_button_title: String?
    let primary_button_action: String? // "open_store", "open_url", "commute_setup", "support", "dismiss"
    let primary_button_url: String?
    let secondary_button_title: String?
    let is_critical: Bool?
    let min_version: String?
    let max_version: String?
}

@MainActor
class AppUpdateManager: ObservableObject {
    static let shared = AppUpdateManager()
    
    @Published var isUpdateAvailable: Bool = false
    @Published var storeVersion: String = ""
    @Published var storeURL: URL = URL(string: "https://apps.apple.com/it/app/in-orario/id6773419855")!
    @Published var updateTitle: String = "Nuova versione disponibile! 🚀"
    @Published var updateMessage: String = "È disponibile un nuovo aggiornamento di In Orario su App Store. Aggiorna ora per avere tutte le ultime novità, percorsi e miglioramenti!"
    @Published var isCriticalUpdate: Bool = false
    
    @Published var showUpdatePrompt: Bool = false
    @Published var showSupporterCommuteAlert: Bool = false
    @Published var showNotificationPermissionPrompt: Bool = false
    @Published var notificationPermissionAuthStatus: UNAuthorizationStatus = .notDetermined
    var pendingNotificationSettingsReturn: Bool = false
    
    // Avviso remoto personalizzabile da server
    @Published var activeRemoteAlert: RemoteAlertInfo? = nil
    @Published var showRemoteAlert: Bool = false
    
    private let lastCheckKey = "last_app_update_check_timestamp"
    private let snoozedVersionKey = "snoozed_update_version"
    private let snoozedTimeKey = "snoozed_update_timestamp"
    private let supporterLastSeenVersionKey = "supporter_last_seen_version"
    private let supporterCommuteSnoozedUntilKey = "supporter_commute_alert_snoozed_until"
    private let hasLaunchedBeforeKey = "has_launched_before_key"
    private let lastSeenRemoteAlertIdKey = "last_seen_remote_alert_id"
    private let notificationPromptCampaignKey = "post_update_notification_prompt_v3_3_handled"
    var hasCheckedSupporterPopupThisLaunch: Bool = false
    
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    // MARK: - Supporter Update Popup
    
    func checkSupporterUpdatePopup(hasSupport: Bool, forcedByBackend: Bool = false) {
        guard hasSupport else { return }
        if !forcedByBackend && hasCheckedSupporterPopupThisLaunch {
            return
        }
        hasCheckedSupporterPopupThisLaunch = true

        let hasConfiguredCommute = !SupporterCommuteManager.shared.origins.isEmpty &&
                                   !SupporterCommuteManager.shared.destinations.isEmpty
        if hasConfiguredCommute && !forcedByBackend {
            UserDefaults.standard.set(true, forKey: hasLaunchedBeforeKey)
            UserDefaults.standard.set(currentVersion, forKey: supporterLastSeenVersionKey)
            return
        }
        
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: hasLaunchedBeforeKey)
        let lastSeen = UserDefaults.standard.string(forKey: supporterLastSeenVersionKey)
        
        if !hasLaunchedBefore {
            // Primo avvio assoluto dell'app: memorizza versione e non interrompere
            UserDefaults.standard.set(true, forKey: hasLaunchedBeforeKey)
            UserDefaults.standard.set(currentVersion, forKey: supporterLastSeenVersionKey)
            return
        }
        
        guard let lastSeen = lastSeen else {
            // Prima installazione di questa logica: salva la versione corrente senza popup a sorpresa
            UserDefaults.standard.set(currentVersion, forKey: supporterLastSeenVersionKey)
            return
        }

        let now = Date().timeIntervalSince1970
        let snoozedUntil = UserDefaults.standard.double(forKey: supporterCommuteSnoozedUntilKey)
        if !forcedByBackend && snoozedUntil > now {
            return
        }
        
        // Mostra il popup ai sostenitori SOLO per aggiornamenti principali (es. 1.4 -> 1.5)
        // o se espressamente attivato dal backend, MAI per i piccoli bug fix o micro-patch.
        let isMajorOrMinor = Self.isMajorOrMinorUpdate(from: lastSeen, to: currentVersion)
        if (isMajorOrMinor || forcedByBackend) && Self.isVersion(currentVersion, greaterThan: lastSeen) {
            self.showSupporterCommuteAlert = true
        }
    }
    
    func dismissSupporterCommuteAlert() {
        UserDefaults.standard.set(currentVersion, forKey: supporterLastSeenVersionKey)
        UserDefaults.standard.removeObject(forKey: supporterCommuteSnoozedUntilKey)
        self.showSupporterCommuteAlert = false
    }
    
    func snoozeSupporterCommuteAlert() {
        let later = Date().addingTimeInterval(3 * 86400).timeIntervalSince1970
        UserDefaults.standard.set(later, forKey: supporterCommuteSnoozedUntilKey)
        self.showSupporterCommuteAlert = false
    }
    
    static func isMajorOrMinorUpdate(from oldVersion: String, to newVersion: String) -> Bool {
        let pOld = oldVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).split(separator: ".").compactMap { Int($0) }
        let pNew = newVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).split(separator: ".").compactMap { Int($0) }
        let majorOld = pOld.count > 0 ? pOld[0] : 0
        let minorOld = pOld.count > 1 ? pOld[1] : 0
        let majorNew = pNew.count > 0 ? pNew[0] : 0
        let minorNew = pNew.count > 1 ? pNew[1] : 0
        return majorNew > majorOld || (majorNew == majorOld && minorNew > minorOld)
    }
    
    // MARK: - Post-Update Notification Permission Prompt (v3.3)
    
    func markNotificationPermissionPromptHandled() {
        UserDefaults.standard.set(true, forKey: notificationPromptCampaignKey)
    }
    
    func evaluatePostUpdateNotificationPrompt(canPresent: @escaping @MainActor () -> Bool) async {
        guard !UserDefaults.standard.bool(forKey: notificationPromptCampaignKey) else { return }
        guard UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") else { return }
        
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            markNotificationPermissionPromptHandled()
            return
        case .notDetermined, .denied:
            self.notificationPermissionAuthStatus = settings.authorizationStatus
            guard canPresent() else { return }
            self.showNotificationPermissionPrompt = true
        @unknown default:
            return
        }
    }
    
    func openSystemNotificationSettings() {
        pendingNotificationSettingsReturn = true
        if let notifUrl = URL(string: UIApplication.openNotificationSettingsURLString),
           UIApplication.shared.canOpenURL(notifUrl) {
            UIApplication.shared.open(notifUrl)
        } else if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    // MARK: - Roadmap v3.4: Post-update Location Permission Prompt (deferred to v3.4 so notifications and location prompts are spaced across releases)
    
    // MARK: - App Store & Backend Update Check
    
    func checkForAvailableUpdates(hasSupport: Bool = false, strikeRegion: String = "Tutte", force: Bool = false) async {
        let now = Date().timeIntervalSince1970
        let lastCheck = UserDefaults.standard.double(forKey: lastCheckKey)
        
        // Verifica al massimo ogni 30 minuti a meno che non sia forzata
        if !force && (now - lastCheck < 1800) {
            return
        }
        UserDefaults.standard.set(now, forKey: lastCheckKey)
        
        // 1. Prova prima il backend rapido di In Orario (immediato, bypassa i ritardi di cache App Store)
        let backendFound = await checkBackendUpdate(hasSupport: hasSupport, strikeRegion: strikeRegion)
        if backendFound { return }
        
        // 2. Controllo ufficiale App Store via iTunes Lookup
        await checkAppStoreUpdate()
    }
    
    private func checkBackendUpdate(hasSupport: Bool, strikeRegion: String) async -> Bool {
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/app/version") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3.5
        
        do {
            let (data, response) = try await NetworkService.shared.get(request: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            
            struct BackendVersionInfo: Codable {
                let latest_version: String?
                let store_url: String?
                let title: String?
                let message: String?
                let is_critical: Bool?
                let remote_alert: RemoteAlertInfo?
            }
            
            let decoded = try JSONDecoder().decode(BackendVersionInfo.self, from: data)
            
            // Gestione avviso personalizzato da server (se presente ed abilitato)
            if let alert = decoded.remote_alert, (alert.enabled ?? true), !alert.id.isEmpty {
                self.evaluateAndShowRemoteAlert(alert, hasSupport: hasSupport, strikeRegion: strikeRegion)
            }
            
            if let latest = decoded.latest_version, Self.isVersion(latest, greaterThan: currentVersion) {
                self.isUpdateAvailable = true
                self.storeVersion = latest
                if let sUrl = decoded.store_url, let parsed = URL(string: sUrl) {
                    self.storeURL = parsed
                }
                if let t = decoded.title { self.updateTitle = t }
                if let m = decoded.message { self.updateMessage = m }
                self.isCriticalUpdate = decoded.is_critical ?? false
                
                triggerPromptIfAllowed()
                return true
            }
        } catch {
            // Backend non raggiungibile o offline, continua con iTunes Lookup
        }
        return false
    }
    
    // MARK: - Remote In-App Alert Handling
    
    func evaluateAndShowRemoteAlert(_ alert: RemoteAlertInfo, hasSupport: Bool, strikeRegion: String = "Tutte") {
        let lastSeenId = UserDefaults.standard.string(forKey: lastSeenRemoteAlertIdKey)
        let isCritical = alert.is_critical ?? false
        let alreadySeen = (lastSeenId == alert.id)
        
        // Se già visualizzato e non è critico, non disturbare di nuovo l'utente
        if alreadySeen && !isCritical {
            return
        }
        
        // Filtro destinatari: all, supporters, free, unset_region
        if let target = alert.target?.lowercased(), !target.isEmpty && target != "all" {
            if (target == "supporters" || target == "premium") && !hasSupport {
                return
            }
            if target == "free" && hasSupport {
                return
            }
            if target == "unset_region" {
                let normRegion = strikeRegion.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let unsetValues = ["", "tutte", "nazionale", "nazionale / tutte", "tutta italia", "non impostata"]
                if !unsetValues.contains(normRegion) {
                    return
                }
            }
        }
        
        // Filtro versione min / max se specificate
        if let minV = alert.min_version, !minV.isEmpty, Self.isVersion(minV, greaterThan: currentVersion) {
            return
        }
        if let maxV = alert.max_version, !maxV.isEmpty, Self.isVersion(currentVersion, greaterThan: maxV) {
            return
        }
        
        self.activeRemoteAlert = alert
        self.showRemoteAlert = true
    }
    
    func dismissRemoteAlert(alertId: String?) {
        if let id = alertId {
            UserDefaults.standard.set(id, forKey: lastSeenRemoteAlertIdKey)
        }
        self.showRemoteAlert = false
        self.activeRemoteAlert = nil
    }
    
    func handleRemoteAlertPrimaryAction(alert: RemoteAlertInfo, onCustomAction: (String) -> Void) {
        dismissRemoteAlert(alertId: alert.id)
        
        guard let action = alert.primary_button_action?.lowercased() else { return }
        switch action {
        case "open_store":
            openAppStore()
        case "open_url":
            if let urlStr = alert.primary_button_url, let url = URL(string: urlStr) {
                UIApplication.shared.open(url)
            }
        case "commute_setup", "support", "open_region_settings":
            onCustomAction(action)
        default:
            break
        }
    }
    
    private func checkAppStoreUpdate() async {
        let bundleID = Bundle.main.bundleIdentifier ?? "carlo.InOrario"
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)&country=it") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        
        do {
            let (data, response) = try await NetworkService.shared.get(request: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first else {
                return
            }
            
            if let version = first["version"] as? String, Self.isVersion(version, greaterThan: currentVersion) {
                self.isUpdateAvailable = true
                self.storeVersion = version
                if let trackUrlStr = first["trackViewUrl"] as? String, let parsed = URL(string: trackUrlStr) {
                    self.storeURL = parsed
                }
                triggerPromptIfAllowed()
            }
        } catch {
            // Ignora errori di rete silenziosamente
        }
    }
    
    private func triggerPromptIfAllowed() {
        guard !isCriticalUpdate else {
            self.showUpdatePrompt = true
            return
        }
        
        let snoozedVer = UserDefaults.standard.string(forKey: snoozedVersionKey)
        let snoozedTime = UserDefaults.standard.double(forKey: snoozedTimeKey)
        let now = Date().timeIntervalSince1970
        
        // Se l'utente ha posticipato questa versione nelle ultime 24 ore, non mostrare di continuo
        if snoozedVer == storeVersion && (now - snoozedTime < 86400) {
            return
        }
        
        self.showUpdatePrompt = true
    }
    
    func openAppStore() {
        Haptics.play(.medium)
        let itmsString = storeURL.absoluteString.replacingOccurrences(of: "https://", with: "itms-apps://")
        if let itmsUrl = URL(string: itmsString), UIApplication.shared.canOpenURL(itmsUrl) {
            UIApplication.shared.open(itmsUrl)
        } else {
            UIApplication.shared.open(storeURL)
        }
    }
    
    func snoozeUpdatePrompt() {
        UserDefaults.standard.set(storeVersion, forKey: snoozedVersionKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: snoozedTimeKey)
        self.showUpdatePrompt = false
    }
    
    // MARK: - Semantic Version Comparison
    
    static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let parts1 = clean1.split(separator: ".").compactMap { Int($0) }
        let parts2 = clean2.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(parts1.count, parts2.count)
        
        for i in 0..<maxCount {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return true }
            if p1 < p2 { return false }
        }
        return false
    }
}

// MARK: - App Update Prompt Sheet

struct AppUpdatePromptSheet: View {
    @ObservedObject var updateManager = AppUpdateManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 38))
                    .foregroundColor(.blue)
            }
            .padding(.top, 10)
            
            VStack(spacing: 6) {
                Text(updateManager.updateTitle)
                    .font(.title3)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(updateManager.updateMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 10) {
                Button {
                    updateManager.openAppStore()
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.app.fill")
                        Text("Aggiorna ora su App Store")
                            .fontWeight(.bold)
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                
                if !updateManager.isCriticalUpdate {
                    Button {
                        Haptics.play(.light)
                        updateManager.snoozeUpdatePrompt()
                    } label: {
                        Text("Più tardi")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(20)
        .presentationDetents([.height(310)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Post-Update Notification Permission Prompt Sheet

struct NotificationPermissionPromptSheet: View {
    @ObservedObject var updateManager = AppUpdateManager.shared
    @EnvironmentObject var manager: TrainManager
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.22), Color.blue.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .padding(.top, 8)
                
                VStack(spacing: 6) {
                    Text("Attiva le notifiche di In Orario")
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                    
                    Text("Le notifiche risultano disattivate. Attivale per ricevere solo gli avvisi davvero utili per i tuoi viaggi:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 10) {
                    NotificationFeatureRow(
                        icon: "exclamationmark.triangle.fill",
                        color: .orange,
                        title: "Scioperi ferroviari",
                        subtitle: "Avvisi in anticipo sugli scioperi nazionali e della tua regione, con orari e fasce garantite."
                    )
                    
                    NotificationFeatureRow(
                        icon: "tram.fill",
                        color: .blue,
                        title: "Monitoraggio treni",
                        subtitle: "Ritardi, cambi di binario, partenze e aggiornamenti in tempo reale dei tuoi treni preferiti."
                    )
                    
                    NotificationFeatureRow(
                        icon: "megaphone.fill",
                        color: .indigo,
                        title: "Avvisi di circolazione",
                        subtitle: "Guasti sulla linea, interruzioni improvvise e comunicazioni importanti sui trasporti."
                    )
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Nessuna pubblicità o spam: puoi gestirle o disattivarle quando vuoi.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                
                VStack(spacing: 10) {
                    if updateManager.notificationPermissionAuthStatus == .denied {
                        Button {
                            Haptics.play(.medium)
                            updateManager.markNotificationPermissionPromptHandled()
                            updateManager.showNotificationPermissionPrompt = false
                            updateManager.openSystemNotificationSettings()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "gearshape.fill")
                                Text("Apri Impostazioni per attivarle")
                                    .fontWeight(.bold)
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        
                        Text("Ti porteremo nelle Impostazioni di iOS alla sezione Notifiche.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Button {
                            Haptics.play(.medium)
                            updateManager.markNotificationPermissionPromptHandled()
                            updateManager.showNotificationPermissionPrompt = false
                            manager.requestNotificationPermission()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "bell.badge.fill")
                                Text("Attiva le notifiche")
                                    .fontWeight(.bold)
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    
                    Button {
                        Haptics.play(.light)
                        updateManager.markNotificationPermissionPromptHandled()
                        updateManager.showNotificationPermissionPrompt = false
                    } label: {
                        Text("Non ora")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(20)
        }
        .presentationDetents([.height(540), .large])
        .presentationDragIndicator(.visible)
    }
}

private struct NotificationFeatureRow: View {
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.subheadline.bold())
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
