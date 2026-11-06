import SwiftUI
import Combine

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
    
    private let lastCheckKey = "last_app_update_check_timestamp"
    private let snoozedVersionKey = "snoozed_update_version"
    private let snoozedTimeKey = "snoozed_update_timestamp"
    private let supporterLastSeenVersionKey = "supporter_last_seen_version"
    private let hasLaunchedBeforeKey = "has_launched_before_key"
    
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    // MARK: - Supporter Update Popup
    
    func checkSupporterUpdatePopup(hasSupport: Bool, forcedByBackend: Bool = false) {
        guard hasSupport else { return }
        
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
        
        // Mostra il popup ai sostenitori SOLO per aggiornamenti principali (es. 1.4 -> 1.5)
        // o se espressamente attivato dal backend, MAI per i piccoli bug fix o micro-patch.
        let isMajorOrMinor = Self.isMajorOrMinorUpdate(from: lastSeen, to: currentVersion)
        if (isMajorOrMinor || forcedByBackend) && Self.isVersion(currentVersion, greaterThan: lastSeen) {
            self.showSupporterCommuteAlert = true
        }
    }
    
    func dismissSupporterCommuteAlert() {
        UserDefaults.standard.set(currentVersion, forKey: supporterLastSeenVersionKey)
        self.showSupporterCommuteAlert = false
    }
    
    func snoozeSupporterCommuteAlert() {
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
    
    // MARK: - App Store & Backend Update Check
    
    func checkForAvailableUpdates(force: Bool = false) async {
        let now = Date().timeIntervalSince1970
        let lastCheck = UserDefaults.standard.double(forKey: lastCheckKey)
        
        // Verifica al massimo ogni 4 ore a meno che non sia forzata
        if !force && (now - lastCheck < 14400) {
            return
        }
        UserDefaults.standard.set(now, forKey: lastCheckKey)
        
        // 1. Prova prima il backend rapido di In Orario (immediato, bypassa i ritardi di cache App Store)
        let backendFound = await checkBackendUpdate()
        if backendFound { return }
        
        // 2. Controllo ufficiale App Store via iTunes Lookup
        await checkAppStoreUpdate()
    }
    
    private func checkBackendUpdate() async -> Bool {
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
            }
            
            let decoded = try JSONDecoder().decode(BackendVersionInfo.self, from: data)
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
