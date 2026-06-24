
import SwiftUI
import BackgroundTasks
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var manager: TrainManager?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        
        let ignoreAction = UNNotificationAction(identifier: "IGNORE_STRIKE", title: "Sì lo so, non avvisarmi più", options: [.destructive])
        let strikeCategory = UNNotificationCategory(identifier: "STRIKE_CATEGORY", actions: [ignoreAction], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([strikeCategory])
        
        return true
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
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
    
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
    @StateObject private var locationManager = LocationManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(manager)
                .environmentObject(passanteManager)
                .environmentObject(metroCache)
                .environmentObject(locationManager)
                .onAppear {
                    appDelegate.manager = manager
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                scheduleAppRefresh()
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
}


