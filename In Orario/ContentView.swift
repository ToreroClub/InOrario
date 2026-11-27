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
    @EnvironmentObject var personalLinesManager: PersonalLinesManager
    @EnvironmentObject var navigationCoordinator: MainNavigationCoordinator
    @Environment(\.scenePhase) var scenePhase
    
    @State private var showingMetroView = false

    
    @State private var newsItems: [NewsItem] = []
    @State private var allNewsItems: [NewsItem] = []
    
    @State private var isPassanteExpanded = false
    @State private var isFavoritesExpanded = true
    @State private var isMyStationsExpanded = true
    @State private var isFavoriteRoutesExpanded = true
    @State private var isNearbyExpanded = true
    @State private var expandedHomeLineIDs: Set<String> = []
    @State private var showSearchSheet = false
    @State private var searchSheetSessionID = UUID()
    @State private var searchInitialAssistant = false
    @State private var searchAutoStartVoice = false
    @State private var searchInitialQuery: String? = nil
    @State private var showMetroHistorySheet = false
    @State private var showSavedTrips = false
    @State private var activeHistorySheet: HistorySheetPresentation? = nil
    @State private var showProfile = false
    @State private var highlightRegionInProfile = false
    @State private var showNotificationsSettings = false
    @State private var showNewsCenter = false
    @State private var newsCenterInitialCategory: NewsCategory? = nil
    @State private var showCustomizeDashboardSheet = false
    @State private var showAllHomeTrains = false
    @State private var showAllHomeStations = false
    @State private var showAllHomeTrips = false
    @State private var showOnboarding = false
    @State private var onboardingMode: OnboardingPresentationMode = .fullFirstLaunch
    @State private var onboardingInitialPermissions = OnboardingPermissionSnapshot(
        notifications: .notDetermined,
        location: .notDetermined
    )
    @State private var showNewSmartRouteSheet = false
    @State private var showPassanteDetailSheet = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(OnboardingCampaign.seenUpdateIDKey) private var lastSeenOnboardingUpdateID: String = ""
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
    @State private var showInteractiveCommuteSheet = false
    @State private var interactiveCommuteInitialReturn = false
    @State private var openCommuteSetupAfterOnboarding = false
    
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
        newsItems.contains { $0.isStrikeToday }
    }

    private var urgentNewsCount: Int {
        newsItems.filter { item in
            if item.isStrikeToday { return true }
            if item.isStrikeCategory, let days = item.daysUntilStrike, days >= 0 && days <= 2 {
                return true
            }
            return false
        }.count
    }

    private static let strikeDateFormatters: [DateFormatter] = {
        ["yyyy-MM-dd", "dd/MM/yyyy"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "it_IT")
            formatter.timeZone = TimeZone(identifier: "Europe/Rome")
            formatter.dateFormat = format
            formatter.isLenient = false
            return formatter
        }
    }()

    private func strikeDate(from value: String?) -> Date? {
        guard let value else { return nil }
        for formatter in Self.strikeDateFormatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
    
    
    var body: some View {
        Group {
            if showingMetroView {
                NavigationStack {
                    MetroHomeView()
                        .background(Color(.systemGroupedBackground))
                        .navigationTitle(appTitle)
                        .toolbar {
                            mainToolbarContent()
                        }
                }
            } else {
                TabView(selection: Binding(
                    get: { navigationCoordinator.selectedTab },
                    set: { newTab in
                        if navigationCoordinator.selectedTab != newTab {
                            navigationCoordinator.selectTab(newTab)
                        }
                    }
                )) {
                    ForEach(MainTab.barOrder) { tab in
                        Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                            tabStackView(for: tab)
                        }
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .background(hiddenSheets())
        .background(hiddenLifecycle1())
        .background(hiddenLifecycle2())
        .background(hiddenLifecycle3())
    }

    @ViewBuilder
    private func tabStackView(for tab: MainTab) -> some View {
        if navigationCoordinator.mountedTabs.contains(tab) || navigationCoordinator.selectedTab == tab {
            NavigationStack {
                switch tab {
                case .trains:
                    TrainsTabRootView(
                        isMetroModeActive: $showingMetroView,
                        isActiveTab: navigationCoordinator.selectedTab == .trains,
                        hasUrgentNews: hasUrgentNews,
                        onOpenNotifications: { showNotificationsSettings = true },
                        onOpenHistory: { openHistory(for: .trains) },
                        onOpenNews: { openNewsCenter() },
                        onOpenProfile: { showProfile = true }
                    )
                case .stations:
                    StationsTabRootView(
                        isMetroModeActive: $showingMetroView,
                        isActiveTab: navigationCoordinator.selectedTab == .stations,
                        hasUrgentNews: hasUrgentNews,
                        onOpenNotifications: { showNotificationsSettings = true },
                        onOpenHistory: { openHistory(for: .stations) },
                        onOpenNews: { openNewsCenter() },
                        onOpenProfile: { showProfile = true }
                    )
                case .home:
                    homeTabRootView
                case .trips:
                    TripsTabRootView(
                        isMetroModeActive: $showingMetroView,
                        isActiveTab: navigationCoordinator.selectedTab == .trips,
                        hasUrgentNews: hasUrgentNews,
                        onOpenHistory: { openHistory(for: .trips) },
                        onOpenNotifications: { showNotificationsSettings = true },
                        onOpenNews: { openNewsCenter() },
                        onOpenProfile: { showProfile = true }
                    )
                case .lines:
                    LinesTabRootView(
                        news: allNewsItems,
                        isActiveTab: navigationCoordinator.selectedTab == .lines,
                        onOpenNotifications: { showNotificationsSettings = true }
                    )
                }
            }
        } else {
            Color(.systemGroupedBackground)
        }
    }

    private struct HistorySheetPresentation: Identifiable {
        let id = UUID()
        let initialTab: Int
    }

    private func openHistory(for tab: MainTab) {
        activeHistorySheet = HistorySheetPresentation(initialTab: tab.defaultHistoryTabIndex)
    }

    private func openNewsCenter(category: NewsCategory? = nil) {
        newsCenterInitialCategory = category
        showNewsCenter = true
    }

    private var homeTabRootView: some View {
        mainListContent()
            .navigationTitle(appTitle)
            .navigationBarTitleDisplayMode(.large)
            .environment(\.editMode, $editMode)
            .navigationDestination(item: $selectedSuggestedStation) { s in
                SmartBoardView(station: s)
            }
            .navigationDestination(item: $selectedSuggestedRoute) { r in
                FavoriteRouteSolutionView(route: r)
            }
            .toolbar {
                InOrarioTabToolbar(
                    tab: .home,
                    hasUrgentNews: hasUrgentNews,
                    isMetroBetaEnabled: metroMilanoBetaEnabled || showingMetroView,
                    isMetroModeActive: $showingMetroView,
                    onSearch: { navigationCoordinator.openContextualSearch(for: .home) },
                    onOpenAssistant: { navigationCoordinator.openAssistantSearch(for: .home) },
                    onOpenHistory: { openHistory(for: .home) },
                    onOpenNotifications: { showNotificationsSettings = true },
                    onOpenNews: { openNewsCenter() },
                    onOpenProfile: { showProfile = true },
                    onOpenCustomizeHome: { showCustomizeDashboardSheet = true }
                )
            }
    }
    
    func loadNews() async {
        // 1. Carica subito la cache offline per visualizzarla all'istante (zero lag all'apertura)
        let offlineCache = manager.getCachedStrikesAndNews()
        if !offlineCache.isEmpty {
            await MainActor.run {
                self.allNewsItems = offlineCache
                self.newsItems = offlineCache.filter { $0.title != "Info" || $0.isUrgent }
            }
        }
        
        // 2. Esegue il controllo del server in background. Internamente se la cache ha meno di 5 minuti (300s),
        // questa chiamata restituisce la cache all'istante senza inviare chiamate di rete al server Cloud.
        // Se la cache ha più di 5 minuti, effettua una singola chiamata al server e aggiorna la schermata.
        let decodedNews = await manager.fetchStrikesAndNews(forceRefresh: false)
        await MainActor.run {
            self.allNewsItems = decodedNews
            self.newsItems = decodedNews.filter { $0.title != "Info" || $0.isUrgent }
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

    private func fetchCurrentPermissionSnapshot() async -> OnboardingPermissionSnapshot {
        locationManager.refreshAuthorizationStatus()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return OnboardingPermissionSnapshot.from(
            notificationStatus: settings.authorizationStatus,
            remoteNotificationsEnabled: manager.remoteNotificationsEnabled,
            locationStatus: locationManager.authorizationStatus
        )
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
        if isPassanteExpanded && !expandedHomeLineIDs.intersection(PassanteManager.tunnelLineIDs).isEmpty {
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
            Image(systemName: "tram.fill").foregroundColor(.blue)
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
                Label("Rimuovi dai preferiti", systemImage: "star.slash.fill")
            }
        }
    }
    
    @ViewBuilder
    func favoriteRouteRow(route: FavoriteRoute) -> some View {
        NavigationLink(destination: FavoriteRouteSolutionView(route: route)) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.green)
                    .frame(width: 22, alignment: .center)
                HStack(spacing: 6) {
                    Text(route.effectiveOriginName.compactStationName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Image(systemName: "arrow.left.and.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(route.effectiveDestinationName.compactStationName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                .minimumScaleFactor(0.85)
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation(.snappy(duration: 0.25)) {
                    manager.toggleFavoriteRoute(
                        originName: route.originName,
                        originID: route.originID,
                        destName: route.destinationName,
                        destID: route.destinationID
                    )
                }
            } label: {
                Label("Rimuovi dai preferiti", systemImage: "star.slash.fill")
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
                                Label("Rimuovi dai preferiti", systemImage: "star.slash.fill")
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
        let commuteSlot = commuteManager.currentCommuteRouteSlot()
        if commuteSlot != nil || !manager.favoriteRoutes.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $isFavoriteRoutesExpanded) {
                    if let slot = commuteSlot {
                        commuteHabitRouteRow(slot: slot)
                    }
                    ForEach(manager.favoriteRoutes) { route in
                        favoriteRouteRow(route: route)
                    }
                    .onMove { from, to in
                        manager.moveFavoriteRoutes(from: from, to: to)
                    }
                } label: {
                    Label("Le Mie Tratte Abituali", systemImage: "arrow.left.arrow.right")
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
            if hasUrgentNews, let activeStrike = newsItems.first(where: { $0.isStrikeToday }) {
                Button {
                    openNewsCenter(category: .sciopero)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sciopero in corso oggi")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.red)
                            Text(activeStrike.title)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

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
                            habitCommuteSlot: (commuteManager.homeBannerPlanB == nil && commuteManager.followedTrip == nil) ? commuteManager.activeHabitCommuteSlot() : nil,
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
                        homeFavoriteTrainsCard()
                    case .myStations:
                        homeStationsCard()
                    case .favoriteRoutes:
                        homeTripsCard()
                    case .passante:
                        homeLinesCard()
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
            let activeNearby = locationManager.manualNearbyStation ?? locationManager.nearbyStation
            let homeTrainsMax = manager.homeMaxItems(for: .favoriteTrains)
            let homeTrains = TrainManager.selectHomeTrains(
                favoriteTrains: manager.favoriteTrains,
                snapshots: manager.liveTrainSnapshots,
                maxActiveCount: homeTrainsMax,
                fallbackCount: homeTrainsMax
            ).refreshCandidates
            let pinnedLiveTrains: [SavedTrain] = manager.activeLiveActivities.compactMap { liveNum in
                if homeTrains.contains(where: { $0.number == liveNum }) { return nil }
                if let fav = manager.favoriteTrains.first(where: { $0.number == liveNum }) { return fav }
                return SavedTrain(number: liveNum, description: "")
            }
            let trainsToRefresh = homeTrains + pinnedLiveTrains
            let homeStations = manager.myStations
            await withTaskGroup(of: Void.self) { group in
                if !trainsToRefresh.isEmpty {
                    group.addTask {
                        await manager.refreshFavoriteTrainSnapshotsIfNeeded(trains: trainsToRefresh, force: true, ttl: 120)
                    }
                }
                var stationsToRefresh: [Station] = []
                if isNearbyExpanded, let nearby = activeNearby {
                    stationsToRefresh.append(nearby)
                }
                stationsToRefresh.append(contentsOf: homeStations)
                if !stationsToRefresh.isEmpty {
                    let targetStations = stationsToRefresh
                    group.addTask {
                        await manager.refreshStationSnapshotsIfNeeded(stations: targetStations, force: true, ttl: 300)
                    }
                }
                if !personalLinesManager.savedLines.isEmpty && passanteManager.userUsesTunnel {
                    group.addTask {
                        _ = await passanteManager.refreshTunnelHealthIfNeeded(manager: manager, minInterval: 0, force: true)
                    }
                }
            }
        }
        .task(id: "\(navigationCoordinator.selectedTab == .home)|\(manager.activeLiveActivities.sorted().joined(separator: ","))") {
            guard navigationCoordinator.selectedTab == .home, !manager.activeLiveActivities.isEmpty else { return }
            let pinnedTrains: [SavedTrain] = manager.activeLiveActivities.map { num in
                manager.favoriteTrains.first(where: { $0.number == num }) ?? SavedTrain(number: num, description: "")
            }
            await manager.refreshFavoriteTrainSnapshotsIfNeeded(trains: pinnedTrains, force: false, ttl: 90)
        }
    }

    @ViewBuilder
    private func homeSectionHeader(
        title: String,
        systemImage: String,
        iconColor: Color,
        alertSeverity: HomeAlertSeverity = .none,
        tabButtonTitle: String,
        targetTab: MainTab
    ) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                if alertSeverity != .none {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(alertSeverity == .critical ? .red : .orange)
                        .accessibilityLabel(alertSeverity == .critical ? "Treno cancellato o criticità" : "Ritardo superiore a 15 minuti")
                }
            }

            Spacer(minLength: 8)

            Button {
                Haptics.play(.light)
                navigationCoordinator.selectedTab = targetTab
            } label: {
                HStack(spacing: 3) {
                    Text(tabButtonTitle)
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(.accentColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .textCase(nil)
        .padding(.bottom, 2)
    }

    private var homePassanteLinesAlertSeverity: HomeAlertSeverity {
        guard passanteManager.userUsesTunnel else { return .none }
        let hex = passanteManager.passanteTunnelHealthColor.lowercased()
        let msg = passanteManager.passanteTunnelHealthMessage.lowercased()
        if hex.contains("e30613") || hex.contains("ff3b30") || hex.contains("d32f2f")
            || msg.contains("interrott") || msg.contains("blocc") || msg.contains("forti ritardi") || msg.contains("critic")
            || passanteManager.passanteTunnelAverageDelay >= 15 {
            return .critical
        }
        if hex.contains("f39200") || hex.contains("ff9500") || hex.contains("f57c00")
            || msg.contains("rallent") || msg.contains("ritard")
            || passanteManager.passanteTunnelAverageDelay >= 5 {
            return .warning
        }
        return .none
    }

    @ViewBuilder
    private func homeFavoriteTrainsCard() -> some View {
        if !manager.favoriteTrains.isEmpty {
            let maxCount = manager.homeMaxItems(for: .favoriteTrains)
            let selection = TrainManager.selectHomeTrains(
                favoriteTrains: manager.favoriteTrains,
                snapshots: manager.liveTrainSnapshots,
                maxActiveCount: maxCount,
                fallbackCount: maxCount
            )
            let displayed = selection.trains
            let refreshTargets = selection.refreshCandidates
            let refreshTargetsKey = refreshTargets.map(\.number).joined(separator: ",")

            Section {
                ForEach(displayed) { saved in
                    let dummy = manager.createDummyTrain(from: saved)
                    let snap = manager.liveTrainSnapshots[saved.number]
                    NavigationLink(destination: TrainStopsView(train: dummy, showCloseButton: false)) {
                        homeTrainRow(saved: saved, snapshot: snap)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        let isLive = manager.activeLiveActivities.contains(saved.number)
                        Button {
                            Task { _ = await manager.toggleQuickLiveActivity(for: saved) }
                        } label: {
                            Label(
                                isLive ? "Ferma Dynamic Island" : "Dynamic Island",
                                systemImage: isLive ? "livephoto.slash" : "livephoto.play"
                            )
                        }
                        .tint(isLive ? .red : .indigo)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation(.snappy(duration: 0.25)) {
                                manager.toggleFavorite(trainNumber: saved.number, description: saved.description)
                            }
                        } label: {
                            Label("Rimuovi dai preferiti", systemImage: "star.slash.fill")
                        }
                    }
                }
            } header: {
                homeSectionHeader(
                    title: "Treni",
                    systemImage: "tram.fill",
                    iconColor: .blue,
                    alertSeverity: selection.alertSeverity,
                    tabButtonTitle: "Tutti",
                    targetTab: .trains
                )
            }
            .task(id: "\(navigationCoordinator.selectedTab == .home)|\(refreshTargetsKey)|\(manager.activeLiveActivities.sorted().joined(separator: ","))") {
                guard navigationCoordinator.selectedTab == .home else { return }
                let pinnedOnly: [SavedTrain] = manager.activeLiveActivities.compactMap { num in
                    if refreshTargets.contains(where: { $0.number == num }) { return nil }
                    if let fav = manager.favoriteTrains.first(where: { $0.number == num }) { return fav }
                    return SavedTrain(number: num, description: "")
                }
                let combined = refreshTargets + pinnedOnly
                guard !combined.isEmpty else { return }
                await manager.refreshFavoriteTrainSnapshotsIfNeeded(trains: combined, force: false, ttl: 120)
            }
        }
    }

    @ViewBuilder
    private func homeTrainRow(saved: SavedTrain, snapshot: TrainLiveSnapshot?) -> some View {
        let endpoints: (origin: String?, destination: String) = {
            if let snapshot, let dest = snapshot.destination, !dest.isEmpty {
                return (snapshot.origin, dest)
            }
            return saved.parsedEndpoints
        }()
        let timeRange: (departure: String, arrival: String?)? = {
            if let stops = snapshot?.stops, let first = stops.first, let last = stops.last {
                return (first.time, last.time)
            }
            return saved.formattedTimeRange
        }()
        let routeText: String = {
            let dest = endpoints.destination.compactStationName
            if let orig = endpoints.origin?.compactStationName, !orig.isEmpty, orig != dest {
                return "\(orig) → \(dest)"
            }
            return dest
        }()
        let hasNotifications = manager.remoteNotificationsEnabled
            && manager.trainNotificationsEnabled
            && saved.hasActiveNotifications

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TrainCategoryBadge(category: snapshot?.category ?? saved.resolvedCategoryCode(), compact: true)
                Text(saved.number)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if let times = timeRange {
                    HStack(spacing: 3) {
                        Text(times.departure)
                        if let arr = times.arrival {
                            Text("→")
                                .foregroundColor(.secondary)
                            Text(arr)
                        }
                    }
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                TrainLiveDelayPill(snapshot: snapshot, compact: true)
            }

            HStack(spacing: 6) {
                Text(routeText)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if hasNotifications {
                    Image(systemName: "bell.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func homeStationsCard() -> some View {
        let activeNearby = locationManager.manualNearbyStation ?? locationManager.nearbyStation
        let homeEligibleStations = manager.myStations.filter { !(activeNearby?.matches($0) ?? false) }
        if !homeEligibleStations.isEmpty {
            let maxCount = manager.homeMaxItems(for: .myStations)
            let hasOverflow = homeEligibleStations.count > maxCount
            let displayed = (showAllHomeStations || !hasOverflow)
                ? homeEligibleStations
                : Array(homeEligibleStations.prefix(maxCount))
            let hiddenStations = hasOverflow ? Array(homeEligibleStations.dropFirst(maxCount)) : []
            let hiddenSummary = TrainManager.homeHiddenStationsSummary(
                hiddenStations: hiddenStations,
                snapshots: manager.stationBoardSnapshots
            )
            let stationAlert = TrainManager.stationsAlertSeverity(
                stations: homeEligibleStations,
                snapshots: manager.stationBoardSnapshots
            )
            let stationsTaskKey = homeEligibleStations.map { TrainManager.canonicalStationKey(for: $0) }.joined(separator: ",")

            Section {
                ForEach(displayed) { station in
                    let key = TrainManager.canonicalStationKey(for: station)
                    let snap = manager.stationBoardSnapshots[key]
                    let hasProblem = snap?.circulationState == .warning || snap?.circulationState == .disrupted
                    let dotColor: Color = {
                        guard let snap else { return .gray }
                        switch snap.circulationState {
                        case .regular: return .green
                        case .warning: return .orange
                        case .disrupted: return .red
                        case .noData: return .gray
                        }
                    }()

                    NavigationLink(destination: SmartBoardView(station: station)) {
                        HStack(spacing: 10) {
                            Image(systemName: "building.2.crop.circle.fill")
                                .foregroundColor(.blue)
                                .font(.body)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(station.formattedName)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                if hasProblem, let snap {
                                    Text(snap.healthMessage)
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(dotColor)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 6)

                            Circle()
                                .fill(dotColor)
                                .frame(width: 9, height: 9)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: hasProblem ? 8 : 7, leading: 16, bottom: hasProblem ? 8 : 7, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation(.snappy(duration: 0.25)) {
                                manager.removeMyStation(station)
                            }
                        } label: {
                            Label("Rimuovi dai preferiti", systemImage: "star.slash.fill")
                        }
                    }
                }
                .onMove { from, to in
                    Haptics.play(.light)
                    moveHomeEligibleStations(from: from, to: to, excludingNearby: activeNearby)
                }

                if hasOverflow {
                    if !showAllHomeStations, let summary = hiddenSummary {
                        Button {
                            Haptics.play(.light)
                            withAnimation(.snappy(duration: 0.25)) {
                                showAllHomeStations = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(summary.text)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.blue)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if summary.alertCount > 0 {
                                    Circle()
                                        .fill(summary.hasCritical ? Color.red : Color.orange)
                                        .frame(width: 7, height: 7)
                                }
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.blue)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .moveDisabled(true)
                        .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                    } else if showAllHomeStations {
                        Button {
                            Haptics.play(.light)
                            withAnimation(.snappy(duration: 0.25)) {
                                showAllHomeStations = false
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Mostra meno")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.blue)
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.up")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.blue)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .moveDisabled(true)
                        .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                    }
                }
            } header: {
                homeSectionHeader(
                    title: "Stazioni",
                    systemImage: "building.2.crop.circle.fill",
                    iconColor: .blue,
                    alertSeverity: stationAlert,
                    tabButtonTitle: "Tutte",
                    targetTab: .stations
                )
            }
            .environment(\.defaultMinListRowHeight, 38)
            .task(id: "\(navigationCoordinator.selectedTab == .home)|\(stationsTaskKey)") {
                guard navigationCoordinator.selectedTab == .home, !homeEligibleStations.isEmpty else { return }
                await manager.refreshStationSnapshotsIfNeeded(stations: homeEligibleStations, force: false, ttl: 300)
            }
        }
    }

    private func moveHomeEligibleStations(from source: IndexSet, to destination: Int, excludingNearby activeNearby: Station?) {
        guard let activeNearby,
              let excludedIdx = manager.myStations.firstIndex(where: { $0.matches(activeNearby) }) else {
            manager.moveMyStations(from: source, to: destination)
            return
        }
        var rest = manager.myStations.filter { !$0.matches(activeNearby) }
        rest.move(fromOffsets: source, toOffset: destination)
        let insertIdx = min(excludedIdx, rest.count)
        rest.insert(manager.myStations[excludedIdx], at: insertIdx)
        manager.myStations = rest
        manager.saveFavorites()
    }

    @ViewBuilder
    private func commuteHabitRouteRow(slot: ActiveHabitCommuteSlot) -> some View {
        Button {
            Haptics.play(.light)
            interactiveCommuteInitialReturn = slot.isReturn
            showInteractiveCommuteSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: slot.isReturn ? "briefcase.fill" : "house.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(slot.isReturn ? .purple : .blue)
                    .frame(width: 22, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formatCityOrStationSummary(slot.origins)) → \(formatCityOrStationSummary(slot.destinations))")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("\(slot.isReturn ? "Lavoro → Casa" : "Casa → Lavoro") · \(slot.timeBand)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Haptics.play(.medium)
                withAnimation {
                    commuteManager.toggleCommuteRouteDirection()
                }
            } label: {
                Label("Inverti", systemImage: "arrow.left.arrow.right")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                Haptics.play(.light)
                showCommuteSetupSheet = true
            } label: {
                Label("Configura", systemImage: "slider.horizontal.3")
            }
            .tint(.blue)
        }
    }

    @ViewBuilder
    private func homeTripsCard() -> some View {
        let commuteSlot = commuteManager.currentCommuteRouteSlot()
        let commuteCount = commuteSlot != nil ? 1 : 0
        let totalCount = commuteCount + manager.favoriteRoutes.count + manager.savedTrips.count
        if totalCount > 0 {
            let maxCount = manager.homeMaxItems(for: .favoriteRoutes)
            let routesBudget = max(0, maxCount - commuteCount)
            let displayedRoutes = Array(manager.favoriteRoutes.prefix(routesBudget))
            let remainingBudget = max(0, routesBudget - displayedRoutes.count)
            let sortedTrips = TrainManager.sortedSavedTripsByDeparture(manager.savedTrips)
            let displayedTrips = Array(sortedTrips.prefix(remainingBudget))

            Section {
                if let slot = commuteSlot {
                    commuteHabitRouteRow(slot: slot)
                }

                ForEach(displayedRoutes) { route in
                    favoriteRouteRow(route: route)
                }
                .onMove { from, to in
                    Haptics.play(.light)
                    manager.moveFavoriteRoutes(from: from, to: to)
                }

                ForEach(displayedTrips) { trip in
                    let sol = trip.asTravelSolution
                    let transfers = max(0, trip.segments.count - 1)
                    NavigationLink(destination: TravelSolutionDetailsView(solution: sol)) {
                        HStack(spacing: 10) {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.green)
                                .frame(width: 22, alignment: .center)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(trip.origin.compactStationName)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(trip.destination.compactStationName)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                }
                                .minimumScaleFactor(0.85)

                                HStack(spacing: 4) {
                                    Text(trip.departureTime)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 9))
                                    Text(trip.arrivalTime)
                                    Text("·")
                                    Text(transfers == 0 ? "Diretto" : "\(transfers) camb\(transfers == 1 ? "io" : "i")")
                                        .foregroundColor(transfers == 0 ? .green : .orange)
                                }
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 3)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation(.snappy(duration: 0.25)) {
                                manager.toggleSavedTrip(solution: sol)
                            }
                        } label: {
                            Label("Rimuovi dai preferiti", systemImage: "star.slash.fill")
                        }
                    }
                }
            } header: {
                homeSectionHeader(
                    title: "Viaggi e Tratte",
                    systemImage: "map.fill",
                    iconColor: .green,
                    tabButtonTitle: "Tutti",
                    targetTab: .trips
                )
            }
        }
    }

    @ViewBuilder
    private func homeLinesCard() -> some View {
        let maxCount = manager.homeMaxItems(for: .passante)
        let lines = Array(personalLinesManager.savedLines.prefix(maxCount))
        if !lines.isEmpty {
            Section {
                ForEach(lines) { line in
                    ExpandableLineRowView(
                        line: line,
                        isExpanded: expandedHomeLineIDs.contains(line.id),
                        relevantNewsCount: personalLinesManager.relevantNews(for: line, from: newsItems).count,
                        expandedDisplayMode: .nearbyOnly,
                        showDetailButtonInExpanded: true,
                        onPrimaryTap: {
                            Haptics.play(.light)
                            if expandedHomeLineIDs.contains(line.id) {
                                expandedHomeLineIDs.remove(line.id)
                            } else {
                                expandedHomeLineIDs.insert(line.id)
                                UserInterestTelemetryManager.shared.recordLineView(
                                    lineID: line.id,
                                    code: line.code,
                                    name: line.name,
                                    kind: line.kind.rawValue,
                                    region: line.effectiveRegion
                                )
                            }
                        },
                        onToggleExpand: {
                            Haptics.play(.light)
                            if expandedHomeLineIDs.contains(line.id) {
                                expandedHomeLineIDs.remove(line.id)
                            } else {
                                expandedHomeLineIDs.insert(line.id)
                                UserInterestTelemetryManager.shared.recordLineView(
                                    lineID: line.id,
                                    code: line.code,
                                    name: line.name,
                                    kind: line.kind.rawValue,
                                    region: line.effectiveRegion
                                )
                            }
                        },
                        onOpenDetail: {
                            navigationCoordinator.openLineDetail(lineID: line.id)
                        },
                        onOpenPassanteDetail: {
                            showPassanteDetailSheet = true
                        },
                        onSelectStation: { station in
                            selectedSuggestedStation = station
                        }
                    )
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }
            } header: {
                homeSectionHeader(
                    title: "Linee",
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up.fill",
                    iconColor: .orange,
                    alertSeverity: homePassanteLinesAlertSeverity,
                    tabButtonTitle: "Tutte",
                    targetTab: .lines
                )
            }
            .task(id: "\(navigationCoordinator.selectedTab == .home)|\(passanteManager.userUsesTunnel)") {
                guard navigationCoordinator.selectedTab == .home, passanteManager.userUsesTunnel else { return }
                _ = await passanteManager.refreshTunnelHealthIfNeeded(manager: manager, minInterval: 240)
            }
        }
    }

    private func syncPersonalLines() {
        personalLinesManager.syncFromExistingUserState(
            trainManager: manager,
            passanteManager: passanteManager,
            usageTracker: usageTracker,
            commuteManager: commuteManager
        )
    }

    @ViewBuilder
    func hiddenSheets() -> some View {
        Color.clear
            .sheet(isPresented: $showSavedTrips) {
                NavigationStack {
                    SavedTripsView()
                }
            }
            .sheet(item: $navigationCoordinator.activeSearchRequest, onDismiss: {
                manager.loadFavorites()
                syncPersonalLines()
            }) { req in
                if showingMetroView {
                    MetroSearchView { station in
                        NotificationCenter.default.post(name: NSNotification.Name("OpenMetroStation"), object: station)
                    }
                } else {
                    SearchView(
                        initialScope: req.scope,
                        initialAssistantMode: req.initialAssistantMode,
                        autoStartVoice: req.autoStartVoice,
                        initialQuery: req.initialQuery,
                        initialOriginName: req.initialOriginName,
                        initialOriginID: req.initialOriginID,
                        initialDestName: req.initialDestName,
                        initialDestID: req.initialDestID,
                        autoSearchSolutions: req.autoSearchSolutions
                    )
                    .id(req.id)
                }
            }
            .sheet(isPresented: $showSearchSheet, onDismiss: {
                searchSheetSessionID = UUID()
                searchInitialAssistant = false
                searchAutoStartVoice = false
                searchInitialQuery = nil
                manager.loadFavorites()
                syncPersonalLines()
            }) {
                if showingMetroView {
                    MetroSearchView { station in
                        NotificationCenter.default.post(name: NSNotification.Name("OpenMetroStation"), object: station)
                    }
                } else {
                    SearchView(
                        initialScope: .trainsAndStations,
                        initialAssistantMode: searchInitialAssistant,
                        autoStartVoice: searchAutoStartVoice,
                        initialQuery: searchInitialQuery
                    )
                    .id(searchSheetSessionID)
                }
            }
            .sheet(isPresented: $showMetroHistorySheet) {
                MetroHistorySheet()
                    .environmentObject(metroManager)
            }
            .sheet(item: $activeHistorySheet) { presentation in
                HistoryView(initialTab: presentation.initialTab)
            }
            .sheet(isPresented: $showNotificationsSettings) {
                NavigationStack { NotificationsSettingsView(showCloseButton: true) }
            }
            .sheet(isPresented: $showProfile, onDismiss: {
                highlightRegionInProfile = false
            }) {
                ProfileView(highlightRegionSelector: highlightRegionInProfile)
                    .environmentObject(manager)
                    .environmentObject(passanteManager)
                    .environmentObject(personalLinesManager)
                    .environmentObject(usageTracker)
                    .environmentObject(locationManager)
            }
            .sheet(isPresented: $showNewsCenter) {
                NewsCenterView(news: $allNewsItems, initialCategory: newsCenterInitialCategory)
                    .environmentObject(manager)
            }
            .sheet(isPresented: $showCustomizeDashboardSheet) {
                NavigationStack {
                    CustomizeDashboardView()
                        .environmentObject(manager)
                        .environmentObject(passanteManager)
                        .environmentObject(personalLinesManager)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Chiudi") { showCustomizeDashboardSheet = false }
                                    .fontWeight(.bold)
                            }
                        }
                }
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
                OnboardingView(
                    showOnboarding: $showOnboarding,
                    mode: onboardingMode,
                    initialPermissionSnapshot: onboardingInitialPermissions,
                    onOpenCommuteSettings: {
                        openCommuteSetupAfterOnboarding = true
                        showOnboarding = false
                    }
                )
                .environmentObject(locationManager)
                .environmentObject(manager)
                .environmentObject(passanteManager)
                .onDisappear {
                    let wasUpdateMode = (onboardingMode == .updateWhatsNew)
                    let shouldOpenCommute = openCommuteSetupAfterOnboarding
                    openCommuteSetupAfterOnboarding = false
                    hasCompletedOnboarding = true
                    lastSeenOnboardingUpdateID = OnboardingCampaign.currentUpdateID
                    updateManager.markNotificationPermissionPromptHandled()

                    let locStatus = locationManager.authorizationStatus
                    if locStatus == .authorizedWhenInUse || locStatus == .authorizedAlways {
                        locationManager.requestLocation()
                        hasRequestedLocation = true
                    }
                    if manager.remoteNotificationsEnabled {
                        UIApplication.shared.registerForRemoteNotifications()
                        manager.syncRemoteNotifications()
                    }

                    let aiManager = AIFeatureManager.shared
                    if aiManager.aiModeChoice == .local && !aiManager.isAppleIntelligenceAvailable {
                        aiManager.aiModeChoice = .none
                    }

                    if shouldOpenCommute {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showCommuteSetupSheet = true
                        }
                    } else if wasUpdateMode {
                        updateManager.checkSupporterUpdatePopup(hasSupport: manager.hasSupport())
                        Task {
                            await updateManager.checkForAvailableUpdates(hasSupport: manager.hasSupport(), strikeRegion: manager.strikeRegion)
                        }
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
                        .environmentObject(manager)
                        .environmentObject(locationManager)
                        .environmentObject(passanteManager)
                        .environmentObject(metroCache)
                        .environmentObject(usageTracker)
                }
            }
            .sheet(isPresented: $showInteractiveCommuteSheet) {
                let slot = commuteManager.currentCommuteRouteSlot()
                let isRet = slot?.isReturn ?? interactiveCommuteInitialReturn
                let stOrigins = slot?.origins ?? (isRet ? commuteManager.destinations : commuteManager.origins)
                let stDests = slot?.destinations ?? (isRet ? commuteManager.origins : commuteManager.destinations)
                let placeholder = PlanBReportDTO(
                    title: isRet ? "Lavoro → Casa" : "Casa → Lavoro",
                    body: "\(formatCityOrStationSummary(stOrigins)) → \(formatCityOrStationSummary(stDests))",
                    incident_type: "simulation",
                    incident_detail: nil,
                    cancelled_train: nil,
                    target_time: SharedFormatters.time.string(from: Date()),
                    origins: stOrigins,
                    destinations: stDests,
                    alternatives: [],
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
                NavigationStack {
                    PlanBDetailView(
                        plan: placeholder,
                        customTitle: isRet ? "Lavoro → Casa" : "Casa → Lavoro",
                        interactiveCommuteMode: true,
                        initialIsReturn: isRet,
                        autoLoadOnAppear: true
                    )
                    .environmentObject(manager)
                    .environmentObject(passanteManager)
                    .environmentObject(locationManager)
                    .environmentObject(metroCache)
                    .environmentObject(usageTracker)
                }
            }
            .sheet(isPresented: $showPlanBDetailSheet, onDismiss: {
                planBSheetCustomTitle = nil
                if commuteManager.followedTrip != nil {
                    commuteManager.clearPlanBAfterFollow()
                }
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
                    syncPersonalLines()
                    Task {
                        await commuteManager.refreshFollowedTripStatus(manager: manager)
                    }

                    let launchDecisionAtInit = OnboardingLaunchDecision.resolve(
                        hasCompletedOnboarding: hasCompletedOnboarding,
                        lastSeenUpdateID: lastSeenOnboardingUpdateID
                    )

                    // Controllo popup sostenitori (solo al primo caricamento dopo aggiornamento) e verifica aggiornamenti su App Store
                    if launchDecisionAtInit == .none {
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

                let launchDecision = OnboardingLaunchDecision.resolve(
                    hasCompletedOnboarding: hasCompletedOnboarding,
                    lastSeenUpdateID: lastSeenOnboardingUpdateID
                )

                switch launchDecision {
                case .showFullOnboarding:
                    updateManager.markNotificationPermissionPromptHandled()
                    Task {
                        await TipManager.shared.updatePurchases()
                        let snap = await fetchCurrentPermissionSnapshot()
                        onboardingMode = .fullFirstLaunch
                        onboardingInitialPermissions = snap
                        showOnboarding = true
                    }
                case .showUpdateOnboarding:
                    updateManager.markNotificationPermissionPromptHandled()
                    if (locationManager.authorizationStatus == .authorizedWhenInUse ||
                        locationManager.authorizationStatus == .authorizedAlways),
                       !hasRequestedLocation {
                        locationManager.requestLocation()
                        hasRequestedLocation = true
                    }
                    Task {
                        await TipManager.shared.updatePurchases()
                        let snap = await fetchCurrentPermissionSnapshot()
                        onboardingMode = .updateWhatsNew
                        onboardingInitialPermissions = snap
                        showOnboarding = true
                    }
                case .none:
                    if locationManager.authorizationStatus == .notDetermined {
                        locationManager.requestAuthorization()
                    }
                    if !hasRequestedLocation {
                        locationManager.requestLocation()
                        hasRequestedLocation = true
                    }
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
                        await TipManager.shared.updatePurchases()
                        let snap = await fetchCurrentPermissionSnapshot()
                        onboardingMode = .fullFirstLaunch
                        onboardingInitialPermissions = snap
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
            .onChange(of: manager.favoriteTrains.count) { _, _ in
                syncPersonalLines()
            }
            .onChange(of: manager.myStations.count) { _, _ in
                syncPersonalLines()
            }
            .onChange(of: manager.favoriteRoutes.count) { _, _ in
                syncPersonalLines()
            }
            .onChange(of: manager.savedTrips.count) { _, _ in
                syncPersonalLines()
            }
            .onChange(of: passanteManager.selectedSuburbanLines) { _, _ in
                syncPersonalLines()
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
                            Label("Treni", systemImage: "tram.fill")
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
                        openHistory(for: navigationCoordinator.selectedTab)
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
            .alert("Aggiornamento Notifiche", isPresented: Binding(
                get: { manager.freeMigrationNoticeMessage != nil },
                set: { if !$0 { manager.freeMigrationNoticeMessage = nil } }
            )) {
                Button("Passa a In Orario Pro") {
                    manager.freeMigrationNoticeMessage = nil
                    manager.showPaywallSheet = true
                }
                Button("Ho capito", role: .cancel) {
                    manager.freeMigrationNoticeMessage = nil
                }
            } message: {
                if let msg = manager.freeMigrationNoticeMessage {
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
                    locationManager.refreshAuthorizationStatus()
                    if updateManager.pendingNotificationSettingsReturn {
                        updateManager.pendingNotificationSettingsReturn = false
                        manager.checkAndAutoEnableNotifications()
                    }
                    if hasCompletedOnboarding {
                        print("App tornata attiva, aggiorno posizione e passante...")
                        locationManager.requestLocation()
                        Task {
                            await commuteManager.refreshFollowedTripStatus(manager: manager)
                        }
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
    @State private var selectedTab: Int // 0: Soluzioni, 1: Stazioni, 2: Treni

    init(initialTab: Int = 0) {
        _selectedTab = State(initialValue: initialTab)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    historyTabPill(title: "Soluzioni", systemImage: "arrow.left.arrow.right", tag: 0)
                    historyTabPill(title: "Stazioni", systemImage: "building.2.crop.circle.fill", tag: 1)
                    historyTabPill(title: "Treni", systemImage: "tram.fill", tag: 2)
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
                icon: "arrow.left.arrow.right",
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
                icon: "tram.fill",
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
            Image(systemName: "arrow.left.arrow.right")
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
            Image(systemName: "tram.fill")
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
    var isFollowedTrip: Bool = false
    var liveOrigin: String? = nil
    var liveDestination: String? = nil
}

struct NativeSuggestionRow: View {
    let chip: ForYouChipItem
    var onSelectTrain: ((Train) -> Void)? = nil
    var onSelectStation: ((Station) -> Void)? = nil
    var onSelectRoute: ((FavoriteRoute) -> Void)? = nil
    
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var guessingEngine: TrainGuessingEngine
    @ObservedObject private var commuteManager = SupporterCommuteManager.shared
    
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
            if chip.isFollowedTrip {
                Button(role: .destructive) {
                    Haptics.play(.light)
                    withAnimation(.spring()) {
                        commuteManager.stopFollowing(manager: manager)
                    }
                } label: {
                    Label("Smetti di seguire", systemImage: "xmark.circle")
                }
            } else if chip.isLiveActivity, case .train(let t) = item {
                Button(role: .destructive) {
                    Haptics.play(.light)
                    Task {
                        await manager.endLiveActivity(trainNumber: t.number)
                    }
                } label: {
                    Label("Rimuovi pin", systemImage: "xmark.circle")
                }
            } else if !chip.isLiveActivity && !chip.isActiveGuess && !chip.isConfirmed {
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
            return "tram.fill"
        } else if chip.isLiveActivity {
            return "livephoto.play"
        } else if chip.isFollowedTrip {
            return "tram.fill"
        } else if chip.isNearby {
            return "location.circle.fill"
        } else {
            switch item {
            case .station:
                return "building.2.crop.circle.fill"
            case .train:
                return "sparkles"
            case .route:
                return "arrow.left.arrow.right"
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
        } else if chip.isFollowedTrip {
            return .orange
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
                
                if chip.isFollowedTrip {
                    if !cleanDest.isEmpty && cleanDest != "Live Activity" {
                        return "Il tuo treno \(label) \(cleanDest)"
                    }
                    return "Il tuo treno \(label)"
                }
                
                if !cleanOrig.isEmpty && !cleanDest.isEmpty && cleanOrig != cleanDest {
                    return "\(label) \(cleanOrig) → \(cleanDest)"
                } else if !cleanDest.isEmpty && cleanDest != "Live Activity" {
                    return "\(label) \(cleanDest)"
                }
                return label
            }
            if chip.isFollowedTrip {
                let rawDest = chip.liveDestination ?? train.destination
                let cleanDest = compactLiveStation(rawDest)
                if !cleanDest.isEmpty && cleanDest != "Live Activity" {
                    return "Il tuo treno \(label) \(cleanDest)"
                }
                return "Il tuo treno \(label)"
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
        } else if chip.isFollowedTrip {
            if case .train(let train) = item, !train.time.isEmpty && train.time != "--:--" {
                Text(train.time)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
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
        if chip.isFollowedTrip {
            Button(role: .destructive) {
                Haptics.play(.medium)
                withAnimation(.spring()) {
                    commuteManager.stopFollowing(manager: manager)
                }
            } label: {
                Label("Smetti di seguire", systemImage: "xmark.circle")
            }
        } else if chip.isCurrentTrain || chip.isConfirmed {
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
    @ObservedObject private var commuteManager = SupporterCommuteManager.shared
    
    var body: some View {
        Group {
            if let trip = commuteManager.followedTrip, !trip.isSingleTrain {
                Section {
                    FollowedTripCardView(trip: trip)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Haptics.play(.light)
                                withAnimation(.spring()) {
                                    commuteManager.stopFollowing(manager: manager)
                                }
                            } label: {
                                Label("Smetti di seguire", systemImage: "xmark.circle")
                            }
                        }
                }
            }
            
            nearbyContentSection
        }
    }
    
    @ViewBuilder
    private var nearbyContentSection: some View {
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
            
            // 3. Live Activities attive (rimosse automaticamente se il treno è già arrivato a destinazione)
            for liveNum in manager.activeLiveActivities {
                if let snap = manager.liveTrainSnapshots[liveNum],
                   TrainManager.shouldAutoEndLiveActivity(snapshot: snap) {
                    continue
                }
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
                    let isFollowedLive = commuteManager.followedTrip?.isSingleTrain == true &&
                        commuteManager.followedTrip?.railLegs.first?.train_number == liveNum
                    list.append(ForYouChipItem(
                        id: "live_\(liveNum)",
                        suggestion: .train(foundTrain),
                        isLiveActivity: true,
                        isFollowedTrip: isFollowedLive,
                        liveOrigin: originStation,
                        liveDestination: destStation
                    ))
                }
            }
            
            // 3b. Treno singolo seguito (fallback quando la Live Activity non è attiva)
            if let trip = commuteManager.followedTrip,
               trip.isSingleTrain,
               let leg = trip.railLegs.first,
               !list.contains(where: { $0.id.contains(leg.train_number) }) {
                let cleanCat = cleanTrainCategory(leg.category)
                let fallbackTrain = Train(
                    category: cleanCat,
                    number: leg.train_number,
                    destination: leg.destination,
                    time: leg.departure_time,
                    delay: "",
                    platform: leg.platform
                )
                list.append(ForYouChipItem(
                    id: "followed_\(leg.train_number)",
                    suggestion: .train(fallbackTrain),
                    isFollowedTrip: true,
                    liveOrigin: leg.origin,
                    liveDestination: leg.destination
                ))
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
                            Image(systemName: "arrow.left.arrow.right")
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

