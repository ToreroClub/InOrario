import SwiftUI
import Combine
import Foundation
import CoreLocation
import ActivityKit


struct SmartBoardView: View {
    let station: Station
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var guessingEngine: TrainGuessingEngine
    
    private var resolvedStation: Station {
        // Se ha già un rfiID valido (non vuoto e numerico), la stazione è già pronta per RFI
        if let rfi = station.rfiID, !rfi.isEmpty, !rfi.hasPrefix("S"), !rfi.hasPrefix("N") {
            return station
        }
        // Se non ha rfiID (o se aveva un ID errato), risolviamolo SEMPRE dal catalogo RFI
        return manager.resolveStation(name: station.name, fallbackVtID: station.vtID, fallbackRfiID: station.rfiID)
    }
    
    var body: some View {
        let currentStation = resolvedStation
        Group {
            if let rfi = currentStation.rfiID, !rfi.isEmpty {
                // Tabellone ufficiale RFI (con scraping IECHUB partenze/arrivi e avvisi stazione)
                StationBoardView(station: currentStation)
            } else if let vt = currentStation.vtID, !vt.isEmpty {
                // Stazioni non RFI (Ferrovie Nord come Castano Primo, Saronno, Cadorna, ecc.): ViaggiaTreno
                VTStationBoardView(stationName: currentStation.name, vtID: vt)
            } else {
                Text("Errore: Nessun ID stazione valido.")
            }
        }
        .onAppear {
            if let vt = currentStation.vtID {
                manager.addToViewedRecentStations(name: currentStation.name, vtID: vt)
            }
            let isNear = locationManager.nearbyStation?.name == currentStation.name
            usageTracker.recordStationVisit(name: currentStation.name, vtID: currentStation.vtID, rfiID: currentStation.rfiID, gpsNear: isNear, location: locationManager.userLocation?.coordinate)
            
            // Registra per l'indovino solo se l'utente si trova davvero in quella stazione
            if isNear {
                guessingEngine.markStationSeen(currentStation.name)
            }
        }
    }
}

struct StationBoardView: View {
    let station: Station
    @State private var showingDepartures = true
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var cache: MetroCache
    @EnvironmentObject var usageTracker: UsageTracker
    @Environment(\.scenePhase) var scenePhase
    @State private var selectedTrain: Train?
    
    @State private var isMetroExpanded = false
    @State private var isAlertExpanded = false

    @StateObject private var filterController = StationBoardFilterController()
    @ObservedObject private var commuteManager = SupporterCommuteManager.shared
    @State private var showPaywallSheet = false
    @State private var showCommuteSetupSheet = false
    @State private var showSolutionsFallbackSheet = false
    
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var filteredTrains: [Train] {
        filterController.filterState.apply(
            to: manager.trains,
            favoriteTrainNumbers: Set(manager.favoriteTrains.map(\.number)),
            commuteMatches: filterController.commuteMatches,
            isAlreadyAtTargetStation: filterController.isAlreadyAtTargetStation
        )
    }

    private func handleSelectCommute(_ target: CommuteTargetFilter) {
        let targetStations = target == .home ? commuteManager.origins : commuteManager.destinations
        if !showingDepartures && filterController.filterState.commuteTarget != target {
            showingDepartures = true
            filterController.filterState.commuteTarget = target
            return
        }
        filterController.toggleCommuteTarget(
            target,
            currentStationName: station.name,
            boardTrains: manager.trains,
            targetStations: targetStations
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(station.formattedName)
                    .font(.title)
                    .bold()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button {
                        if !showingDepartures {
                            showingDepartures = true
                            Haptics.play(.medium)
                        }
                    } label: {
                        Text("P")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .frame(width: 36, height: 36)
                            .background(showingDepartures ? Color.orange : Color(.systemGray5))
                            .foregroundColor(showingDepartures ? .white : .primary)
                            .clipShape(Circle())
                    }
                    
                    Button {
                        if showingDepartures {
                            showingDepartures = false
                            Haptics.play(.medium)
                        }
                    } label: {
                        Text("A")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .frame(width: 36, height: 36)
                            .background(!showingDepartures ? Color.orange : Color(.systemGray5))
                            .foregroundColor(!showingDepartures ? .white : .primary)
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 12)
            .background(Color(.systemGroupedBackground))
            .zIndex(1)

            ActiveStationFiltersBar(
                filterController: filterController,
                commuteOrigins: commuteManager.origins,
                commuteDestinations: commuteManager.destinations,
                backgroundColor: Color(.systemGroupedBackground)
            )
            
            List {
                // Sezione Salute / Avvisi
                Section {
                    // Riga unica: stato health a sx, triangolo avvisi a dx (solo se presenti)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(manager.lineHealth.color)
                            .frame(width: 10, height: 10)
                        Text(manager.lineHealth.message)
                            .font(.subheadline.bold())
                            .foregroundColor(manager.lineHealth.color)
                        Spacer()
                        
                        if manager.isLoading {
                            ProgressView()
                        } else if manager.stationAlerts != nil {
                            Button {
                                isAlertExpanded.toggle()
                                Haptics.play(.light)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Image(systemName: isAlertExpanded ? "chevron.up" : "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Testo avvisi (visibile solo se espanso)
                    if let alerts = manager.stationAlerts, isAlertExpanded {
                        Text(alerts)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                // Sezione Metropolitana — card bianca automatica da insetGrouped
                if !station.metroLines.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $isMetroExpanded) {
                            VStack(spacing: 8) {
                                ForEach(station.metroLines) { metro in
                                    MetroRowView(metro: metro, currentTime: currentTime)
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            Label("Metropolitana", systemImage: "tram.fill")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        .onChange(of: isMetroExpanded) { _, _ in Haptics.play(.light) }
                    }
                }

                
                Section {
                    if filterController.filterState.isActive && filteredTrains.isEmpty && (!manager.trains.isEmpty || filterController.isResolvingCommute) {
                        FilteredEmptyBoardView(filterController: filterController) {
                            showSolutionsFallbackSheet = true
                        }
                    } else {
                        ForEach(filteredTrains) { train in
                            let activeCommuteTarget = filterController.isAlreadyAtTargetStation ? nil : filterController.filterState.commuteTarget
                            let cMatch = activeCommuteTarget != nil
                                ? filterController.filterState.commuteMatch(for: train, in: filterController.commuteMatches)
                                : nil
                            TrainRowView(
                                train: train,
                                showPassanteTag: passanteManager.isCentralPassanteStation(station.name),
                                stationName: station.name,
                                commuteMatch: cMatch,
                                commuteTarget: activeCommuteTarget
                            )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Haptics.play(.light)
                                    selectedTrain = train
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button { manager.toggleFavorite(trainNumber: train.number, description: train.destination, departureTime: train.time) } label: {
                                        let isFav = manager.isFavorite(trainNumber: train.number)
                                        Label(isFav ? "Rimuovi" : "Preferito", systemImage: isFav ? "star.slash.fill" : "star.fill")
                                    }
                                    .tint(manager.isFavorite(trainNumber: train.number) ? .red : .yellow)
                                }
                        }
                    }
                }
                
                Section {
                    Text("Dati in tempo reale da tabelloni RFI")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .environment(\.defaultMinListHeaderHeight, 0)
            .contentMargins(.top, 0, for: .scrollContent)
            .refreshable {
                Haptics.play(.light)
                await manager.fetchTrains(for: station, isDepartures: showingDepartures, force: true)
                filterController.refreshCommuteIfNeeded(
                    currentStationName: station.name,
                    boardTrains: manager.trains,
                    commuteManager: commuteManager,
                    force: true
                )
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                StationFilterToolbarMenu(
                    stationName: station.name,
                    allTrains: manager.trains,
                    favoriteTrainNumbers: Set(manager.favoriteTrains.map(\.number)),
                    hasSupport: manager.hasSupport(),
                    commuteOrigins: commuteManager.origins,
                    commuteDestinations: commuteManager.destinations,
                    filterController: filterController,
                    onSelectCommute: { handleSelectCommute($0) },
                    onRequirePro: { showPaywallSheet = true },
                    onOpenCommuteSetup: { showCommuteSetupSheet = true }
                )
            }

            if #available(iOS 26, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if manager.isMyStation(station) {
                        manager.removeMyStation(station)
                    } else {
                        manager.addMyStation(station)
                    }
                } label: {
                    Image(systemName: manager.isMyStation(station) ? "star.fill" : "star").foregroundColor(.yellow)
                }
            }
        }
        .sheet(item: $selectedTrain) { t in
            let trainWithOrigin = Train(
                category: t.category,
                number: t.number,
                destination: t.destination,
                time: t.time,
                delay: t.delay,
                platform: t.platform,
                isDelayUncertain: t.isDelayUncertain,
                origin: showingDepartures ? station.name : t.origin
            )
            NavigationStack { TrainStopsView(train: trainWithOrigin) }
        }
        .sheet(isPresented: $showPaywallSheet) {
            SupportPaywallSheet()
                .environmentObject(manager)
        }
        .sheet(isPresented: $showCommuteSetupSheet) {
            NavigationStack {
                CommuteSetupView()
                    .environmentObject(manager)
                    .environmentObject(locationManager)
                    .environmentObject(passanteManager)
                    .environmentObject(cache)
                    .environmentObject(usageTracker)
            }
        }
        .sheet(isPresented: $showSolutionsFallbackSheet) {
            let targetList = filterController.filterState.commuteTarget == .work
                ? commuteManager.destinations
                : commuteManager.origins
            let targetName = targetList.first ?? ""
            SearchView(
                isTravelOnly: true,
                initialOriginName: station.name,
                initialOriginID: station.rfiID ?? station.vtID,
                initialDestName: targetName,
                autoSearchSolutions: !targetName.isEmpty
            )
            .environmentObject(manager)
            .environmentObject(locationManager)
        }
        .onAppear {
            manager.startAutoRefresh(for: station, isDepartures: showingDepartures)
            filterController.restorePersistedFilters(
                for: station.name,
                boardTrains: manager.trains,
                commuteManager: commuteManager,
                hasSupport: manager.hasSupport()
            )
        }
        .onDisappear { manager.stopAutoRefresh() }
        .onReceive(timer) { input in
            guard scenePhase == .active else { return }
            self.currentTime = input
        }
        .task(id: showingDepartures) { await manager.fetchTrains(for: station, isDepartures: showingDepartures) }
        .onChange(of: showingDepartures) { _, newValue in
            manager.startAutoRefresh(for: station, isDepartures: newValue)
            if !newValue && filterController.filterState.commuteTarget != nil {
                filterController.clearCommuteTarget(for: station.name)
            }
        }
        .onChange(of: filterController.filterState) { _, _ in
            filterController.persistCurrentFilters(for: station.name)
        }
        .onChange(of: manager.trains) { _, newTrains in
            filterController.refreshCommuteIfNeeded(
                currentStationName: station.name,
                boardTrains: newTrains,
                commuteManager: commuteManager
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                manager.startAutoRefresh(for: station, isDepartures: showingDepartures)
            } else {
                manager.stopAutoRefresh()
            }
        }
    }
}

struct VTStationBoardView: View {

    let stationName: String
    let vtID: String
    @State private var showingDepartures = true
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var cache: MetroCache
    @EnvironmentObject var usageTracker: UsageTracker
    @State private var selectedTrain: Train?

    @StateObject private var filterController = StationBoardFilterController()
    @ObservedObject private var commuteManager = SupporterCommuteManager.shared
    @State private var showPaywallSheet = false
    @State private var showCommuteSetupSheet = false
    @State private var showSolutionsFallbackSheet = false

    private var displayTrains: [Train] {
        filterController.filterState.apply(
            to: manager.trains,
            favoriteTrainNumbers: Set(manager.favoriteTrains.map(\.number)),
            commuteMatches: filterController.commuteMatches,
            isAlreadyAtTargetStation: filterController.isAlreadyAtTargetStation
        )
    }

    private func handleSelectCommute(_ target: CommuteTargetFilter) {
        let targetStations = target == .home ? commuteManager.origins : commuteManager.destinations
        if !showingDepartures && filterController.filterState.commuteTarget != target {
            showingDepartures = true
            filterController.filterState.commuteTarget = target
            return
        }
        filterController.toggleCommuteTarget(
            target,
            currentStationName: stationName,
            boardTrains: manager.trains,
            targetStations: targetStations
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(stationName.capitalized)
                    .font(.title)
                    .bold()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                
                HStack(spacing: 8) {
                    Button {
                        if !showingDepartures { showingDepartures = true; Haptics.play(.medium) }
                    } label: {
                        Text("P").font(.system(size: 15, weight: .bold)).frame(width: 36, height: 36)
                            .background(showingDepartures ? Color.orange : Color(.systemGray5))
                            .foregroundColor(showingDepartures ? .white : .primary).clipShape(Circle())
                    }
                    Button {
                        if showingDepartures { showingDepartures = false; Haptics.play(.medium) }
                    } label: {
                        Text("A").font(.system(size: 15, weight: .bold)).frame(width: 36, height: 36)
                            .background(!showingDepartures ? Color.orange : Color(.systemGray5))
                            .foregroundColor(!showingDepartures ? .white : .primary).clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 12)
            .background(Color(.systemBackground))
            .zIndex(1)

            ActiveStationFiltersBar(
                filterController: filterController,
                commuteOrigins: commuteManager.origins,
                commuteDestinations: commuteManager.destinations,
                backgroundColor: Color(.systemBackground)
            )
            
            if manager.isLoading && manager.trains.isEmpty {
                VStack { Spacer(); ProgressView("Caricamento treni..."); Spacer() }
            } else if manager.trains.isEmpty && !manager.isLoading {
                VStack { Spacer(); Text("Nessun treno trovato in questa stazione.").foregroundColor(.secondary); Spacer() }
            } else if filterController.filterState.isActive && displayTrains.isEmpty {
                List {
                    Section {
                        FilteredEmptyBoardView(filterController: filterController) {
                            showSolutionsFallbackSheet = true
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                List(displayTrains) { train in
                    let activeCommuteTarget = filterController.isAlreadyAtTargetStation ? nil : filterController.filterState.commuteTarget
                    let cMatch = activeCommuteTarget != nil
                        ? filterController.filterState.commuteMatch(for: train, in: filterController.commuteMatches)
                        : nil
                    TrainRowView(
                        train: train,
                        showPassanteTag: passanteManager.isCentralPassanteStation(stationName),
                        stationName: stationName,
                        commuteMatch: cMatch,
                        commuteTarget: activeCommuteTarget
                    )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Haptics.play(.light)
                            selectedTrain = train
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button { manager.toggleFavorite(trainNumber: train.number, description: train.destination, departureTime: train.time) } label: {
                                let isFav = manager.isFavorite(trainNumber: train.number)
                                Label(isFav ? "Rimuovi" : "Preferito", systemImage: isFav ? "star.slash.fill" : "star.fill")
                            }
                            .tint(manager.isFavorite(trainNumber: train.number) ? .red : .yellow)
                        }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListHeaderHeight, 0)
                .contentMargins(.top, 0, for: .scrollContent)
                .refreshable {
                    Haptics.play(.light)
                    await manager.fetchVTTrains(for: vtID, isDepartures: showingDepartures, force: true)
                    filterController.refreshCommuteIfNeeded(
                        currentStationName: stationName,
                        boardTrains: manager.trains,
                        commuteManager: commuteManager,
                        force: true
                    )
                }
            }
            Text("Dati in tempo reale da ViaggiaTreno").font(.caption2).foregroundColor(.secondary).padding(.bottom, 8)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                StationFilterToolbarMenu(
                    stationName: stationName,
                    allTrains: manager.trains,
                    favoriteTrainNumbers: Set(manager.favoriteTrains.map(\.number)),
                    hasSupport: manager.hasSupport(),
                    commuteOrigins: commuteManager.origins,
                    commuteDestinations: commuteManager.destinations,
                    filterController: filterController,
                    onSelectCommute: { handleSelectCommute($0) },
                    onRequirePro: { showPaywallSheet = true },
                    onOpenCommuteSetup: { showCommuteSetupSheet = true }
                )
            }

            if #available(iOS 26, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if manager.isMyStation(vtID: vtID) {
                        manager.removeMyStation(vtID: vtID)
                    } else {
                        manager.addMyStation(name: stationName, vtID: vtID)
                    }
                } label: {
                    Image(systemName: manager.isMyStation(vtID: vtID) ? "star.fill" : "star").foregroundColor(.yellow)
                }
            }
        }
        .sheet(item: $selectedTrain) { t in
            let trainWithOrigin = Train(
                category: t.category,
                number: t.number,
                destination: t.destination,
                time: t.time,
                delay: t.delay,
                platform: t.platform,
                isDelayUncertain: t.isDelayUncertain,
                origin: showingDepartures ? stationName : t.origin
            )
            NavigationStack { TrainStopsView(train: trainWithOrigin) }
        }
        .sheet(isPresented: $showPaywallSheet) {
            SupportPaywallSheet()
                .environmentObject(manager)
        }
        .sheet(isPresented: $showCommuteSetupSheet) {
            NavigationStack {
                CommuteSetupView()
                    .environmentObject(manager)
                    .environmentObject(locationManager)
                    .environmentObject(passanteManager)
                    .environmentObject(cache)
                    .environmentObject(usageTracker)
            }
        }
        .sheet(isPresented: $showSolutionsFallbackSheet) {
            let targetList = filterController.filterState.commuteTarget == .work
                ? commuteManager.destinations
                : commuteManager.origins
            let targetName = targetList.first ?? ""
            let resolvedOrigin = manager.resolveStation(name: stationName, fallbackVtID: vtID, fallbackRfiID: nil)
            SearchView(
                isTravelOnly: true,
                initialOriginName: resolvedOrigin.name,
                initialOriginID: resolvedOrigin.rfiID ?? vtID,
                initialDestName: targetName,
                autoSearchSolutions: !targetName.isEmpty
            )
            .environmentObject(manager)
            .environmentObject(locationManager)
        }
        .onAppear {
            filterController.restorePersistedFilters(
                for: stationName,
                boardTrains: manager.trains,
                commuteManager: commuteManager,
                hasSupport: manager.hasSupport()
            )
        }
        .task(id: showingDepartures) { await manager.fetchVTTrains(for: vtID, isDepartures: showingDepartures) }
        .onChange(of: showingDepartures) { _, newValue in
            if !newValue && filterController.filterState.commuteTarget != nil {
                filterController.clearCommuteTarget(for: stationName)
            }
        }
        .onChange(of: filterController.filterState) { _, _ in
            filterController.persistCurrentFilters(for: stationName)
        }
        .onChange(of: manager.trains) { _, newTrains in
            filterController.refreshCommuteIfNeeded(
                currentStationName: stationName,
                boardTrains: newTrains,
                commuteManager: commuteManager
            )
        }
    }
}

