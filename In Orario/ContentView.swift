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
    @Environment(\.scenePhase) var scenePhase
    
    @State private var showingMetroView = false

    
    @State private var newsItems: [NewsItem] = []
    @State private var allNewsItems: [NewsItem] = []
    
    @State private var isPassanteExpanded = false
    @State private var isFavoritesExpanded = true
    @State private var isMyStationsExpanded = true
    @State private var isSmartExpanded = true
    @State private var showSearchSheet = false
    @State private var showMetroHistorySheet = false
    @State private var showSavedTrips = false
    @State private var showHistorySheet = false
    @State private var showProfile = false
    @State private var showNewsCenter = false
    @State private var showOnboarding = false
    @State private var showNewSmartRouteSheet = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("showSuburbanLines") private var showSuburbanLines = true
    @State private var hasRequestedLocation = false
    
    @State private var deepLinkTrain: Train? = nil
    @State private var deepLinkStation: Station? = nil
    @State private var selectedFavoriteTrain: Train? = nil
    @State private var isPulsing = false
    @State private var editMode: EditMode = .inactive
    
    @AppStorage("rememberPassanteState") private var rememberPassanteState = false
    @AppStorage("rememberFavoriteTrainsState") private var rememberFavoriteTrainsState = false
    @AppStorage("rememberMyStationsState") private var rememberMyStationsState = false
    
    @AppStorage("storedIsPassanteExpanded") private var storedIsPassanteExpanded = false
    @AppStorage("storedIsFavoritesExpanded") private var storedIsFavoritesExpanded = true
    @AppStorage("storedIsMyStationsExpanded") private var storedIsMyStationsExpanded = true
    
    let passanteTimer = Timer.publish(every: 45, on: .main, in: .common).autoconnect()
    
    var appTitle: String {
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
            VStack(spacing: 0) {
                if showingMetroView {
                    MetroHomeView()
                } else {
                    // Banner spazio AI (sopra la lista)
                    SpaceAlertBannerView()
                        .animation(.easeInOut, value: AIFeatureManager.shared.isLocalModelInstalled)
                    
                    mainListContent()
                }
            } // end VStack
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
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
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
    @ViewBuilder
    func favoriteTrainRow(fav: SavedTrain, dummy: Train) -> some View {
        HStack {
            Image(systemName: "train.side.front.car").foregroundColor(.blue)
            VStack(alignment: .leading) {
                if let time = fav.departureTime {
                    Text("\(dummy.category) \(fav.number) • \(time)").font(.headline)
                } else {
                    Text("\(dummy.category) \(fav.number)").font(.headline)
                }
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
                    Label("Passante Ferroviario", systemImage: "tram.fill")
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
    func settingsSection() -> some View {
        Section {
            HStack {
                Spacer()
                Button(action: {
                    NotificationCenter.default.post(name: Notification.Name("OpenProfile"), object: nil)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                        Text("Impostazioni")
                    }
                    .font(.headline)
                    .foregroundColor(.blue)
                    .padding(.vertical, 16)
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    func mainListContent() -> some View {
        List {
            ForEach(manager.sectionOrder, id: \.self) { section in
                switch section {
                case .nearby:
                    NearbySectionView(
                        smartSuggestions: usageTracker.suggestionsForNow(
                            location: locationManager.userLocation?.coordinate,
                            excludeStations: manager.myStations.map { $0.name } + [locationManager.nearbyStation?.name].compactMap { $0 }
                        ),
                        nearby: locationManager.nearbyStation,
                        selectedFavoriteTrain: $selectedFavoriteTrain
                    )
                case .favoriteTrains:
                    favoriteTrainsSection()
                case .myStations:
                    myStationsSection()
                case .passante:
                    passanteSection()
                }
            }
            
            settingsSection()
        }
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
            .navigationDestination(isPresented: $showSavedTrips) { SavedTripsView() }
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
                    .onDisappear {
                        hasCompletedOnboarding = true
                        locationManager.requestAuthorization()
                        requestNotificationPermissions()
                        
                        let aiManager = AIFeatureManager.shared
                        if aiManager.aiModeChoice == .local && !aiManager.isLocalModelInstalled {
                            aiManager.downloadModel(aiManager.selectedModel)
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
    }

    @ViewBuilder
    func hiddenLifecycle1() -> some View {
        Color.clear
            .onAppear {
                if rememberPassanteState { isPassanteExpanded = storedIsPassanteExpanded }
                if rememberFavoriteTrainsState { isFavoritesExpanded = storedIsFavoritesExpanded }
                if rememberMyStationsState { isMyStationsExpanded = storedIsMyStationsExpanded }
                manager.loadFavorites()
                manager.syncLiveActivities()
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
                
                Task {
                    for train in manager.favoriteTrains {
                        await manager.enrichFavoriteTrainData(trainNumber: train.number)
                    }
                }
                
                if isPassanteExpanded {
                    Task {
                        await passanteManager.fetchPassanteLive(manager: manager)
                    }
                }
                
                if let initialNearby = locationManager.manualNearbyStation ?? locationManager.nearbyStation {
                    syncPassanteStation(initialNearby)
                }
            }
            .onChange(of: hasCompletedOnboarding) { oldValue, newValue in
                if !newValue {
                    showProfile = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showOnboarding = true
                    }
                }
            }
            .task { await loadNews() }
            .onChange(of: manager.strikeRegion) { oldValue, newValue in
                Task {
                    await loadNews()
                }
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
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Haptics.play(.medium)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showingMetroView.toggle()
                }
            } label: {
                Image(systemName: showingMetroView ? "tram.fill" : "m.square.fill")
                    .font(.title3.bold())
                    .foregroundColor(showingMetroView ? .orange : .red)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        
        // ─── BOLLA NEWS (più a sinistra) ───
        if !showingMetroView {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.play(.medium)
                    showNewsCenter = true
                } label: {
                    Image(systemName: "newspaper.fill")
                        .foregroundColor(hasUrgentNews ? .red : .primary)
                }
            }

            if #available(iOS 26, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }

            // ─── BOLLA TRATTE SALVATE ───
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.play(.medium)
                    showSavedTrips = true
                } label: {
                    Image(systemName: "map.fill")
                        .foregroundColor(.green)
                }
            }

            if #available(iOS 26, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
        }

        // ─── BOLLA CRONOLOGIA + RICERCA (più a destra) ───
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !showingMetroView {
                Button {
                    Haptics.play(.medium)
                    showHistorySheet = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            } else {
                Button {
                    Haptics.play(.medium)
                    showMetroHistorySheet = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
            Button {
                Haptics.play(.medium)
                showSearchSheet = true
            } label: {
                Image(systemName: "magnifyingglass")
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
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
                    .onAppear {
                        if let targetIndex = visibleStations.firstIndex(where: { isStationNearby(station: $0, activeNearby: activeNearby) }) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation {
                                    proxy.scrollTo(targetIndex, anchor: .center)
                                }
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
                if manager.viewedRecentTrains.isEmpty && manager.viewedRecentStations.isEmpty {
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
                    if !manager.viewedRecentTrains.isEmpty {
                        Section(header: HStack {
                            Text("Treni visti di recente")
                            Spacer()
                            Button("Cancella") {
                                manager.clearViewedRecentTrains()
                                Haptics.play(.medium)
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }) {
                            ForEach(manager.viewedRecentTrains) { result in
                                let dummy = manager.createDummyTrain(from: result)
                                NavigationLink(destination: TrainStopsView(train: dummy, showCloseButton: false)) {
                                    HStack {
                                        Image(systemName: "train.side.front.car").foregroundColor(.blue)
                                        VStack(alignment: .leading) {
                                            Text("Treno \(result.number)").font(.headline)
                                            Text(result.description).font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    if !manager.viewedRecentStations.isEmpty {
                        Section(header: HStack {
                            Text("Stazioni viste di recente")
                            Spacer()
                            Button("Cancella") {
                                manager.clearViewedRecentStations()
                                Haptics.play(.medium)
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }) {
                            ForEach(manager.viewedRecentStations) { result in
                                let possibleRFI = manager.getRfiID(for: result.nomeLungo)
                                let tempStation = Station(name: result.nomeLungo, rfiID: possibleRFI, vtID: result.vtID, lat: nil, lon: nil)
                                
                                NavigationLink(destination: SmartBoardView(station: tempStation)) {
                                    HStack {
                                        Image(systemName: "building.2.crop.circle.fill").foregroundColor(.orange)
                                        Text(result.nomeLungo).font(.headline)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Cronologia Recenti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Smart Suggestion Card

struct SmartSuggestionCard: View {
    let suggestion: SmartSuggestion
    @EnvironmentObject var usageTracker: UsageTracker
    
    var body: some View {
        switch suggestion {
        case .station(let station):
            NavigationLink(destination: SmartBoardView(station: station)) {
                cardContent(
                    icon: "tram.fill",
                    iconColor: .blue,
                    title: station.formattedName,
                    subtitle: "Stazione frequente"
                )
            }
            .buttonStyle(.plain)
            
        case .train(let train):
            NavigationLink(destination: TrainStopsView(train: train, showCloseButton: false)) {
                cardContent(
                    icon: "train.side.front.car",
                    iconColor: .orange,
                    title: "\(train.category) \(train.number)",
                    subtitle: train.destination
                )
            }
            .buttonStyle(.plain)
            
        case .route(let route):
            NavigationLink(destination: FavoriteRouteSolutionView(route: route)) {
                cardContent(
                    icon: "arrow.triangle.swap",
                    iconColor: .purple,
                    title: "\(route.originName.replacingOccurrences(of: "Milano ", with: "")) → \(route.destinationName.replacingOccurrences(of: "Milano ", with: ""))",
                    subtitle: "Tratta abituale"
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    func cardContent(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(iconColor)
                Spacer()
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundColor(.purple.opacity(0.4))
            }
            
            Spacer(minLength: 4)
            
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            
            Text(subtitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 145, height: 105)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color(.secondarySystemGroupedBackground))
                
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        LinearGradient(
                            colors: [iconColor.opacity(0.06), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(iconColor.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Nearby Section View
struct NearbySectionView: View {
    let smartSuggestions: [SmartSuggestion]
    let nearby: Station?
    @Binding var selectedFavoriteTrain: Train?
    
    @EnvironmentObject var manager: TrainManager
    @State private var isPulsing = false
    
    var body: some View {
        let hasLiveActivities = !manager.activeLiveActivities.isEmpty
        
        if !smartSuggestions.isEmpty || hasLiveActivities || nearby != nil {
            Section(header: Label("Per te", systemImage: "sparkles").font(.subheadline.bold()).foregroundColor(.purple)) {
                
                // --- LIVE ACTIVITIES (MONITORED TRAINS) ---
                if hasLiveActivities {
                    ForEach(Array(manager.activeLiveActivities), id: \.self) { trainNum in
                        Button {
                            Haptics.play(.medium)
                            let dummy = Train(category: "Treno", number: trainNum, destination: "Caricamento...", time: "--:--", delay: "In orario", platform: "--")
                            selectedFavoriteTrain = dummy
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "timer")
                                    .font(.title3)
                                    .foregroundColor(.red)
                                    .frame(width: 32, height: 32)
                                    .background(Color.red.opacity(0.12))
                                    .cornerRadius(8)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Treno Monitorato \(trainNum)")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("Live Activity Attiva")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                
                                Spacer()
                                
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .opacity(isPulsing ? 0.3 : 1.0)
                                    .onAppear {
                                        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                                            isPulsing = true
                                        }
                                    }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                // --- SUGGESTIONS ---
                if !smartSuggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(smartSuggestions) { suggestion in
                                SmartSuggestionCard(suggestion: suggestion)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                
                // --- NEARBY STATION ---
                if let nearby = nearby {
                    NavigationLink(destination: SmartBoardView(station: nearby)) {
                        HStack(spacing: 12) {
                            Image(systemName: "location.fill")
                                .font(.title3)
                                .foregroundColor(.orange)
                                .frame(width: 32, height: 32)
                                .background(Color.orange.opacity(0.12))
                                .cornerRadius(8)
                            
                            Text(nearby.formattedName)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}
