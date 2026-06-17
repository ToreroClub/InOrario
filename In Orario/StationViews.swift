import SwiftUI
import Combine
import Foundation
import CoreLocation
import ActivityKit


struct SmartBoardView: View {
    let station: Station
    @EnvironmentObject var manager: TrainManager
    
    var body: some View {
        let isFerrovienord = station.vtID?.hasPrefix("N") == true
        if !isFerrovienord, let rfi = station.rfiID, !rfi.isEmpty {
            StationBoardView(station: station)
        } else if let vt = station.vtID, !vt.isEmpty {
            VTStationBoardView(stationName: station.name, vtID: vt)
        } else {
            Text("Errore: Nessun ID stazione valido.")
        }
    }
}

struct StationBoardView: View {
    let station: Station
    @State private var showingDepartures = true
    @State private var selectedPassanteDirection = "Ovest"
    @EnvironmentObject var manager: TrainManager
    @State private var selectedTrain: Train?
    
    @State private var isMetroExpanded = false
    @State private var isAlertExpanded = false
    
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var filteredTrains: [Train] {
        var result = manager.trains
        if manager.isPassanteDirectionalStation(station.name) {
            result = result.filter { train in
                manager.getPassanteDirection(for: train) == selectedPassanteDirection
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
                Text(station.name)
                    .font(.title)
                    .bold()
                
                Spacer()
                
                if manager.isPassanteDirectionalStation(station.name) {
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
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle()
                        .fill(manager.lineHealth.color)
                        .frame(width: 10, height: 10)
                    Text(manager.lineHealth.message)
                        .font(.subheadline.bold())
                        .foregroundColor(manager.lineHealth.color)
                    Spacer()
                    
                    if manager.isLoading {
                        ProgressView()
                    } else if manager.stationAlerts != nil && !isAlertExpanded {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .transition(.scale)
                    }
                }
                
                if let alerts = manager.stationAlerts {
                    Divider()
                    DisclosureGroup(isExpanded: $isAlertExpanded) {
                        Text(alerts)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.subheadline)
                            Text("Avvisi della Stazione")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                        }
                    }
                    .tint(.orange)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.top, 10)

            if !station.metroLines.isEmpty {
                VStack(spacing: 0) {
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
                    .onChange(of: isMetroExpanded) { oldValue, newValue in Haptics.play(.light) }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.top, 10)
            }
            
            Spacer().frame(height: 10)

            List {
                Section(header: Text("Treni RFI")) {
                    ForEach(filteredTrains) { train in
                        TrainRowView(train: train, showPassanteTag: manager.isCentralPassanteStation(station.name), stationName: station.name)
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
            .listStyle(.insetGrouped)
            .refreshable {
                Haptics.play(.light)
                await manager.fetchTrains(for: station, isDepartures: showingDepartures)
            }
            
            Text("Dati in tempo reale da tabelloni RFI")
                .font(.caption2).foregroundColor(.secondary).padding(.bottom, 8)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedTrain) { t in NavigationStack { TrainStopsView(train: t) } }
        .onAppear { manager.startAutoRefresh(for: station, isDepartures: showingDepartures) }
        .onDisappear { manager.stopAutoRefresh() }
        .onReceive(timer) { input in self.currentTime = input }
        .task(id: showingDepartures) { await manager.fetchTrains(for: station, isDepartures: showingDepartures) }
        .onChange(of: showingDepartures) { _, newValue in
            manager.startAutoRefresh(for: station, isDepartures: newValue)
        }
    }
}

struct VTStationBoardView: View {
    let stationName: String
    let vtID: String
    @State private var showingDepartures = true
    @State private var selectedPassanteDirection = "Ovest"
    @EnvironmentObject var manager: TrainManager
    @State private var selectedTrain: Train?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(stationName.capitalized)
                    .font(.title)
                    .bold()
                Spacer()
                
                if manager.isPassanteDirectionalStation(stationName) {
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
                if manager.isPassanteDirectionalStation(stationName) {
                    result = result.filter { train in
                        manager.getPassanteDirection(for: train) == selectedPassanteDirection
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
                    TrainRowView(train: train, showPassanteTag: manager.isCentralPassanteStation(stationName), stationName: stationName)
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
                    await manager.fetchVTTrains(for: vtID, isDepartures: manager.isPassanteDirectionalStation(stationName) ? true : showingDepartures)
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
        .task(id: showingDepartures) { await manager.fetchVTTrains(for: vtID, isDepartures: manager.isPassanteDirectionalStation(stationName) ? true : showingDepartures) }
    }
}

