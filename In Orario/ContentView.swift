import SwiftUI
import Combine
import Foundation
import CoreLocation
import ActivityKit


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
    @Environment(\.scenePhase) var scenePhase

    
    @State private var newsItems: [NewsItem] = []
    @State private var allNewsItems: [NewsItem] = []
    
    @State private var isPassanteExpanded = false
    @State private var isFavoritesExpanded = true
    @State private var isMyStationsExpanded = true
    @State private var showSearchSheet = false
    @State private var showSavedTrips = false
    @State private var showHistorySheet = false
    @State private var showProfile = false
    @State private var showNewsCenter = false
    @State private var showOnboarding = false
    @State private var showNewSmartRouteSheet = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var hasRequestedLocation = false
    
    @State private var deepLinkTrain: Train? = nil
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
        return "In Orario"
    }
    
    var hasUrgentNews: Bool {
        newsItems.contains { item in
            if item.isUrgent {
                // Se la notizia è uno sciopero, mostriamo "In Orario? No!" solo se è imminente (entro 48 ore)
                if item.category == "sciopero", let dateStr = item.date {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    formatter.timeZone = TimeZone(identifier: "Europe/Rome")
                    if let strikeDate = formatter.date(from: dateStr) {
                        let now = Date()
                        let diff = strikeDate.timeIntervalSince(now)
                        // Mostra "In Orario? No!" se lo sciopero inizia entro le prossime 48 ore (e non è finito da oltre 24 ore)
                        return diff >= -86400 && diff <= 172800
                    }
                    return false
                }
                // Per notizie realtime o lavori urgenti, manteniamo il comportamento standard (sempre In Orario? No!)
                return true
            }
            return false
        }
    }
    
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    ForEach(manager.sectionOrder, id: \.self) { section in
                        switch section {
                        case .nearby:
                            if let nearby = locationManager.nearbyStation {
                                Section(header: Text("📍 Stazione Vicina").font(.subheadline.bold())) {
                                    NavigationLink(destination: SmartBoardView(station: nearby)) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Sei qui")
                                                    .font(.caption2)
                                                    .fontWeight(.heavy)
                                                    .foregroundColor(.orange)
                                                    .textCase(.uppercase)
                                                Text(nearby.name)
                                                    .font(.title3)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.primary)
                                            }
                                            Spacer()
                                            Image(systemName: "location.circle.fill")
                                                .font(.title)
                                                .foregroundColor(.orange)
                                        }
                                        .padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                    }
                                }
                            }
                            
                        case .favoriteTrains:
                            if !manager.favoriteTrains.isEmpty {
                                Section {
                                    DisclosureGroup(isExpanded: $isFavoritesExpanded) {
                                        ForEach(manager.favoriteTrains) { fav in
                                            let dummy = manager.createDummyTrain(from: fav)
                                            Button {
                                                selectedFavoriteTrain = dummy
                                            } label: {
                                                HStack {
                                                    Image(systemName: "train.side.front.car").foregroundColor(.blue)
                                                    VStack(alignment: .leading) {
                                                        let depText = fav.departureTime != nil ? " • \(fav.departureTime!)" : ""
                                                        Text("\(dummy.category) \(fav.number)\(depText)").font(.headline)
                                                        Text(fav.description).font(.caption).foregroundColor(.secondary)
                                                    }
                                                    Spacer()
                                                }
                                                .padding(.vertical, 4)
                                                .contentShape(Rectangle())
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
                            

                            
                        case .myStations:
                            if !manager.myStations.isEmpty {
                                Section {
                                    DisclosureGroup(isExpanded: $isMyStationsExpanded) {
                                        ForEach(manager.myStations) { s in
                                            NavigationLink(destination: SmartBoardView(station: s)) {
                                                Label(s.name, systemImage: "building.2.crop.circle.fill")
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
                            
                        case .passante:
                            if !passanteManager.selectedSuburbanLines.isEmpty {
                                Section {
                                    DisclosureGroup(isExpanded: $isPassanteExpanded) {
                                        VStack(alignment: .leading, spacing: 15) {
                                            
                                            if passanteManager.userUsesTunnel {
                                                PassanteTunnelStatusHeaderView()
                                            }
                                            
                                            
                                            let selectedLines = SuburbanData.shared.allLines.filter { passanteManager.selectedSuburbanLines.contains($0.id) }
                                            ForEach(selectedLines) { line in
                                                let hiddenForLine = passanteManager.hiddenSuburbanStations[line.id] ?? []
                                                let visibleStations = line.stations.filter { !hiddenForLine.contains($0.name) }
                                                        
                                                        if !visibleStations.isEmpty {
                                                            let activeNearby = locationManager.manualNearbyStation ?? locationManager.nearbyStation
                                                            SuburbanLineView(line: line, visibleStations: visibleStations, activeNearby: activeNearby)
                                                            
                                                            if line.id != selectedLines.last?.id {
                                                                Divider().padding(.vertical, 5)
                                                            }
                                                        }
                                                    }
                                        }
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
                    }
                    

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
            .navigationTitle(appTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 10) {
                        Button {
                            Haptics.play(.medium)
                            showProfile = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.title2)
                                .foregroundColor(.orange)
                        }
                        
                        if !manager.activeLiveActivities.isEmpty {
                            ForEach(Array(manager.activeLiveActivities), id: \.self) { trainNum in
                                Button {
                                    Haptics.play(.medium)
                                    let dummy = Train(category: "Treno", number: trainNum, destination: "Caricamento...", time: "--:--", delay: "In orario", platform: "--")
                                    selectedFavoriteTrain = dummy
                                } label: {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 6, height: 6)
                                            .opacity(isPulsing ? 0.3 : 1.0)
                                            .onAppear {
                                                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                                                    isPulsing = true
                                                }
                                            }
                                        Text("Treno \(trainNum)")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red.opacity(0.12))
                                    .foregroundColor(.red)
                                    .cornerRadius(10)
                                }
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 20) {
                        Button {
                            Haptics.play(.medium)
                            showNewsCenter = true
                        } label: {
                            Image(systemName: "newspaper.fill")
                                .foregroundColor(hasUrgentNews ? .red : .blue)
                                .overlay(
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 10, y: -10)
                                        .opacity(newsItems.isEmpty ? 0 : 1)
                                )
                        }
                        
                        Button {
                            Haptics.play(.medium)
                            showSavedTrips = true
                        } label: {
                            Image(systemName: "bookmark.fill")
                                .foregroundColor(.green)
                                .overlay(
                                    Group {
                                        if !manager.savedTrips.isEmpty {
                                            Text("\(manager.savedTrips.count)")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(Color.green)
                                                .clipShape(Capsule())
                                                .offset(x: 10, y: -10)
                                        }
                                    }
                                )
                        }
                        
                        Button {
                            Haptics.play(.medium)
                            showHistorySheet = true
                        } label: { Image(systemName: "clock.arrow.circlepath").fontWeight(.medium) }
                        
                        Button {
                            Haptics.play(.medium)
                            showSearchSheet = true
                        } label: { Image(systemName: "magnifyingglass").fontWeight(.bold) }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationDestination(isPresented: $showSavedTrips) { SavedTripsView() }
            .sheet(isPresented: $showSearchSheet, onDismiss: { manager.loadFavorites() }) { SearchView() }
            .sheet(isPresented: $showHistorySheet) { HistoryView() }
            .sheet(isPresented: $showProfile) { ProfileView() }
            .sheet(isPresented: $showNewsCenter) { NewsCenterView(news: allNewsItems) }
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
                    }
            }
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
        .environmentObject(metroCache)
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
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                print("App tornata attiva, aggiorno posizione e passante...")
                locationManager.requestLocation()
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
    }
    
    func loadNews() async {
        let decodedNews = await manager.fetchStrikesAndNews()
        await MainActor.run {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                self.allNewsItems = decodedNews
                self.newsItems = decodedNews.filter { $0.title != "Info" || $0.isUrgent }
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
                    }
                }
                .padding(.bottom, 20)
                .padding(.top, 20)
                .padding(.horizontal, 10)
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
