import SwiftUI
import BackgroundTasks
import UserNotifications
import CoreSpotlight

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var manager: TrainManager?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        
        let ignoreAction = UNNotificationAction(identifier: "IGNORE_STRIKE", title: "Sì lo so, non avvisarmi più", options: [.destructive])
        let strikeCategory = UNNotificationCategory(identifier: "STRIKE_CATEGORY", actions: [ignoreAction], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([strikeCategory])
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.toreroclub.inorario.ai_processing", using: nil) { task in
            guard let bgTask = task as? BGProcessingTask else { return }
            self.handleAIProcessingTask(task: bgTask)
        }
        
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
            if await MainActor.run(resultType: Bool.self, body: { aiManager.preferLocalAI && !aiManager.isLocalModelInstalled }) {
                await MainActor.run {
                    aiManager.downloadModel(aiManager.recommendedModel)
                }
            }
            
            let hasLocalAI = await MainActor.run {
                aiManager.isAppleIntelligenceAvailable || (aiManager.isHardwareCompatible && aiManager.isLocalModelInstalled)
            }
            if hasLocalAI {
                let tempManager = await MainActor.run { TrainManager() }
                let region = await MainActor.run { tempManager.strikeRegion }
                let items = await tempManager.executeRawScraping(region: region)
                let formatted = await AIEngine.shared.formatWithLocalModel(rawItems: items)
                await MainActor.run {
                    tempManager.saveCache(items: formatted)
                    if !tempManager.hasSupport() {
                        aiManager.recordLocalAIExecution()
                    }
                }
            }
            
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
        
        DispatchQueue.main.async {
            self.manager?.apnsToken = token
            self.manager?.syncRemoteNotifications()
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Errore registrazione push remota APNs: \(error.localizedDescription)")
    }
    
    // Mostra le notifiche anche ad app aperta
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
    
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "IGNORE_STRIKE" {
            if let strikeId = response.notification.request.content.userInfo["strike_id"] as? String {
                manager?.ignoreStrike(strikeId: strikeId)
            }
        } else {
            if let trainNumber = response.notification.request.content.userInfo["train_number"] as? String {
                DispatchQueue.main.async {
                    self.manager?.deepLinkTrain = Train(category: "Treno", number: trainNumber, destination: "Caricamento...", time: "--:--", delay: "In orario", platform: "--")
                }
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
    @Environment(\.scenePhase) private var scenePhase

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
                .onAppear {
                    appDelegate.manager = manager
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                        if identifier.starts(with: "inorario://train/") {
                            let trainNumber = identifier.replacingOccurrences(of: "inorario://train/", with: "")
                            DispatchQueue.main.async {
                                manager.deepLinkTrain = Train(category: "Treno", number: trainNumber, destination: "Caricamento...", time: "--:--", delay: "In orario", platform: "--")
                            }
                        } else if identifier.starts(with: "inorario://station/") {
                            let stationId = identifier.replacingOccurrences(of: "inorario://station/", with: "")
                            DispatchQueue.main.async {
                                // If it's not a UUID, let's create a temporary station with the name as the ID
                                // The station views just need a Station object with a name and possibly vtID/rfiID
                                manager.deepLinkStation = Station(name: stationId, rfiID: nil, vtID: stationId, lat: nil, lon: nil)
                            }
                        }
                    }
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                scheduleAppRefresh()
                scheduleAIProcessing()
            }
            if newPhase == .active {
                // Aggiorna spazio libero ogni volta che l'app torna in foreground
                AIFeatureManager.shared.refreshFreeSpace()
                
                // Trigger guessing engine single-shot GPS and logic
                guessingEngine.appEnteredActive(locationManager: locationManager, passanteManager: passanteManager, manager: manager)
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


