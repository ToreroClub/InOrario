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
    
    var body: some View {
        let isFerrovienord = station.vtID?.hasPrefix("N") == true
        Group {
            if !isFerrovienord, let rfi = station.rfiID, !rfi.isEmpty {
                StationBoardView(station: station)
            } else if let vt = station.vtID, !vt.isEmpty {
                VTStationBoardView(stationName: station.name, vtID: vt)
            } else {
                Text("Errore: Nessun ID stazione valido.")
            }
        }
        .onAppear {
            if let vt = station.vtID {
                manager.addToViewedRecentStations(name: station.name, vtID: vt)
            }
            let isNear = locationManager.nearbyStation?.name == station.name
            usageTracker.recordStationVisit(name: station.name, vtID: station.vtID, rfiID: station.rfiID, gpsNear: isNear, location: locationManager.userLocation?.coordinate)
        }
    }
}

struct StationBoardView: View {
    let station: Station
    @State private var showingDepartures = true
    @State private var selectedPassanteDirection = "Ovest"
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @Environment(\.scenePhase) var scenePhase
    @State private var selectedTrain: Train?
    
    @State private var isMetroExpanded = false
    @State private var isAlertExpanded = false
    
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var filteredTrains: [Train] {
        var result = manager.trains
        if passanteManager.isPassanteDirectionalStation(station.name) {
            result = result.filter { train in
                passanteManager.getPassanteDirection(for: train) == selectedPassanteDirection
            }
        }
        if manager.isHomeFilterActive && !manager.homeDestinationStationName.isEmpty {
            result = manager.filterTrainsForHome(result, currentStationName: station.name)
        }
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(station.formattedName)
                    .font(.title)
                    .bold()
                
                Spacer()
                
                if passanteManager.isPassanteDirectionalStation(station.name) {
                    HStack(spacing: 4) {
                        Button {
                            if selectedPassanteDirection != "Ovest" {
                                selectedPassanteDirection = "Ovest"
                                Haptics.play(.medium)
                            }
                        } label: {
                            Text("← Bovisa/Rho")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedPassanteDirection == "Ovest" ? Color.orange : Color(.systemGray5))
                                .foregroundColor(selectedPassanteDirection == "Ovest" ? .white : .primary)
                                .cornerRadius(18)
                        }
                        
                        Button {
                            if selectedPassanteDirection != "Est" {
                                selectedPassanteDirection = "Est"
                                Haptics.play(.medium)
                            }
                        } label: {
                            Text("Rogoredo/Forlanini →")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedPassanteDirection == "Est" ? Color.orange : Color(.systemGray5))
                                .foregroundColor(selectedPassanteDirection == "Est" ? .white : .primary)
                                .cornerRadius(18)
                        }
                    }
                } else {
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
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 6)
            
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
                    ForEach(filteredTrains) { train in
                        TrainRowView(train: train, showPassanteTag: passanteManager.isCentralPassanteStation(station.name), stationName: station.name)
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
            .refreshable {
                Haptics.play(.light)
                await manager.fetchTrains(for: station, isDepartures: showingDepartures, force: true)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .sheet(item: $selectedTrain) { t in NavigationStack { TrainStopsView(train: t) } }
        .onAppear { manager.startAutoRefresh(for: station, isDepartures: showingDepartures) }
        .onDisappear { manager.stopAutoRefresh() }
        .onReceive(timer) { input in
            guard scenePhase == .active else { return }
            self.currentTime = input
        }
        .task(id: showingDepartures) { await manager.fetchTrains(for: station, isDepartures: showingDepartures) }
        .onChange(of: showingDepartures) { _, newValue in
            manager.startAutoRefresh(for: station, isDepartures: newValue)
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
    @State private var selectedPassanteDirection = "Ovest"
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @State private var selectedTrain: Train?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(stationName.capitalized)
                    .font(.title)
                    .bold()
                Spacer()
                
                if passanteManager.isPassanteDirectionalStation(stationName) {
                    HStack(spacing: 4) {
                        Button {
                            if selectedPassanteDirection != "Ovest" {
                                selectedPassanteDirection = "Ovest"
                                Haptics.play(.medium)
                            }
                        } label: {
                            Text("← Bovisa/Rho")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedPassanteDirection == "Ovest" ? Color.orange : Color(.systemGray5))
                                .foregroundColor(selectedPassanteDirection == "Ovest" ? .white : .primary)
                                .cornerRadius(18)
                        }
                        
                        Button {
                            if selectedPassanteDirection != "Est" {
                                selectedPassanteDirection = "Est"
                                Haptics.play(.medium)
                            }
                        } label: {
                            Text("Rogoredo/Forlanini →")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedPassanteDirection == "Est" ? Color.orange : Color(.systemGray5))
                                .foregroundColor(selectedPassanteDirection == "Est" ? .white : .primary)
                                .cornerRadius(18)
                        }
                    }
                } else {
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
            }
            .padding(.horizontal)
            .padding(.top, 10)
            
            let displayTrains: [Train] = {
                var result = manager.trains
                if passanteManager.isPassanteDirectionalStation(stationName) {
                    result = result.filter { train in
                        passanteManager.getPassanteDirection(for: train) == selectedPassanteDirection
                    }
                }
                if manager.isHomeFilterActive && !manager.homeDestinationStationName.isEmpty {
                    result = manager.filterTrainsForHome(result, currentStationName: stationName)
                }
                return result
            }()
            
            if manager.isLoading && displayTrains.isEmpty {
                VStack { Spacer(); ProgressView("Caricamento treni..."); Spacer() }
            } else if displayTrains.isEmpty && !manager.isLoading {
                VStack { Spacer(); Text("Nessun treno trovato in questa stazione.").foregroundColor(.secondary); Spacer() }
            } else {
                List(displayTrains) { train in
                    TrainRowView(train: train, showPassanteTag: passanteManager.isCentralPassanteStation(stationName), stationName: stationName)
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
                .refreshable {
                    Haptics.play(.light)
                    await manager.fetchVTTrains(for: vtID, isDepartures: passanteManager.isPassanteDirectionalStation(stationName) ? true : showingDepartures, force: true)
                }
            }
            Text("Dati in tempo reale da ViaggiaTreno").font(.caption2).foregroundColor(.secondary).padding(.bottom, 8)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .sheet(item: $selectedTrain) { t in NavigationStack { TrainStopsView(train: t) } }
        .onAppear { manager.loadFavorites() }
        .task(id: showingDepartures) { await manager.fetchVTTrains(for: vtID, isDepartures: passanteManager.isPassanteDirectionalStation(stationName) ? true : showingDepartures) }
    }
}

