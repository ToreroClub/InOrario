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
    @State private var isNearbyExpanded = true
    @State private var showSearchSheet = false
    @State private var showMetroHistorySheet = false
    @State private var showSavedTrips = false
    @State private var showHistorySheet = false
    @State private var showProfile = false
    @State private var showNotificationsSettings = false
    @State private var showNewsCenter = false
    @State private var showOnboarding = false
    @State private var showNewSmartRouteSheet = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("showSuburbanLines") private var showSuburbanLines = true
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
    @State private var showCommuteSetupSheet = false
    @State private var showPlanBDetailSheet = false
    
    @AppStorage("rememberNearbyState") private var rememberNearbyState = true
    @AppStorage("rememberPassanteState") private var rememberPassanteState = true
    @AppStorage("rememberFavoriteTrainsState") private var rememberFavoriteTrainsState = true
    @AppStorage("rememberMyStationsState") private var rememberMyStationsState = false
    
    @AppStorage("storedIsNearbyExpanded") private var storedIsNearbyExpanded = true
    @AppStorage("storedIsPassanteExpanded") private var storedIsPassanteExpanded = true
    @AppStorage("storedIsFavoritesExpanded") private var storedIsFavoritesExpanded = true
    @AppStorage("storedIsMyStationsExpanded") private var storedIsMyStationsExpanded = true
    
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
                PassanteTunnelStatusHeaderView()
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
    func passanteSection() -> some View {
        if showSuburbanLines && !passanteManager.selectedSuburbanLines.isEmpty {
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
                switch section {
                case .nearby:
                    NearbySectionView(
                        smartSuggestions: usageTracker.suggestionsForNow(
                            location: locationManager.userLocation?.coordinate,
                            excludeStations: [locationManager.manualNearbyStation?.name, locationManager.nearbyStation?.name].compactMap { $0 },
                            excludeTrainNumbers: isFavoritesExpanded ? manager.favoriteTrains.map { $0.number } : [],
                            favoriteTrains: manager.favoriteTrains
                        ),
                        nearby: locationManager.manualNearbyStation ?? locationManager.nearbyStation,
                        nearbyDistance: locationManager.manualNearbyStation != nil ? nil : locationManager.nearbyStationDistance,
                        activePlan: commuteManager.pinnedPlanB ?? commuteManager.activePlanB,
                        onSelectPlanB: {
                            showPlanBDetailSheet = true
                        },
                        onDismissPlanB: {
                            commuteManager.unpinPlanB()
                            commuteManager.activePlanB = nil
                        },
                        selectedFavoriteTrain: $selectedFavoriteTrain,
                        selectedSuggestedStation: $selectedSuggestedStation,
                        selectedSuggestedRoute: $selectedSuggestedRoute
                    )
                case .favoriteTrains:
                    favoriteTrainsSection()
                case .myStations:
                    myStationsSection()
                case .passante:
                    passanteSection()
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
            .sheet(isPresented: $showSearchSheet, onDismiss: { manager.loadFavorites() }) {
                if showingMetroView {
                    MetroSearchView { station in
                        NotificationCenter.default.post(name: NSNotification.Name("OpenMetroStation"), object: station)
                    }
                } else {
                    SearchView()
                }
            }
            .sheet(isPresented: $showMetroHistorySheet) {
                MetroHistorySheet()
                    .environmentObject(metroManager)
            }
            .sheet(isPresented: $showHistorySheet) { HistoryView() }
            .sheet(isPresented: $showNotificationsSettings) {
                NavigationStack { NotificationsSettingsView() }
            }
            .sheet(isPresented: $showProfile) {
                ProfileView()
                    .environmentObject(usageTracker)
            }
            .sheet(isPresented: $showNewsCenter) {
                NewsCenterView(news: $allNewsItems)
                    .environmentObject(manager)
            }
            .sheet(isPresented: $showNewSmartRouteSheet) {
                PassanteQuickSetupView()
                    .environmentObject(manager)
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView(showOnboarding: $showOnboarding)
                    .environmentObject(locationManager)
                    .environmentObject(manager)
                    .environmentObject(passanteManager)
                    .onDisappear {
                        hasCompletedOnboarding = true
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
                    CommuteSetupView()
                }
            }
            .sheet(isPresented: $showPlanBDetailSheet) {
                if let plan = commuteManager.pinnedPlanB ?? commuteManager.activePlanB {
                    NavigationStack {
                        PlanBDetailView(plan: plan, initialFocusedAlternativeId: commuteManager.chosenAlternativeId)
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
    }

    @ViewBuilder
    func hiddenLifecycle1() -> some View {
        Color.clear
            .onAppear {
                if !hasPerformedInitialLoad {
                    hasPerformedInitialLoad = true
                    if rememberNearbyState { isNearbyExpanded = storedIsNearbyExpanded }
                    if rememberPassanteState { isPassanteExpanded = storedIsPassanteExpanded }
                    if rememberFavoriteTrainsState { isFavoritesExpanded = storedIsFavoritesExpanded }
                    if rememberMyStationsState { isMyStationsExpanded = storedIsMyStationsExpanded }
                    manager.loadFavorites()
                    manager.syncLiveActivities()
                    
                    Task {
                        for train in manager.favoriteTrains {
                            guard !Task.isCancelled else { break }
                            await manager.enrichFavoriteTrainData(trainNumber: train.number)
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
                
                // Controllo popup sostenitori (dopo aggiornamento app) e verifica aggiornamenti disponibili su App Store
                if hasCompletedOnboarding {
                    updateManager.checkSupporterUpdatePopup(hasSupport: manager.hasSupport())
                    Task {
                        await updateManager.checkForAvailableUpdates()
                    }
                }
                
            }
            .onChange(of: hasCompletedOnboarding) { oldValue, newValue in
                if !newValue {
                    showProfile = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        showOnboarding = true
                    }
                } else {
                    updateManager.checkSupporterUpdatePopup(hasSupport: manager.hasSupport())
                    Task {
                        await updateManager.checkForAvailableUpdates()
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
    }

    @ToolbarContentBuilder
    func mainToolbarContent() -> some ToolbarContent {
        // ─── MENU (tre puntini, a sinistra) ───
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button {
                    Haptics.play(.medium)
                    showProfile = true
                } label: {
                    Label("Impostazioni", systemImage: "gearshape")
                }

                Button {
                    Haptics.play(.medium)
                    showHistorySheet = true
                } label: {
                    Label("Cronologia", systemImage: "clock.arrow.circlepath")
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
            Button {
                Haptics.play(.medium)
                showSearchSheet = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
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
                    Button("Sostieni il progetto") {
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
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    if hasCompletedOnboarding {
                        print("App tornata attiva, aggiorno posizione e passante...")
                        locationManager.requestLocation()
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
                if isPassanteExpanded {
                    Task {
                        await passanteManager.fetchPassanteLive(manager: manager)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenProfile"))) { _ in
                showProfile = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenCommutePlanB"))) { _ in
                showPlanBDetailSheet = true
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

struct HistoryView: View {
    @EnvironmentObject var manager: TrainManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if manager.unifiedRecentTrains.isEmpty && manager.unifiedRecentStations.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "clock.badge.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("Cronologia vuota")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("I treni e le stazioni che aprirai appariranno qui automaticamente.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 50)
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    if !manager.unifiedRecentTrains.isEmpty {
                        Section(header: HStack {
                            Text("Treni visti di recente")
                            Spacer()
                            Button("Cancella") {
                                manager.clearRecentTrains()
                                manager.clearViewedRecentTrains()
                                Haptics.play(.medium)
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }) {
                            ForEach(manager.unifiedRecentTrains) { result in
                                let dummy = manager.createDummyTrain(from: result)
                                NavigationLink(destination: TrainStopsView(train: dummy, showCloseButton: false)) {
                                    HStack {
                                        Image(systemName: "train.side.front.car").foregroundColor(.blue)
                                        VStack(alignment: .leading) {
                                            Text(String(format: String(localized: "Treno %@"), result.number)).font(.headline)
                                            Text(result.description).font(.caption).foregroundColor(.secondary)
                                        }
                                    }
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
                    
                    if !manager.unifiedRecentStations.isEmpty {
                        Section(header: HStack {
                            Text("Stazioni viste di recente")
                            Spacer()
                            Button("Cancella") {
                                manager.clearRecentStations()
                                manager.clearViewedRecentStations()
                                Haptics.play(.medium)
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }) {
                            ForEach(manager.unifiedRecentStations) { result in
                                let tempStation = manager.resolveStation(name: result.nomeLungo, fallbackVtID: result.vtID)
                                
                                NavigationLink(destination: SmartBoardView(station: tempStation)) {
                                    HStack {
                                        Image(systemName: "building.2.crop.circle.fill").foregroundColor(.orange)
                                        Text(tempStation.name.formattedStationName).font(.headline)
                                    }
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
            }
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
        } else if case .train(let train) = item, !train.delay.isEmpty, train.delay != "--" {
            Text(train.delay)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(train.delay.hasPrefix("+") ? .orange : (train.delay.lowercased().contains("in orario") ? .green : .secondary))
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
    var onSelectPlanB: (() -> Void)? = nil
    var onDismissPlanB: (() -> Void)? = nil
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
                    let alreadyHasStation = list.contains { item in
                        if case .station = item.suggestion { return true }
                        return false
                    }
                    if nearby == nil && !alreadyHasStation && !usageTracker.isStationIgnored(s.name) {
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
        
        if !chips.isEmpty || activePlan != nil {
            Section {
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
                                if let chosen = chosenAlt {
                                    let cleanCat = cleanTrainCategory(chosen.category)
                                    HStack(spacing: 5) {
                                        Text("Percorso alternativo")
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
                                    Text("Percorso alternativo")
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

