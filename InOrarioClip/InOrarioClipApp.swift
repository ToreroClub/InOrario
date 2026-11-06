import SwiftUI

@main
struct InOrarioClipApp: App {
    @State private var currentStation: Station = ClipLinkHandler.shared.defaultStation()
    @StateObject private var locationManager = ClipLocationManager.shared
    @State private var didReceiveExplicitURL = false
    
    var body: some Scene {
        WindowGroup {
            ClipStationBoardView(station: $currentStation)
                .tint(.orange)
                .onAppear {
                    checkAndApplyNearbyStationIfNeeded()
                }
                .onChange(of: locationManager.nearbyStations.first?.station.id) { _ in
                    checkAndApplyNearbyStationIfNeeded()
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    handleIncomingActivity(userActivity)
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
    }
    
    private func checkAndApplyNearbyStationIfNeeded() {
        // Se l'utente ha scansionato un link specifico per una stazione, diamo priorità a quello
        guard !didReceiveExplicitURL else { return }
        
        // Se la posizione è già autorizzata e abbiamo una stazione vicina, impostala automaticamente
        if let closest = locationManager.closestStation {
            self.currentStation = closest
        }
    }
    
    // MARK: - Link Handlers
    
    private func handleIncomingActivity(_ activity: NSUserActivity) {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = activity.webpageURL else {
            return
        }
        handleIncomingURL(url)
    }
    
    private func handleIncomingURL(_ url: URL) {
        if let resolved = ClipLinkHandler.shared.resolveStation(from: url) {
            self.didReceiveExplicitURL = true
            self.currentStation = resolved
        }
    }
}
