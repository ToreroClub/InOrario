import SwiftUI
import BackgroundTasks
import UserNotifications
import CoreSpotlight
import WidgetKit

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var manager: TrainManager?
    var pendingDeepLinkTrain: Train?
    var pendingOpenRegionSettings: Bool = false

    private func extractTrainNumber(from userInfo: [AnyHashable: Any]) -> String? {
        if let s = userInfo["train_number"] as? String, !s.isEmpty { return s }
        if let n = userInfo["train_number"] as? NSNumber { return n.stringValue }
        return nil
    }

    @MainActor
    private func setDeepLinkTrain(_ train: Train) {
        if let manager = self.manager {
            manager.deepLinkTrain = train
        } else {
            self.pendingDeepLinkTrain = train
        }
    }

    @MainActor
    private func triggerOpenRegionSettings() {
        if let manager = self.manager {
            manager.pendingOpenRegionSettings = true
            NotificationCenter.default.post(name: NSNotification.Name("OpenRegionSettings"), object: nil)
        } else {
            self.pendingOpenRegionSettings = true
        }
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        
        let ignoreAction = UNNotificationAction(identifier: "IGNORE_STRIKE", title: "Sì lo so, non avvisarmi più", options: [.destructive])
        let strikeCategory = UNNotificationCategory(identifier: "STRIKE_CATEGORY", actions: [ignoreAction], intentIdentifiers: [], options: [])
        
        let confirmTrainAction = UNNotificationAction(identifier: "CONFIRM_TRAIN_GUESS", title: "Sì, sono a bordo", options: [.foreground])
        let dismissTrainAction = UNNotificationAction(identifier: "DISMISS_TRAIN_GUESS", title: "No", options: [.destructive])
        let trainGuessCategory = UNNotificationCategory(identifier: "TRAIN_GUESS_CATEGORY", actions: [confirmTrainAction, dismissTrainAction], intentIdentifiers: [], options: [])
        
        UNUserNotificationCenter.current().setNotificationCategories([strikeCategory, trainGuessCategory])
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.toreroclub.inorario.ai_processing", using: nil) { task in
            guard let bgTask = task as? BGProcessingTask else { return }
            self.handleAIProcessingTask(task: bgTask)
        }
        
        UIApplication.shared.registerForRemoteNotifications()
        
        return true
    }
    
    func handleAIProcessingTask(task: BGProcessingTask) {
        let aiManager = AIFeatureManager.shared
        
        task.expirationHandler = {
            if aiManager.isDownloadingModel {
                aiManager.cancelDownload()
            }
        }
        
        Task {
            let tempManager = await MainActor.run { TrainManager() }
            _ = await tempManager.fetchStrikesAndNews(forceRefresh: true)
            
            await MainActor.run {
                AIFeatureManager.shared.performDailySpaceCheck()
            }
            
            task.setTaskCompleted(success: true)
        }
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("Device Token APNs: \(token)")
        
        UserDefaults.standard.set(token, forKey: "apnsTokenKey_v1")
        
        DispatchQueue.main.async {
            let isNewToken = self.manager?.apnsToken != token
            self.manager?.apnsToken = token
            if let mgr = self.manager, !mgr.remoteNotificationsEnabled {
                mgr.remoteNotificationsEnabled = true
                mgr.strikeNotificationsEnabled = true
                mgr.saveFavorites()
            }
            if isNewToken {
                self.manager?.syncLiveActivities()
            }
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Errore registrazione push remota APNs: \(error.localizedDescription)")
    }
    
    // Mostra le notifiche anche ad app aperta
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        let category = notification.request.content.categoryIdentifier
        if category == "DEVELOPER_REPLY" || userInfo["type"] as? String == "developer_reply" {
            let title = notification.request.content.title
            let body = notification.request.content.body
            DeveloperReplyManager.shared.handleIncomingReply(userInfo: userInfo, title: title, body: body)
        }
        completionHandler([.banner, .sound, .badge])
    }
    
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let userInfo = response.notification.request.content.userInfo
        
        if category == "DEVELOPER_REPLY" || userInfo["type"] as? String == "developer_reply" {
            let title = response.notification.request.content.title
            let body = response.notification.request.content.body
            DeveloperReplyManager.shared.handleIncomingReply(userInfo: userInfo, title: title, body: body)
        } else if action == "IGNORE_STRIKE" {
            if let strikeId = userInfo["strike_id"] as? String {
                manager?.ignoreStrike(strikeId: strikeId)
            }
        } else if action == "CONFIRM_TRAIN_GUESS" || (action == UNNotificationDefaultActionIdentifier && category == "TRAIN_GUESS_CATEGORY") {
            NotificationCenter.default.post(name: NSNotification.Name("ConfirmTrainGuessNotification"), object: nil, userInfo: userInfo)
            if let trainNumber = extractTrainNumber(from: userInfo) {
                let cat = userInfo["train_category"] as? String ?? "Treno"
                let dest = userInfo["train_destination"] as? String ?? "Destinazione"
                let time = userInfo["train_time"] as? String ?? "--:--"
                let delay = userInfo["train_delay"] as? String ?? "In orario"
                let platform = userInfo["train_platform"] as? String ?? "--"
                
                let t = Train(category: cat, number: trainNumber, destination: dest, time: time, delay: delay, platform: platform)
                setDeepLinkTrain(t)
            }
        } else if action == "DISMISS_TRAIN_GUESS" {
            NotificationCenter.default.post(name: NSNotification.Name("DismissTrainGuessNotification"), object: nil)
        } else if category == "COMMUTE_PLAN_B" || userInfo["plan_b"] != nil {
            if let planData = userInfo["plan_b"] as? [String: Any],
               let jsonData = try? JSONSerialization.data(withJSONObject: planData),
               let plan = try? JSONDecoder().decode(PlanBReportDTO.self, from: jsonData) {
                SupporterCommuteManager.shared.chosenAlternativeId = nil
                SupporterCommuteManager.shared.unpinPlanB()
                if plan.incident_type == "summary_ok" {
                    SupporterCommuteManager.shared.activePlanB = nil
                    SupporterCommuteManager.shared.pendingOpenPlanBSheet = false
                } else {
                    SupporterCommuteManager.shared.activePlanB = plan
                    SupporterCommuteManager.shared.pendingOpenPlanBSheet = true
                    NotificationCenter.default.post(name: NSNotification.Name("OpenCommutePlanB"), object: nil)
                }
            }
        } else if category == "SELECT_REGION" || userInfo["type"] as? String == "select_region" {
            triggerOpenRegionSettings()
        } else {
            if let trainNumber = extractTrainNumber(from: userInfo) {
                let t = Train(category: "Treno", number: trainNumber, destination: "Caricamento...", time: "--:--", delay: "In orario", platform: "--")
                setDeepLinkTrain(t)
            }
        }
        completionHandler()
    }
}

@main
struct InOrario: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var manager = TrainManager()
    @StateObject private var passanteManager = PassanteManager()
    @StateObject private var metroCache = MetroCache()
    @StateObject private var metroManager = MetroManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var usageTracker = UsageTracker()
    @StateObject private var guessingEngine = TrainGuessingEngine()
    @StateObject private var personalLinesManager = PersonalLinesManager()
    @StateObject private var navigationCoordinator = MainNavigationCoordinator()
    @Environment(\.scenePhase) private var scenePhase
    @State private var foregroundHousekeepingTask: Task<Void, Never>? = nil
    @State private var lastEntitlementCheckAt: Date = .distantPast
    
    @AppStorage("app_language") private var appLanguage: String = "it"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(manager)
                .environmentObject(passanteManager)
                .environmentObject(metroCache)
                .environmentObject(metroManager)
                .environmentObject(locationManager)
                .environmentObject(usageTracker)
                .environmentObject(guessingEngine)
                .environmentObject(personalLinesManager)
                .environmentObject(navigationCoordinator)
                .environment(\.locale, Locale(identifier: appLanguage))
                .onAppear {
                    appDelegate.manager = manager
                    if let pending = appDelegate.pendingDeepLinkTrain {
                        manager.deepLinkTrain = pending
                        appDelegate.pendingDeepLinkTrain = nil
                    }
                    if appDelegate.pendingOpenRegionSettings {
                        manager.pendingOpenRegionSettings = true
                        appDelegate.pendingOpenRegionSettings = false
                    }
                    if let savedToken = UserDefaults.standard.string(forKey: "apnsTokenKey_v1"), !savedToken.isEmpty {
                        if manager.apnsToken != savedToken {
                            manager.apnsToken = savedToken
                        }
                    }
                    UserInterestTelemetryManager.shared.syncIfNeededForToday(manager: manager, usageTracker: usageTracker)
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                        if identifier.starts(with: "inorario://train/") {
                            let trainNumber = identifier.replacingOccurrences(of: "inorario://train/", with: "")
                            manager.deepLinkTrain = Train(category: "Treno", number: trainNumber, destination: "Caricamento...", time: "--:--", delay: "In orario", platform: "--")
                        } else if identifier.starts(with: "inorario://station/") {
                            let stationId = identifier.replacingOccurrences(of: "inorario://station/", with: "")
                            // If it's not a UUID, let's create a temporary station with the name as the ID
                            // The station views just need a Station object with a name and possibly vtID/rfiID
                            manager.deepLinkStation = Station(name: stationId, rfiID: nil, vtID: stationId, lat: nil, lon: nil)
                        }
                    }
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                foregroundHousekeepingTask?.cancel()
                foregroundHousekeepingTask = nil
                UserInterestTelemetryManager.shared.flushToDiskNow()
                scheduleAppRefresh()
                scheduleAIProcessing()
                WidgetCenter.shared.reloadAllTimelines()
            }
            if newPhase == .active {
                // Operazioni leggere/visibili immediate al ritorno in foreground
                manager.syncLiveActivities()
                guessingEngine.appEnteredActive(locationManager: locationManager, passanteManager: passanteManager, manager: manager)
                Task {
                    await manager.backgroundLiveActivityUpdate()
                }

                // Scagliona i task secondari (StoreKit, spazio libero, sync push, telemetria) per evitare picchi al risveglio
                foregroundHousekeepingTask?.cancel()
                foregroundHousekeepingTask = Task {
                    try? await Task.sleep(for: .milliseconds(1500))
                    guard !Task.isCancelled else { return }
                    AIFeatureManager.shared.refreshFreeSpace()
                    if Date().timeIntervalSince(lastEntitlementCheckAt) >= 30 {
                        lastEntitlementCheckAt = Date()
                        await TipManager.shared.updatePurchases()
                    }
                    manager.syncRemoteNotifications()
                    UserInterestTelemetryManager.shared.syncIfNeededForToday(manager: manager, usageTracker: usageTracker)
                }
            }
        }
        .backgroundTask(.appRefresh("com.carlo.InOrario.refresh")) {
            await manager.backgroundLiveActivityUpdate()
        }
    }
    
    private func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.carlo.InOrario.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 10 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Impossibile schedulare l'aggiornamento in background: \(error)")
        }
    }
    
    private func scheduleAIProcessing() {
        let request = BGProcessingTaskRequest(identifier: "com.toreroclub.inorario.ai_processing")
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = true // Preferibilmente di notte sotto carica
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // Tra un'ora
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Impossibile schedulare l'elaborazione AI in background: \(error)")
        }
    }
}


