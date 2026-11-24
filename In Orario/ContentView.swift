import SwiftUI
import Combine
import Foundation
import CoreLocation
import ActivityKit
import UserNotifications


struct NewsBannerView: View {
    let news: [NewsItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(news) { item in
                HStack {
                    Image(systemName: item.isUrgent ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundColor(item.isUrgent ? .white : .orange)
                        .font(.title3)
                    
                    VStack(alignment: .leading) {
                        Text(item.title)
                            .font(.headline)
                        Text(item.content)
                            .font(.subheadline)
                    }
                    .foregroundColor(item.isUrgent ? .white : .primary)
                    Spacer()
                }
                .padding()
                .background(item.isUrgent ? Color.red : Color.orange.opacity(0.2))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            }
        }
        .padding(.bottom, 8)
    }
}

struct ContentView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var metroCache: MetroCache
    @EnvironmentObject var metroManager: MetroManager
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var guessingEngine: TrainGuessingEngine
    @Environment(\.scenePhase) var scenePhase
    
    @State private var showingMetroView = false

    
    @State private var newsItems: [NewsItem] = []
    @State private var allNewsItems: [NewsItem] = []
    
    @State private var isPassanteExpanded = false
    @State private var isFavoritesExpanded = true
    @State private var isMyStationsExpanded = true
    @State private var isFavoriteRoutesExpanded = true
    @State private var isNearbyExpanded = true
    @State private var showSearchSheet = false
    @State private var searchInitialAssistant = false
    @State private var searchAutoStartVoice = false
    @State private var searchInitialQuery: String? = nil
    @State private var showMetroHistorySheet = false
    @State private var showSavedTrips = false
    @State private var showHistorySheet = false
    @State private var showProfile = false
    @State private var highlightRegionInProfile = false
    @State private var showNotificationsSettings = false
    @State private var showNewsCenter = false
    @State private var showOnboarding = false
    @State private var showNewSmartRouteSheet = false
    @State private var showPassanteDetailSheet = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("showSuburbanLines") private var showSuburbanLines = true
    @AppStorage("metroMilanoBetaEnabled") private var metroMilanoBetaEnabled = false
    @State private var hasRequestedLocation = false
    @State private var hasPerformedInitialLoad = false
    
    @State private var deepLinkTrain: Train? = nil
    @State private var deepLinkStation: Station? = nil
    @State private var selectedFavoriteTrain: Train? = nil
    @State private var selectedSuggestedStation: Station? = nil
    @State private var selectedSuggestedRoute: FavoriteRoute? = nil
    @State private var isPulsing = false
    @State private var editMode: EditMode = .inactive
    
    @StateObject private var commuteManager = SupporterCommuteManager.shared
    @ObservedObject private var updateManager = AppUpdateManager.shared
    @ObservedObject private var developerReplyManager = DeveloperReplyManager.shared
    @State private var showCommuteSetupSheet = false
    @State private var showPlanBDetailSheet = false
    @State private var planBSheetCustomTitle: String? = nil
    @State private var isLoadingHabitTrip = false
    
    @AppStorage("rememberNearbyState") private var rememberNearbyState = true
    @AppStorage("rememberPassanteState") private var rememberPassanteState = true
    @AppStorage("rememberFavoriteTrainsState") private var rememberFavoriteTrainsState = true
    @AppStorage("rememberMyStationsState") private var rememberMyStationsState = false
    @AppStorage("rememberFavoriteRoutesState") private var rememberFavoriteRoutesState = true
    
    @AppStorage("storedIsNearbyExpanded") private var storedIsNearbyExpanded = true
    @AppStorage("storedIsPassanteExpanded") private var storedIsPassanteExpanded = false
    @AppStorage("storedIsFavoritesExpanded") private var storedIsFavoritesExpanded = true
    @AppStorage("storedIsMyStationsExpanded") private var storedIsMyStationsExpanded = true
    @AppStorage("storedIsFavoriteRoutesExpanded") private var storedIsFavoriteRoutesExpanded = true
    
    let passanteTimer = Timer.publish(every: 45, on: .main, in: .common).autoconnect()
    
    var appTitle: LocalizedStringKey {
        if showingMetroView {
            return "In Orario? Metro"
        }
        if hasUrgentNews {
            return "In Orario? No!"
        }
        return "In Orario?"
    }
    
    var hasUrgentNews: Bool {
        newsItems.contains { item in
            let category = item.category?.lowercased()

            // Uno sciopero cambia il titolo solo nel giorno in cui si svolge.
            if category == "sciopero", let date = strikeDate(from: item.date) {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
                return calendar.isDateInToday(date)
            }

            return false
        }
    }

    private func strikeDate(from value: String?) -> Date? {
        guard let value else { return nil }

        for format in ["yyyy-MM-dd", "dd/MM/yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "it_IT")
            formatter.timeZone = TimeZone(identifier: "Europe/Rome")
            formatter.dateFormat = format
            formatter.isLenient = false

            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }
    
    
    var body: some View {
        NavigationStack {
            Group {
                if showingMetroView {
                    MetroHomeView()
                } else {
                    mainListContent()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(appTitle)
            .toolbar {
                mainToolbarContent()
            }
            .environment(\.editMode, $editMode)
            .background(hiddenSheets())
            .background(hiddenLifecycle1())
            .background(hiddenLifecycle2())
            .background(hiddenLifecycle3())
        }
    }
    
    func loadNews() async {
        // 1. Carica subito la cache offline per visualizzarla all'istante (zero lag all'apertura)
        let offlineCache = manager.getCachedStrikesAndNews()
        if !offlineCache.isEmpty {
            await MainActor.run {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    self.allNewsItems = offlineCache
                    self.newsItems = offlineCache.filter { $0.title != "Info" || $0.isUrgent }
                }
            }
        }
        
        // 2. Esegue il controllo del server in background. Internamente se la cache ha meno di 5 minuti (300s),
        // questa chiamata restituisce la cache all'istante senza inviare chiamate di rete al server Cloud.
        // Se la cache ha più di 5 minuti, effettua una singola chiamata al server e aggiorna la schermata.
        let decodedNews = await manager.fetchStrikesAndNews(forceRefresh: false)
        await MainActor.run {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                self.allNewsItems = decodedNews
                self.newsItems = decodedNews.filter { $0.title != "Info" || $0.isUrgent }
            }
        }
    }
    
    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    self.manager.remoteNotificationsEnabled = true
                    self.manager.strikeNotificationsEnabled = true
                    self.manager.saveFavorites()
                    UIApplication.shared.registerForRemoteNotifications()
                    self.manager.syncRemoteNotifications()
                }
            }
        }
    }

    private func canPresentPostUpdatePrompt() -> Bool {
        !showOnboarding &&
        !showProfile &&
        !showNotificationsSettings &&
        !showCommuteSetupSheet &&
        !showPlanBDetailSheet &&
        !showSearchSheet &&
        !showNewsCenter &&
        deepLinkTrain == nil &&
        deepLinkStation == nil &&
        !manager.pendingOpenRegionSettings &&
        !updateManager.showUpdatePrompt &&
        !updateManager.showRemoteAlert &&
        !updateManager.showSupporterCommuteAlert &&
        !developerReplyManager.showReplyModal
    }

    private func openProfileForRegionSelection() {
        manager.pendingOpenRegionSettings = false
        highlightRegionInProfile = true
        if showProfile {
            return
        }
        let hadOtherSheet = showNotificationsSettings || showCommuteSetupSheet || showPlanBDetailSheet || showSearchSheet || showNewsCenter || updateManager.showNotificationPermissionPrompt
        showNotificationsSettings = false
        showCommuteSetupSheet = false
        showPlanBDetailSheet = false
        showSearchSheet = false
        showNewsCenter = false
        updateManager.showNotificationPermissionPrompt = false
        if hadOtherSheet {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showProfile = true
            }
        } else {
            showProfile = true
        }
    }
    
    func syncPassanteStation(_ station: Station) {
        var canonicalStation: Station? = nil
        for line in SuburbanData.shared.allLines {
            if let matched = line.stations.first(where: { $0.matches(station) }) {
                canonicalStation = matched
                break
            }
        }
        
        guard let canonical = canonicalStation else { return }
        
        if passanteManager.selectedPassanteStation.matches(canonical) {
            return
        }
        
        passanteManager.selectedPassanteStation = canonical
        if isPassanteExpanded {
            Task {
                await passanteManager.fetchPassanteLive(manager: manager)
            }
        }
    }
    func favoriteTrainRow(fav: SavedTrain, dummy: Train) -> some View {
        let titleText: String = {
            if let time = fav.departureTime {
                return "\(dummy.category) \(fav.number) • \(time)"
            } else {
                return "\(dummy.category) \(fav.number)"
            }
        }()
        
        return HStack {
            Image(systemName: "train.side.front.car").foregroundColor(.blue)
            VStack(alignment: .leading) {
                Text(titleText).font(.headline)
                Text(fav.description).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    func passanteLinesContent(activeNearby: Station?) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            if passanteManager.userUsesTunnel {
                PassanteTunnelStatusHeaderView {
                    showPassanteDetailSheet = true
                }
            }
            
            let selectedLines = SuburbanData.shared.allLines.filter { passanteManager.selectedSuburbanLines.contains($0.id) }
            ForEach(selectedLines) { line in
                let hiddenForLine = passanteManager.hiddenSuburbanStations[line.id] ?? []
                let visibleStations = line.stations.filter { !hiddenForLine.contains($0.name) }
                        
                if !visibleStations.isEmpty {
                    SuburbanLineView(line: line, visibleStations: visibleStations, activeNearby: activeNearby)
                    
                    if line.id != selectedLines.last?.id {
                        Divider().padding(.vertical, 5)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    func myStationRow(s: Station) -> some View {
        NavigationLink(destination: SmartBoardView(station: s)) {
            Label(s.formattedName, systemImage: "building.2.crop.circle.fill")
                .foregroundColor(.blue)
                .font(.headline)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                if let vtID = s.vtID {
                    manager.removeMyStation(vtID: vtID)
                }
            } label: {
                Label("Rimuovi", systemImage: "trash.fill")
            }
        }
    }
    
    @ViewBuilder
    func favoriteRouteRow(route: FavoriteRoute) -> some View {
        NavigationLink(destination: FavoriteRouteSolutionView(route: route)) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.swap")
                    .foregroundColor(.green)
                HStack(spacing: 6) {
                    Text(route.originName.formattedStationName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(route.destinationName.formattedStationName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                manager.toggleFavoriteRoute(
                    originName: route.originName,
                    originID: route.originID,
                    destName: route.destinationName,
                    destID: route.destinationID
                )
            } label: {
                Label("Rimuovi", systemImage: "trash.fill")
            }
        }
    }
    
    @ViewBuilder
    func favoriteTrainsSection() -> some View {
        if !manager.favoriteTrains.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $isFavoritesExpanded) {
                    ForEach(manager.favoriteTrains) { fav in
                        let dummy = manager.createDummyTrain(from: fav)
                        Button {
                            selectedFavoriteTrain = dummy
                        } label: {
                            favoriteTrainRow(fav: fav, dummy: dummy)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { Haptics.play(.medium) })
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                manager.toggleFavorite(trainNumber: fav.number, description: fav.description)
                            } label: {
                                Label("Rimuovi", systemImage: "trash.fill")
                            }
                        }
                    }
                    .onMove { from, to in
                        manager.moveFavoriteTrains(from: from, to: to)
                    }
                } label: {
                    Label("I miei Treni", systemImage: "star.fill").font(.headline).foregroundColor(.yellow).padding(.vertical, 4)
                        .onLongPressGesture {
                            Haptics.play(.medium)
                            withAnimation {
                                editMode = editMode == .active ? .inactive : .active
                            }
                        }
                }
                .onChange(of: isFavoritesExpanded) { oldValue, newValue in
                    if rememberFavoriteTrainsState { storedIsFavoritesExpanded = newValue }
                    Haptics.play(.light)
                }
            }
        }
    }
    
    @ViewBuilder
    func myStationsSection() -> some View {
        if !manager.myStations.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $isMyStationsExpanded) {
                    ForEach(manager.myStations) { s in
                        myStationRow(s: s)
                    }
                    .onMove { from, to in
                        manager.moveMyStations(from: from, to: to)
                    }
                } label: {
                    Label("Le Mie Stazioni", systemImage: "building.2.crop.circle.fill")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .padding(.vertical, 4)
                        .onLongPressGesture {
                            Haptics.play(.medium)
                            withAnimation {
                                editMode = editMode == .active ? .inactive : .active
                            }
                        }
                }
                .onChange(of: isMyStationsExpanded) { oldValue, newValue in
                    if rememberMyStationsState { storedIsMyStationsExpanded = newValue }
                    Haptics.play(.light)
                }
            }
        }
    }
    
    @ViewBuilder
    func favoriteRoutesSection() -> some View {
        if !manager.favoriteRoutes.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $isFavoriteRoutesExpanded) {
                    ForEach(manager.favoriteRoutes) { route in
                        favoriteRouteRow(route: route)
                    }
                    .onMove { from, to in
                        manager.moveFavoriteRoutes(from: from, to: to)
                    }
                } label: {
                    Label("Le Mie Tratte Abituali", systemImage: "arrow.triangle.swap")
                        .font(.headline)
                        .foregroundColor(.green)
                        .padding(.vertical, 4)
                        .onLongPressGesture {
                            Haptics.play(.medium)
                            withAnimation {
                                editMode = editMode == .active ? .inactive : .active
                            }
                        }
                }
                .onChange(of: isFavoriteRoutesExpanded) { oldValue, newValue in
                    if rememberFavoriteRoutesState { storedIsFavoriteRoutesExpanded = newValue }
                    Haptics.play(.light)
                }
            }
        }
    }
    
    @ViewBuilder
    func passanteSection() -> some View {
        if !passanteManager.selectedSuburbanLines.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $isPassanteExpanded) {
                    passanteLinesContent(activeNearby: locationManager.manualNearbyStation ?? locationManager.nearbyStation)
                    .padding(.vertical, 10)
                } label: {
                    Label("Linee Suburbane", systemImage: "tram.fill")
                        .font(.headline)
                        .foregroundColor(.orange)
                        .padding(.vertical, 4)
                }
                .onChange(of: isPassanteExpanded) { oldValue, newValue in
                    if rememberPassanteState { storedIsPassanteExpanded = newValue }
                    Haptics.play(.light)
                    if newValue {
                        Task {
                            await passanteManager.fetchPassanteLive(manager: manager)
                        }
                    }
                }
            }
        }
    }
    @ViewBuilder
    func mainListContent() -> some View {
        List {
            if commuteManager.shouldShowPromptBanner {
                CommutePromptBannerView {
                    showCommuteSetupSheet = true
                }
            }
            
            ForEach(manager.sectionOrder, id: \.self) { section in
                if manager.isSectionVisible(section) {
                    switch section {
                    case .nearby:
                        NearbySectionView(
                            smartSuggestions: usageTracker.suggestionsForNow(
                                location: locationManager.userLocation?.coordinate,
                                excludeStations: [locationManager.manualNearbyStation?.name, locationManager.nearbyStation?.name].compactMap { $0 },
                                excludeTrainNumbers: manager.favoriteTrains.map { $0.number },
                                favoriteTrains: manager.favoriteTrains,
                                favoriteStations: manager.myStations
                            ),
                            nearby: locationManager.manualNearbyStation ?? locationManager.nearbyStation,
                            nearbyDistance: locationManager.manualNearbyStation != nil ? nil : locationManager.nearbyStationDistance,
                            activePlan: commuteManager.homeBannerPlanB,
                            habitCommuteSlot: commuteManager.homeBannerPlanB == nil ? commuteManager.activeHabitCommuteSlot() : nil,
                            isLoadingHabitTrip: isLoadingHabitTrip,
                            onSelectPlanB: {
                                planBSheetCustomTitle = nil
                                showPlanBDetailSheet = true
                            },
                            onDismissPlanB: {
                                commuteManager.unpinPlanB()
                                commuteManager.activePlanB = nil
                            },
                            onSelectHabitTrip: { slot in
                                guard !isLoadingHabitTrip else { return }
                                Task {
                                    isLoadingHabitTrip = true
                                    let loc = await locationManager.getCurrentLocation(maxAge: 60)
                                    await commuteManager.requestHabitTripPlan(
                                        for: slot,
                                        userLat: loc?.coordinate.latitude,
                                        userLon: loc?.coordinate.longitude
                                    )
                                    isLoadingHabitTrip = false
                                    if commuteManager.activePlanB != nil {
                                        planBSheetCustomTitle = "Viaggio abituale"
                                        showPlanBDetailSheet = true
                                    }
                                }
                            },
                            selectedFavoriteTrain: $selectedFavoriteTrain,
                            selectedSuggestedStation: $selectedSuggestedStation,
                            selectedSuggestedRoute: $selectedSuggestedRoute
                        )
                    case .favoriteTrains:
                        favoriteTrainsSection()
                    case .myStations:
                        myStationsSection()
                    case .favoriteRoutes:
                        favoriteRoutesSection()
                    case .passante:
                        passanteSection()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.custom(14))
        .refreshable {
            Haptics.play(.medium)
            locationManager.requestLocation()
            await loadNews()
            manager.loadFavorites()
            for train in manager.favoriteTrains {
                await manager.enrichFavoriteTrainData(trainNumber: train.number)
            }
            if isPassanteExpanded {
                await passanteManager.fetchPassanteLive(manager: manager)
            }
        }
    }

    @ViewBuilder
    func hiddenSheets() -> some View {
        Color.clear
            .sheet(isPresented: $showSavedTrips) {
                NavigationStack {
                    SavedTripsView()
                }
            }
            .navigationDestination(item: $selectedSuggestedStation) { s in SmartBoardView(station: s) }
            .navigationDestination(item: $selectedSuggestedRoute) { r in FavoriteRouteSolutionView(route: r) }
            .sheet(isPresented: $showSearchSheet, onDismiss: {
                searchInitialAssistant = false
                searchAutoStartVoice = false
                searchInitialQuery = nil
                manager.loadFavorites()
            }) {
                if showingMetroView {
                    MetroSearchView { station in
                        NotificationCenter.default.post(name: NSNotification.Name("OpenMetroStation"), object: station)
                    }
                } else {
                    SearchView(
                        initialAssistantMode: searchInitialAssistant,
                        autoStartVoice: searchAutoStartVoice,
                        initialQuery: searchInitialQuery
                    )
                }
            }
            .sheet(isPresented: $showMetroHistorySheet) {
                MetroHistorySheet()
                    .environmentObject(metroManager)
            }
            .sheet(isPresented: $showHistorySheet) {
                HistoryView()
            }
            .sheet(isPresented: $showNotificationsSettings) {
                NavigationStack { NotificationsSettingsView(showCloseButton: true) }
            }
            .sheet(isPresented: $showProfile, onDismiss: {
                highlightRegionInProfile = false
            }) {
                ProfileView(highlightRegionSelector: highlightRegionInProfile)
                    .environmentObject(usageTracker)
                    .environmentObject(locationManager)
            }
            .sheet(isPresented: $showNewsCenter) {
                NewsCenterView(news: $allNewsItems)
                    .environmentObject(manager)
            }
            .sheet(isPresented: $showNewSmartRouteSheet) {
                PassanteQuickSetupView()
                    .environmentObject(manager)
            }
            .sheet(isPresented: $showPassanteDetailSheet) {
                PassanteTunnelDetailView()
                    .environmentObject(manager)
                    .environmentObject(passanteManager)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView(showOnboarding: $showOnboarding)
                    .environmentObject(locationManager)
                    .environmentObject(manager)
                    .environmentObject(passanteManager)
                    .onDisappear {
                        hasCompletedOnboarding = true
                        updateManager.markNotificationPermissionPromptHandled()
                        locationManager.requestAuthorization()
                        requestNotificationPermissions()
                        
                        let aiManager = AIFeatureManager.shared
                        if aiManager.aiModeChoice == .local && !aiManager.isAppleIntelligenceAvailable {
                            aiManager.aiModeChoice = .none
                        }
                    }
            }
            .sheet(item: $selectedFavoriteTrain) { t in
                NavigationStack {
                    TrainStopsView(train: t)
                }
            }
            .sheet(item: $deepLinkTrain) { t in
                NavigationStack {
                    TrainStopsView(train: t)
                }
            }
            .sheet(item: $deepLinkStation) { s in
                NavigationStack {
                    StationBoardView(station: s)
                }
            }
            .sheet(isPresented: $showCommuteSetupSheet) {
                NavigationStack {
                    CommuteSetupView(showCloseButton: true)
                }
            }
            .sheet(isPresented: $showPlanBDetailSheet, onDismiss: {
                planBSheetCustomTitle = nil
            }) {
                if commuteManager.hasSupport(),
                   let plan = commuteManager.activePlanB ?? commuteManager.pinnedPlanB {
                    NavigationStack {
                        PlanBDetailView(
                            plan: plan,
                            initialFocusedAlternativeId: commuteManager.chosenAlternativeId,
                            customTitle: planBSheetCustomTitle
                        )
                            .environmentObject(manager)
                            .environmentObject(passanteManager)
                            .environmentObject(locationManager)
                            .environmentObject(metroCache)
                            .environmentObject(usageTracker)
                    }
                }
            }
            .sheet(isPresented: $manager.showPaywallSheet) {
                SupportPaywallSheet()
                    .environmentObject(manager)
            }
            .alert("Soluzioni alternative", isPresented: $updateManager.showSupporterCommuteAlert) {
                Button("Ricordamelo più tardi", role: .cancel) {
                    updateManager.snoozeSupporterCommuteAlert()
                }
                Button("Ok, andiamo") {
                    updateManager.dismissSupporterCommuteAlert()
                    showCommuteSetupSheet = true
                }
            } message: {
                Text("Personalizza le tue abitudini di viaggio per restare sempre aggiornato su eventuali cambiamenti della tua linea, gravi ritardi o cancellazioni che vengono comunicate in anticipo con un elenco di alternative.")
            }
            .sheet(isPresented: $updateManager.showUpdatePrompt) {
                AppUpdatePromptSheet()
            }
            .sheet(isPresented: $updateManager.showNotificationPermissionPrompt, onDismiss: {
                updateManager.markNotificationPermissionPromptHandled()
            }) {
                NotificationPermissionPromptSheet()
                    .environmentObject(manager)
            }
            .sheet(isPresented: $developerReplyManager.showReplyModal) {
                if let reply = developerReplyManager.activeReply {
                    DeveloperReplySheet(reply: reply)
                }
            }
            .alert(
                updateManager.activeRemoteAlert?.title ?? "Avviso",
                isPresented: $updateManager.showRemoteAlert,
                presenting: updateManager.activeRemoteAlert
            ) { alert in
                if !(alert.is_critical ?? false) {
                    Button(alert.secondary_button_title ?? "Chiudi", role: .cancel) {
                        updateManager.dismissRemoteAlert(alertId: alert.id)
                    }
                }
                
                if let primaryTitle = alert.primary_button_title, !primaryTitle.isEmpty {
                    Button(primaryTitle) {
                        updateManager.handleRemoteAlertPrimaryAction(alert: alert) { action in
                            switch action {
                            case "commute_setup":
                                if manager.hasSupport() {
                                    showCommuteSetupSheet = true
                                } else {
                                    manager.showPaywallSheet = true
                                }
                            case "support":
                                manager.showPaywallSheet = true
                            case "open_region_settings":
                                openProfileForRegionSelection()
                            default:
                                break
                            }
                        }
                    }
                }
            } message: { alert in
                Text(alert.message)
            }
    }

    @ViewBuilder
    func hiddenLifecycle1() -> some View {
        Color.clear
            .onAppear {
                if !hasPerformedInitialLoad {
                    hasPerformedInitialLoad = true
                    isNearbyExpanded = rememberNearbyState ? storedIsNearbyExpanded : true
                    isPassanteExpanded = rememberPassanteState ? storedIsPassanteExpanded : false
                    isFavoritesExpanded = rememberFavoriteTrainsState ? storedIsFavoritesExpanded : true
                    isMyStationsExpanded = rememberMyStationsState ? storedIsMyStationsExpanded : true
                    isFavoriteRoutesExpanded = rememberFavoriteRoutesState ? storedIsFavoriteRoutesExpanded : true
                    manager.loadFavorites()
                    manager.syncLiveActivities()
                    
                    Task {
                        for train in manager.favoriteTrains {
                            guard !Task.isCancelled else { break }
                            await manager.enrichFavoriteTrainData(trainNumber: train.number)
                        }
                    }

                    // Controllo popup sostenitori (solo al primo caricamento dopo aggiornamento) e verifica aggiornamenti su App Store
                    if hasCompletedOnboarding {
                        updateManager.checkSupporterUpdatePopup(hasSupport: manager.hasSupport())
                        Task {
                            await updateManager.checkForAvailableUpdates(hasSupport: manager.hasSupport(), strikeRegion: manager.strikeRegion)
                        }
                        Task {
                            try? await Task.sleep(for: .milliseconds(900))
                            await updateManager.evaluatePostUpdateNotificationPrompt {
                                self.canPresentPostUpdatePrompt()
                            }
                        }
                    }
                }
                
                if hasCompletedOnboarding {
                    if locationManager.authorizationStatus == .notDetermined {
                        locationManager.requestAuthorization()
                    }
                    if !hasRequestedLocation {
                        locationManager.requestLocation()
                        hasRequestedLocation = true
                    }
                } else {
                    showOnboarding = true
                }
                if let pendingTrain = manager.deepLinkTrain {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        self.deepLinkTrain = pendingTrain
                        manager.deepLinkTrain = nil
                    }
                }
                if manager.pendingOpenRegionSettings {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        openProfileForRegionSelection()
                    }
                }
                if commuteManager.pendingOpenPlanBSheet, commuteManager.hasSupport(), commuteManager.activePlanB != nil {
                    commuteManager.pendingOpenPlanBSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        self.showPlanBDetailSheet = true
                    }
                }
                withAnimation(.spring()) { }
                
                if isPassanteExpanded {
                    Task {
                        await passanteManager.fetchPassanteLive(manager: manager)
                    }
                }
                
                if let initialNearby = locationManager.manualNearbyStation ?? locationManager.nearbyStation {
                    syncPassanteStation(initialNearby)
                    guessingEngine.markStationSeen(initialNearby.name)
                }
                
            }
            .onChange(of: hasCompletedOnboarding) { oldValue, newValue in
                if !newValue {
                    showProfile = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        showOnboarding = true
                    }
                } else if !oldValue && newValue {
                    updateManager.checkSupporterUpdatePopup(hasSupport: manager.hasSupport())
                    Task {
                        await updateManager.checkForAvailableUpdates(hasSupport: manager.hasSupport(), strikeRegion: manager.strikeRegion)
                    }
                }
            }
            .task(id: manager.strikeRegion) {
                await loadNews()
            }
    }

    @ViewBuilder
    func hiddenLifecycle3() -> some View {
        Color.clear
            .onChange(of: allNewsItems) { oldValue, newValue in
                self.newsItems = newValue.filter { $0.title != "Info" || $0.isUrgent }
            }
            .onChange(of: locationManager.nearbyStation) { oldValue, newValue in
                if let newStation = newValue {
                    if locationManager.manualNearbyStation == nil {
                        syncPassanteStation(newStation)
                    }
                    guessingEngine.markStationSeen(newStation.name)
                }
            }
            .onChange(of: locationManager.manualNearbyStation) { oldValue, newValue in
                if let newStation = newValue {
                    syncPassanteStation(newStation)
                } else if let gpsStation = locationManager.nearbyStation {
                    syncPassanteStation(gpsStation)
                }
            }
            .onChange(of: metroMilanoBetaEnabled) { _, isEnabled in
                if !isEnabled && showingMetroView {
                    showingMetroView = false
                }
            }
            .onChange(of: manager.strikeRegion) { _, newRegion in
                if newRegion != "Lombardia" && !metroMilanoBetaEnabled && showingMetroView {
                    showingMetroView = false
                }
            }
    }

    @ToolbarContentBuilder
    func mainToolbarContent() -> some ToolbarContent {
        // ─── MENU (tre puntini, a sinistra) ───
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                if metroMilanoBetaEnabled || showingMetroView {
                    Button {
                        Haptics.play(.medium)
                        withAnimation {
                            showingMetroView.toggle()
                        }
                    } label: {
                        if showingMetroView {
                            Label("Treni", systemImage: "train.side.front.car")
                        } else {
                            Label("Metropolitana", systemImage: "tram.fill")
                        }
                    }
                }

                Button {
                    Haptics.play(.medium)
                    if showingMetroView {
                        showMetroHistorySheet = true
                    } else {
                        showHistorySheet = true
                    }
                } label: {
                    Label("Cronologia", systemImage: "clock.arrow.circlepath")
                }

                Button {
                    Haptics.play(.medium)
                    showProfile = true
                } label: {
                    Label("Impostazioni", systemImage: "gearshape")
                }

                Button {
                    Haptics.play(.medium)
                    showNotificationsSettings = true
                } label: {
                    Label("Notifiche", systemImage: "bell.fill")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
            }
        }

        // ─── NEWS + VIAGGI + RICERCA (a destra, pillole separate) ───
        if !showingMetroView {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.play(.medium)
                    showNewsCenter = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "newspaper.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("News")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(hasUrgentNews ? .red : .primary)
                }
            }

            if #available(iOS 26, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.play(.medium)
                    showSavedTrips = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "signpost.right.and.left.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Viaggi")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.green)
                }
            }

            if #available(iOS 26, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    Haptics.play(.light)
                    searchInitialAssistant = false
                    searchAutoStartVoice = false
                    searchInitialQuery = nil
                    showSearchSheet = true
                } label: {
                    Label("Cerca", systemImage: "magnifyingglass")
                }

                if !showingMetroView {
                    Button {
                        Haptics.play(.medium)
                        searchInitialAssistant = true
                        searchAutoStartVoice = true
                        searchInitialQuery = nil
                        showSearchSheet = true
                    } label: {
                        Label("Chiedi all'Assistente", systemImage: "sparkles")
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
            } primaryAction: {
                Haptics.play(.medium)
                searchInitialAssistant = false
                searchAutoStartVoice = false
                searchInitialQuery = nil
                showSearchSheet = true
            }
        }
    }

    @ViewBuilder
    func hiddenLifecycle2() -> some View {
        Color.clear
            .alert(manager.hasSupport() ? "Limite Raggiunto" : "Limite gratuito raggiunto", isPresented: Binding(
                get: { manager.notificationLimitError != nil },
                set: { if !$0 { manager.notificationLimitError = nil } }
            )) {
                if !manager.hasSupport() {
                    Button("Passa a In Orario Pro") {
                        manager.notificationLimitError = nil
                        manager.showPaywallSheet = true
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                if let msg = manager.notificationLimitError {
                    Text(msg)
                }
            }
            .onOpenURL { url in
                guard url.scheme == "inorario" else { return }
                
                if url.host == "settings" && url.path.contains("region") {
                    openProfileForRegionSelection()
                    return
                }
                
                let number = url.path.replacingOccurrences(of: "/", with: "")
                let finalNumber = number.isEmpty ? (url.host ?? "") : number
                
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    let dummy = Train(category: "Treno", number: finalNumber, destination: "Caricamento...", time: "--:--", delay: "In orario", platform: "--")
                    self.deepLinkTrain = dummy
                }
            }
            .onChange(of: manager.deepLinkTrain?.number) { old, newNumber in
                if let newNumber = newNumber {
                    let dummy = Train(category: "Treno", number: newNumber, destination: "Caricamento...", time: "--:--", delay: "In orario", platform: "--")
                    self.deepLinkTrain = dummy
                    manager.deepLinkTrain = nil
                }
            }
            .onChange(of: manager.deepLinkStation?.name) { old, newName in
                if let newStation = manager.deepLinkStation {
                    self.deepLinkStation = newStation
                    manager.deepLinkStation = nil
                }
            }
            .onChange(of: manager.pendingOpenRegionSettings) { _, shouldOpen in
                if shouldOpen {
                    openProfileForRegionSelection()
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    if updateManager.pendingNotificationSettingsReturn {
                        updateManager.pendingNotificationSettingsReturn = false
                        manager.checkAndAutoEnableNotifications()
                    }
                    if hasCompletedOnboarding {
                        print("App tornata attiva, aggiorno posizione e passante...")
                        locationManager.requestLocation()
                        Task {
                            await updateManager.checkForAvailableUpdates(hasSupport: manager.hasSupport(), strikeRegion: manager.strikeRegion)
                        }
                        Task {
                            try? await Task.sleep(for: .milliseconds(700))
                            await updateManager.evaluatePostUpdateNotificationPrompt {
                                self.canPresentPostUpdatePrompt()
                            }
                        }
                    }
                    if isPassanteExpanded {
                        Task {
                            await passanteManager.fetchPassanteLive(manager: manager)
                        }
                    }
                }
            }
            .onReceive(passanteTimer) { _ in
                guard scenePhase == .active else { return }
                if isPassanteExpanded && !showPassanteDetailSheet {
                    Task {
                        await passanteManager.fetchPassanteLive(manager: manager)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenProfile"))) { _ in
                showProfile = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenRegionSettings"))) { _ in
                openProfileForRegionSelection()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenCommutePlanB"))) { _ in
                commuteManager.pendingOpenPlanBSheet = false
                guard commuteManager.hasSupport() else {
                    manager.showPaywallSheet = true
                    return
                }
                let hadSheet = showProfile || showNotificationsSettings || showCommuteSetupSheet
                showProfile = false
                showNotificationsSettings = false
                showCommuteSetupSheet = false
                if hadSheet {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        showPlanBDetailSheet = true
                    }
                } else {
                    showPlanBDetailSheet = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerOpenMetroHistorySheet"))) { _ in
                showMetroHistorySheet = true
            }
    }
}

func isStationNearby(station: Station, activeNearby: Station?) -> Bool {
    guard let activeNearby = activeNearby else { return false }
    return station.matches(activeNearby)
}

struct SuburbanLineView: View {
    let line: SuburbanLine
    let visibleStations: [Station]
    let activeNearby: Station?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(line.name)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(line.color)
                .padding(.top, 5)
                .padding(.horizontal, 10)
            
            ScrollView(.horizontal, showsIndicators: false) {
                ScrollViewReader { proxy in
                    HStack(spacing: 0) {
                        ForEach(0..<visibleStations.count, id: \.self) { index in
                            let station = visibleStations[index]
                            let isNearby = isStationNearby(station: station, activeNearby: activeNearby)
                            
                            NavigationLink(destination: SmartBoardView(station: station)) {
                                PassanteNodeView(
                                    station: station,
                                    isFirst: index == 0,
                                    isLast: index == visibleStations.count - 1,
                                    isNearby: isNearby,
                                    lineColor: line.color,
                                    lineId: line.id
                                )
                            }
                            .id(index)
                        }
                    }
                    .padding(.bottom, 20)
                    .padding(.top, 20)
                    .padding(.horizontal, 10)
                    .task {
                        if let targetIndex = visibleStations.firstIndex(where: { isStationNearby(station: $0, activeNearby: activeNearby) }) {
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            guard !Task.isCancelled else { return }
                            withAnimation {
                                proxy.scrollTo(targetIndex, anchor: .center)
                            }
                        }
                    }
                    .onChange(of: activeNearby?.name) { _, _ in
                        if let targetIndex = visibleStations.firstIndex(where: { isStationNearby(station: $0, activeNearby: activeNearby) }) {
                            withAnimation {
                                proxy.scrollTo(targetIndex, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .padding(.vertical, 5)
    }
}

enum HistoryCategory {
    case trips
    case routes
    case stations
    case trains

    var navigationTitle: LocalizedStringKey {
        switch self {
        case .trips: return "Viaggi Recenti"
        case .routes: return "Tratte Recenti"
        case .stations: return "Stazioni Recenti"
        case .trains: return "Treni Recenti"
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var manager: TrainManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab: Int = 0 // 0: Soluzioni, 1: Stazioni, 2: Treni
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    historyTabPill(title: "Soluzioni", systemImage: "arrow.triangle.swap", tag: 0)
                    historyTabPill(title: "Stazioni", systemImage: "building.2.crop.circle.fill", tag: 1)
                    historyTabPill(title: "Treni", systemImage: "train.side.front.car", tag: 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .background(Color(.systemGroupedBackground))

                List {
                    switch selectedTab {
                    case 0:
                        solutionsHistorySections
                    case 1:
                        stationsHistorySection
                    default:
                        trainsHistorySection
                    }
                }
                .listStyle(.insetGrouped)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Cronologia Recenti")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chiudi") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
    }

    @ViewBuilder
    private func historySectionHeader(title: LocalizedStringKey, category: HistoryCategory) -> some View {
        HStack {
            Text(title)
            Spacer()
            NavigationLink {
                ExpandedHistoryView(category: category)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                    .padding(.leading, 12)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Mostra tutta la cronologia")
        }
    }

    @ViewBuilder
    private func historyTabPill(title: LocalizedStringKey, systemImage: String, tag: Int) -> some View {
        let isSelected = selectedTab == tag
        Button {
            Haptics.play(.light)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                selectedTab = tag
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .padding(.horizontal, 8)
            .foregroundColor(isSelected ? .white : .primary)
            .background(
                Capsule()
                    .fill(isSelected ? Color.blue : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(isSelected ? 0 : 0.08), lineWidth: 0.5)
            )
            .shadow(color: isSelected ? Color.blue.opacity(0.22) : .clear, radius: 4, y: 1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func emptyHistoryView(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 46))
                .foregroundColor(.secondary.opacity(0.6))
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 50)
        .listRowBackground(Color.clear)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var solutionsHistorySections: some View {
        if manager.recentViewedTrips.isEmpty && manager.recentRoutes.isEmpty {
            emptyHistoryView(
                icon: "arrow.triangle.swap",
                title: "Nessun viaggio o tratta recente",
                subtitle: "I viaggi e le tratte recenti appariranno qui automaticamente."
            )
        } else {
            if !manager.recentViewedTrips.isEmpty {
                Section(header: historySectionHeader(title: "Viaggi Recenti", category: .trips)) {
                    ForEach(manager.recentViewedTrips.prefix(4)) { trip in
                        NavigationLink(destination: TravelSolutionDetailsView(solution: trip.asTravelSolution)) {
                            RecentViewedTripRow(trip: trip)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                manager.removeRecentViewedTrip(id: trip.id)
                                Haptics.play(.light)
                            } label: {
                                Label("Elimina", systemImage: "trash.fill")
                            }
                        }
                    }
                }
            }

            if !manager.recentRoutes.isEmpty {
                Section(header: historySectionHeader(title: "Tratte Recenti", category: .routes)) {
                    ForEach(manager.recentRoutes.prefix(4)) { route in
                        NavigationLink(destination: FavoriteRouteSolutionView(route: route)) {
                            RecentRouteHistoryRow(route: route)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                manager.removeRecentRoute(route)
                                Haptics.play(.light)
                            } label: {
                                Label("Elimina", systemImage: "trash.fill")
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stationsHistorySection: some View {
        if manager.unifiedRecentStations.isEmpty {
            emptyHistoryView(
                icon: "building.2.crop.circle",
                title: "Nessuna stazione recente",
                subtitle: "Le stazioni che consulterai appariranno qui automaticamente."
            )
        } else {
            Section(header: historySectionHeader(title: "Stazioni viste di recente", category: .stations)) {
                ForEach(manager.unifiedRecentStations.prefix(8)) { result in
                    let tempStation = manager.resolveStation(name: result.nomeLungo, fallbackVtID: result.vtID)
                    NavigationLink(destination: SmartBoardView(station: tempStation)) {
                        RecentStationHistoryRow(stationName: tempStation.name.formattedStationName)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            manager.removeRecentStation(name: result.nomeLungo, vtID: result.vtID)
                            Haptics.play(.light)
                        } label: {
                            Label("Elimina", systemImage: "trash.fill")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var trainsHistorySection: some View {
        if manager.unifiedRecentTrains.isEmpty {
            emptyHistoryView(
                icon: "train.side.front.car",
                title: "Nessun treno recente",
                subtitle: "I treni che aprirai appariranno qui automaticamente."
            )
        } else {
            Section(header: historySectionHeader(title: "Treni visti di recente", category: .trains)) {
                ForEach(manager.unifiedRecentTrains.prefix(7)) { result in
                    let dummy = manager.createDummyTrain(from: result)
                    NavigationLink(destination: TrainStopsView(train: dummy, showCloseButton: false)) {
                        RecentTrainHistoryRow(train: result)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            manager.removeRecentTrain(number: result.number)
                            Haptics.play(.light)
                        } label: {
                            Label("Elimina", systemImage: "trash.fill")
                        }
                    }
                }
            }
        }
    }
}

struct ExpandedHistoryView: View {
    @EnvironmentObject var manager: TrainManager
    let category: HistoryCategory

    private var isEmpty: Bool {
        switch category {
        case .trips: return manager.recentViewedTrips.isEmpty
        case .routes: return manager.recentRoutes.isEmpty
        case .stations: return manager.unifiedRecentStations.isEmpty
        case .trains: return manager.unifiedRecentTrains.isEmpty
        }
    }

    private func clearAll() {
        Haptics.play(.medium)
        switch category {
        case .trips:
            manager.clearRecentViewedTrips()
        case .routes:
            manager.clearRecentRoutes()
        case .stations:
            manager.clearRecentStations()
            manager.clearViewedRecentStations()
        case .trains:
            manager.clearRecentTrains()
            manager.clearViewedRecentTrains()
        }
    }

    var body: some View {
        List {
            if isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "clock.badge.slash")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Cronologia vuota")
                        .font(.title3.bold())
                }
                .padding(.top, 50)
                .listRowBackground(Color.clear)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                switch category {
                case .trips:
                    let sections = groupHistoryByTime(manager.recentViewedTrips, dateFor: { $0.lastViewedAt })
                    ForEach(sections) { section in
                        Section(header: Text(section.title)) {
                            ForEach(section.items) { trip in
                                NavigationLink(destination: TravelSolutionDetailsView(solution: trip.asTravelSolution)) {
                                    RecentViewedTripRow(trip: trip)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        manager.removeRecentViewedTrip(id: trip.id)
                                        Haptics.play(.light)
                                    } label: {
                                        Label("Elimina", systemImage: "trash.fill")
                                    }
                                }
                            }
                        }
                    }
                case .routes:
                    let sections = groupHistoryByTime(manager.recentRoutes, dateFor: { $0.lastViewedAt })
                    ForEach(sections) { section in
                        Section(header: Text(section.title)) {
                            ForEach(section.items) { route in
                                NavigationLink(destination: FavoriteRouteSolutionView(route: route)) {
                                    RecentRouteHistoryRow(route: route)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        manager.removeRecentRoute(route)
                                        Haptics.play(.light)
                                    } label: {
                                        Label("Elimina", systemImage: "trash.fill")
                                    }
                                }
                            }
                        }
                    }
                case .stations:
                    let sections = groupHistoryByTime(manager.unifiedRecentStations, dateFor: { $0.lastViewedAt })
                    ForEach(sections) { section in
                        Section(header: Text(section.title)) {
                            ForEach(section.items) { result in
                                let tempStation = manager.resolveStation(name: result.nomeLungo, fallbackVtID: result.vtID)
                                NavigationLink(destination: SmartBoardView(station: tempStation)) {
                                    RecentStationHistoryRow(stationName: tempStation.name.formattedStationName)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        manager.removeRecentStation(name: result.nomeLungo, vtID: result.vtID)
                                        Haptics.play(.light)
                                    } label: {
                                        Label("Elimina", systemImage: "trash.fill")
                                    }
                                }
                            }
                        }
                    }
                case .trains:
                    let sections = groupHistoryByTime(manager.unifiedRecentTrains, dateFor: { $0.lastViewedAt ?? $0.addedDate })
                    ForEach(sections) { section in
                        Section(header: Text(section.title)) {
                            ForEach(section.items) { result in
                                let dummy = manager.createDummyTrain(from: result)
                                NavigationLink(destination: TrainStopsView(train: dummy, showCloseButton: false)) {
                                    RecentTrainHistoryRow(train: result)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        manager.removeRecentTrain(number: result.number)
                                        Haptics.play(.light)
                                    } label: {
                                        Label("Elimina", systemImage: "trash.fill")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(category.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancella") {
                        clearAll()
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }
}

struct RecentRouteHistoryRow: View {
    let route: FavoriteRoute

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.swap")
                .foregroundColor(.blue)
            HStack(spacing: 6) {
                Text(route.originName.formattedStationName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(route.destinationName.formattedStationName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct RecentStationHistoryRow: View {
    let stationName: String

    var body: some View {
        HStack {
            Image(systemName: "building.2.crop.circle.fill")
                .foregroundColor(.orange)
            Text(stationName)
                .font(.headline)
        }
    }
}

struct RecentTrainHistoryRow: View {
    let train: SavedTrain

    var body: some View {
        let endpoints = train.parsedEndpoints
        let timeRange = train.formattedTimeRange

        HStack(spacing: 12) {
            Image(systemName: "train.side.front.car")
                .foregroundColor(.blue)
                .font(.body)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(train.fullTypeAndNumberTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 6)

                    if let range = timeRange {
                        HStack(spacing: 3) {
                            Text(range.departure)
                            if let arr = range.arrival {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(arr)
                            }
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }

                if let origin = endpoints.origin {
                    HStack(spacing: 5) {
                        Text(origin)
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                        Text(endpoints.destination)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } else {
                    Text(endpoints.destination)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct RecentViewedTripRow: View {
    let trip: SavedTrip

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: "tram.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 14))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("\(trip.origin.formattedStationName) ➔ \(trip.destination.formattedStationName)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(trip.duration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Text(trip.departureTime)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.blue)
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(trip.arrivalTime)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)

                    let compactSummary = trip.compactTrainsSummary
                    if !compactSummary.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(compactSummary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Modern Suggestion Pill (Compact Single-Row Strip Design)

struct ForYouChipItem: Identifiable {
    let id: String
    let suggestion: SmartSuggestion
    var isNearby: Bool = false
    var nearbyDistance: Double? = nil
    var isCurrentTrain: Bool = false
    var isConfirmed: Bool = false
    var isActiveGuess: Bool = false
    var isLiveActivity: Bool = false
    var liveOrigin: String? = nil
    var liveDestination: String? = nil
}

struct NativeSuggestionRow: View {
    let chip: ForYouChipItem
    var onSelectTrain: ((Train) -> Void)? = nil
    var onSelectStation: ((Station) -> Void)? = nil
    var onSelectRoute: ((FavoriteRoute) -> Void)? = nil
    
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var guessingEngine: TrainGuessingEngine
    
    @State private var isPulsing = false
    
    var item: SmartSuggestion { chip.suggestion }
    
    var body: some View {
        Group {
            if chip.isActiveGuess {
                rowContent
                    .onTapGesture {
                        Haptics.play(.medium)
                        guessingEngine.confirmGuess()
                        if case .train(let t) = item {
                            onSelectTrain?(t)
                        }
                    }
            } else {
                Button {
                    Haptics.play(.light)
                    handleTap()
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
            }
        }
        .contextMenu { contextMenuContent }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !chip.isLiveActivity && !chip.isActiveGuess && !chip.isConfirmed {
                Button(role: .destructive) {
                    Haptics.play(.light)
                    withAnimation(.spring()) {
                        usageTracker.ignoreSuggestion(item)
                    }
                } label: {
                    Label("Nascondi", systemImage: "eye.slash")
                }
            }
        }
        .onAppear {
            if chip.isLiveActivity {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
    }
    
    private var rowContent: some View {
        HStack(spacing: 10) {
            Image(systemName: dynamicIconName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 22, height: 22)
                .foregroundColor(dynamicColor)
                .opacity(chip.isLiveActivity && isPulsing ? 0.35 : 1.0)
            
            Text(titleText)
                .font(.headline)
                .foregroundColor(dynamicColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            
            Spacer()
            
            trailingAccessory
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
    
    private func handleTap() {
        switch item {
        case .station(let station):
            onSelectStation?(station)
        case .train(let train):
            onSelectTrain?(train)
        case .route(let route):
            onSelectRoute?(route)
        }
    }
    
    // MARK: - Dynamic Icon & Color
    private var dynamicIconName: String {
        if chip.isActiveGuess {
            return "sparkles"
        } else if chip.isCurrentTrain || chip.isConfirmed {
            return "train.side.front.car"
        } else if chip.isLiveActivity {
            return "livephoto.play"
        } else if chip.isNearby {
            return "location.circle.fill"
        } else {
            switch item {
            case .station:
                return "building.2.crop.circle.fill"
            case .train:
                return "sparkles"
            case .route:
                return "arrow.triangle.swap"
            }
        }
    }
    
    private var dynamicColor: Color {
        if chip.isActiveGuess {
            return .purple
        } else if chip.isCurrentTrain || chip.isConfirmed {
            return .green
        } else if chip.isLiveActivity {
            return .red
        } else if chip.isNearby {
            return .blue
        } else {
            switch item {
            case .station:
                return .orange
            case .train:
                return .purple
            case .route:
                return .purple
            }
        }
    }
    
    // MARK: - Texts
    private func compactLiveStation(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "Partenza", name != "Live Activity" else { return "" }
        
        // Rimuovi prefisso "Milano " se c'è un'altra parola specifica (es. "Milano Centrale" -> "Centrale")
        if name.lowercased().hasPrefix("milano ") {
            let sub = String(name.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            if !sub.isEmpty {
                name = sub
            }
        }
        
        let mappings: [(String, String)] = [
            ("Torino Porta Nuova", "Torino P.N."),
            ("Torino P. Nuova", "Torino P.N."),
            ("Torino Porta Susa", "Torino P.S."),
            ("Torino P. Susa", "Torino P.S."),
            ("Venezia Santa Lucia", "Venezia S.L."),
            ("Venezia S. Lucia", "Venezia S.L."),
            ("Firenze Santa Maria Novella", "Firenze S.M.N."),
            ("Firenze S.M.N.", "Firenze S.M.N."),
            ("Roma Tiburtina", "Roma Tib."),
            ("Bologna Centrale", "Bologna Cle"),
            ("Napoli Centrale", "Napoli Cle"),
            ("Genova Piazza Principe", "Genova P.P."),
            ("Genova P. Principe", "Genova P.P."),
            ("Porta Garibaldi", "P. Garibaldi"),
            ("Porta Nuova", "P.N."),
            ("Porta Susa", "P.S."),
            ("Santa Maria Novella", "S.M.N."),
            ("Santa Lucia", "S.L.")
        ]
        
        for (target, replacement) in mappings {
            if name.localizedCaseInsensitiveContains(target) {
                name = name.replacingOccurrences(of: target, with: replacement, options: .caseInsensitive)
                break
            }
        }
        return name
    }
    
    private var titleText: String {
        switch item {
        case .station(let station):
            return station.formattedName
        case .train(let train):
            let label = (train.category.isEmpty || train.category == "Treno") ? "\(train.number)" : "\(train.category) \(train.number)"
            if chip.isActiveGuess {
                return "Sei su \(label)?"
            }
            if chip.isLiveActivity {
                var orig = chip.liveOrigin ?? ""
                var dest = chip.liveDestination ?? train.destination
                
                // Se la destinazione contiene " - ", estrai partenza e arrivo
                if dest.contains(" - ") {
                    let parts = dest.components(separatedBy: " - ")
                    if orig.isEmpty || orig == "Partenza" { orig = parts[0] }
                    dest = parts[1]
                }
                
                let cleanOrig = compactLiveStation(orig)
                let cleanDest = compactLiveStation(dest)
                
                if !cleanOrig.isEmpty && !cleanDest.isEmpty && cleanOrig != cleanDest {
                    return "\(label) \(cleanOrig) → \(cleanDest)"
                } else if !cleanDest.isEmpty && cleanDest != "Live Activity" {
                    return "\(label) \(cleanDest)"
                }
                return label
            }
            if !train.destination.isEmpty && train.destination != "Live Activity" {
                return "\(label) per \(train.destination)"
            }
            return label
        case .route(let route):
            let orig = route.originName.replacingOccurrences(of: "Milano ", with: "")
            let dest = route.destinationName.replacingOccurrences(of: "Milano ", with: "")
            return "\(orig) → \(dest)"
        }
    }
    
    // MARK: - Trailing Accessory
    @ViewBuilder
    private var trailingAccessory: some View {
        if chip.isActiveGuess {
            HStack(spacing: 8) {
                Button {
                    Haptics.play(.medium)
                    guessingEngine.confirmGuess()
                    if case .train(let t) = item {
                        onSelectTrain?(t)
                    }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                
                Button {
                    Haptics.play(.light)
                    withAnimation(.spring()) {
                        guessingEngine.dismissGuess()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.6))
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
            }
        } else if chip.isCurrentTrain || chip.isConfirmed {
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                Text("A bordo")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.green)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.12))
            .clipShape(Capsule())
        } else if chip.isLiveActivity {
            // Rimosso l'indicatore live dalla barra per massimizzare lo spazio orizzontale
            EmptyView()
        } else if chip.isNearby, let dist = chip.nearbyDistance {
            Text(formattedDistance(dist))
                .font(.subheadline)
                .foregroundColor(.secondary)
        } else if case .station = item {
            Text("Abituale")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
        } else if case .train(let train) = item {
            if !train.delay.isEmpty && train.delay != "--" {
                Text(train.delay)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(train.delay.hasPrefix("+") ? .orange : (train.delay.lowercased().contains("in orario") ? .green : .secondary))
            } else if !train.time.isEmpty && train.time != "--:--" {
                Text(train.time)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func formattedDistance(_ dist: Double) -> String {
        if dist < 1000 {
            let rounded = max(50, Int((dist / 50.0).rounded() * 50))
            return "\(rounded) m"
        } else {
            let km = dist / 1000.0
            let formatted = String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",")
            return "\(formatted) km"
        }
    }
    
    // MARK: - Context Menu
    @ViewBuilder
    private var contextMenuContent: some View {
        if chip.isCurrentTrain || chip.isConfirmed {
            Button {
                Haptics.play(.medium)
                withAnimation(.spring()) {
                    guessingEngine.dismissGuess()
                }
            } label: {
                Label("Termina viaggio a bordo", systemImage: "figure.walk")
            }
            
            Button(role: .destructive) {
                Haptics.play(.medium)
                withAnimation(.spring()) {
                    guessingEngine.dismissGuess()
                }
            } label: {
                Label("Non sono su questo treno", systemImage: "xmark.circle")
            }
        } else if chip.isActiveGuess {
            Button {
                Haptics.play(.medium)
                guessingEngine.confirmGuess()
                if case .train(let t) = item {
                    onSelectTrain?(t)
                }
            } label: {
                Label("Conferma di essere a bordo", systemImage: "checkmark.circle")
            }
            
            Button(role: .destructive) {
                Haptics.play(.medium)
                withAnimation(.spring()) {
                    guessingEngine.dismissGuess()
                }
            } label: {
                Label("Non sono su questo treno", systemImage: "xmark.circle")
            }
        } else if !chip.isLiveActivity {
            Button(role: .destructive) {
                Haptics.play(.medium)
                withAnimation(.spring()) {
                    usageTracker.ignoreSuggestion(item)
                }
            } label: {
                Label("Nascondi da Per te", systemImage: "eye.slash")
            }
        }
    }
}

// MARK: - NearbySectionView (Native Inset-Grouped Pill)

struct NearbySectionView: View {
    let smartSuggestions: [SmartSuggestion]
    let nearby: Station?
    var nearbyDistance: Double? = nil
    var activePlan: PlanBReportDTO? = nil
    var habitCommuteSlot: ActiveHabitCommuteSlot? = nil
    var isLoadingHabitTrip: Bool = false
    var onSelectPlanB: (() -> Void)? = nil
    var onDismissPlanB: (() -> Void)? = nil
    var onSelectHabitTrip: ((ActiveHabitCommuteSlot) -> Void)? = nil
    @Binding var selectedFavoriteTrain: Train?
    @Binding var selectedSuggestedStation: Station?
    @Binding var selectedSuggestedRoute: FavoriteRoute?
    
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var guessingEngine: TrainGuessingEngine
    @EnvironmentObject var usageTracker: UsageTracker
    
    var body: some View {
        let chips: [ForYouChipItem] = {
            var list: [ForYouChipItem] = []
            
            // 1. Treno confermato a bordo
            if let cg = guessingEngine.confirmedGuess {
                list.append(ForYouChipItem(
                    id: "confirmed_\(cg.number)",
                    suggestion: .train(cg),
                    isCurrentTrain: true,
                    isConfirmed: true
                ))
            }
            
            // 2. Active Guess (rilevato, da confermare)
            if let ag = guessingEngine.activeGuess {
                list.append(ForYouChipItem(
                    id: "active_\(ag.number)",
                    suggestion: .train(ag),
                    isActiveGuess: true
                ))
            }
            
            // 3. Live Activities attive
            for liveNum in manager.activeLiveActivities {
                if !list.contains(where: { $0.id.contains(liveNum) }) {
                    var originStation = ""
                    var destStation = ""
                    var trainCategory = ""
                    
                    if let act = Activity<TrainLiveActivityAttributes>.activities.first(where: { $0.attributes.trainNumber == liveNum }) {
                        originStation = act.attributes.origin
                        destStation = act.attributes.destination
                        trainCategory = act.attributes.category
                    }
                    
                    if let fav = manager.favoriteTrains.first(where: { $0.number == liveNum }) {
                        if fav.description.contains(" - ") {
                            let parts = fav.description.components(separatedBy: " - ")
                            if originStation.isEmpty || originStation == "Partenza" { originStation = parts[0] }
                            if destStation.isEmpty || destStation == "Live Activity" { destStation = parts[1] }
                        } else if destStation.isEmpty || destStation == "Live Activity" {
                            destStation = fav.description
                        }
                    }
                    
                    let foundTrain: Train = {
                        if let fav = manager.favoriteTrains.first(where: { $0.number == liveNum }) {
                            let dummy = manager.createDummyTrain(from: fav)
                            let finalCat = (trainCategory.isEmpty || trainCategory == "Treno") ? dummy.category : trainCategory
                            let finalDest = (destStation.isEmpty || destStation == "Live Activity") ? dummy.destination : destStation
                            return Train(category: finalCat, number: dummy.number, destination: finalDest, time: dummy.time, delay: dummy.delay, platform: dummy.platform)
                        }
                        if let sugTrain = smartSuggestions.compactMap({ sug -> Train? in
                            if case .train(let t) = sug { return t }
                            return nil
                        }).first(where: { $0.number == liveNum }) {
                            return sugTrain
                        }
                        return Train(category: trainCategory.isEmpty ? "Treno" : trainCategory, number: liveNum, destination: destStation.isEmpty ? "Live Activity" : destStation, time: "--:--", delay: "", platform: "")
                    }()
                    list.append(ForYouChipItem(
                        id: "live_\(liveNum)",
                        suggestion: .train(foundTrain),
                        isLiveActivity: true,
                        liveOrigin: originStation,
                        liveDestination: destStation
                    ))
                }
            }
            
            // 4. Stazione vicina (da GPS o manuale)
            if let n = nearby, !usageTracker.isStationIgnored(n.name) {
                list.append(ForYouChipItem(
                    id: "nearby_\(n.name)",
                    suggestion: .station(n),
                    isNearby: true,
                    nearbyDistance: nearbyDistance
                ))
            }
            
            // 5. Suggerimenti basati su abitudini consolidate
            for sug in smartSuggestions {
                switch sug {
                case .station(let s):
                    let alreadyHasSuggestedStation = list.contains { $0.id.hasPrefix("sug_station_") }
                    let matchesNearby = nearby?.name.localizedCaseInsensitiveCompare(s.name) == .orderedSame
                    if !alreadyHasSuggestedStation && !matchesNearby && !usageTracker.isStationIgnored(s.name) {
                        list.append(ForYouChipItem(id: "sug_station_\(s.name)", suggestion: sug))
                    }
                case .train(let t):
                    if !list.contains(where: { $0.id.contains(t.number) }) && !usageTracker.isTrainIgnored(t.number) {
                        list.append(ForYouChipItem(id: "sug_train_\(t.number)", suggestion: sug))
                    }
                case .route(let r):
                    let key = "\(r.originID)-\(r.destinationID)"
                    if !usageTracker.isRouteIgnored(key) {
                        list.append(ForYouChipItem(id: "sug_route_\(key)", suggestion: sug))
                    }
                }
            }
            
            return Array(list.prefix(2))
        }()
        
        if !chips.isEmpty || activePlan != nil || habitCommuteSlot != nil {
            Section {
                // Viaggio abituale nella fascia oraria configurata
                if activePlan == nil, let slot = habitCommuteSlot {
                    let originSummary = formatCityOrStationSummary(slot.origins)
                    let destSummary = formatCityOrStationSummary(slot.destinations)
                    Button {
                        Haptics.play(.light)
                        onSelectHabitTrip?(slot)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "tram.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 22, height: 22)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("Viaggio abituale")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(slot.isReturn ? "Ritorno" : "Andata")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundColor(.blue)
                                        .clipShape(Capsule())
                                }
                                Text("\(originSummary) → \(destSummary) · \(slot.timeBand)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            if isLoadingHabitTrip {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingHabitTrip)
                }

                // Percorso alternativo integrato in stile nativo
                if let plan = activePlan {
                    let chosenAlt = plan.alternatives.first(where: {
                        $0.id == SupporterCommuteManager.shared.chosenAlternativeId ||
                        SupporterCommuteManager.shared.chosenAlternativeId?.hasPrefix("\($0.train_number)_\($0.departure_time)") == true
                    })
                    let originSummary = formatCityOrStationSummary(plan.origins)
                    let destSummary = formatCityOrStationSummary(plan.destinations)
                    let timeText: String = {
                        if let first = plan.alternatives.first?.departure_time, !first.isEmpty, first != "--:--" {
                            return first
                        }
                        if !plan.target_time.isEmpty {
                            return plan.target_time
                        }
                        return ""
                    }()
                    
                    Button {
                        Haptics.play(.light)
                        onSelectPlanB?()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.triangle.swap")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 22, height: 22)
                                .foregroundColor(.orange)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                let bannerTitle = (plan.incident_type == "summary_ok") ? "Treno seguito" : "Percorso alternativo"
                                if let chosen = chosenAlt {
                                    let cleanCat = cleanTrainCategory(chosen.category)
                                    HStack(spacing: 5) {
                                        Text(bannerTitle)
                                            .font(.headline)
                                            .foregroundColor(.orange)
                                        Text("· \(cleanCat.isEmpty ? "" : "\(cleanCat) ")\(chosen.train_number)")
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                    }
                                    Text("da \(chosen.station) per \(chosen.destination)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text(bannerTitle)
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    HStack(spacing: 4) {
                                        Text("\(originSummary) – \(destSummary)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                        if !timeText.isEmpty {
                                            Text("· \(timeText)")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            if let chosen = chosenAlt {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(chosen.departure_time)
                                        .font(.subheadline.weight(.heavy))
                                        .foregroundColor(chosen.delay > 0 ? .orange : .green)
                                    if chosen.delay > 0 {
                                        Text("+\(chosen.delay) min")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    } else {
                                        Text("In orario")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    }
                                }
                            } else if !plan.alternatives.isEmpty {
                                Text("\(plan.alternatives.count) opzioni")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Haptics.play(.light)
                            onDismissPlanB?()
                        } label: {
                            Label("Nascondi", systemImage: "eye.slash")
                        }
                    }
                }
                
                ForEach(chips) { chip in
                    NativeSuggestionRow(
                        chip: chip,
                        onSelectTrain: { t in selectedFavoriteTrain = t },
                        onSelectStation: { s in selectedSuggestedStation = s },
                        onSelectRoute: { r in selectedSuggestedRoute = r }
                    )
                }
            }
        }
    }
}

