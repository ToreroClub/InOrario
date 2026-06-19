import SwiftUI
import Combine
import Foundation
import CoreLocation
import ActivityKit

struct LiveTrainBand: View {
    @EnvironmentObject var manager: TrainManager
    let segment: TravelSegment
    
    @State private var isExpanded = false
    @State private var liveStatus: StopsResult?
    @State private var isLoading = false
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let res = liveStatus {
                    if let err = res.errorMessage {
                        Text(err).font(.caption).foregroundColor(.red)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(res.status.statusMessage).font(.subheadline).bold().foregroundColor(.secondary)
                            if res.status.lastStation != "--" {
                                Text("Ultimo rilevamento: \(res.status.lastStation) alle \(res.status.lastTime)").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        ForEach(res.stops) { stop in
                            HStack {
                                Circle().fill(stop.delay > 0 ? Color.red : Color.green).frame(width: 8, height: 8)
                                Text(stop.stationName).font(.caption)
                                Spacer()
                                Text(stop.actualTime ?? stop.time).font(.caption).bold()
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: segment.trainCategory == "Trasporto Urbano" ? "tram.fill" : "train.side.front.car")
                        .foregroundColor(segment.trainCategory == "Trasporto Urbano" ? .purple : .blue)
                    Text("\(segment.trainCategory) \(segment.trainNumber)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    
                    if segment.trainCategory == "Trasporto Urbano" {
                        Text("15 min stimati")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if isLoading {
                        ProgressView().scaleEffect(0.8)
                    } else if let res = liveStatus, res.errorMessage == nil {
                        let delayStr = res.status.statusMessage
                        Text(delayStr)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(delayStr.contains("orario") || delayStr.contains("viaggio") || delayStr.contains("attesa") ? .green : .red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((delayStr.contains("orario") || delayStr.contains("viaggio") || delayStr.contains("attesa") ? Color.green : Color.red).opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Da: \(segment.origin)").font(.subheadline)
                        Text("A: \(segment.destination)").font(.subheadline)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(segment.departureTime).font(.subheadline).fontWeight(.bold)
                        Text(segment.arrivalTime).font(.subheadline).fontWeight(.bold)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .contextMenu {
            if segment.trainCategory != "Trasporto Urbano" {
                Button(action: {
                    let desc = "\(segment.origin) - \(segment.destination)"
                    manager.toggleFavorite(trainNumber: segment.trainNumber, description: desc, departureTime: segment.departureTime)
                    Haptics.play(.medium)
                }) {
                    let isFav = manager.favoriteTrains.contains(where: { $0.number == segment.trainNumber })
                    Label(isFav ? "Rimuovi dai Preferiti" : "Aggiungi ai Preferiti", systemImage: isFav ? "star.slash.fill" : "star.fill")
                }
            }
        }
        .onChange(of: isExpanded) { oldValue, newValue in
            if newValue && liveStatus == nil && segment.trainCategory != "Trasporto Urbano" {
                Task {
                    isLoading = true
                    liveStatus = await manager.fetchLiveStops(for: segment.trainNumber)
                    isLoading = false
                }
            }
        }
        .task {
            if liveStatus == nil && segment.trainCategory != "Trasporto Urbano" {
                isLoading = true
                liveStatus = await manager.fetchLiveStops(for: segment.trainNumber)
                isLoading = false
            }
        }
    }
}

struct TravelSolutionDetailsView: View {
    @EnvironmentObject var manager: TrainManager
    let solution: TravelSolution
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .center, spacing: 8) {
                    HStack {
                        VStack {
                            Text(solution.origin).font(.headline).multilineTextAlignment(.center)
                            Text(solution.departureTime).font(.title2).fontWeight(.bold)
                        }
                        Spacer()
                        VStack {
                            Image(systemName: "arrow.right").font(.title2).foregroundColor(.gray)
                            Text(solution.duration).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack {
                            Text(solution.destination).font(.headline).multilineTextAlignment(.center)
                            Text(solution.arrivalTime).font(.title2).fontWeight(.bold)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            Section(header: Text("Treni del Viaggio")) {
                if solution.segments.isEmpty {
                    Text("Nessun dettaglio treni disponibile.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(solution.segments) { segment in
                        LiveTrainBand(segment: segment)
                    }
                }
            }
        }
        .navigationTitle("Dettagli Viaggio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    manager.toggleSavedTrip(solution: solution)
                }) {
                    Image(systemName: manager.isTripSaved(solution: solution) ? "bookmark.fill" : "bookmark")
                        .foregroundColor(manager.isTripSaved(solution: solution) ? .green : .blue)
                }
            }
        }
    }
}

struct StationSelectionSheet: View {
    @EnvironmentObject var manager: TrainManager
    @Environment(\.dismiss) var dismiss
    @Binding var selectedName: String
    @Binding var selectedID: String
    @State private var query = ""
    let title: String
    
    var body: some View {
        NavigationStack {
            List {
                if manager.isSearching {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if manager.searchTrenitaliaLocations.isEmpty && !query.isEmpty {
                    Text("Nessuna stazione trovata.").foregroundColor(.secondary)
                } else {
                    ForEach(manager.searchTrenitaliaLocations) { result in
                        Button {
                            selectedName = result.name
                            selectedID = String(result.id)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "building.2.crop.circle.fill").foregroundColor(.orange)
                                Text(result.name).font(.headline).foregroundColor(.primary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Annulla") { dismiss() }.fontWeight(.bold)
                }
            }
            .searchable(text: $query, prompt: "Cerca stazione...")
            .onChange(of: query) { oldValue, newValue in
                Task { await manager.searchTravelLocations(query: newValue) }
            }
        }
    }
}

struct TravelSearchView: View {
    @EnvironmentObject var manager: TrainManager
    
    @State private var originName = ""
    @State private var originID = ""
    @State private var destName = ""
    @State private var destID = ""
    @State private var searchDate = Date()
    
    @State private var showOriginSearch = false
    @State private var showDestSearch = false
    @State private var hasSearched = false
    
    var body: some View {
        Form {
            Section(header: Text("Dettagli Viaggio")) {
                Button(action: { showOriginSearch = true }) {
                    HStack {
                        Text("Partenza")
                        Spacer()
                        Text(originName.isEmpty ? "Seleziona" : originName)
                            .foregroundColor(originName.isEmpty ? .secondary : .primary)
                    }
                }
                
                Button(action: { showDestSearch = true }) {
                    HStack {
                        Text("Arrivo")
                        Spacer()
                        Text(destName.isEmpty ? "Seleziona" : destName)
                            .foregroundColor(destName.isEmpty ? .secondary : .primary)
                    }
                }
                
                DatePicker("Data e Ora", selection: $searchDate, displayedComponents: [.date, .hourAndMinute])
                    .environment(\.locale, Locale(identifier: "it_IT"))
            }
            
            if !originID.isEmpty && !destID.isEmpty {
                Section {
                    Button(action: {
                        hasSearched = true
                        Task {
                            await manager.searchTravelSolutions(originID: originID, destID: destID, date: searchDate)
                        }
                    }) {
                        HStack {
                            Spacer()
                            if manager.isSearchingSolutions {
                                ProgressView().tint(.white)
                            } else {
                                Text("Cerca Soluzioni")
                                    .fontWeight(.bold)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(manager.isSearchingSolutions)
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                
                Section {
                    Button(action: {
                        manager.toggleFavoriteRoute(originName: originName, originID: originID, destName: destName, destID: destID)
                    }) {
                        HStack {
                            Image(systemName: manager.isFavoriteRoute(originID: originID, destID: destID) ? "star.fill" : "star")
                                .foregroundColor(manager.isFavoriteRoute(originID: originID, destID: destID) ? .yellow : .blue)
                            Text(manager.isFavoriteRoute(originID: originID, destID: destID) ? "Rimuovi dai Preferiti" : "Aggiungi ai Preferiti")
                        }
                    }
                }
            }
            
            if manager.isSearchingSolutions {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Ricerca soluzioni su ViaggiaTreno in corso...").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                }
            } else if !manager.travelSolutions.isEmpty {
                Section(header: Text("Soluzioni Trovate")) {
                    ForEach(manager.travelSolutions) { solution in
                        NavigationLink(destination: TravelSolutionDetailsView(solution: solution)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(solution.category) \(solution.trainNumber)").font(.headline)
                                    Spacer()
                                    Text(solution.duration).font(.subheadline).foregroundColor(.secondary)
                                }
                                HStack {
                                    Text(solution.departureTime).fontWeight(.bold)
                                    Image(systemName: "arrow.right").foregroundColor(.secondary).font(.caption)
                                    Text(solution.arrivalTime).fontWeight(.bold)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .contextMenu {
                            let validSegments = solution.segments.filter { $0.trainCategory != "Trasporto Urbano" && !$0.trainNumber.isEmpty }
                            if !validSegments.isEmpty {
                                ForEach(validSegments) { segment in
                                    Button(action: {
                                        let desc = "\(segment.origin) - \(segment.destination)"
                                        manager.toggleFavorite(trainNumber: segment.trainNumber, description: desc, departureTime: segment.departureTime)
                                        Haptics.play(.medium)
                                    }) {
                                        let isFav = manager.favoriteTrains.contains(where: { $0.number == segment.trainNumber })
                                        Label(
                                            isFav ? "Rimuovi \(segment.trainCategory) \(segment.trainNumber) dai Preferiti" : "Aggiungi \(segment.trainCategory) \(segment.trainNumber) ai Preferiti",
                                            systemImage: isFav ? "star.slash.fill" : "star.fill"
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            } else if hasSearched && !manager.isSearchingSolutions {
                Section {
                    Text("Nessuna soluzione trovata in questo orario. Riprova con un'altra data o orario.").foregroundColor(.secondary).font(.subheadline)
                }
            }
        }
        .sheet(isPresented: $showOriginSearch) {
            StationSelectionSheet(selectedName: $originName, selectedID: $originID, title: "Stazione di Partenza")
        }
        .sheet(isPresented: $showDestSearch) {
            StationSelectionSheet(selectedName: $destName, selectedID: $destID, title: "Stazione di Arrivo")
        }
    }
}

struct SearchView: View {
    @EnvironmentObject var manager: TrainManager
    @State private var query = ""
    @State private var searchType = 0
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tipo Ricerca", selection: $searchType) {
                    Text("Viaggi").tag(0)
                    Text("Treni").tag(1)
                    Text("Stazioni").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: searchType) { oldValue, newValue in Haptics.play(.light) }
                
                if searchType == 0 {
                    TravelSearchView()
                } else {
                    List {
                        if manager.isSearching {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else if searchType == 1 {
                            if query.isEmpty {
                                if !manager.recentTrains.isEmpty {
                                    Section(header: HStack {
                                        Text("Ricerche Recenti")
                                        Spacer()
                                        Button("Cancella") {
                                            manager.clearRecentTrains()
                                            Haptics.play(.medium)
                                        }
                                        .font(.caption)
                                        .foregroundColor(.red)
                                    }) {
                                        ForEach(manager.recentTrains) { result in
                                            let dummy = manager.createDummyTrain(from: result)
                                            NavigationLink(destination: TrainStopsView(train: dummy, showCloseButton: false).onAppear {
                                                manager.addToRecentTrains(result)
                                            }) {
                                                HStack {
                                                    Image(systemName: "clock").foregroundColor(.gray)
                                                    VStack(alignment: .leading) {
                                                        Text("Treno \(result.number)").font(.headline)
                                                        Text(result.description).font(.caption).foregroundColor(.secondary)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    Text("Digita il numero di un treno per cercarlo.").foregroundColor(.secondary)
                                }
                            } else {
                                if manager.searchResults.isEmpty {
                                    Text("Nessun treno trovato.").foregroundColor(.secondary)
                                } else {
                                    ForEach(manager.searchResults) { result in
                                        let dummy = manager.createDummyTrain(from: result)
                                        NavigationLink(destination: TrainStopsView(train: dummy, showCloseButton: false).onAppear {
                                            manager.addToRecentTrains(result)
                                        }) {
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
                        } else if searchType == 2 {
                            if query.isEmpty {
                                if !manager.recentStations.isEmpty {
                                    Section(header: HStack {
                                        Text("Ricerche Recenti")
                                        Spacer()
                                        Button("Cancella") {
                                            manager.clearRecentStations()
                                            Haptics.play(.medium)
                                        }
                                        .font(.caption)
                                        .foregroundColor(.red)
                                    }) {
                                        ForEach(manager.recentStations) { result in
                                            HStack {
                                                Image(systemName: "clock").foregroundColor(.gray)
                                                
                                                let possibleRFI = manager.getRfiID(for: result.nomeLungo)
                                                let tempStation = Station(name: result.nomeLungo, rfiID: possibleRFI, vtID: result.vtID, lat: nil, lon: nil)
                                                
                                                NavigationLink(destination: SmartBoardView(station: tempStation).onAppear {
                                                    manager.addToRecentStations(result)
                                                }) {
                                                    Text(result.nomeLungo).font(.headline)
                                                }
                                                Spacer()
                                                
                                                Button {
                                                    if manager.isMyStation(vtID: result.vtID) {
                                                        manager.removeMyStation(vtID: result.vtID)
                                                    } else {
                                                        manager.addMyStation(name: result.nomeLungo, vtID: result.vtID)
                                                    }
                                                } label: {
                                                    Image(systemName: manager.isMyStation(vtID: result.vtID) ? "checkmark.circle.fill" : "plus.circle")
                                                        .foregroundColor(.blue)
                                                        .font(.title2)
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                            }
                                            .padding(.vertical, 4)
                                        }
                                    }
                                } else {
                                    Text("Digita il nome di una stazione per cercarla.").foregroundColor(.secondary)
                                }
                            } else {
                                if manager.searchStationResults.isEmpty {
                                    Text("Nessuna stazione trovata.").foregroundColor(.secondary)
                                } else {
                                    ForEach(manager.searchStationResults) { result in
                                        HStack {
                                            Image(systemName: "building.2.crop.circle.fill").foregroundColor(.orange)
                                            
                                            let possibleRFI = manager.getRfiID(for: result.nomeLungo)
                                            let tempStation = Station(name: result.nomeLungo, rfiID: possibleRFI, vtID: result.vtID, lat: nil, lon: nil)
                                            
                                            NavigationLink(destination: SmartBoardView(station: tempStation).onAppear {
                                                manager.addToRecentStations(result)
                                            }) {
                                                Text(result.nomeLungo).font(.headline)
                                            }
                                            Spacer()
                                            
                                            Button {
                                                if manager.isMyStation(vtID: result.vtID) {
                                                    manager.removeMyStation(vtID: result.vtID)
                                                } else {
                                                    manager.addMyStation(name: result.nomeLungo, vtID: result.vtID)
                                                }
                                            } label: {
                                                Image(systemName: manager.isMyStation(vtID: result.vtID) ? "checkmark.circle.fill" : "plus.circle")
                                                    .foregroundColor(.blue)
                                                    .font(.title2)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $query, prompt: searchType == 1 ? "Es. 2010" : "Es. Bologna Centrale")
                    .onChange(of: query) { oldValue, newValue in
                        Task {
                            if searchType == 1 { await manager.searchTrains(query: newValue) }
                            else if searchType == 2 { await manager.searchStations(query: newValue) }
                        }
                    }
                }
            }
            .navigationTitle(searchType == 0 ? "Cerca Viaggi" : (searchType == 1 ? "Cerca Treno" : "Cerca Stazione"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { dismiss() }.fontWeight(.bold)
                }
            }
        }
    }
}
